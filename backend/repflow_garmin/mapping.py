"""RepFlow's exercise vocabulary, mapped onto Garmin's enum by hand.

Fuzzy matching is good enough for a name nobody anticipated. It is not good
enough for the eighty movements RepFlow ships, because its failures are silent
and confident: left to itself the matcher files "Barbell Curl" as a barbell
*wrist* curl and "Dumbbell Press" as a shoulder press — both plausible strings,
both the wrong muscle group, and the muscle group is the whole point.

So the app's own vocabulary is curated here, and `catalogue.resolve` is only
consulted for names that arrive from somewhere else (a Hevy import, a custom
exercise). A test asserts that every catalogue name RepFlow ships has an entry
and that every entry is a pair Garmin actually accepts.

**Where a movement is approximated, it says so.** Garmin's enum has real gaps —
no pec deck, no skullcrusher, no triceps pushdown, no leg extension as a quad
machine. For those the category is kept and the variant is dropped: Garmin then
shows the category's own name, which is true, instead of a specific exercise
that is not the one performed.
"""

from __future__ import annotations

from .catalogue import _tokens, is_valid

#: RepFlow / Hevy name -> (category, exercise). `None` as the exercise means
#: "this muscle group, variant not established" — see the module docstring.
#:
#: Keys are matched on their **words**, not their spelling, so the equipment
#: suffix Hevy uses ("(DB)", "(Dumbbell)") and the 40-character truncation the
#: watch applies to a FIT string both resolve to the same entry.
RAW: dict[str, tuple[str, str | None]] = {
    # ---- Chest ----------------------------------------------------------
    "Bench Press": ("BENCH_PRESS", "BENCH_PRESS"),
    "Bench Press (Barbell)": ("BENCH_PRESS", "BARBELL_BENCH_PRESS"),
    "Incline Bench Press": ("BENCH_PRESS", "INCLINE_BARBELL_BENCH_PRESS"),
    "Incline Bench Press (DB)": ("BENCH_PRESS", "INCLINE_DUMBBELL_BENCH_PRESS"),
    "Incline DB Press": ("BENCH_PRESS", "INCLINE_DUMBBELL_BENCH_PRESS"),
    "Dumbbell Press": ("BENCH_PRESS", "DUMBBELL_BENCH_PRESS"),
    # Garmin has no barbell decline bench press, only the dumbbell one.
    "Decline Bench Press": ("BENCH_PRESS", None),
    "Chest Press (Machine)": ("BENCH_PRESS", None),
    "Cable Fly": ("FLYE", "FLYE"),
    "Chest Fly (Machine)": ("FLYE", "FLYE"),
    "Pec Deck": ("FLYE", "FLYE"),          # no pec deck in Garmin's enum
    "Push-Up": ("PUSH_UP", "PUSH_UP"),
    # Garmin files every dip under triceps extension, chest-focused or not.
    "Chest Dip": ("TRICEPS_EXTENSION", "BODY_WEIGHT_DIP"),

    # ---- Back -----------------------------------------------------------
    "Deadlift": ("DEADLIFT", "DEADLIFT"),
    "Pull-Up": ("PULL_UP", "PULL_UP"),
    "Chin-Up": ("PULL_UP", "CHIN_UP"),
    "Lat Pulldown": ("PULL_UP", "LAT_PULLDOWN"),
    "Lat Pulldown (Cable)": ("PULL_UP", "LAT_PULLDOWN"),
    "Seated Row": ("ROW", "SEATED_CABLE_ROW"),
    "Seated Row (Machine)": ("ROW", "SEATED_CABLE_ROW"),
    "Barbell Row": ("ROW", "BARBELL_ROW"),
    "Dumbbell Row": ("ROW", "DUMBBELL_ROW"),
    "T-Bar Row": ("ROW", "T_BAR_ROW"),
    "Face Pull": ("ROW", "FACE_PULL"),
    "Shrug": ("SHRUG", "SHRUG"),
    "Straight-Arm Pulldown": ("PULL_UP", "STRAIGHT_ARM_PULLDOWN"),
    "Iso-Lateral Low Row": ("ROW", None),   # a machine, not a Garmin variant

    # ---- Shoulders ------------------------------------------------------
    "Overhead Press": ("SHOULDER_PRESS", "OVERHEAD_BARBELL_PRESS"),
    "DB Shoulder Press": ("SHOULDER_PRESS", "DUMBBELL_SHOULDER_PRESS"),
    "Shoulder Press (Dumbbell)": ("SHOULDER_PRESS", "DUMBBELL_SHOULDER_PRESS"),
    "Arnold Press": ("SHOULDER_PRESS", "ARNOLD_PRESS"),
    "Arnold Press (Dumbbell)": ("SHOULDER_PRESS", "ARNOLD_PRESS"),
    "Lateral Raise": ("LATERAL_RAISE", "LATERAL_RAISE"),
    "Lateral Raise (Dumbbell)": ("LATERAL_RAISE", "DUMBBELL_LATERAL_RAISE"),
    "Cable Lateral Raise": ("LATERAL_RAISE", None),
    "Front Raise": ("LATERAL_RAISE", "FRONT_RAISE"),
    "Rear Delt Fly": ("FLYE", None),
    "Upright Row": ("SHRUG", "UPRIGHT_ROW"),

    # ---- Biceps ---------------------------------------------------------
    "Barbell Curl": ("CURL", "BARBELL_BICEPS_CURL"),
    "Bicep Curl (Barbell)": ("CURL", "BARBELL_BICEPS_CURL"),
    "Dumbbell Curl": ("CURL", "DUMBBELL_BICEPS_CURL"),
    "Bicep Curl (Dumbbell)": ("CURL", "DUMBBELL_BICEPS_CURL"),
    "Hammer Curl": ("CURL", "DUMBBELL_HAMMER_CURL"),
    "Hammer Curl (Dumbbell)": ("CURL", "DUMBBELL_HAMMER_CURL"),
    "Hammer Curl (Cable)": ("CURL", "CABLE_HAMMER_CURL"),
    "Preacher Curl": ("CURL", "EZ_BAR_PREACHER_CURL"),
    "Cable Curl": ("CURL", "CABLE_BICEPS_CURL"),
    "Concentration Curl": ("CURL", "ONE_ARM_CONCENTRATION_CURL"),
    "Incline DB Curl": ("CURL", "INCLINE_DUMBBELL_BICEPS_CURL"),

    # ---- Triceps --------------------------------------------------------
    # Garmin's enum has no pushdown and no skullcrusher at all.
    "Triceps Pushdown": ("TRICEPS_EXTENSION", None),
    "Rope Pushdown": ("TRICEPS_EXTENSION", None),
    "Triceps Rope Pushdown": ("TRICEPS_EXTENSION", None),
    "Skullcrusher": ("TRICEPS_EXTENSION", None),
    "Overhead Extension": ("TRICEPS_EXTENSION", None),
    "Triceps Extension (Cable)": ("TRICEPS_EXTENSION", None),
    "Triceps Extension (DB)": ("TRICEPS_EXTENSION", None),
    "Triceps Dip": ("TRICEPS_EXTENSION", "BODY_WEIGHT_DIP"),
    "Close-Grip Bench": ("BENCH_PRESS", "CLOSE_GRIP_BARBELL_BENCH_PRESS"),
    "Triceps Kickback": ("TRICEPS_EXTENSION", "DUMBBELL_KICKBACK"),
    "Cable Kickback": ("TRICEPS_EXTENSION", "CABLE_KICKBACK"),

    # ---- Legs -----------------------------------------------------------
    "Back Squat": ("SQUAT", "BARBELL_BACK_SQUAT"),
    "Front Squat": ("SQUAT", "BARBELL_FRONT_SQUAT"),
    "Hack Squat": ("SQUAT", "BARBELL_HACK_SQUAT"),
    "Goblet Squat": ("SQUAT", "GOBLET_SQUAT"),
    "Leg Press": ("SQUAT", "LEG_PRESS"),
    # Garmin has no quad-machine extension. SQUAT is the nearest category that
    # draws the quadriceps; the variant is deliberately not claimed.
    "Leg Extension": ("SQUAT", None),
    "Step-Up": ("SQUAT", "STEP_UP"),
    "Romanian Deadlift": ("DEADLIFT", "ROMANIAN_DEADLIFT"),
    "Stiff-Leg Deadlift": ("DEADLIFT", None),
    "Sumo Deadlift": ("DEADLIFT", "SUMO_DEADLIFT"),
    "Lying Leg Curl": ("LEG_CURL", "LEG_CURL"),
    "Seated Leg Curl": ("LEG_CURL", "LEG_CURL"),
    "Nordic Curl": ("LEG_CURL", None),
    "Good Morning": ("LEG_CURL", "GOOD_MORNING"),
    "Walking Lunge": ("LUNGE", "WALKING_LUNGE"),
    # Only equipment-specific Bulgarian split squats exist in the enum.
    "Bulgarian Split Squat": ("LUNGE", None),
    "Hip Thrust": ("HIP_RAISE", "BARBELL_HIP_THRUST_WITH_BENCH"),
    "Glute Bridge": ("HIP_RAISE", None),
    "Hip Abduction": ("HIP_STABILITY", None),
    "Hip Adduction": ("HIP_STABILITY", None),

    # ---- Calves ---------------------------------------------------------
    "Standing Calf Raise": ("CALF_RAISE", "STANDING_CALF_RAISE"),
    "Seated Calf Raise": ("CALF_RAISE", "SEATED_CALF_RAISE"),
    "Single-Leg Calf Raise": ("CALF_RAISE", None),
    "Calf Press": ("CALF_RAISE", None),

    # ---- Core -----------------------------------------------------------
    "Plank": ("PLANK", "PLANK"),
    "Side Plank": ("PLANK", "SIDE_PLANK"),
    "Hanging Leg Raise": ("LEG_RAISE", "HANGING_LEG_RAISE"),
    "Cable Crunch": ("CRUNCH", "CABLE_CRUNCH"),
    "Russian Twist": ("CORE", "RUSSIAN_TWIST"),
    "Ab Wheel": ("CORE", "KNEELING_AB_WHEEL"),
    "Weighted Sit-Up": ("SIT_UP", "WEIGHTED_SIT_UP"),
    "Back Extension": ("HYPEREXTENSION", "HYPEREXTENSION"),
    "Pallof Press": ("CORE", None),         # anti-rotation, no Garmin variant
}


def _build() -> dict[tuple[str, ...], tuple[str, str | None]]:
    """Index the table by words, and refuse to build a contradictory one.

    Two spellings of the same movement are meant to collapse onto one entry —
    that is the point of indexing by words. Two spellings that collapse onto
    *different* answers is a mistake in the table, and it would otherwise be
    resolved silently by whichever line happened to come last.
    """
    index: dict[tuple[str, ...], tuple[str, str | None]] = {}
    for name, target in RAW.items():
        key = tuple(sorted(set(_tokens(name))))
        existing = index.get(key)
        if existing is not None and existing != target:
            raise ValueError(
                f"{name!r} collides with an earlier entry on {key}: "
                f"{existing} vs {target}"
            )
        index[key] = target
    return index


_INDEX = _build()


#: Words that name a piece of equipment rather than a movement.
#:
#: Hevy suffixes many movements with theirs — "Leg Extension (Machine)" — and a
#: curated entry written without the suffix misses, because the entries are
#: indexed by their words. The fallback below drops these and tries again.
EQUIPMENT_WORDS = frozenset({
    "machine", "cable", "dumbbell", "barbell", "smith", "kettlebell",
    "band", "bodyweight", "plate", "ez_bar", "ezbar", "sled",
})


def lookup(name: str) -> tuple[str, str | None] | None:
    """The curated answer for `name`, or None to fall through to matching.

    Tried twice: once on the name as given, and once with the equipment words
    removed. Order matters and is the whole safety of it — "Bicep Curl
    (Barbell)" and "Bicep Curl (Dumbbell)" are different entries with different
    answers, and they match on the first pass, so the second never sees them.
    The second pass only catches names whose equipment the table does not
    distinguish, which is exactly where it should apply.

    Without it "Leg Extension (Machine)" missed its entry and the matcher filed
    it under HIP_RAISE — a glute movement, drawn on the wrong half of the muscle
    map, and silent. Found against the athlete's real routines, not imagined.
    """
    words = set(_tokens(name))
    exact = _INDEX.get(tuple(sorted(words)))
    if exact is not None:
        return exact
    bare = words - EQUIPMENT_WORDS
    if bare and bare != words:
        return _INDEX.get(tuple(sorted(bare)))
    return None


def resolve(name: str) -> tuple[str, str | None] | None:
    """Resolve any exercise name to a `(category, exercise)` Garmin accepts.

    Curated first, matched second, and validated last: a pair that Garmin's enum
    does not contain is degraded to its category rather than sent and rejected,
    because a 400 loses the whole session's table, not one row.
    """
    from .catalogue import resolve as match

    answer = lookup(name)
    if answer is None:
        answer = match(name)
    if answer is None:
        return None

    category, exercise = answer
    if is_valid(category, exercise):
        return answer
    if is_valid(category, None):
        return (category, None)
    return None
