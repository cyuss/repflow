"""Garmin's strength exercise enum, and the name matching that reaches it.

Garmin validates an exercise set against its own enum and rejects anything else
with a 400 "Invalid Sub-Category Passed". So every RepFlow name has to be
resolved to a `(category, exercise)` pair Garmin already knows, and the
resolution has to be conservative: **category is what draws the muscle map**, and
a set filed under the wrong category is worse than one filed under no variant at
all.

That gives the matcher its shape. It tries to name the exact variant, and when
it cannot do so confidently it falls back to the category with `name=None` —
which Garmin accepts — rather than guessing between two plausible variants. A
wrong guess is silent; a missing variant is visible in the table and still lands
in the right muscle group.
"""

from __future__ import annotations

import json
import pathlib
from dataclasses import dataclass
from functools import lru_cache

_DATA = pathlib.Path(__file__).resolve().parent / "data" / "garmin_exercises.json"

#: Gym shorthand, and the words Garmin actually spells out. Applied token by
#: token before matching, so "Incline DB Press" and "Incline Dumbbell Press"
#: become the same query.
SYNONYMS: dict[str, str] = {
    "db": "dumbbell",
    "dbs": "dumbbell",
    "bb": "barbell",
    "kb": "kettlebell",
    "ez": "ez_bar",
    "bw": "bodyweight",
    "pulldown": "pull_down",
    "pushdown": "push_down",
    "pullup": "pull_up",
    "pushup": "push_up",
    "chinup": "chin_up",
    "situp": "sit_up",
    "tricep": "triceps",
    "bicep": "biceps",
    "abs": "abdominal",
    "ab": "abdominal",
    "delt": "deltoid",
    "delts": "deltoid",
    "lats": "lat",
    "quad": "quadriceps",
    "quads": "quadriceps",
    "ham": "hamstring",
    "hams": "hamstring",
    "glute": "glutes",
    "machine": "machine",
    "cable": "cable",
    "smith": "smith_machine",
    "rdl": "romanian_deadlift",
    "ohp": "overhead_press",
}

#: Words that say nothing about which movement this is. Dropping them stops
#: "Seated Row (Machine)" and "Seated Cable Row" from being separated by the
#: word "seated" alone.
_NOISE = frozenset({"the", "a", "with", "and", "of", "on", "in", "to"})


def _tokens(name: str) -> tuple[str, ...]:
    """A name reduced to comparable words.

    Parentheses carry equipment in both vocabularies — RepFlow writes "Lat
    Pulldown (Cable)", Garmin writes "Cable Lat Pulldown" — so they are opened
    rather than stripped, and word order is discarded by comparing sets.
    """
    cleaned = []
    for raw in name.lower().replace("(", " ").replace(")", " ").replace("/", " ").split():
        word = "".join(ch for ch in raw if ch.isalnum() or ch == "-")
        word = word.replace("-", "")
        if not word or word in _NOISE:
            continue
        mapped = SYNONYMS.get(word, word)
        cleaned.extend(mapped.split("_"))
    return tuple(cleaned)


@dataclass(frozen=True)
class Movement:
    """One row of Garmin's enum."""

    display: str
    category: str
    exercise: str | None

    @property
    def tokens(self) -> tuple[str, ...]:
        return _tokens(self.display)


@lru_cache(maxsize=1)
def catalogue() -> tuple[Movement, ...]:
    raw = json.loads(_DATA.read_text())
    return tuple(
        Movement(display=display, category=category, exercise=exercise or None)
        for display, category, exercise in raw["exercises"]
    )


@lru_cache(maxsize=1)
def categories() -> frozenset[str]:
    return frozenset(m.category for m in catalogue())


@lru_cache(maxsize=1)
def _display_names() -> dict[tuple[str, str | None], str]:
    return {(m.category, m.exercise): m.display for m in catalogue()}


def display_name(category: str, exercise: str | None) -> str:
    """The name Garmin Connect will show for this pair.

    The only form of the answer an athlete can check against the movement they
    actually performed — `PULL_UP / LAT_PULLDOWN` tells them nothing, "Lat
    Pull-down" tells them everything. A category with no named variant falls
    back to the category's own words, which is exactly what Garmin displays.
    """
    named = _display_names().get((category, exercise))
    if named is not None:
        return named
    return category.replace("_", " ").title()


@lru_cache(maxsize=1)
def _pairs() -> frozenset[tuple[str, str | None]]:
    return frozenset((m.category, m.exercise) for m in catalogue())


def is_valid(category: str, exercise: str | None) -> bool:
    """Is this a pair Garmin will accept?

    The `exercise` half of the enum is **not unique**: 27 of them appear under
    more than one category — FACE_PULL is both a ROW and a SUSPENSION exercise,
    PLANK is three different things. So a pair has to be checked as a pair.
    Validating the halves separately is how a face pull ends up filed as
    suspension training, and the muscle map is drawn from the category.

    `exercise=None` is accepted under any known category: Garmin renders it as
    the category's own name, which is the honest way to say "this muscle group,
    variant not established".
    """
    if exercise is None:
        return category in categories()
    return (category, exercise) in _pairs()


#: Categories that describe a **piece of equipment** rather than a movement.
#: Garmin files "the banded version of X" under BANDED_EXERCISES, not under X,
#: so these categories are full of movement names that would otherwise be the
#: best token match — "Back Extension" matches "Banded Back Extension" on every
#: word it has. Letting that win puts a hyperextension in the resistance-band
#: group and draws the wrong muscles. They are only reachable when the query
#: actually names the equipment.
EQUIPMENT_CATEGORIES: dict[str, frozenset[str]] = {
    "BANDED_EXERCISES": frozenset({"banded", "band", "bands"}),
    "SUSPENSION": frozenset({"suspension", "suspended", "trx", "ring", "rings"}),
    "SLED": frozenset({"sled", "prowler"}),
    "SANDBAG": frozenset({"sandbag"}),
    "BATTLE_ROPE": frozenset({"battle", "rope"}),
    "TIRE": frozenset({"tire", "tyre"}),
    "SLEDGE_HAMMER": frozenset({"sledge", "sledgehammer"}),
    "WARM_UP": frozenset({"warm", "warmup", "stretch"}),
}


@lru_cache(maxsize=1)
def _indexed() -> tuple[tuple[frozenset[str], Movement], ...]:
    return tuple((frozenset(m.tokens), m) for m in catalogue())


def score(query: frozenset[str], candidate: frozenset[str]) -> float:
    """How well two token sets match, from 0.0 to 1.0.

    Jaccard overlap, with an exact set match pinned to 1.0 so that "Bench Press
    (Barbell)" resolving onto "Barbell Bench Press" is never beaten by a longer
    name that happens to contain more of the query's words.
    """
    if not query or not candidate:
        return 0.0
    if query == candidate:
        return 1.0
    intersection = len(query & candidate)
    if not intersection:
        return 0.0
    return intersection / len(query | candidate)


#: Below this, the variant is not named and only the category is sent. Chosen
#: from the sweep in tests/test_catalogue.py over every name RepFlow ships:
#: at 0.60 every confident match is a correct one, and the rest degrade to a
#: category rather than to a wrong exercise.
CONFIDENT = 0.60


def resolve(name: str, overrides: dict[str, tuple[str, str | None]] | None = None) -> tuple[str, str | None] | None:
    """Resolve a RepFlow exercise name to Garmin's `(category, exercise)`.

    Returns None when nothing in Garmin's enum is recognisably the same
    movement, which is the caller's cue to drop the set rather than file it
    somewhere wrong.
    """
    if overrides:
        fixed = overrides.get(name) or overrides.get(name.strip().lower())
        if fixed is not None:
            return fixed

    query = frozenset(_tokens(name))
    if not query:
        return None

    best: Movement | None = None
    best_score = 0.0
    for tokens, movement in _indexed():
        gate = EQUIPMENT_CATEGORIES.get(movement.category)
        if gate is not None and not (query & gate):
            continue
        s = score(query, tokens)
        # Ties go to the shorter Garmin name: it is the more general variant,
        # and generality is the safer error here.
        if s > best_score or (s == best_score and best is not None and len(movement.display) < len(best.display)):
            best, best_score = movement, s

    if best is None or best_score == 0.0:
        return None
    if best_score < CONFIDENT:
        # Recognisable muscle group, unconvincing variant: keep the category,
        # drop the claim about which variant it was.
        return (best.category, None)
    return (best.category, best.exercise)
