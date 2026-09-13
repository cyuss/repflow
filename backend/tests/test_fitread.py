"""Reading RepFlow's laps back out of a FIT file.

The fixture is encoded with Garmin's own Python FIT SDK, so these tests compare
the reader against Garmin's definition of the format rather than against the
same assumptions the reader was written with.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from fitfixture import build_fit, zipped

from repflow_garmin.fitread import NotARepFlowActivity, read_sets, unzip

T0 = datetime(2026, 9, 13, 12, 7, 0, tzinfo=timezone.utc)


def lap(index: int, **overrides) -> dict:
    base = {
        "start": T0 + timedelta(seconds=index * 90),
        "duration": 90.0,
        "exercise": "Bench Press",
        "set": index + 1,
        "reps": 8,
        "weight": 80.0,
        "rest": 45,
    }
    base.update(overrides)
    return base


def test_the_poc_session_round_trips() -> None:
    """Bench Press 3x8x80 and Lat Pulldown 3x10x60 — the fixture the whole
    investigation is measured against. See docs/garmin-strength-integration-poc.md."""
    laps = [lap(i) for i in range(3)]
    laps += [
        lap(3 + i, exercise="Lat Pulldown", set=i + 1, reps=10, weight=60.0)
        for i in range(3)
    ]
    sets = read_sets(build_fit(laps))

    assert len(sets) == 6
    assert sum(s.reps for s in sets) == 54
    assert sum(s.reps * (s.weight_kg or 0) for s in sets) == pytest.approx(3720.0)
    assert [s.exercise for s in sets[:3]] == ["Bench Press"] * 3
    assert [s.set_number for s in sets[3:]] == [1, 2, 3]


def test_start_times_come_back_as_utc() -> None:
    sets = read_sets(build_fit([lap(0)]))
    assert sets[0].start_time == T0
    assert sets[0].start_time.tzinfo is not None


def test_a_bodyweight_set_has_no_weight_rather_than_zero() -> None:
    laps = [lap(0, exercise="Push-Up", reps=15)]
    del laps[0]["weight"]
    assert read_sets(build_fit(laps))[0].weight_kg is None


def test_the_rest_field_is_read_when_the_watch_wrote_it() -> None:
    sets = read_sets(build_fit([lap(0, rest=45)]))
    assert sets[0].rest_s == 45.0
    assert sets[0].work_s == 45.0     # 90 s lap, 45 s of it rest


def test_a_file_from_before_the_rest_field_still_reads() -> None:
    # Every activity recorded before the field existed must stay fillable.
    sets = read_sets(build_fit([lap(0)], include_rest=False))
    assert sets[0].rest_s is None
    assert sets[0].work_s == 90.0


def test_laps_without_an_exercise_are_not_sets() -> None:
    # Garmin closes a final lap of its own, and the athlete can press LAP.
    plain = {"start": T0 + timedelta(minutes=10), "duration": 5.0}
    assert len(read_sets(build_fit([lap(0), plain]))) == 1


def test_a_long_imported_name_survives() -> None:
    name = "Bulgarian Split Squat (Dumbbell)"   # 32 chars, under the 40 cap
    assert read_sets(build_fit([lap(0, exercise=name)]))[0].exercise == name


def test_an_activity_with_no_repflow_laps_says_so() -> None:
    plain = {"start": T0, "duration": 60.0}
    with pytest.raises(NotARepFlowActivity):
        read_sets(build_fit([plain]))


def test_garmins_zip_wrapper_is_unwrapped() -> None:
    raw = build_fit([lap(0)])
    assert unzip(zipped(raw)) == raw


def test_a_bare_fit_file_passes_through_unwrapping() -> None:
    raw = build_fit([lap(0)])
    assert unzip(raw) == raw
