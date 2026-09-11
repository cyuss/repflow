import Toybox.Lang;
import Toybox.Test;

//! Behaviour tests for the flexible workout engine.
//!
//! These encode the product promise: any exercise, any time, without losing
//! state. They are deliberately written against observable behaviour rather
//! than internals, so they keep their value as the engine evolves.

// ----------------------------------------------------------------------
// 1. Straightforward A -> B -> C completion
// ----------------------------------------------------------------------
(:test)
function testLinearCompletion(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    var ids = ["A", "B", "C"] as Array<String>;

    for (var i = 0; i < ids.size(); i++) {
        Test.assert(engine.selectExercise(ids[i]));
        Test.assertEqual(TestSupport.stateOf(engine, ids[i]), EX_ACTIVE);
        TestSupport.completeSets(engine, 2);
        Test.assertEqual(TestSupport.stateOf(engine, ids[i]), EX_COMPLETED);
    }

    Test.assert(engine.isWorkoutComplete());
    Test.assertEqual(engine.unfinishedExercises().size(), 0);
    return true;
}

// ----------------------------------------------------------------------
// 2. A -> skip B -> C -> return to B
// ----------------------------------------------------------------------
(:test)
function testSkipForNowAndReturn(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();

    engine.selectExercise("A");
    TestSupport.completeSets(engine, 2);
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_COMPLETED);

    // The machine is busy: defer B. It must NOT become completed or skipped.
    engine.selectExercise("B");
    Test.assert(engine.deferExercise("B"));
    Test.assertEqual(TestSupport.stateOf(engine, "B"), EX_PENDING);
    Test.assertNotEqual(TestSupport.stateOf(engine, "B"), EX_COMPLETED);
    Test.assertNotEqual(TestSupport.stateOf(engine, "B"), EX_SKIPPED);
    Test.assert(engine.currentExerciseId() == null);

    engine.selectExercise("C");
    TestSupport.completeSets(engine, 2);
    Test.assertEqual(TestSupport.stateOf(engine, "C"), EX_COMPLETED);

    // B is still offered as unfinished work, and is resumable.
    Test.assertEqual(engine.unfinishedExercises().size(), 1);
    Test.assert(!engine.isWorkoutComplete());

    engine.selectExercise("B");
    Test.assertEqual(TestSupport.stateOf(engine, "B"), EX_ACTIVE);
    TestSupport.completeSets(engine, 2);
    Test.assertEqual(TestSupport.stateOf(engine, "B"), EX_COMPLETED);
    Test.assert(engine.isWorkoutComplete());
    return true;
}

// ----------------------------------------------------------------------
// 3. Alternating two partially completed exercises (superset)
//    A1 -> B1 -> A2 -> B2
// ----------------------------------------------------------------------
(:test)
function testAlternatingExercises(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();

    engine.selectExercise("A");
    TestSupport.completeSets(engine, 1);

    engine.selectExercise("B");
    // Leaving A part-done must park it as PENDING, never lose it.
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_PENDING);
    Test.assertEqual(TestSupport.exerciseOf(engine, "A").completedSetCount(), 1);
    TestSupport.completeSets(engine, 1);

    engine.selectExercise("A");
    Test.assertEqual(TestSupport.stateOf(engine, "B"), EX_PENDING);
    Test.assertEqual(TestSupport.exerciseOf(engine, "A").completedSetCount(), 1);
    // Resumes on set 2, not set 1 — no state was lost.
    Test.assertEqual(TestSupport.exerciseOf(engine, "A").currentSetNumber(), 2);
    TestSupport.completeSets(engine, 1);
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_COMPLETED);

    engine.selectExercise("B");
    Test.assertEqual(TestSupport.exerciseOf(engine, "B").completedSetCount(), 1);
    TestSupport.completeSets(engine, 1);
    Test.assertEqual(TestSupport.stateOf(engine, "B"), EX_COMPLETED);

    Test.assertEqual(TestSupport.exerciseOf(engine, "A").sets.size(), 2);
    Test.assertEqual(TestSupport.exerciseOf(engine, "B").sets.size(), 2);
    return true;
}

// ----------------------------------------------------------------------
// 4. COMPLETED is unreachable early unless explicitly forced
// ----------------------------------------------------------------------
(:test)
function testCannotCompleteEarlyWithoutForcing(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();

    engine.selectExercise("A");
    TestSupport.completeSets(engine, 1);
    Test.assertNotEqual(TestSupport.stateOf(engine, "A"), EX_COMPLETED);
    Test.assert(!TestSupport.exerciseOf(engine, "A").hasReachedTargetSets());

    // Navigating away parks it as PENDING, still not COMPLETED.
    engine.selectExercise("B");
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_PENDING);

    // Only an explicit force gets there.
    Test.assert(engine.forceCompleteExercise("A"));
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_COMPLETED);
    Test.assert(TestSupport.exerciseOf(engine, "A").forcedComplete);
    Test.assertEqual(TestSupport.exerciseOf(engine, "A").completedSetCount(), 1);
    return true;
}

// ----------------------------------------------------------------------
// 5. PENDING stays resumable, and resumes mid-exercise
// ----------------------------------------------------------------------
(:test)
function testPendingRemainsResumable(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();

    engine.selectExercise("C");
    engine.completeCurrentSet(8, 62.5, TestSupport.T0);
    engine.deferExercise("C");
    Test.assertEqual(TestSupport.stateOf(engine, "C"), EX_PENDING);

    // Still counted as work left, and suggested as what to do next.
    Test.assert(!engine.isWorkoutComplete());
    var next = engine.suggestNextExercise() as Exercise;
    Test.assertEqual(next.id, "C");

    engine.selectExercise("C");
    Test.assertEqual(TestSupport.stateOf(engine, "C"), EX_ACTIVE);
    var c = TestSupport.exerciseOf(engine, "C");
    Test.assertEqual(c.completedSetCount(), 1);
    Test.assertEqual(c.currentSetNumber(), 2);
    // The values performed before deferring are still the ones inherited.
    Test.assertEqual(c.plannedWeight(), 62.5);
    Test.assertEqual(c.plannedReps(), 8);
    return true;
}

// ----------------------------------------------------------------------
// 6 & 7. Weight and repetition inheritance
// ----------------------------------------------------------------------
(:test)
function testWeightAndRepInheritance(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    var a = TestSupport.exerciseOf(engine, "A");

    // Set 1 starts from the exercise defaults.
    Test.assertEqual(a.plannedWeight(), 50.0);
    Test.assertEqual(a.plannedReps(), 10);

    engine.completeCurrentSet(10, 55.0, TestSupport.T0);
    // Set 2 inherits what was actually performed, not the template values.
    Test.assertEqual(a.plannedWeight(), 55.0);
    Test.assertEqual(a.plannedReps(), 10);

    // Change the load on set 2 ...
    engine.completeCurrentSet(8, 57.5, TestSupport.T0 + 60);
    // ... and set 3 follows the change.
    Test.assertEqual(a.plannedWeight(), 57.5);
    Test.assertEqual(a.plannedReps(), 8);
    return true;
}

//! Inheritance must survive navigating away and back.
(:test)
function testInheritanceSurvivesNavigation(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    engine.completeCurrentSet(9, 62.5, TestSupport.T0);

    engine.selectExercise("B");
    engine.completeCurrentSet(12, 40.0, TestSupport.T0 + 30);

    engine.selectExercise("A");
    var a = TestSupport.exerciseOf(engine, "A");
    Test.assertEqual(a.plannedWeight(), 62.5);
    Test.assertEqual(a.plannedReps(), 9);
    return true;
}

// ----------------------------------------------------------------------
// 8. Rest timer state
// ----------------------------------------------------------------------
(:test)
function testRestTimer(logger as Test.Logger) as Boolean {
    var rest = new RestTimer();
    Test.assert(!rest.isRunning());

    rest.start(3);
    Test.assert(rest.isRunning());
    Test.assertEqual(rest.remaining(), 3);
    Test.assertEqual(rest.format(), "00:03");

    Test.assert(!rest.tick());
    Test.assertEqual(rest.remaining(), 2);
    Test.assert(!rest.tick());
    // The tick that reaches zero reports true exactly once, so the haptic fires once.
    Test.assert(rest.tick());
    Test.assert(!rest.isRunning());
    Test.assertEqual(rest.remaining(), 0);
    Test.assert(!rest.tick());

    // Skip cuts rest short.
    rest.start(90);
    Test.assertEqual(rest.format(), "01:30");
    rest.skip();
    Test.assert(!rest.isRunning());
    Test.assertEqual(rest.remaining(), 0);

    // Extending restarts a finished timer; it never goes negative.
    rest.extend(15);
    Test.assert(rest.isRunning());
    Test.assertEqual(rest.remaining(), 15);
    rest.extend(-100);
    Test.assertEqual(rest.remaining(), 0);
    Test.assert(!rest.isRunning());

    // A zero-length rest is simply not running.
    rest.start(0);
    Test.assert(!rest.isRunning());
    return true;
}

// ----------------------------------------------------------------------
// 9. Session summary calculations
// ----------------------------------------------------------------------
(:test)
function testSessionSummary(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();

    engine.selectExercise("A");
    engine.completeCurrentSet(10, 50.0, TestSupport.T0);   // 500
    engine.completeCurrentSet(8, 55.0, TestSupport.T0);    // 440

    engine.selectExercise("B");
    engine.completeCurrentSet(12, 40.0, TestSupport.T0);   // 480

    var summary = engine.summary(TestSupport.T0 + 1800);
    Test.assertEqual(summary.durationSec, 1800);
    Test.assertEqual(summary.exerciseCount, 3);
    Test.assertEqual(summary.exercisesWorked, 2);  // C untouched
    Test.assertEqual(summary.completedSets, 3);
    Test.assertEqual(summary.totalReps, 30);
    Test.assertEqual(summary.totalVolume, 1420.0);

    // Finishing freezes the duration at the finish time.
    var finished = engine.finishWorkout(TestSupport.T0 + 2000);
    Test.assertEqual(finished.durationSec, 2000);
    Test.assertEqual(engine.getSession().state, SESSION_FINISHED);
    Test.assert(engine.currentExerciseId() == null);
    return true;
}

//! An empty session must not produce garbage numbers.
(:test)
function testEmptySessionSummary(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    var summary = engine.summary(TestSupport.T0);
    Test.assertEqual(summary.completedSets, 0);
    Test.assertEqual(summary.totalReps, 0);
    Test.assertEqual(summary.totalVolume, 0.0);
    Test.assertEqual(summary.exercisesWorked, 0);
    Test.assertEqual(summary.durationSec, 0);
    return true;
}

// ----------------------------------------------------------------------
// 10. Persistence serialization round-trip
// ----------------------------------------------------------------------
(:test)
function testSessionSerializationRoundTrip(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    engine.completeCurrentSet(9, 57.5, TestSupport.T0 + 10);
    engine.selectExercise("B");
    engine.deferExercise("B");
    engine.selectExercise("C");
    engine.forceCompleteExercise("C");
    engine.selectExercise("A");

    var restored = WorkoutSession.fromStorage(engine.getSession().toStorage());

    Test.assertEqual(restored.startedAt, TestSupport.T0);
    Test.assertEqual(restored.currentExerciseId as String, "A");
    Test.assertEqual(restored.state, SESSION_ACTIVE);
    Test.assertEqual(restored.workout.name, "Test");
    Test.assertEqual(restored.workout.exercises.size(), 3);

    var a = restored.workout.findExercise("A") as Exercise;
    Test.assertEqual(a.state, EX_ACTIVE);
    Test.assertEqual(a.sets.size(), 1);
    Test.assert(a.sets[0].completed);
    // Nullable on WorkoutSet; the `completed` assertion above is what guarantees them.
    Test.assertEqual(a.sets[0].actualReps as Number, 9);
    Test.assertEqual(a.sets[0].actualWeight as Float, 57.5);
    Test.assertEqual(a.sets[0].completedAt as Number, TestSupport.T0 + 10);
    // Inheritance still works after a restore — this is what makes resume useful.
    Test.assertEqual(a.plannedWeight(), 57.5);
    Test.assertEqual(a.plannedReps(), 9);

    Test.assertEqual((restored.workout.findExercise("B") as Exercise).state, EX_PENDING);

    var c = restored.workout.findExercise("C") as Exercise;
    Test.assertEqual(c.state, EX_COMPLETED);
    Test.assert(c.forcedComplete);

    // A restored engine keeps behaving identically.
    var restoredEngine = new WorkoutEngine(restored);
    Test.assertEqual(restoredEngine.unfinishedExercises().size(), 2);
    Test.assert(!restoredEngine.isWorkoutComplete());
    return true;
}

// ----------------------------------------------------------------------
// Additional engine invariants
// ----------------------------------------------------------------------

//! Selecting an untouched exercise and leaving it again must not mark it
//! started — it goes back to NOT_STARTED, not PENDING.
(:test)
function testUntouchedExerciseReturnsToNotStarted(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_ACTIVE);
    engine.selectExercise("B");
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_NOT_STARTED);
    return true;
}

//! A permanently skipped exercise stops blocking workout completion, but can
//! still be picked again if the athlete changes their mind.
(:test)
function testSkippedExercise(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    TestSupport.completeSets(engine, 2);
    engine.selectExercise("B");
    TestSupport.completeSets(engine, 2);

    Test.assert(!engine.isWorkoutComplete());
    Test.assert(engine.skipExercise("C"));
    Test.assertEqual(TestSupport.stateOf(engine, "C"), EX_SKIPPED);
    Test.assert(engine.isWorkoutComplete());

    engine.selectExercise("C");
    Test.assertEqual(TestSupport.stateOf(engine, "C"), EX_ACTIVE);
    Test.assert(!engine.isWorkoutComplete());
    return true;
}

//! Unknown ids are rejected rather than corrupting the session.
(:test)
function testUnknownExerciseIdIsRejected(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    Test.assert(!engine.selectExercise("nope"));
    Test.assert(!engine.deferExercise("nope"));
    Test.assert(!engine.skipExercise("nope"));
    Test.assert(!engine.forceCompleteExercise("nope"));
    Test.assert(engine.currentExerciseId() == null);
    return true;
}

//! Completing a set with nothing selected is a no-op, not a crash.
(:test)
function testCompleteSetWithNoSelection(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    Test.assert(engine.completeCurrentSet(10, 50.0, TestSupport.T0) == null);
    Test.assertEqual(engine.summary(TestSupport.T0).completedSets, 0);
    return true;
}

//! Extra sets beyond the target are allowed and counted.
(:test)
function testExtraSetsBeyondTarget(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    TestSupport.completeSets(engine, 3);
    var a = TestSupport.exerciseOf(engine, "A");
    Test.assertEqual(a.completedSetCount(), 3);
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_COMPLETED);
    Test.assertEqual(engine.summary(TestSupport.T0).completedSets, 3);
    return true;
}

//! Undo removes the last set and reopens the exercise.
(:test)
function testUndoLastSet(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    TestSupport.completeSets(engine, 2);
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_COMPLETED);

    Test.assert(engine.undoLastSet());
    Test.assertEqual(TestSupport.exerciseOf(engine, "A").completedSetCount(), 1);
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_ACTIVE);
    Test.assert(!engine.isWorkoutComplete());
    return true;
}

//! suggestNextExercise prefers finishing the current exercise, then resuming a
//! pending one, then starting a fresh one, and returns null when all is done.
(:test)
function testSuggestNextExercise(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    Test.assertEqual((engine.suggestNextExercise() as Exercise).id, "A");

    engine.selectExercise("A");
    TestSupport.completeSets(engine, 1);
    // Mid-exercise: stay on it.
    Test.assertEqual((engine.suggestNextExercise() as Exercise).id, "A");

    engine.deferExercise("A");
    // Nothing selected: resume the pending one before starting something new.
    Test.assertEqual((engine.suggestNextExercise() as Exercise).id, "A");

    engine.selectExercise("A");
    TestSupport.completeSets(engine, 1);
    engine.selectExercise("B");
    TestSupport.completeSets(engine, 2);
    engine.selectExercise("C");
    TestSupport.completeSets(engine, 2);
    Test.assert(engine.suggestNextExercise() == null);
    return true;
}
