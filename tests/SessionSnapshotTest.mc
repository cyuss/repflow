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
    Test.assert((restored.workout.findExercise("A") as Exercise).plannedWeight() == 57.5);
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
    Test.assert(a.plannedWeight() == 50.0);
    Test.assertEqual(a.totalVolume(), 500.0);
    return true;
}

//! A v1 snapshot is brought forward, not thrown away.
//!
//! Discarding an unknown version was right while nobody had any history. It
//! stops being right the moment they do: an athlete mid-workout when an update
//! lands would silently lose the session. v1 differed from v2 only by the
//! absent muscle tag, so every set survives the upgrade and only the muscle
//! breakdown of that one workout is unknown.
(:test)
function testV1SnapshotMigratesForward(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    engine.completeCurrentSet(9, 57.5, TestSupport.T0 + 10);
    engine.selectExercise("B");
    engine.deferExercise("B");

    // Write what v1 would have written: no version bump, no muscle tags.
    var raw = engine.getSession().toStorage();
    raw.put("v", 1);
    var exercises = (raw["w"] as Dictionary)["e"] as Array;
    for (var i = 0; i < exercises.size(); i++) {
        (exercises[i] as Dictionary).remove("m");
    }
    Test.assert(!SessionSnapshot.isValid(raw));      // not current, as expected

    var migrated = SessionSnapshot.migrate(raw);
    Test.assert(migrated != null);
    Test.assert(SessionSnapshot.isValid(migrated));

    var restored = WorkoutSession.fromStorage(migrated as Dictionary);
    Test.assertEqual(restored.workout.exercises.size(), 3);
    var a = restored.workout.findExercise("A") as Exercise;
    Test.assert(a.plannedWeight() == 57.5);          // the work survived
    Test.assertEqual(a.completedSetCount(), 1);
    Test.assertEqual(a.muscle, Muscle.OTHER);        // and only this is unknown
    Test.assertEqual(TestSupport.stateOf(engine, "B"), EX_PENDING);
    return true;
}

//! Migration still refuses what it cannot read.
//!
//! Bringing data forward must not become a licence to guess: a version this
//! build has never seen, or a v1 snapshot that was damaged before the upgrade,
//! is as dangerous as it ever was.
(:test)
function testMigrationRefusesWhatItCannotRead(logger as Test.Logger) as Boolean {
    Test.assert(SessionSnapshot.migrate(null) == null);
    Test.assert(SessionSnapshot.migrate("nonsense") == null);
    Test.assert(SessionSnapshot.migrate({} as Dictionary) == null);

    var engine = TestSupport.newEngine();

    // From the future.
    var future = engine.getSession().toStorage();
    future.put("v", SessionSnapshot.SCHEMA_VERSION + 1);
    Test.assert(SessionSnapshot.migrate(future) == null);

    // Older than anything this build knows.
    var ancient = engine.getSession().toStorage();
    ancient.put("v", 0);
    Test.assert(SessionSnapshot.migrate(ancient) == null);

    // A v1 snapshot that was already damaged: the muscle tag is not the only
    // thing missing, so there is nothing safe to upgrade.
    var damaged = engine.getSession().toStorage();
    damaged.put("v", 1);
    (damaged["w"] as Dictionary).remove("e");
    Test.assert(SessionSnapshot.migrate(damaged) == null);

    // And a current snapshot passes straight through.
    var current = engine.getSession().toStorage();
    Test.assert(SessionSnapshot.migrate(current) != null);
    return true;
}

//! The custom-workout store validates with the same refusal to guess.
(:test)
function testCustomWorkoutValidation(logger as Test.Logger) as Boolean {
    var workout = TestSupport.abcWorkout();
    Test.assert(SessionSnapshot.isValidWorkout(workout.toStorage()));

    Test.assert(!SessionSnapshot.isValidWorkout(null));
    Test.assert(!SessionSnapshot.isValidWorkout("no"));
    Test.assert(!SessionSnapshot.isValidWorkout([] as Array));

    var raw = workout.toStorage();
    raw.remove("n");
    Test.assert(!SessionSnapshot.isValidWorkout(raw));

    // An exercise with a muscle group outside the enum is not a muscle group.
    var bad = workout.toStorage();
    ((bad["e"] as Array)[0] as Dictionary).put("m", 99);
    Test.assert(!SessionSnapshot.isValidWorkout(bad));
    return true;
}
