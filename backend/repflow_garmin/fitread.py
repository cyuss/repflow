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

from dataclasses import dataclass

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


@dataclass(frozen=True)
class SessionMetrics:
    """What Garmin measured across the whole session.

    Hevy has nowhere to put any of it — its API carries weight, reps, distance,
    duration, RPE and a custom metric, and nothing physiological at all — so
    these end up in the workout's description, which is the only free-text field
    the endpoint accepts. Not a chart, but the numbers land where the athlete
    reads the session rather than nowhere.
    """

    avg_heart_rate: int | None = None
    max_heart_rate: int | None = None
    calories: int | None = None
    training_effect: float | None = None
    elapsed_s: float | None = None


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
            "no laps in this activity carry RepFlow's exercise field.\n"
            "  It was recorded by something else — Garmin's own strength mode, "
            "or another app — or by a build of RepFlow from before the developer "
            "fields were declared.\n"
            "  Run `repflow-garmin list` and name the right one with --activity."
        )
    return sets


def read_session(fit_bytes: bytes) -> SessionMetrics:
    """The FIT session message, which is where Garmin puts the whole-session
    figures. Absent fields stay absent — a watch with no strap paired reports no
    heart rate, and that is not a zero."""
    for message in _messages(fit_bytes, "session"):
        return SessionMetrics(
            avg_heart_rate=_as_int(message.get("avg_heart_rate")),
            max_heart_rate=_as_int(message.get("max_heart_rate")),
            calories=_as_int(message.get("total_calories")),
            training_effect=_number(message.get("total_training_effect")),
            elapsed_s=_number(message.get("total_elapsed_time")),
        )
    return SessionMetrics()


def _as_int(value: object) -> int | None:
    number = _number(value)
    return None if number is None else int(number)


def _laps(fit_bytes: bytes) -> Iterator[dict[str, object]]:
    return _messages(fit_bytes, "lap")


def _messages(fit_bytes: bytes, name: str) -> Iterator[dict[str, object]]:
    with fitdecode.FitReader(io.BytesIO(fit_bytes)) as reader:
        for frame in reader:
            if not isinstance(frame, fitdecode.FitDataMessage):
                continue
            if frame.name != name:
                continue
            yield {field.name: field.value for field in frame.fields}
