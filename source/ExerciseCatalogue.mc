import Toybox.Lang;

//! The movements RepFlow knows about, grouped by muscle.
//!
//! Eighty-two entries, enough that an unplanned exercise is almost always in
//! here, and small enough to keep in the code section of a 128 KB watch app.
//!
//! **Memory shape matters more than the count.** Each group is built only when
//! the athlete opens it, as an array of flat arrays of primitives:
//!
//!     [id, name, targetReps, defaultWeightKg, restSeconds]
//!
//! Nothing becomes an `Exercise` object until one is actually chosen. Holding
//! all eighty as objects would cost more memory than the running workout.
//!
//! Names are in English because that is the vocabulary of a gym floor almost
//! everywhere — a French lifter says "bench press" and "curl". Translating them
//! would make the catalogue harder to search, not easier.
//!
//! Default loads are a starting point for an average trainee, not a
//! prescription. They are inherited forward from the athlete's own last set the
//! moment one is performed, so a wrong default costs exactly one correction.
module ExerciseCatalogue {

    //! Index of the fields in a catalogue row.
    const F_ID = 0;
    const F_NAME = 1;
    const F_REPS = 2;
    const F_WEIGHT = 3;
    const F_REST = 4;

    //! The rows for one muscle group. Built on demand; never cached.
    public function forMuscle(group as Number) as Array {
        switch (group) {
            case Muscle.CHEST:      return _chest();
            case Muscle.BACK:       return _back();
            case Muscle.SHOULDERS:  return _shoulders();
            case Muscle.BICEPS:     return _biceps();
            case Muscle.TRICEPS:    return _triceps();
            case Muscle.QUADS:      return _quads();
            case Muscle.HAMSTRINGS: return _hamstrings();
            case Muscle.GLUTES:     return _glutes();
            case Muscle.CALVES:     return _calves();
            case Muscle.CORE:       return _core();
            default:                return [] as Array;
        }
    }

    //! Turn a catalogue row into a fresh exercise for this session.
    //!
    //! The id is suffixed so the same movement can appear twice in one workout
    //! — a second round of curls at the end is an ordinary thing to want — while
    //! `catalogueId` keeps pointing at the movement, which is what history and
    //! records are keyed by.
    public function toExercise(row as Array, group as Number, sets as Number, suffix as Number) as Exercise {
        var id = (row[F_ID] as String);
        var uniqueId = suffix > 0 ? id + "#" + suffix.toString() : id;
        var ex = new Exercise(
            uniqueId,
            row[F_NAME] as String,
            sets,
            row[F_REPS] as Number,
            (row[F_WEIGHT] as Number).toFloat(),
            row[F_REST] as Number
        );
        ex.muscle = group;
        return ex;
    }

    //! The movement an exercise id refers to, with any "#2" suffix removed.
    public function movementId(exerciseId as String) as String {
        var cut = exerciseId.find("#");
        if (cut == null) {
            return exerciseId;
        }
        var base = exerciseId.substring(0, cut);
        return base == null ? exerciseId : base;
    }

    // ------------------------------------------------------------------
    // The catalogue itself.
    // ------------------------------------------------------------------

    function _chest() as Array {
        return [
            ["c_bench", "Bench Press", 8, 60, 150],
            ["c_incline_bb", "Incline Bench Press", 8, 50, 150],
            ["c_db_press", "Dumbbell Press", 10, 24, 120],
            ["c_incline_db", "Incline DB Press", 10, 22, 120],
            ["c_cable_fly", "Cable Fly", 12, 15, 60],
            ["c_pec_deck", "Pec Deck", 12, 40, 60],
            ["c_dip", "Chest Dip", 10, 0, 120],
            ["c_pushup", "Push-Up", 15, 0, 60],
            ["c_decline", "Decline Bench Press", 8, 55, 150],
            ["c_chest_press", "Chest Press (Machine)", 10, 40, 90]
        ] as Array;
    }

    function _back() as Array {
        return [
            ["b_deadlift", "Deadlift", 5, 100, 210],
            ["b_pullup", "Pull-Up", 8, 0, 150],
            ["b_chinup", "Chin-Up", 8, 0, 150],
            ["b_lat_pulldown", "Lat Pulldown", 10, 55, 90],
            ["b_seated_row", "Seated Row", 10, 60, 90],
            ["b_bb_row", "Barbell Row", 8, 60, 120],
            ["b_db_row", "Dumbbell Row", 10, 28, 90],
            ["b_tbar_row", "T-Bar Row", 10, 45, 120],
            ["b_face_pull", "Face Pull", 15, 25, 60],
            ["b_shrug", "Shrug", 12, 60, 60],
            ["b_pullover", "Straight-Arm Pulldown", 12, 30, 60],
            ["b_iso_low_row", "Iso-Lateral Low Row", 10, 30, 90]
        ] as Array;
    }

    function _shoulders() as Array {
        return [
            ["s_ohp", "Overhead Press", 8, 40, 150],
            ["s_db_press", "DB Shoulder Press", 10, 18, 120],
            ["s_arnold", "Arnold Press", 10, 16, 120],
            ["s_lateral", "Lateral Raise", 15, 8, 60],
            ["s_front", "Front Raise", 12, 8, 60],
            ["s_rear_delt", "Rear Delt Fly", 15, 8, 60],
            ["s_upright_row", "Upright Row", 12, 30, 60],
            ["s_cable_lateral", "Cable Lateral Raise", 15, 7, 60]
        ] as Array;
    }

    function _biceps() as Array {
        return [
            ["bi_bb_curl", "Barbell Curl", 10, 30, 60],
            ["bi_db_curl", "Dumbbell Curl", 12, 12, 60],
            ["bi_hammer", "Hammer Curl", 12, 14, 60],
            ["bi_preacher", "Preacher Curl", 10, 25, 60],
            ["bi_incline", "Incline DB Curl", 12, 10, 60],
            ["bi_cable", "Cable Curl", 12, 25, 60],
            ["bi_concentration", "Concentration Curl", 12, 10, 45],
            ["bi_hammer_cable", "Hammer Curl (Cable)", 10, 20, 75]
        ] as Array;
    }

    function _triceps() as Array {
        return [
            ["tr_pushdown", "Triceps Pushdown", 12, 30, 60],
            ["tr_rope", "Rope Pushdown", 15, 25, 60],
            ["tr_skullcrusher", "Skullcrusher", 10, 25, 90],
            ["tr_overhead", "Overhead Extension", 12, 20, 60],
            ["tr_close_bench", "Close-Grip Bench", 8, 50, 120],
            ["tr_dip", "Triceps Dip", 12, 0, 90],
            ["tr_kickback", "Triceps Kickback", 15, 8, 45],
            ["tr_cable_ext", "Triceps Extension (Cable)", 10, 20, 75],
            ["tr_db_ext", "Triceps Extension (Dumbbell)", 10, 12, 90]
        ] as Array;
    }

    function _quads() as Array {
        return [
            ["q_back_squat", "Back Squat", 5, 90, 210],
            ["q_front_squat", "Front Squat", 6, 60, 180],
            ["q_leg_press", "Leg Press", 10, 140, 120],
            ["q_hack_squat", "Hack Squat", 10, 80, 150],
            ["q_leg_extension", "Leg Extension", 12, 45, 60],
            ["q_goblet", "Goblet Squat", 12, 24, 90],
            ["q_lunge", "Walking Lunge", 12, 20, 90],
            ["q_bulgarian", "Bulgarian Split Squat", 10, 16, 90],
            ["q_step_up", "Step-Up", 12, 16, 60]
        ] as Array;
    }

    function _hamstrings() as Array {
        return [
            ["h_rdl", "Romanian Deadlift", 8, 80, 150],
            ["h_leg_curl", "Lying Leg Curl", 12, 40, 60],
            ["h_seated_curl", "Seated Leg Curl", 12, 45, 60],
            ["h_good_morning", "Good Morning", 10, 40, 120],
            ["h_stiff_deadlift", "Stiff-Leg Deadlift", 8, 70, 150],
            ["h_nordic", "Nordic Curl", 8, 0, 120]
        ] as Array;
    }

    function _glutes() as Array {
        return [
            ["g_hip_thrust", "Hip Thrust", 10, 80, 120],
            ["g_glute_bridge", "Glute Bridge", 15, 40, 90],
            ["g_cable_kickback", "Cable Kickback", 15, 12, 45],
            ["g_abduction", "Hip Abduction", 15, 40, 45],
            ["g_sumo_deadlift", "Sumo Deadlift", 5, 90, 180],
            ["g_back_extension", "Back Extension", 15, 0, 60]
        ] as Array;
    }

    function _calves() as Array {
        return [
            ["cf_standing", "Standing Calf Raise", 15, 60, 45],
            ["cf_seated", "Seated Calf Raise", 15, 40, 45],
            ["cf_leg_press", "Calf Press", 15, 100, 45],
            ["cf_single", "Single-Leg Calf Raise", 15, 0, 45]
        ] as Array;
    }

    function _core() as Array {
        return [
            ["co_plank", "Plank", 1, 0, 60],
            ["co_hanging_raise", "Hanging Leg Raise", 12, 0, 60],
            ["co_cable_crunch", "Cable Crunch", 15, 30, 60],
            ["co_ab_wheel", "Ab Wheel", 12, 0, 60],
            ["co_russian", "Russian Twist", 20, 10, 45],
            ["co_side_plank", "Side Plank", 1, 0, 45],
            ["co_pallof", "Pallof Press", 12, 15, 45],
            ["co_situp", "Weighted Sit-Up", 15, 10, 60]
        ] as Array;
    }
}
