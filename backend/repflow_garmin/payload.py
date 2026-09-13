"""Turn RepFlow's sets into the body Garmin Connect's exerciseSets endpoint wants.

Pure: a list of `LoggedSet` in, a JSON-shaped dict out. Everything that can be
wrong about the conversion — the unit of weight, the shape of a timestamp, what
happens to a bodyweight set, how rest is separated from work — is decided here
and tested here, without an account or a network.

The shape itself is not documented by Garmin. It was taken from a payload posted
by a Garmin Connect user in the forum thread cited in
docs/garmin-strength-integration-poc.md, and matches what the library at
cyberjunky/python-garminconnect sends.
"""

from __future__ import annotations

from collections.abc import Callable, Iterable, Sequence
from datetime import datetime, timezone
from typing import Any

from .mapping import resolve as default_resolver
from .model import LoggedSet

#: Garmin stores the load in grams, as a float. A kilogram field sent as
#: kilograms shows up as a 60-gram bench press.
GRAMS_PER_KG = 1000.0

#: How confident the exercise identification is, 0-100. Garmin's own on-watch
#: rep detection sends a probability distribution over several guesses because
#: it is guessing. RepFlow is not: the athlete chose the exercise by name, so
#: there is one entry at full confidence.
CERTAIN = 100.0


def format_time(moment: datetime) -> str:
    """Garmin's timestamp shape: `2026-09-13T12:07:33.0`.

    No zone and one decimal place. FIT records in UTC and the activity's own
    `startTimeGMT` is in the same shape, so a naive datetime is treated as UTC
    rather than as the machine's local time — which would silently shift every
    set by the operator's offset.
    """
    if moment.tzinfo is not None:
        moment = moment.astimezone(timezone.utc).replace(tzinfo=None)
    return moment.strftime("%Y-%m-%dT%H:%M:%S") + f".{moment.microsecond // 100000}"


def _rest_entry(start: datetime, duration: float) -> dict[str, Any]:
    """A rest interval. No exercise, no reps, no load — those are not zero, they
    are absent, and Garmin renders the two differently."""
    return {
        "exercises": [],
        "duration": round(duration, 3),
        "repetitionCount": None,
        "weight": None,
        "setType": "REST",
        "startTime": format_time(start),
        "wktStepIndex": None,
    }


def _active_entry(
    start: datetime,
    duration: float,
    reps: int,
    weight_kg: float | None,
    category: str,
    exercise: str | None,
) -> dict[str, Any]:
    return {
        "exercises": [
            {"category": category, "name": exercise, "probability": CERTAIN}
        ],
        "duration": round(duration, 3),
        "repetitionCount": reps,
        # A bodyweight set has no load. Sending 0.0 would claim the athlete
        # lifted nothing, which is a different and false statement.
        "weight": None if weight_kg is None else round(weight_kg * GRAMS_PER_KG, 1),
        "setType": "ACTIVE",
        "startTime": format_time(start),
        "wktStepIndex": None,
    }


def build(
    activity_id: int | str,
    sets: Iterable[LoggedSet],
    resolver: Callable[[str], tuple[str, str | None] | None] = default_resolver,
) -> tuple[dict[str, Any], list[str]]:
    """Build the request body, and report what could not be mapped.

    The second return value names every exercise Garmin's enum does not
    recognise. Those sets are **dropped rather than guessed**: an unmappable
    name has no category, and a set with no category is a row Garmin refuses.
    Returning them instead of swallowing them is what lets the caller say which
    exercises are missing from the table rather than leaving a silent hole.

    Sets are emitted in time order regardless of the order they arrive in —
    which matters, because RepFlow's whole premise is that the athlete does them
    in whatever order the gym allows.
    """
    entries: list[dict[str, Any]] = []
    unmapped: list[str] = []
    seen_unmapped: set[str] = set()

    for logged in sorted(sets, key=lambda s: s.start_time):
        target = resolver(logged.exercise)
        if target is None:
            if logged.exercise not in seen_unmapped:
                seen_unmapped.add(logged.exercise)
                unmapped.append(logged.exercise)
            continue

        category, exercise = target
        start = logged.start_time
        rest = logged.rest_s

        # A RepFlow lap is closed when a set is logged, so it covers the rest
        # taken beforehand plus the set itself. Splitting it needs the rest the
        # watch measured; without it the lap is reported as one working set,
        # which overstates work time but invents nothing.
        if rest is not None and rest > 0:
            # A rest longer than the lap that contains it is a clock artefact,
            # not a fact. Clamping keeps the two intervals inside the lap
            # Garmin already has; the set itself is still reported, because the
            # reps happened whatever the timestamps say.
            rest = min(rest, logged.duration_s)
            entries.append(_rest_entry(start, rest))
            start = start.fromtimestamp(start.timestamp() + rest, tz=start.tzinfo)

        entries.append(
            _active_entry(
                start, logged.work_s, logged.reps, logged.weight_kg, category, exercise
            )
        )

    return {"activityId": int(activity_id), "exerciseSets": entries}, unmapped


def summarise(entries: Sequence[dict[str, Any]]) -> str:
    """One line describing what is about to be written, for the operator.

    This runs before a destructive replace-all, so it counts what the payload
    actually contains rather than what the caller believes it contains.
    """
    active = [e for e in entries if e["setType"] == "ACTIVE"]
    rests = len(entries) - len(active)
    reps = sum(e["repetitionCount"] or 0 for e in active)
    volume = sum(
        (e["weight"] or 0.0) / GRAMS_PER_KG * (e["repetitionCount"] or 0)
        for e in active
    )
    return (
        f"{len(active)} sets, {reps} reps, {volume:,.0f} kg of volume"
        f"{f', {rests} rest intervals' if rests else ''}"
    )
