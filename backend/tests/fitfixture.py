"""Build a FIT file shaped like the one RepFlow's watch app writes.

Written with Garmin's own Python FIT SDK encoder, so the bytes `fitread` is
tested against are produced by Garmin's definition of the format rather than by
the same assumptions the reader makes. Field numbers, names and types mirror
`source/GarminRecorder.mc` exactly — if that file's developer fields change, the
test that reads this fixture is where it shows up.
"""

from __future__ import annotations

import io
from datetime import datetime, timezone

from garmin_fit_sdk import Encoder, Profile

#: Profile indexes base types by id; the encoder wants the id for a name.
_BASE_TYPE_ID = {name: number for number, name in Profile["types"]["fit_base_type"].items()}

#: Mirrors GarminRecorder.mc. Name, field number, FIT base type.
LAP_FIELDS = (
    ("exercise", 10, "string"),
    ("set", 11, "uint16"),
    ("reps", 12, "uint16"),
    ("weight", 13, "float32"),
    ("rest", 14, "uint16"),
)

_DEVELOPER_DATA_INDEX = 0


def _descriptions(include_rest: bool = True) -> dict[str, dict]:
    developer_data_id = {
        "mesg_num": Profile["mesg_num"]["DEVELOPER_DATA_ID"],
        "developer_data_index": _DEVELOPER_DATA_INDEX,
        "application_id": list(range(16)),
    }
    out = {}
    for name, number, base_type in LAP_FIELDS:
        if name == "rest" and not include_rest:
            continue
        out[name] = {
            "developer_data_id_mesg": developer_data_id,
            "field_description_mesg": {
                "mesg_num": Profile["mesg_num"]["FIELD_DESCRIPTION"],
                "developer_data_index": _DEVELOPER_DATA_INDEX,
                "field_definition_number": number,
                "fit_base_type_id": _BASE_TYPE_ID[base_type],
                "field_name": name,
                "native_mesg_num": Profile["mesg_num"]["LAP"],
            },
        }
    return out


def build_fit(laps: list[dict], include_rest: bool = True) -> bytes:
    """Encode `laps` into FIT bytes.

    Each lap is `{start, duration, exercise, set, reps, weight, rest}`; any of
    the developer values may be omitted, which is how a bodyweight set (no
    weight) and a pre-rest-field recording are both represented.
    """
    descriptions = _descriptions(include_rest)
    encoder = Encoder(field_descriptions=descriptions)

    start: datetime = laps[0]["start"] if laps else datetime.now(timezone.utc)
    encoder.write_mesg(
        {
            "mesg_num": Profile["mesg_num"]["FILE_ID"],
            "type": "activity",
            "manufacturer": "garmin",
            "product": 3110,           # fenix 6 Pro
            "time_created": start,
            "serial_number": 1,
        }
    )
    for description in descriptions.values():
        encoder.write_mesg(description["developer_data_id_mesg"])
    for description in descriptions.values():
        encoder.write_mesg(description["field_description_mesg"])

    for lap in laps:
        developer_fields = {
            name: lap[name]
            for name, _, _ in LAP_FIELDS
            if name in lap and (name != "rest" or include_rest)
        }
        encoder.write_mesg(
            {
                "mesg_num": Profile["mesg_num"]["LAP"],
                "timestamp": lap["start"],
                "start_time": lap["start"],
                "total_elapsed_time": lap["duration"],
                "total_timer_time": lap["duration"],
                "developer_fields": developer_fields,
            }
        )

    encoder.write_mesg(
        {
            "mesg_num": Profile["mesg_num"]["SESSION"],
            "timestamp": start,
            "start_time": start,
            "sport": "training",
            "sub_sport": "strength_training",
            "total_elapsed_time": sum(lap["duration"] for lap in laps),
        }
    )
    return encoder.close()


def zipped(fit_bytes: bytes, name: str = "activity.fit") -> bytes:
    """Wrap FIT bytes the way Garmin serves an original activity download."""
    import zipfile

    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr(name, fit_bytes)
    return buffer.getvalue()
