import Toybox.Lang;
import Toybox.Test;

//! Persisted-snapshot validation.
//!
//! These guard a crash that actually happened: a session stored by an earlier
//! build was read back by a newer one, a field was not the type the parser
//! expected, and the resulting "Symbol Not Found" runtime error — which is NOT
//! a Lang.Exception and is therefore not caught — killed the app on launch.
//! On a watch that would mean RepFlow crashing every single time it opened,
//! with no way for the athlete to clear it.
//!
//! So the rule is: validate before parsing, and reject anything unrecognised.

//! A snapshot RepFlow itself produced must always be accepted.
(:test)
function testRoundTripSnapshotIsValid(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    engine.completeCurrentSet(9, 57.5, TestSupport.T0 + 10);
    engine.selectExercise("B");
    engine.deferExercise("B");

    var raw = engine.getSession().toStorage();
    Test.assert(SessionSnapshot.isValid(raw));

    // And it must still parse back to the same thing.
    var restored = WorkoutSession.fromStorage(raw);
    Test.assertEqual(restored.workout.exercises.size(), 3);
    Test.assertEqual((restored.workout.findExercise("A") as Exercise).plannedWeight(), 57.5);
    return true;
}

//! An empty session round-trips too.
(:test)
function testEmptySnapshotIsValid(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    Test.assert(SessionSnapshot.isValid(engine.getSession().toStorage()));
    return true;
}

//! Anything that is not a snapshot is rejected rather than parsed.
(:test)
function testNonSnapshotValuesAreRejected(logger as Test.Logger) as Boolean {
    Test.assert(!SessionSnapshot.isValid(null));
    Test.assert(!SessionSnapshot.isValid("not a session"));
    Test.assert(!SessionSnapshot.isValid(42));
    Test.assert(!SessionSnapshot.isValid([1, 2, 3] as Array));
    Test.assert(!SessionSnapshot.isValid({} as Dictionary));
    return true;
}

//! A snapshot from a different schema version is dropped, not misread.
//! This is the case that caused the crash.
(:test)
function testWrongSchemaVersionIsRejected(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    var raw = engine.getSession().toStorage();
    Test.assert(SessionSnapshot.isValid(raw));

    raw.put("v", SessionSnapshot.SCHEMA_VERSION + 1);
    Test.assert(!SessionSnapshot.isValid(raw));

    raw.put("v", SessionSnapshot.SCHEMA_VERSION - 1);
    Test.assert(!SessionSnapshot.isValid(raw));

    // A snapshot with no version at all is exactly what an older build wrote.
    raw.remove("v");
    Test.assert(!SessionSnapshot.isValid(raw));
    return true;
}

//! Every required top-level field is actually required.
(:test)
function testMissingTopLevelFieldsAreRejected(logger as Test.Logger) as Boolean {
    var keys = ["w", "s", "st"] as Array<String>;
    for (var i = 0; i < keys.size(); i++) {
        var engine = TestSupport.newEngine();
        var raw = engine.getSession().toStorage();
        raw.remove(keys[i]);
        Test.assert(!SessionSnapshot.isValid(raw));
    }
    return true;
}

//! A field of the wrong type is rejected — this is what would otherwise blow up
//! inside fromStorage.
(:test)
function testWrongTypesAreRejected(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    var raw = engine.getSession().toStorage();
    raw.put("s", "yesterday");           // startedAt should be a Number
    Test.assert(!SessionSnapshot.isValid(raw));

    raw = TestSupport.newEngine().getSession().toStorage();
    raw.put("c", 7);                     // currentExerciseId should be a String
    Test.assert(!SessionSnapshot.isValid(raw));

    raw = TestSupport.newEngine().getSession().toStorage();
    raw.put("w", "not a workout");
    Test.assert(!SessionSnapshot.isValid(raw));
    return true;
}

//! Optional fields are genuinely optional.
(:test)
function testOptionalFieldsMayBeNull(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    var raw = engine.getSession().toStorage();
    raw.put("f", null);      // not finished
    raw.put("c", null);      // nothing selected
    Test.assert(SessionSnapshot.isValid(raw));
    return true;
}

//! Damage nested inside an exercise is caught too, not just at the top level.
(:test)
function testCorruptExerciseIsRejected(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    var raw = engine.getSession().toStorage();
    var workout = raw["w"] as Dictionary;
    var exercises = workout["e"] as Array;

    var exercise = exercises[1] as Dictionary;
    exercise.remove("ts");
    Test.assert(!SessionSnapshot.isValid(raw));

    // An exercise that is not even a dictionary.
    raw = TestSupport.newEngine().getSession().toStorage();
    workout = raw["w"] as Dictionary;
    exercises = workout["e"] as Array;
    exercises[0] = "broken";
    Test.assert(!SessionSnapshot.isValid(raw));
    return true;
}

//! And damage inside a stored set.
(:test)
function testCorruptSetIsRejected(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    engine.completeCurrentSet(10, 50.0, TestSupport.T0);

    var raw = engine.getSession().toStorage();
    var workout = raw["w"] as Dictionary;
    var exercises = workout["e"] as Array;
    var exercise = exercises[0] as Dictionary;
    var sets = exercise["s"] as Array;
    Test.assertEqual(sets.size(), 1);

    // A set array of the wrong length — an older or newer layout.
    sets[0] = [1, 2, 3] as Array;
    Test.assert(!SessionSnapshot.isValid(raw));
    return true;
}

//! Storage may hand a whole number back as a Number even though a Float was
//! written, so weights must survive that round trip.
(:test)
function testIntegerWeightsAreAccepted(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    engine.completeCurrentSet(10, 50.0, TestSupport.T0);

    var raw = engine.getSession().toStorage();
    var workout = raw["w"] as Dictionary;
    var exercises = workout["e"] as Array;
    var exercise = exercises[0] as Dictionary;

    // Simulate Storage narrowing 50.0 to 50.
    exercise.put("w", 50);
    var sets = exercise["s"] as Array;
    var set = sets[0] as Array;
    set[2] = 50;
    set[4] = 50;

    Test.assert(SessionSnapshot.isValid(raw));

    // And parsing must still yield usable Floats, not crash.
    var restored = WorkoutSession.fromStorage(raw);
    var a = restored.workout.findExercise("A") as Exercise;
    Test.assertEqual(a.plannedWeight(), 50.0);
    Test.assertEqual(a.totalVolume(), 500.0);
    return true;
}
