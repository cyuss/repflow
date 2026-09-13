"""Building the Hevy workout, without touching an account.

Two of Hevy's rules lose the **whole** workout rather than one set when broken —
an unknown `exercise_template_id` and an `rpe` off the enumeration — so both are
enforced here, where they can be checked for free.
"""

from __future__ import annotations

import pathlib
import re
from datetime import datetime, timedelta, timezone

import pytest

from repflow_garmin.hevy import (
    RPE_SCALE,
    HevyError,
    Template,
    build_workout,
    resolve,
    summarise,
)
from repflow_garmin.model import LoggedSet

T0 = datetime(2026, 9, 13, 12, 7, 0, tzinfo=timezone.utc)

CATALOGUE = [
    Template("t-bench", "Bench Press (Barbell)"),
    Template("t-incline", "Incline Bench Press (Dumbbell)"),
    Template("t-lat", "Lat Pulldown (Cable)"),
    Template("t-row", "Seated Row (Machine)"),
    Template("t-push", "Push Up"),
]


def a_set(minute: int = 0, **overrides) -> LoggedSet:
    base = dict(
        exercise="Bench Press (Barbell)",
        set_number=1,
        reps=8,
        weight_kg=80.0,
        start_time=T0 + timedelta(minutes=minute),
        duration_s=60.0,
        rpe=None,
    )
    base.update(overrides)
    return LoggedSet(**base)


def workout(body) -> dict:
    return body["workout"]


class TestMatchingAMovement:
    def test_a_name_that_came_from_hevy_matches_exactly(self) -> None:
        # Every routine RepFlow imports is already titled in Hevy's words, so
        # this is the common case and it must never be re-guessed.
        assert resolve("Bench Press (Barbell)", CATALOGUE).id == "t-bench"

    def test_matching_ignores_case_and_spacing(self) -> None:
        assert resolve("  bench press (barbell) ", CATALOGUE).id == "t-bench"

    def test_a_name_the_watch_truncated_still_matches(self) -> None:
        # The FIT string field has a fixed size; a lost bracket must not cost
        # the exercise. See GarminRecorder.EXERCISE_NAME_MAX.
        assert resolve("Incline Bench Press (Dumbbell", CATALOGUE).id == "t-incline"

    def test_word_order_and_shorthand_do_not_matter(self) -> None:
        assert resolve("Cable Lat Pulldown", CATALOGUE).id == "t-lat"

    def test_an_unknown_movement_returns_nothing_rather_than_the_nearest(self) -> None:
        # A set filed under the wrong movement is worse in someone's training
        # history than a set that is missing from it.
        assert resolve("Zercher Carry", CATALOGUE) is None


class TestTheEffortRating:
    def test_the_scale_is_the_one_hevy_publishes(self) -> None:
        assert RPE_SCALE == (6.0, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0)

    def test_a_rating_off_the_ladder_is_dropped_not_sent(self) -> None:
        # 6.5 is not in Hevy's enumeration. Sending it answers 400 and loses
        # every set in the workout, not this one.
        body, _ = build_workout("W", [a_set(rpe=6.5)], CATALOGUE)
        assert workout(body)["exercises"][0]["sets"][0]["rpe"] is None

    def test_a_rating_on_the_ladder_survives(self) -> None:
        body, _ = build_workout("W", [a_set(rpe=8.5)], CATALOGUE)
        assert workout(body)["exercises"][0]["sets"][0]["rpe"] == 8.5

    def test_an_unrated_set_sends_null(self) -> None:
        body, _ = build_workout("W", [a_set(rpe=None)], CATALOGUE)
        assert workout(body)["exercises"][0]["sets"][0]["rpe"] is None

    def test_the_watch_and_this_package_agree_on_the_scale(self) -> None:
        """source/Rpe.mc and hevy.py state the same rule in two languages."""
        source = (pathlib.Path(__file__).resolve().parents[2] / "source" / "Rpe.mc").read_text()
        found = re.search(r"const SCALE = \[([^\]]*)\]", source)
        assert found, "Rpe.mc no longer declares SCALE the way this test reads it"
        watch = tuple(float(v.strip()) for v in found.group(1).split(","))
        assert watch == RPE_SCALE


class TestTheWorkoutBody:
    def test_a_bodyweight_set_sends_no_weight_rather_than_zero(self) -> None:
        body, _ = build_workout("W", [a_set(exercise="Push Up", weight_kg=None)], CATALOGUE)
        assert workout(body)["exercises"][0]["sets"][0]["weight_kg"] is None

    def test_consecutive_sets_of_one_movement_become_one_exercise(self) -> None:
        sets = [a_set(minute=i) for i in range(3)]
        body, _ = build_workout("W", sets, CATALOGUE)
        exercises = workout(body)["exercises"]
        assert len(exercises) == 1 and len(exercises[0]["sets"]) == 3

    def test_going_back_to_a_movement_records_it_as_a_second_entry(self) -> None:
        # This is the whole point of the app: the athlete went A, B, A, and
        # collapsing that would rewrite the session into one they did not do.
        sets = [
            a_set(minute=0),
            a_set(minute=2, exercise="Lat Pulldown (Cable)"),
            a_set(minute=4),
        ]
        body, _ = build_workout("W", sets, CATALOGUE)
        ids = [e["exercise_template_id"] for e in workout(body)["exercises"]]
        assert ids == ["t-bench", "t-lat", "t-bench"]

    def test_sets_are_ordered_by_time_whatever_order_they_arrive_in(self) -> None:
        body, _ = build_workout("W", [a_set(minute=5, reps=5), a_set(minute=0, reps=8)], CATALOGUE)
        assert [s["reps"] for s in workout(body)["exercises"][0]["sets"]] == [8, 5]

    def test_the_timestamps_are_zoned(self) -> None:
        body, _ = build_workout("W", [a_set(minute=0), a_set(minute=10)], CATALOGUE)
        assert workout(body)["start_time"] == "2026-09-13T12:07:00Z"
        assert workout(body)["end_time"] == "2026-09-13T12:17:00Z"

    def test_an_unmatched_movement_is_reported_and_the_rest_still_goes(self) -> None:
        body, unmatched = build_workout(
            "W", [a_set(minute=0), a_set(minute=2, exercise="Zercher Carry")], CATALOGUE
        )
        assert unmatched == ["Zercher Carry"]
        assert len(workout(body)["exercises"]) == 1

    def test_it_refuses_rather_than_posting_an_empty_workout(self) -> None:
        with pytest.raises(HevyError):
            build_workout("W", [a_set(exercise="Zercher Carry")], CATALOGUE)

    def test_it_refuses_when_there_are_no_sets_at_all(self) -> None:
        with pytest.raises(HevyError):
            build_workout("W", [], CATALOGUE)

    def test_privacy_is_carried_through(self) -> None:
        body, _ = build_workout("W", [a_set()], CATALOGUE, is_private=True)
        assert workout(body)["is_private"] is True


def test_the_summary_describes_what_is_about_to_be_posted() -> None:
    sets = [a_set(minute=i, reps=8, weight_kg=80.0) for i in range(3)]
    body, _ = build_workout("W", sets, CATALOGUE)
    assert summarise(body) == "1 exercise, 3 sets, 24 reps, 1,920 kg"


def test_the_summary_does_not_say_one_sets() -> None:
    body, _ = build_workout("W", [a_set(reps=1, weight_kg=None, exercise="Push Up")], CATALOGUE)
    assert summarise(body) == "1 exercise, 1 set, 1 rep, 0 kg"
