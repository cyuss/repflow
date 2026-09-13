"""The watch app and this package have to agree, and they are different languages.

Three files describe the same seven developer FIT fields:

    source/GarminRecorder.mc        writes them
    resources/fit_contributions.xml tells Garmin Connect to display them
    repflow_garmin/fitread.py       reads them back

Nothing but these tests connects the three. A field renamed in Monkey C compiles
cleanly, uploads cleanly, displays cleanly — and silently stops being readable
here, which turns "fill in the table" into "this is not a RepFlow activity".
"""

from __future__ import annotations

import pathlib
import re

import pytest

from repflow_garmin import fitread

ROOT = pathlib.Path(__file__).resolve().parents[2]
RECORDER = (ROOT / "source" / "GarminRecorder.mc").read_text()
CONTRIBUTIONS = (ROOT / "resources" / "fit_contributions.xml").read_text()

#: name -> field number, as declared in GarminRecorder.mc.
LAP_FIELDS = {
    "exercise": 10,
    "set": 11,
    "reps": 12,
    "weight": 13,
    "rest": 14,
    "rpe": 15,
}


def created_fields() -> dict[str, int]:
    """Every `createField("name", NUMBER, ...)` in the recorder, resolved."""
    constants = {
        name: int(value)
        for name, value in re.findall(r"const\s+(FIELD_[A-Z_]+)\s*=\s*(\d+)", RECORDER)
    }
    found = {}
    for name, symbol in re.findall(r'createField\(\s*"([a-z_]+)",\s*(FIELD_[A-Z_]+)', RECORDER):
        assert symbol in constants, f"createField uses {symbol}, which is not a const here"
        found[name] = constants[symbol]
    return found


@pytest.mark.parametrize("name,number", sorted(LAP_FIELDS.items()))
def test_the_watch_writes_the_field_this_package_reads(name: str, number: int) -> None:
    assert created_fields().get(name) == number


@pytest.mark.parametrize("name", sorted(LAP_FIELDS))
def test_the_reader_names_match_the_watch(name: str) -> None:
    readable = {
        fitread.FIELD_EXERCISE,
        fitread.FIELD_SET,
        fitread.FIELD_REPS,
        fitread.FIELD_WEIGHT,
        fitread.FIELD_REST,
        fitread.FIELD_RPE,
    }
    assert name in readable


@pytest.mark.parametrize("number", sorted(LAP_FIELDS.values()))
def test_every_lap_field_is_declared_for_garmin_connect(number: int) -> None:
    """Without a <fitField> entry Garmin Connect renders nothing.

    RepFlow shipped once without this block and every developer field was
    invisible. The file was correct; nothing had been asked to draw it.
    """
    assert re.search(rf'<fitField id="{number}"', CONTRIBUTIONS), (
        f"field {number} is written by the watch but not declared in "
        f"resources/fit_contributions.xml"
    )


def test_the_exercise_name_cap_is_long_enough_for_the_names_we_ship() -> None:
    """A truncated name is a mis-identified exercise on this side."""
    cap = int(re.search(r"EXERCISE_NAME_MAX\s*=\s*(\d+)", RECORDER).group(1))
    longest = max(
        (name for name in _shipped_names()),
        key=len,
    )
    assert len(longest) <= cap, f"{longest!r} is {len(longest)} characters, cap is {cap}"


def _shipped_names() -> list[str]:
    names: list[str] = []
    for filename in ("ExerciseCatalogue.mc", "WorkoutRepository.mc"):
        text = (ROOT / "source" / filename).read_text()
        names += re.findall(r'\[\s*"[a-z0-9_]+",\s*"([^"]+)"', text)
    return names
