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

    function _ex(
        id as String,
        name as String,
        sets as Number,
        reps as Number,
        weight as Float,
        rest as Number,
        muscle as Number
    ) as Exercise {
        var ex = new Exercise(id, name, sets, reps, weight, rest);
        ex.muscle = muscle;
        return ex;
    }

    public function backAndTriceps() as Workout {
        return new Workout("w_back_tri", "Back + Triceps", [
            _ex("b_lat_pulldown", "Lat Pulldown", 4, 10, 55.0, 90, Muscle.BACK),
            _ex("b_seated_row", "Seated Row", 4, 10, 60.0, 90, Muscle.BACK),
            _ex("b_face_pull", "Face Pull", 4, 12, 25.0, 60, Muscle.BACK),
            _ex("tr_pushdown", "Triceps Pushdown", 4, 10, 30.0, 60, Muscle.TRICEPS)
        ] as Array<Exercise>);
    }

    public function chestAndBiceps() as Workout {
        return new Workout("w_chest_bi", "Chest + Biceps", [
            _ex("c_bench", "Bench Press", 4, 8, 70.0, 120, Muscle.CHEST),
            _ex("c_incline_db", "Incline DB Press", 3, 10, 24.0, 90, Muscle.CHEST),
            _ex("c_cable_fly", "Cable Fly", 3, 12, 15.0, 60, Muscle.CHEST),
            _ex("bi_bb_curl", "Barbell Curl", 3, 10, 30.0, 60, Muscle.BICEPS),
            _ex("bi_hammer", "Hammer Curl", 3, 12, 14.0, 60, Muscle.BICEPS)
        ] as Array<Exercise>);
    }

    public function legs() as Workout {
        return new Workout("w_legs", "Legs", [
            _ex("q_back_squat", "Back Squat", 5, 5, 90.0, 180, Muscle.QUADS),
            _ex("h_rdl", "Romanian Deadlift", 4, 8, 80.0, 120, Muscle.HAMSTRINGS),
            _ex("q_leg_press", "Leg Press", 4, 10, 140.0, 90, Muscle.QUADS),
            _ex("h_leg_curl", "Lying Leg Curl", 3, 12, 40.0, 60, Muscle.HAMSTRINGS),
            _ex("cf_standing", "Standing Calf Raise", 4, 15, 60.0, 45, Muscle.CALVES)
        ] as Array<Exercise>);
    }
}
