import Toybox.Lang;
import Toybox.Application.Storage;

//! Workout templates: the three that ship, plus whatever the athlete builds.
//!
//! Exercise ids are **catalogue ids** (see ExerciseCatalogue), not ids invented
//! per workout. That is what lets "Lat Pulldown" in the built-in Back session
//! and "Lat Pulldown" added by hand three weeks later be the same movement to
//! history and to records.
//!
//! Custom workouts live in `Application.Storage` under one key, as a plain
//! array of the same dictionaries `Workout.toStorage` already writes. Reading
//! them back validates every field first, for the reason documented in
//! SessionSnapshot: a Monkey C runtime error is not catchable, so a damaged
//! entry has to be rejected rather than parsed.
module WorkoutRepository {

    const KEY_CUSTOM = "workouts";

    //! Storage is finite and one oversized value fails the whole write. A
    //! strength athlete with more than this many routines has a different
    //! problem from the one this app solves.
    const MAX_CUSTOM = 12;

    //! Fresh, unstarted copies of every workout, built-in first.
    //! Each call allocates new objects so a previous session's state never leaks.
    public function all() as Array<Workout> {
        var list = [
            backAndTriceps(),
            chestAndBiceps(),
            legs()
        ] as Array<Workout>;
        var custom = loadCustom();
        for (var i = 0; i < custom.size(); i++) {
            list.add(custom[i]);
        }
        return list;
    }

    public function count() as Number {
        return all().size();
    }

    //! Load a single template by id, or null.
    public function byId(workoutId as String) as Workout? {
        var list = all();
        for (var i = 0; i < list.size(); i++) {
            if (list[i].id.equals(workoutId)) {
                return list[i];
            }
        }
        return null;
    }

    public function isCustom(workoutId as String) as Boolean {
        // substring returns String? — an id shorter than the prefix gives null.
        var prefix = workoutId.substring(0, 2);
        return prefix != null && prefix.equals("u_");
    }

    // ------------------------------------------------------------------
    // The athlete's own workouts
    // ------------------------------------------------------------------

    public function loadCustom() as Array<Workout> {
        var out = [] as Array<Workout>;
        var raw = null;
        try {
            raw = Storage.getValue(KEY_CUSTOM);
        } catch (e) {
            return out;
        }
        if (!(raw instanceof Array)) {
            return out;
        }
        var entries = raw as Array;
        for (var i = 0; i < entries.size(); i++) {
            // One damaged entry must not cost the athlete the others.
            if (!SessionSnapshot.isValidWorkout(entries[i] as Object?)) {
                continue;
            }
            try {
                out.add(Workout.fromStorage(entries[i] as Dictionary));
            } catch (e) {
                // Skip it and keep going.
            }
        }
        return out;
    }

    //! Insert or replace a custom workout. Returns false when storage refused.
    public function saveCustom(workout as Workout) as Boolean {
        var list = loadCustom();
        var replaced = false;
        var raw = [] as Array;
        for (var i = 0; i < list.size(); i++) {
            if (list[i].id.equals(workout.id)) {
                raw.add(workout.toStorage() as Object);
                replaced = true;
            } else {
                raw.add(list[i].toStorage() as Object);
            }
        }
        if (!replaced) {
            if (raw.size() >= MAX_CUSTOM) {
                return false;
            }
            raw.add(workout.toStorage() as Object);
        }
        try {
            Storage.setValue(KEY_CUSTOM, raw as Storage.ValueType);
            return true;
        } catch (e) {
            return false;
        }
    }

    public function removeCustom(workoutId as String) as Boolean {
        var list = loadCustom();
        var raw = [] as Array;
        for (var i = 0; i < list.size(); i++) {
            if (!list[i].id.equals(workoutId)) {
                raw.add(list[i].toStorage() as Object);
            }
        }
        try {
            Storage.setValue(KEY_CUSTOM, raw as Storage.ValueType);
            return true;
        } catch (e) {
            return false;
        }
    }

    public function customCount() as Number {
        return loadCustom().size();
    }

    public function canAddCustom() as Boolean {
        return customCount() < MAX_CUSTOM;
    }

    //! An id no existing workout is using.
    public function newCustomId(now as Number) as String {
        var candidate = "u_" + now.toString();
        var list = loadCustom();
        // Bounded rather than `while (true)`: the type checker wants a return
        // on every path, and there can never be more clashes than workouts.
        for (var suffix = 0; suffix <= MAX_CUSTOM; suffix++) {
            var id = suffix == 0 ? candidate : candidate + "_" + suffix.toString();
            var clash = false;
            for (var i = 0; i < list.size(); i++) {
                if (list[i].id.equals(id)) {
                    clash = true;
                    break;
                }
            }
            if (!clash) {
                return id;
            }
        }
        return candidate + "_x";
    }

    // ------------------------------------------------------------------
    // The built-ins
    // ------------------------------------------------------------------

    //! One row of a shipped workout.
    //!
    //! `hevyId` is Hevy's own template id for the movement, and without it the
    //! exercise is a dead end: `HevyMap.sessionToPayload` files a set against
    //! `exercise_template_id` and drops anything that has none, so a workout of
    //! nameless exercises reaches Hevy as nothing at all. These shipped
    //! workouts had none, which meant performing one logged it to Garmin and
    //! silently not to Hevy.
    //!
    //! The ids are from Hevy's public catalogue — 451 templates, none of them
    //! anybody's custom exercise — so they are the same for every account and
    //! carry nothing personal. An id Hevy does not recognise costs a 400 and
    //! the session stays queued for the next attempt; nothing is lost.
    function _ex(
        id as String,
        name as String,
        sets as Number,
        reps as Number,
        weight as Float,
        rest as Number,
        muscle as Number,
        hevyId as String
    ) as Exercise {
        var ex = new Exercise(id, name, sets, reps, weight, rest);
        ex.muscle = muscle;
        ex.hevyId = hevyId;
        return ex;
    }

    //! The athlete's own three-day programme, transcribed from their routines.
    //!
    //! Repetitions and rest times are exactly as recorded. Loads are as
    //! recorded where a load was set; where the routine left the weight blank
    //! the default is zero, which is what "no target weight" means — the first
    //! set of the session sets it, and every set after that inherits it. After
    //! the first session, last week's load is what appears.
    //!
    //! A routine carries one target per exercise here, not one per set. Where
    //! the original varies — bench press at 20, 20, 20, then 30; curls at 10,
    //! 10, 8, 8 — the opening value is the default and the athlete changes it
    //! on the set itself, which is what they were doing anyway. Per-set targets
    //! are a real feature and a separate one; see docs/FEATURE_BACKLOG.md 2.11.

    public function backAndTriceps() as Workout {
        return new Workout("w_back_tri", "Dos + Triceps", [
            _ex("b_lat_pulldown", "Lat Pulldown (Cable)", 4, 8, 0.0, 120, Muscle.BACK, "6A6C31A5"),
            _ex("b_seated_row", "Seated Row (Machine)", 4, 8, 0.0, 120, Muscle.BACK, "1DF4A847"),
            _ex("b_db_row", "Dumbbell Row", 4, 10, 0.0, 90, Muscle.BACK, "F1E57334"),
            _ex("b_iso_low_row", "Iso-Lateral Low Row", 4, 10, 0.0, 90, Muscle.BACK, "91FAFBA3"),
            _ex("tr_pushdown", "Triceps Pushdown", 4, 10, 0.0, 75, Muscle.TRICEPS, "93A552C6"),
            _ex("tr_cable_ext", "Triceps Extension (Cable)", 4, 10, 0.0, 75, Muscle.TRICEPS, "21310F5F"),
            _ex("tr_rope", "Triceps Rope Pushdown", 4, 12, 0.0, 60, Muscle.TRICEPS, "94B7239B")
        ] as Array<Exercise>);
    }

    public function chestAndBiceps() as Workout {
        return new Workout("w_chest_bi", "Pecs + Biceps", [
            _ex("c_bench", "Bench Press (Barbell)", 4, 12, 20.0, 150, Muscle.CHEST, "79D0BB3A"),
            _ex("c_incline_db", "Incline Bench Press (Dumbbell)", 4, 10, 14.0, 120, Muscle.CHEST, "07B38369"),
            _ex("c_pec_deck", "Chest Fly (Machine)", 4, 12, 39.0, 90, Muscle.CHEST, "78683336"),
            _ex("c_chest_press", "Chest Press (Machine)", 4, 10, 25.0, 90, Muscle.CHEST, "7EB3F7C3"),
            _ex("bi_db_curl", "Bicep Curl (Dumbbell)", 4, 10, 9.0, 75, Muscle.BICEPS, "37FCC2BB"),
            _ex("bi_hammer", "Hammer Curl (Dumbbell)", 4, 8, 9.0, 75, Muscle.BICEPS, "7E3BC8B6"),
            _ex("bi_concentration", "Concentration Curl", 4, 10, 0.0, 60, Muscle.BICEPS, "724CDE60")
        ] as Array<Exercise>);
    }

    //! Shoulders, biceps and triceps. Arnold Press was the one exercise whose
    //! set rows were not visible in the routine; four by ten matches its
    //! neighbours and is the only value here that was not read directly.
    public function legs() as Workout {
        return new Workout("w_shoulders_arms", "Epaules + Bras", [
            _ex("s_db_press", "Shoulder Press (Dumbbell)", 4, 8, 0.0, 120, Muscle.SHOULDERS, "878CD1D0"),
            _ex("s_lateral", "Lateral Raise (Dumbbell)", 4, 12, 0.0, 75, Muscle.SHOULDERS, "422B08F1"),
            _ex("s_arnold", "Arnold Press (Dumbbell)", 4, 10, 0.0, 90, Muscle.SHOULDERS, "A69FF221"),
            _ex("bi_bb_curl", "Bicep Curl (Barbell)", 4, 8, 0.0, 90, Muscle.BICEPS, "A5AC6449"),
            _ex("bi_hammer_cable", "Hammer Curl (Cable)", 4, 10, 0.0, 75, Muscle.BICEPS, "36E8F14E"),
            _ex("tr_db_ext", "Triceps Extension (Dumbbell)", 4, 10, 0.0, 90, Muscle.TRICEPS, "3765684D"),
            _ex("tr_rope", "Triceps Rope Pushdown", 4, 12, 0.0, 75, Muscle.TRICEPS, "94B7239B")
        ] as Array<Exercise>);
    }
}
