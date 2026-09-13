"""The mapping is the part that can be wrong without anything looking wrong.

A bad `(category, exercise)` pair is rejected loudly by Garmin. A *plausible but
incorrect* one is accepted silently and draws the wrong muscles, which is the
failure this file exists to prevent.
"""

from __future__ import annotations

import pathlib
import re

import pytest

from repflow_garmin.catalogue import _tokens, is_valid
from repflow_garmin.mapping import RAW, lookup, resolve

SOURCE = pathlib.Path(__file__).resolve().parents[2] / "source"


def shipped_exercise_names() -> list[str]:
    """Every movement RepFlow puts in front of the athlete.

    Read out of the Monkey C source rather than duplicated here, so adding an
    exercise to the watch app makes this file fail until it is mapped.
    """
    names: list[str] = []
    catalogue = (SOURCE / "ExerciseCatalogue.mc").read_text()
    names += re.findall(r'\[\s*"[a-z0-9_]+",\s*"([^"]+)"', catalogue)
    routines = (SOURCE / "WorkoutRepository.mc").read_text()
    names += re.findall(r'\[\s*"[a-z0-9_]+",\s*"([^"]+)"', routines)
    assert len(names) > 70, "the catalogue scrape found almost nothing; did the format change?"
    return sorted(set(names))


@pytest.mark.parametrize("name", shipped_exercise_names())
def test_every_shipped_exercise_is_curated(name: str) -> None:
    """Fuzzy matching is not good enough for RepFlow's own vocabulary."""
    assert lookup(name) is not None, (
        f"{name!r} has no entry in mapping.RAW. Add one — leaving it to the "
        f"matcher risks a silently wrong muscle group."
    )


@pytest.mark.parametrize("name,target", sorted(RAW.items()))
def test_every_curated_pair_exists_in_garmins_enum(name: str, target: tuple) -> None:
    category, exercise = target
    assert is_valid(category, exercise), (
        f"{name!r} maps to {category}/{exercise}, which Garmin's enum does not "
        f"contain as a pair. It would be rejected with 400 Invalid Sub-Category."
    )


def test_the_table_has_no_contradictions() -> None:
    """Two spellings of one movement must not disagree.

    `mapping._build` raises on import if they do; this states the property so
    the reason is findable when it fires.
    """
    seen: dict[tuple, tuple] = {}
    for name, target in RAW.items():
        key = tuple(sorted(set(_tokens(name))))
        assert seen.setdefault(key, target) == target, f"{name!r} contradicts an earlier entry"


class TestTheMatcherUsedToGetTheseWrong:
    """Regressions, each one observed before the curated table existed."""

    def test_barbell_curl_is_a_biceps_curl_not_a_wrist_curl(self) -> None:
        assert resolve("Barbell Curl") == ("CURL", "BARBELL_BICEPS_CURL")

    def test_dumbbell_press_is_a_chest_press_not_a_shoulder_press(self) -> None:
        assert resolve("Dumbbell Press") == ("BENCH_PRESS", "DUMBBELL_BENCH_PRESS")

    def test_back_extension_is_not_filed_under_resistance_bands(self) -> None:
        category, _ = resolve("Back Extension")
        assert category == "HYPEREXTENSION"

    def test_a_face_pull_is_a_row_not_suspension_training(self) -> None:
        # FACE_PULL exists under both ROW and SUSPENSION; the pair has to win.
        assert resolve("Face Pull") == ("ROW", "FACE_PULL")

    def test_triceps_pushdown_is_not_a_push_up(self) -> None:
        category, _ = resolve("Triceps Pushdown")
        assert category == "TRICEPS_EXTENSION"


class TestNamesThatArriveFromElsewhere:
    """Hevy imports and custom exercises never see the curated table."""

    def test_equipment_in_parentheses_matches_garmins_word_order(self) -> None:
        assert resolve("Bench Press (Barbell)") == ("BENCH_PRESS", "BARBELL_BENCH_PRESS")

    def test_gym_shorthand_is_expanded(self) -> None:
        assert resolve("Incline DB Press") == resolve("Incline Dumbbell Press")

    def test_a_name_truncated_by_the_watch_still_resolves(self) -> None:
        # The FIT string field has a fixed size; a lost closing bracket must
        # not cost the exercise. See GarminRecorder.EXERCISE_NAME_MAX.
        assert resolve("Shoulder Press (Dumbbell") == resolve("Shoulder Press (Dumbbell)")

    def test_an_unknown_movement_keeps_its_muscle_group(self) -> None:
        category, _ = resolve("Kettlebell Windmill")
        assert category in {"CORE", "TOTAL_BODY", "SHOULDER_STABILITY"}

    def test_nonsense_resolves_to_nothing_rather_than_to_something(self) -> None:
        assert resolve("qqqq zzzz") is None


class TestWhatTheAthleteIsShownBeforeWriting:
    """`show` has to print the mapping in a form a person can check.

    A rejected pair is loud. A plausible but wrong one is silent, and the
    category draws the muscle map — so the check has to happen here or nowhere.
    """

    def test_a_named_variant_is_shown_by_garmins_own_words(self) -> None:
        from repflow_garmin.catalogue import display_name

        assert display_name("PULL_UP", "LAT_PULLDOWN") == "Lat Pull-down"

    def test_a_category_without_a_variant_reads_as_the_category(self) -> None:
        # This is what Garmin Connect itself displays for name=None.
        from repflow_garmin.catalogue import display_name

        assert display_name("TRICEPS_EXTENSION", None) == "Triceps Extension"

    def test_the_report_distinguishes_curated_from_matched(self, capsys) -> None:
        from datetime import datetime, timezone

        from repflow_garmin.cli import _print_mapping
        from repflow_garmin.model import LoggedSet

        moment = datetime(2026, 9, 13, 12, 7, tzinfo=timezone.utc)
        _print_mapping(
            [
                LoggedSet("Bench Press", 1, 8, 80.0, moment, 60.0),
                LoggedSet("Kettlebell Windmill", 1, 8, 12.0, moment, 60.0),
            ]
        )
        printed = capsys.readouterr().out
        assert "Bench Press" in printed and "(curated)" in printed
        assert "Kettlebell Windmill" in printed and "(matched)" in printed


class TestChoosingWhichActivity:
    """Picking the wrong activity writes someone's sets onto another session."""

    def test_the_newest_is_chosen_whatever_order_garmin_sends(self) -> None:
        # Garmin's listing is documented as newest-first and was not: a run of
        # this tool picked the session from the day before the one just
        # recorded. The order is established here instead of trusted.
        from repflow_garmin.garmin import ActivitySummary

        rows = [
            {
                "activityId": 1,
                "activityName": "Yesterday",
                "startTimeLocal": "2026-09-12 13:02:46",
                "beginTimestamp": 1_757_681_000_000,
                "activityType": {"typeKey": "strength_training"},
            },
            {
                "activityId": 2,
                "activityName": "Today",
                "startTimeLocal": "2026-09-13 12:07:56",
                "beginTimestamp": 1_757_767_000_000,
                "activityType": {"typeKey": "strength_training"},
            },
        ]
        parsed = [ActivitySummary.parse(r) for r in rows]
        parsed.sort(key=lambda a: a.sort_key, reverse=True)
        assert [a.activity_id for a in parsed] == [2, 1]

    def test_an_activity_with_no_timestamp_sorts_last_not_first(self) -> None:
        from repflow_garmin.garmin import ActivitySummary

        dated = ActivitySummary.parse(
            {
                "activityId": 1,
                "startTimeLocal": "2026-09-13 12:07:56",
                "beginTimestamp": 1_757_767_000_000,
                "activityType": {"typeKey": "strength_training"},
            }
        )
        undated = ActivitySummary.parse(
            {"activityId": 2, "activityType": {"typeKey": "strength_training"}}
        )
        assert max(dated.sort_key, undated.sort_key) == dated.sort_key
