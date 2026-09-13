"""Read RepFlow's sets back out of the FIT file Garmin already has.

This is the step that makes the whole thing self-contained. RepFlow writes one
lap per set carrying the exercise, set number, reps and load as **developer
fields**, and Garmin stores that file verbatim. Developer fields are
self-describing — the file carries its own field definitions — so nothing here
needs to know RepFlow's field numbers, only their names.

The consequence worth stating: every RepFlow activity ever recorded can be
filled in retroactively, because the data was always in the file. Nothing has to
be captured at the time.
"""

from __future__ import annotations

import io
import zipfile
from collections.abc import Iterator
from datetime import datetime, timezone

import fitdecode

from .model import LoggedSet

#: The developer field names RepFlow writes on each lap. Names, not numbers:
#: a FIT file defines its own developer fields, and matching on the name is what
#: keeps this readable against a file written by a version of the watch app that
#: renumbered them.
FIELD_EXERCISE = "exercise"
FIELD_SET = "set"
FIELD_REPS = "reps"
FIELD_WEIGHT = "weight"
FIELD_REST = "rest"
FIELD_RPE = "rpe"


class NotARepFlowActivity(Exception):
    """The FIT file has no RepFlow laps in it."""


def unzip(raw: bytes) -> bytes:
    """Garmin serves the original activity as a zip holding one FIT file."""
    if raw[:2] != b"PK":
        return raw
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        names = [n for n in archive.namelist() if n.lower().endswith(".fit")]
        if not names:
            raise NotARepFlowActivity("the downloaded archive holds no .fit file")
        return archive.read(names[0])


def _as_utc(value: object) -> datetime | None:
    if not isinstance(value, datetime):
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _number(value: object) -> float | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return None


def read_sets(fit_bytes: bytes) -> list[LoggedSet]:
    """Every logged set in the file, in the order the laps were recorded.

    A lap without an exercise name is not a set — it is Garmin closing the
    activity, or a lap the athlete triggered by hand — and it is skipped rather
    than turned into a nameless row.
    """
    sets: list[LoggedSet] = []
    for lap in _laps(fit_bytes):
        name = lap.get(FIELD_EXERCISE)
        if not isinstance(name, str) or not name.strip():
            continue
        reps = _number(lap.get(FIELD_REPS))
        if reps is None:
            continue
        start = _as_utc(lap.get("start_time"))
        if start is None:
            continue

        weight = _number(lap.get(FIELD_WEIGHT))
        rest = _number(lap.get(FIELD_REST))
        rpe = _number(lap.get(FIELD_RPE))
        duration = _number(lap.get("total_elapsed_time")) or _number(
            lap.get("total_timer_time")
        )
        set_number = _number(lap.get(FIELD_SET))

        sets.append(
            LoggedSet(
                exercise=name.strip(),
                set_number=int(set_number) if set_number else len(sets) + 1,
                reps=int(reps),
                # An unwritten load is absent, not zero — see LoggedSet.
                weight_kg=weight,
                start_time=start,
                duration_s=duration if duration is not None else 0.0,
                rest_s=rest,
                rpe=rpe,
            )
        )

    if not sets:
        raise NotARepFlowActivity(
            "no laps in this activity carry RepFlow's exercise field — "
            "either it was not recorded by RepFlow, or it was recorded before "
            "resources/fit_contributions.xml declared the developer fields"
        )
    return sets


def _laps(fit_bytes: bytes) -> Iterator[dict[str, object]]:
    with fitdecode.FitReader(io.BytesIO(fit_bytes)) as reader:
        for frame in reader:
            if not isinstance(frame, fitdecode.FitDataMessage):
                continue
            if frame.name != "lap":
                continue
            yield {field.name: field.value for field in frame.fields}
