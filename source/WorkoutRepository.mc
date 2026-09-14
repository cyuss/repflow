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
    //! Every workout the athlete can start.
    //!
    //! **Nothing is shipped.** RepFlow used to carry three workouts transcribed
    //! by hand from one athlete's Hevy routines, which is a strange thing for an
    //! app to contain: they were that person's programme frozen at the moment
    //! somebody typed them in, and they drifted from the real ones the first
    //! time those changed.
    //!
    //! Workouts come from Hevy, or from the editor. An empty list is not a
    //! broken state — the picker opens on "New workout", which is the right
    //! first screen for someone who has neither imported nor built one yet.
    public function all() as Array<Workout> {
        var list = [] as Array<Workout>;
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
                var workout = Workout.fromStorage(entries[i] as Dictionary);
                _healMuscles(workout);
                out.add(workout);
            } catch (e) {
                // Skip it and keep going.
            }
        }
        return out;
    }

    //! Give a second opinion to exercises that never got a muscle group.
    //!
    //! The group is worked out once, when a routine is imported, and stored —
    //! because a workout outlives the catalogue entry it was built from. That
    //! is right, and it means a fault in the *guessing* is frozen into every
    //! routine already on the watch: "Shoulder Press (Dumbbell)" was landing in
    //! OTHER, which the week's chart does not draw, and re-importing was the
    //! only way to fix it.
    //!
    //! So anything still sitting in OTHER is asked again on every load. Only
    //! OTHER: a group the athlete's own catalogue decided, or that an earlier
    //! guess got right, is never overruled here.
    function _healMuscles(workout as Workout) as Void {
        var list = workout.exercises;
        for (var i = 0; i < list.size(); i++) {
            if (list[i].muscle == Muscle.OTHER) {
                list[i].muscle = HevyMap.muscleFor(list[i].name);
            }
        }
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

}
