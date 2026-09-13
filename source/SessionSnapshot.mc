import Toybox.Lang;

//! Validation for the session snapshot read back from Application.Storage.
//!
//! Why this exists, and why a try/catch was not enough:
//!
//! Monkey C distinguishes `Toybox.Lang.Exception`, which `catch` handles, from
//! runtime *errors* such as "Symbol Not Found" and "Unexpected Type", which it
//! does not — those abort the application. Reading a snapshot written by an
//! older build and calling a method on a value that turned out to be null
//! therefore does not fail gracefully: it crashes the app, on every launch,
//! with no way for the athlete to recover short of reinstalling.
//!
//! That is exactly what happened in the simulator after the storage layout
//! changed under a stored session. So nothing is trusted: the snapshot carries
//! a schema version, and every field is type-checked here *before* anything is
//! constructed from it. Anything unrecognised is dropped rather than parsed.
//!
//! This module is pure — no Storage, no UI — so it is fully unit-tested against
//! malformed input (see tests/SessionSnapshotTest.mc).
module SessionSnapshot {

    //! Bump this whenever the stored layout changes.
    //!
    //!   v1  the original layout
    //!   v2  exercises carry a muscle group ("m"), for weekly volume
    //!   v3  the target weight may be null ("no target load"), and exercises
    //!       carry Hevy's own movement id ("h") when they came from a routine
    //!   v4  a completed set carries its effort rating (RPE) as an eighth
    //!       element, or nothing at all when it was not rated
    const SCHEMA_VERSION = 4;

    //! The oldest layout this build can still bring forward.
    const OLDEST_MIGRATABLE = 1;

    //! Bring an older snapshot up to the current layout, or return null.
    //!
    //! Discarding an unknown version was right while nobody had any history.
    //! It stops being right the moment they do: an athlete mid-workout when an
    //! update lands would have lost the session. A version this build knows how
    //! to read is upgraded in place; anything older, newer, or damaged is still
    //! refused, because guessing at a layout is how the app crashes on launch.
    //!
    //! Migration happens on the raw Dictionary, before anything is constructed,
    //! for the same reason validation does: a Monkey C runtime error here is not
    //! catchable.
    public function migrate(raw as Object?) as Object? {
        if (!(raw instanceof Dictionary)) {
            return null;
        }
        var data = raw as Dictionary;
        var version = data["v"];
        if (!(version instanceof Number)) {
            return null;
        }
        var v = version as Number;
        if (v == SCHEMA_VERSION) {
            return isValid(data) ? data : null;
        }
        if (v < OLDEST_MIGRATABLE || v > SCHEMA_VERSION) {
            return null;
        }

        // v1 -> v2: every exercise gains a muscle group. Nothing in v1 recorded
        // one, so they become OTHER — the session keeps every set it had, and
        // only the muscle breakdown of this one workout is unknown.
        if (v == 1) {
            if (!_isValidShape(data, false)) {
                return null;
            }
            var workout = data["w"] as Dictionary;
            var exercises = workout["e"] as Array;
            for (var i = 0; i < exercises.size(); i++) {
                var ex = exercises[i] as Dictionary;
                ex["m"] = Muscle.OTHER;
            }
            data["v"] = 2;
            v = 2;
        }

        // v2 -> v3: nothing has to be added. A v2 exercise has no Hevy id,
        // which is exactly what "was not imported from Hevy" looks like, and
        // its weight is a number, which v3 still accepts. The version is the
        // only thing that moves.
        if (v == 2) {
            if (!_isValidShape(data, true)) {
                return null;
            }
            data["v"] = 3;
            v = 3;
        }

        // v3 -> v4: a set gains an eighth element for the effort rating. Sets
        // written before it simply do not have one, and an absent rating is
        // exactly what an unrated set means — so nothing is added and nothing
        // is invented. Only the version moves.
        if (v == 3) {
            if (!_isValidShape(data, true)) {
                return null;
            }
            data["v"] = SCHEMA_VERSION;
        }

        return isValid(data) ? data : null;
    }

    //! True when `raw` is a snapshot this build can safely parse.
    public function isValid(raw as Object?) as Boolean {
        if (!(raw instanceof Dictionary)) {
            return false;
        }
        if (!_isNumber((raw as Dictionary)["v"] as Object?) ||
            ((raw as Dictionary)["v"] as Number) != SCHEMA_VERSION) {
            return false;
        }
        return _isValidShape(raw, true);
    }

    //! Everything but the version check. `requireMuscle` is what separates v2
    //! from v1, so the migration can reuse the whole of this.
    function _isValidShape(raw as Object?, requireMuscle as Boolean) as Boolean {
        if (!(raw instanceof Dictionary)) {
            return false;
        }
        var data = raw as Dictionary;

        if (!_isNumber(data["s"] as Object?) || !_isNumber(data["st"] as Object?)) {
            return false;
        }
        // finishedAt and currentExerciseId are legitimately absent.
        if (data["f"] != null && !_isNumber(data["f"] as Object?)) {
            return false;
        }
        if (data["c"] != null && !(data["c"] instanceof String)) {
            return false;
        }
        return _isValidWorkout(data["w"] as Object?, requireMuscle);
    }

    //! True when `raw` is a workout dictionary this build can parse.
    //!
    //! Exposed because custom workouts are stored on their own, outside any
    //! session, and they need exactly the same refusal to guess.
    public function isValidWorkout(raw as Object?) as Boolean {
        return _isValidWorkout(raw, true);
    }

    function _isValidWorkout(raw as Object?, requireMuscle as Boolean) as Boolean {
        if (!(raw instanceof Dictionary)) {
            return false;
        }
        var data = raw as Dictionary;
        if (!(data["i"] instanceof String) || !(data["n"] instanceof String)) {
            return false;
        }
        if (!(data["e"] instanceof Array)) {
            return false;
        }
        var exercises = data["e"] as Array;
        for (var i = 0; i < exercises.size(); i++) {
            if (!_isValidExercise(exercises[i] as Object?, requireMuscle)) {
                return false;
            }
        }
        return true;
    }

    function _isValidExercise(raw as Object?, requireMuscle as Boolean) as Boolean {
        if (!(raw instanceof Dictionary)) {
            return false;
        }
        var data = raw as Dictionary;
        if (!(data["i"] instanceof String) || !(data["n"] instanceof String)) {
            return false;
        }
        if (!_isNumber(data["ts"] as Object?) || !_isNumber(data["tr"] as Object?) || !_isNumber(data["r"] as Object?)) {
            return false;
        }
        if (!_isNumber(data["st"] as Object?) || !(data["fc"] instanceof Boolean)) {
            return false;
        }
        // The target load is legitimately absent: a pull-up has none. Present
        // means it must be a number; absent means absent, not zero.
        if (data["w"] != null && !_isFloat(data["w"] as Object?)) {
            return false;
        }
        if (data["h"] != null && !(data["h"] instanceof String)) {
            return false;
        }
        if (requireMuscle) {
            var m = data["m"];
            if (!(m instanceof Number) || !Muscle.isValid(m as Number)) {
                return false;
            }
        }
        if (!(data["s"] instanceof Array)) {
            return false;
        }
        var sets = data["s"] as Array;
        for (var i = 0; i < sets.size(); i++) {
            if (!_isValidSet(sets[i] as Object?)) {
                return false;
            }
        }
        return true;
    }

    //! A set is stored as a flat array — see WorkoutSet.toStorage.
    //!
    //!   [index, targetReps, targetWeight, actualReps, actualWeight,
    //!    completed, completedAt, rpe]
    //!
    //! Seven elements or eight: the rating was appended in v4, and a set
    //! written by an earlier build is one short. That is not damage — it is a
    //! set nobody rated, which is a state v4 has anyway. Rejecting it would
    //! throw away a session mid-workout when an update lands, which is the
    //! thing migration exists to prevent.
    function _isValidSet(raw as Object?) as Boolean {
        if (!(raw instanceof Array)) {
            return false;
        }
        var set = raw as Array;
        if (set.size() < 7 || set.size() > 8) {
            return false;
        }
        if (!_isNumber(set[0] as Object?) || !_isNumber(set[1] as Object?)) {
            return false;
        }
        if (set[2] != null && !_isFloat(set[2] as Object?)) {
            return false;
        }
        // actualReps / actualWeight / completedAt are null until the set is done.
        if (set[3] != null && !_isNumber(set[3] as Object?)) {
            return false;
        }
        if (set[4] != null && !_isFloat(set[4] as Object?)) {
            return false;
        }
        if (!(set[5] instanceof Boolean)) {
            return false;
        }
        if (set[6] != null && !_isNumber(set[6] as Object?)) {
            return false;
        }
        // Present means it must be a number; a rating off Hevy's ladder is
        // dropped later by Rpe.sanitise rather than rejected here, because a
        // strange rating is not a reason to lose the session it belongs to.
        if (set.size() > 7 && set[7] != null && !_isFloat(set[7] as Object?)) {
            return false;
        }
        return true;
    }

    function _isNumber(value as Object?) as Boolean {
        return value instanceof Number;
    }

    //! Storage may hand a whole number back as a Number even though it was
    //! written as a Float, so both are acceptable for a weight.
    function _isFloat(value as Object?) as Boolean {
        return (value instanceof Float) || (value instanceof Number);
    }
}
