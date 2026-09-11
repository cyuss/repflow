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

    //! Bump this whenever the stored layout changes in a way older data cannot
    //! satisfy. Old snapshots are then discarded instead of misread.
    const SCHEMA_VERSION = 1;

    //! True when `raw` is a snapshot this build can safely parse.
    public function isValid(raw as Object?) as Boolean {
        if (!(raw instanceof Dictionary)) {
            return false;
        }
        var data = raw as Dictionary;

        if (!_isNumber(data["v"] as Object?) || (data["v"] as Number) != SCHEMA_VERSION) {
            return false;
        }
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
        return _isValidWorkout(data["w"] as Object?);
    }

    function _isValidWorkout(raw as Object?) as Boolean {
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
            if (!_isValidExercise(exercises[i] as Object?)) {
                return false;
            }
        }
        return true;
    }

    function _isValidExercise(raw as Object?) as Boolean {
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
        if (!_isFloat(data["w"] as Object?)) {
            return false;
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
    //! [index, targetReps, targetWeight, actualReps, actualWeight, completed, completedAt]
    function _isValidSet(raw as Object?) as Boolean {
        if (!(raw instanceof Array)) {
            return false;
        }
        var set = raw as Array;
        if (set.size() != 7) {
            return false;
        }
        if (!_isNumber(set[0] as Object?) || !_isNumber(set[1] as Object?) || !_isFloat(set[2] as Object?)) {
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
