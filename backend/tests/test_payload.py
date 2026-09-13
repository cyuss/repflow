"""What gets sent to Garmin, decided without an account.

Every mistake this file guards against is one that looks fine in the code and
wrong in the app: a load 1000x off, a bodyweight set claiming zero kilos, a
session shifted by the operator's timezone, rest counted as work.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from repflow_garmin.model import LoggedSet
from repflow_garmin.payload import GRAMS_PER_KG, build, format_time, summarise

T0 = datetime(2026, 9, 13, 12, 7, 0, tzinfo=timezone.utc)


def a_set(**overrides) -> LoggedSet:
    base = dict(
        exercise="Bench Press",
        set_number=1,
        reps=8,
        weight_kg=80.0,
        start_time=T0,
        duration_s=90.0,
        rest_s=None,
    )
    base.update(overrides)
    return LoggedSet(**base)


def active(payload) -> list:
    return [e for e in payload["exerciseSets"] if e["setType"] == "ACTIVE"]


class TestTheLoad:
    def test_kilograms_are_sent_as_grams(self) -> None:
        payload, _ = build(1, [a_set(weight_kg=80.0)])
        assert active(payload)[0]["weight"] == 80.0 * GRAMS_PER_KG

    def test_a_bodyweight_set_has_no_weight_rather_than_zero(self) -> None:
        # 0.0 would render as "0 kg", a claim about the lift. None renders blank.
        payload, _ = build(1, [a_set(exercise="Push-Up", weight_kg=None)])
        assert active(payload)[0]["weight"] is None

    def test_a_half_kilo_survives_the_conversion(self) -> None:
        payload, _ = build(1, [a_set(weight_kg=22.5)])
        assert active(payload)[0]["weight"] == 22500.0


class TestTheTimestamps:
    def test_the_shape_is_the_one_garmin_sends(self) -> None:
        assert format_time(T0) == "2026-09-13T12:07:00.0"

    def test_an_aware_time_is_converted_to_utc_not_truncated(self) -> None:
        paris = timezone(timedelta(hours=2))
        assert format_time(datetime(2026, 9, 13, 14, 7, tzinfo=paris)) == "2026-09-13T12:07:00.0"

    def test_a_naive_time_is_treated_as_utc(self) -> None:
        # Not as the operator's local time, which would shift every set by
        # however far from Greenwich the laptop happens to be.
        assert format_time(datetime(2026, 9, 13, 12, 7)) == "2026-09-13T12:07:00.0"


class TestRestAndWork:
    def test_a_recorded_rest_is_emitted_as_its_own_interval(self) -> None:
        payload, _ = build(1, [a_set(duration_s=90.0, rest_s=60.0)])
        kinds = [e["setType"] for e in payload["exerciseSets"]]
        assert kinds == ["REST", "ACTIVE"]

    def test_the_set_is_only_the_part_that_was_not_rest(self) -> None:
        payload, _ = build(1, [a_set(duration_s=90.0, rest_s=60.0)])
        rest, work = payload["exerciseSets"]
        assert (rest["duration"], work["duration"]) == (60.0, 30.0)

    def test_the_set_starts_when_the_rest_ends(self) -> None:
        payload, _ = build(1, [a_set(duration_s=90.0, rest_s=60.0)])
        assert payload["exerciseSets"][1]["startTime"] == "2026-09-13T12:08:00.0"

    def test_a_rest_interval_carries_no_exercise_reps_or_load(self) -> None:
        payload, _ = build(1, [a_set(rest_s=60.0)])
        rest = payload["exerciseSets"][0]
        assert rest["exercises"] == []
        assert rest["repetitionCount"] is None and rest["weight"] is None

    def test_without_a_recorded_rest_the_lap_is_one_working_set(self) -> None:
        # An overstatement of work time, but it invents nothing. Watches running
        # a build older than the `rest` developer field land here.
        payload, _ = build(1, [a_set(duration_s=90.0, rest_s=None)])
        assert [e["setType"] for e in payload["exerciseSets"]] == ["ACTIVE"]
        assert payload["exerciseSets"][0]["duration"] == 90.0

    def test_a_zero_rest_does_not_produce_an_empty_interval(self) -> None:
        payload, _ = build(1, [a_set(rest_s=0.0)])
        assert [e["setType"] for e in payload["exerciseSets"]] == ["ACTIVE"]


class TestOrderingAndIdentity:
    def test_sets_are_emitted_in_time_order_whatever_order_they_arrive_in(self) -> None:
        # RepFlow's entire premise is that the athlete jumps between exercises,
        # so the laps are not grouped by movement and must not be assumed to be.
        late = a_set(exercise="Lat Pulldown", start_time=T0 + timedelta(minutes=5))
        early = a_set(start_time=T0)
        payload, _ = build(1, [late, early])
        assert [e["startTime"] for e in active(payload)] == [
            "2026-09-13T12:07:00.0",
            "2026-09-13T12:12:00.0",
        ]

    def test_the_exercise_is_asserted_with_full_confidence(self) -> None:
        # Garmin's own detection guesses and sends a distribution. The athlete
        # chose this by name; there is nothing to hedge.
        payload, _ = build(1, [a_set()])
        assert active(payload)[0]["exercises"] == [
            {"category": "BENCH_PRESS", "name": "BENCH_PRESS", "probability": 100.0}
        ]

    def test_the_activity_id_is_an_integer(self) -> None:
        payload, _ = build("21491", [a_set()])
        assert payload["activityId"] == 21491


class TestWhatCannotBeMapped:
    def test_an_unmappable_exercise_is_reported_not_guessed(self) -> None:
        payload, unmapped = build(1, [a_set(exercise="qqqq zzzz")])
        assert unmapped == ["qqqq zzzz"]
        assert payload["exerciseSets"] == []

    def test_it_is_reported_once_however_many_sets_it_had(self) -> None:
        sets = [a_set(exercise="qqqq zzzz", start_time=T0 + timedelta(minutes=i)) for i in range(3)]
        _, unmapped = build(1, sets)
        assert unmapped == ["qqqq zzzz"]

    def test_the_rest_of_the_session_still_goes_through(self) -> None:
        payload, unmapped = build(
            1, [a_set(), a_set(exercise="qqqq zzzz", start_time=T0 + timedelta(minutes=2))]
        )
        assert len(active(payload)) == 1 and unmapped


def test_the_summary_counts_what_is_in_the_payload() -> None:
    # It is printed immediately before a replace-all with no undo, so it has to
    # describe the payload rather than the caller's intentions.
    sets = [
        a_set(start_time=T0 + timedelta(minutes=2 * i), reps=8, weight_kg=80.0, rest_s=60.0)
        for i in range(3)
    ]
    payload, _ = build(1, sets)
    assert summarise(payload["exerciseSets"]) == "3 sets, 24 reps, 1,920 kg of volume, 3 rest intervals"


def test_a_rest_longer_than_its_own_lap_is_clamped() -> None:
    # Clock artefact: the two intervals must still fit inside the lap Garmin has.
    payload, _ = build(1, [a_set(duration_s=60.0, rest_s=900.0)])
    rest, work = payload["exerciseSets"]
    assert rest["duration"] == 60.0 and work["duration"] == 0.0
    assert work["repetitionCount"] == 8   # the reps happened regardless
