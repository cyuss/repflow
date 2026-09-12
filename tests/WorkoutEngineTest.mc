import Toybox.Lang;
import Toybox.Test;
import Toybox.Graphics;

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

// ----------------------------------------------------------------------
// The release smoke test, as an executable scenario.
//
// This mirrors docs/SMOKE_TEST.md step for step. It cannot press buttons, but
// it does exercise the exact engine sequence those steps produce — so a
// regression in the product's core promise fails CI rather than waiting to be
// noticed by hand on a watch.
// ----------------------------------------------------------------------
(:test)
function testSmokeTestScenario(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();

    // Steps 2-5: start on A, complete two sets, raising the load on the second.
    Test.assert(engine.selectExercise("A"));
    engine.completeCurrentSet(10, 50.0, TestSupport.T0);
    var a = TestSupport.exerciseOf(engine, "A");
    Test.assertEqual(a.plannedWeight(), 50.0);      // set 2 inherits set 1
    engine.completeCurrentSet(10, 55.0, TestSupport.T0 + 120);

    // Step 6: the overview shows A worked but not finished (target is 2... so
    // A is in fact complete here; give it a third target-exceeding set later).
    Test.assertEqual(a.completedSetCount(), 2);

    // Steps 7-8: open B, then defer it — the machine is busy.
    Test.assert(engine.selectExercise("B"));
    Test.assert(engine.deferExercise("B"));
    Test.assertEqual(TestSupport.stateOf(engine, "B"), EX_PENDING);
    Test.assertNotEqual(TestSupport.stateOf(engine, "B"), EX_COMPLETED);
    Test.assertNotEqual(TestSupport.stateOf(engine, "B"), EX_SKIPPED);

    // Steps 9-10: do C instead, all the way through.
    Test.assert(engine.selectExercise("C"));
    TestSupport.completeSets(engine, 2);
    Test.assertEqual(TestSupport.stateOf(engine, "C"), EX_COMPLETED);

    // Step 11: the overview reflects all three states accurately.
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_COMPLETED);
    Test.assertEqual(TestSupport.stateOf(engine, "B"), EX_PENDING);
    Test.assertEqual(TestSupport.stateOf(engine, "C"), EX_COMPLETED);
    Test.assert(!engine.isWorkoutComplete());  // B still blocks completion

    // Steps 12-13: B resumes from its original state, nothing lost.
    Test.assert(engine.selectExercise("B"));
    var b = TestSupport.exerciseOf(engine, "B");
    Test.assertEqual(b.completedSetCount(), 0);
    Test.assertEqual(b.currentSetNumber(), 1);
    Test.assertEqual(b.plannedWeight(), 40.0);    // untouched template default
    TestSupport.completeSets(engine, 2);
    Test.assertEqual(TestSupport.stateOf(engine, "B"), EX_COMPLETED);

    // Step 14: returning to A inherits the raised weight from step 5.
    Test.assert(engine.selectExercise("A"));
    Test.assertEqual(a.plannedWeight(), 55.0);
    Test.assertEqual(a.plannedReps(), 10);

    // Steps 16-18: everything done, so ending needs no confirmation, and the
    // summary matches what was actually performed.
    Test.assert(engine.isWorkoutComplete());
    var summary = engine.finishWorkout(TestSupport.T0 + 3600);
    Test.assertEqual(summary.durationSec, 3600);
    Test.assertEqual(summary.exercisesWorked, 3);
    Test.assertEqual(summary.completedSets, 6);
    // Every set the workout asked for was performed, so done equals planned.
    Test.assertEqual(summary.plannedSets, 6);
    // A: 10x50 + 10x55 = 1050. B: 2 x 12x40 = 960. C: 2 x 8x60 = 960.
    Test.assertEqual(summary.totalVolume, 2970.0);
    Test.assertEqual(summary.totalReps, 60);
    Test.assertEqual(engine.getSession().state, SESSION_FINISHED);
    return true;
}

//! Ending early must still report what the workout asked for.
//!
//! The recap shows sets as "done / planned". Without the plan, "2 sets" reads
//! like a finished session; against a plan of six it reads like a session that
//! was cut short, which is what actually happened.
(:test)
function testSummaryReportsPlannedSetsWhenEndedEarly(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    TestSupport.completeSets(engine, 2);

    var summary = engine.finishWorkout(TestSupport.T0 + 600);
    Test.assertEqual(summary.completedSets, 2);
    Test.assertEqual(summary.plannedSets, 6);      // 3 exercises x 2 sets
    Test.assertEqual(summary.exercisesWorked, 1);
    Test.assertEqual(summary.exerciseCount, 3);
    return true;
}

//! Reselecting a finished exercise (to review it, or add an extra set) makes it
//! ACTIVE again. That must not make the workout look unfinished, or ending it
//! would demand a pointless confirmation.
(:test)
function testReselectingFinishedExerciseKeepsWorkoutComplete(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    var ids = ["A", "B", "C"] as Array<String>;
    for (var i = 0; i < ids.size(); i++) {
        engine.selectExercise(ids[i]);
        TestSupport.completeSets(engine, 2);
    }
    Test.assert(engine.isWorkoutComplete());

    // Go back to A to look at it. It becomes ACTIVE again...
    Test.assert(engine.selectExercise("A"));
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_ACTIVE);
    // ...but its sets are all still done, so there is no work left.
    Test.assert(engine.isWorkoutComplete());
    Test.assertEqual(engine.unfinishedExercises().size(), 0);

    // A genuinely unfinished exercise still blocks completion.
    Test.assert(engine.undoLastSet());
    Test.assert(!engine.isWorkoutComplete());
    Test.assertEqual(engine.unfinishedExercises().size(), 1);
    return true;
}

// ----------------------------------------------------------------------
// Layout: fonts must fit the space they are given, not just the width.
//
// These run against a real device Dc obtained from a buffered bitmap, so they
// use the actual font metrics of whichever device the suite is run on. That is
// the point: the bug they guard against only appeared on the smaller, shorter
// screens (a 260x260 Fenix 6 Pro), where a font wide enough to fit was far too
// tall and pushed the reps through the action bar.
// ----------------------------------------------------------------------

(:test)
function testPickFontRespectsHeightBudget(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;   // device without buffered bitmaps: nothing to assert
    }
    var hero = Theme.fontsHero();

    // With no height budget the widest-fitting font wins, and on a short screen
    // it can be very tall indeed.
    var unbounded = Theme.pickFont(dc, "55", hero, 240);
    Test.assert(dc.getFontHeight(unbounded) > 0);

    // Given a budget, the chosen font must honour it — unless even the smallest
    // font in the ladder is taller, in which case the smallest is returned.
    var budgets = [80, 60, 40, 24] as Array<Number>;
    var smallest = hero[hero.size() - 1];
    for (var i = 0; i < budgets.size(); i++) {
        var font = Theme.pickFontFitting(dc, "55", hero, 240, budgets[i]);
        var height = dc.getFontHeight(font);
        Test.assert(height <= budgets[i] || font == smallest);
        // Never larger than the unconstrained choice.
        Test.assert(height <= dc.getFontHeight(unbounded));
    }
    return true;
}

//! usableWidth must stay positive and never exceed the display, at any height.
(:test)
function testUsableWidthStaysOnScreen(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;
    }
    var size = TestSupport.screenSize();
    for (var y = 0; y <= size; y += size / 13) {
        var w = Theme.usableWidth(dc, y);
        Test.assert(w > 0);
        Test.assert(w <= dc.getWidth());
    }
    return true;
}

//! Formatting helpers, which the layout sizes itself around.
(:test)
function testFormatting(logger as Test.Logger) as Boolean {
    // Number formatting is unit-free; the conversion is tested separately,
    // because what formatWeight prints depends on the athlete's setting.
    Test.assertEqual(Theme.formatNumber(55.0), "55");
    Test.assertEqual(Theme.formatNumber(57.5), "57.5");
    Test.assertEqual(Theme.formatNumber(0.0), "0");
    Test.assertEqual(Theme.formatNumber(1.25), "1.3");   // rounded to a tenth
    Test.assertEqual(Theme.formatWeight(0.0), "0");

    Test.assertEqual(Theme.formatDuration(0), "0:00");
    Test.assertEqual(Theme.formatDuration(67), "1:07");
    Test.assertEqual(Theme.formatDuration(3723), "1:02:03");

    // Volume gets a big unit once the number would run long, so the test
    // states the property rather than a literal: what "long" means depends on
    // whether the athlete reads kilos or pounds.
    var small = Units.imperial() ? 100.0 : 960.0;
    Test.assert(Units.fromKg(small) < 1000.0);
    Test.assertEqual(Theme.formatVolume(small),
        Theme.formatNumber(Units.fromKg(small)) + " " + Units.label());

    var large = 9000.0;
    Test.assert(Units.fromKg(large) >= 1000.0);
    var big = Theme.formatVolume(large);
    Test.assert(big.find(Units.imperial() ? "k " : " t") != null);
    Test.assert(big.length() <= 8);   // it exists to stay short
    return true;
}

// ----------------------------------------------------------------------
// The data field grid, on a round display.
//
// Measured against THIS device's screen size and font metrics. Pairing one
// device's fonts with another device's screen size proves nothing about either,
// so the suite is meant to be run on each target — `make test DEVICE=<id>`.
// ----------------------------------------------------------------------

//! The SET page is what the athlete reads mid-set, so its two cells must carry
//! a genuinely large number — not merely a font that technically fits.
//!
//! The geometry mirrors ExerciseView._drawSetPage: header, action bar, and one
//! split band filling everything between them.
(:test)
function testSetPageFieldsAreLarge(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;
    }
    var size = TestSupport.screenSize();

    var top = (size * 30) / 100;          // below the header rule
    var bottom = (size * 76) / 100;       // above the action bar
    var height = bottom - top;
    var half = FieldGrid.bandWidth(dc, top, height) / 2;
    var area = FieldGrid.valueArea(dc, height);

    // A five-character weight in half a cell is the worst case. A seventh of the
    // screen is what the geometry of a circle allows there, and it still reads
    // as a data field at arm's length.
    var values = ["55", "10", "137.5", "12"] as Array<String>;
    for (var i = 0; i < values.size(); i++) {
        TestSupport.assertCellFits(dc, values[i], half, area, size / 7);
    }
    return true;
}

//! The four-field layout packs more in, so its cells are necessarily smaller —
//! exactly as a native Garmin four-field screen is. What must still hold is
//! that every value fits the cell it was given.
//!
//! This is the case that forced the cell font ladder to continue past the big
//! number fonts into the text fonts: on a 260x260 screen a four-field band is
//! shorter than the smallest number font, and a value overflowing its cell is
//! worse than a smaller one.
(:test)
function testFourFieldLayoutCellsFit(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;
    }
    var size = TestSupport.screenSize();

    var top = (size * 26) / 100;
    var bottom = size - size / 11;
    var edge = FieldGrid.edgeHeight(top, bottom);
    var middleTop = top + edge;
    var middleHeight = (bottom - edge) - middleTop;

    // Full-width edge bands carry the wide values.
    var edgeWidth = FieldGrid.bandWidth(dc, top, edge);
    var edgeArea = FieldGrid.valueArea(dc, edge);
    var wide = ["1:02:34", "3.2 t", "132", "2/4", "--"] as Array<String>;
    for (var i = 0; i < wide.size(); i++) {
        TestSupport.assertCellFits(dc, wide[i], edgeWidth, edgeArea, 1);
    }

    // The split middle carries short values only.
    var halfWidth = FieldGrid.bandWidth(dc, middleTop, middleHeight) / 2;
    var middleArea = FieldGrid.valueArea(dc, middleHeight);
    var shortValues = ["128", "210", "84", "12", "--"] as Array<String>;
    for (var j = 0; j < shortValues.size(); j++) {
        TestSupport.assertCellFits(dc, shortValues[j], halfWidth, middleArea, 1);
    }
    return true;
}

//! A band's width must be the chord at its NARROWEST edge, never wider. That is
//! what keeps a cell inside the glass near the top and bottom of a circle, and
//! it is why only the middle band is ever split into columns.
(:test)
function testBandWidthStaysInsideTheGlass(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;
    }
    var size = TestSupport.screenSize();
    var height = size / 6;

    for (var top = 0; top + height < size; top += size / 12) {
        var width = FieldGrid.bandWidth(dc, top, height);
        Test.assert(width > 0);
        Test.assert(width <= Theme.usableWidth(dc, top));
        Test.assert(width <= Theme.usableWidth(dc, top + height));
    }

    // A band near the top of the circle must be narrower than one across the
    // middle, or the geometry is not being respected at all.
    Test.assert(FieldGrid.bandWidth(dc, size / 20, height)
        < FieldGrid.bandWidth(dc, size / 2 - height / 2, height));
    return true;
}

//! Actually DRAW every grid primitive, onto a real off-screen Dc.
//!
//! The measurement tests above all called the sizing helpers directly and were
//! green while the app crashed on launch: inside drawCell a local named
//! `valueArea` shadowed the module function `valueArea`, so the call resolved to
//! an uninitialised local and threw "Symbol Not Found" the moment a screen was
//! painted. Nothing that only measures can catch that — something has to run the
//! drawing code.
(:test)
function testGridPrimitivesDraw(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;
    }
    var size = TestSupport.screenSize();
    var top = (size * 26) / 100;
    var bottom = size - size / 11;
    var edge = FieldGrid.edgeHeight(top, bottom);
    var middleTop = top + edge;
    var middleHeight = (bottom - edge) - middleTop;

    // The full four-field layout, exactly as the metric pages compose it.
    FieldGrid.drawSingle(dc, top, edge, "1:02:34", "TIME", Theme.COLOR_TEXT);
    FieldGrid.drawRule(dc, middleTop);
    FieldGrid.drawPair(dc, middleTop, middleHeight,
        "128", "AVG HR", Theme.COLOR_HR,
        "210", "KCAL", Theme.COLOR_TEXT);
    FieldGrid.drawRule(dc, bottom - edge);
    FieldGrid.drawSingle(dc, bottom - edge, edge, "--", "HR", Theme.COLOR_SKIPPED);

    // A cell so short the caption has to be dropped, and a very wide value.
    FieldGrid.drawCell(dc, 0, 0, size, size / 14, "3.2 t", "VOLUME", Theme.COLOR_ACCENT);
    FieldGrid.drawCell(dc, 0, 0, size, size / 3, "137.5", "WEIGHT", Theme.COLOR_TEXT);

    // And the Theme primitives every screen leans on.
    Theme.drawActionBar(dc, "COMPLETE SET", Theme.COLOR_ACCENT);
    Theme.drawPageDots(dc, 3, 1);
    Theme.drawSetDots(dc, size / 2, 4, 2);
    Theme.drawFitted(dc, size / 3, "Romanian Deadlift", Theme.fontsTitle(), Theme.COLOR_TEXT);
    Theme.drawValueWithUnit(dc, size / 3, "55", "kg", Theme.fontsHero(),
        Theme.COLOR_TEXT, Theme.COLOR_DIM);
    Theme.drawMetricRow(dc, size / 2, "VOLUME", "3.2 t", Theme.COLOR_ACCENT);

    // The heart rate zone gauge, at every zone and with no zone at all. The
    // simulator never reports a heart rate, so this is the only place the
    // filled states are exercised at all.
    Theme.drawZoneBar(dc, size / 4, size / 3, size / 2, size / 20, null);
    for (var zone = 1; zone <= 5; zone++) {
        Theme.drawZoneBar(dc, size / 4, size / 3, size / 2, size / 20, zone);
        Theme.zoneColor(zone);
    }
    Theme.drawHeartRateGauge(dc, size / 8);
    Theme.drawHeartRateField(dc, top, edge, "HR");
    // A band too short for the bar and caption must fall back, not overflow.
    Theme.drawHeartRateField(dc, 0, size / 14, "HR");

    // The plus and minus of the set editor.
    Theme.drawSign(dc, size / 2, size / 3, size / 14, true, Theme.COLOR_ACCENT);
    Theme.drawSign(dc, size / 2, size / 2, size / 14, false, Theme.COLOR_ACCENT);
    return true;
}

//! Paint every page of the end-of-workout recap, with data and without it.
//!
//! The two charts — time in zone, and progress per exercise — are the only
//! drawing in the app that scales one number against another, which is where
//! a division by zero or an empty array turns into an uncatchable runtime
//! error. The simulator never reports a heart rate, so a populated zone chart
//! is drawn here or nowhere.
(:test)
function testSummaryPagesDraw(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;
    }
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    engine.completeCurrentSet(10, 50.0, TestSupport.T0);
    engine.selectExercise("B");
    engine.skipExercise("B");
    var summary = engine.finishWorkout(TestSupport.T0 + 1800);

    var zones = new ZoneTracker();
    for (var i = 0; i < 120; i++) { zones.sample(2); }
    for (var i = 0; i < 45; i++) { zones.sample(4); }
    for (var i = 0; i < 30; i++) { zones.sample(null); }

    var view = new WorkoutSummaryView(summary, engine.getWorkout(), zones, true);
    for (var page = 0; page < WorkoutSummaryView.PAGE_COUNT; page++) {
        view.onUpdate(dc);
        view.turnPage(1);
    }

    // And the same screens with nothing to show: no zone ever reached, and a
    // workout that was ended before a single set was logged.
    var empty = new WorkoutSummaryView(
        new SessionSummary(), TestSupport.abcWorkout(), new ZoneTracker(), false);
    for (var page = 0; page < WorkoutSummaryView.PAGE_COUNT; page++) {
        empty.onUpdate(dc);
        empty.turnPage(1);
    }
    return true;
}

//! Time in zone: the accumulator, and the empty case the chart has to handle.
//!
//! Seconds the watch could not place — no strap, no zones on the profile — are
//! counted as sampled but belong to no bar. A chart that folded them into a
//! zone would report effort that was never measured.
(:test)
function testZoneTrackerCountsOnlyWhatItSaw(logger as Test.Logger) as Boolean {
    var zones = new ZoneTracker();
    Test.assertEqual(zones.total(), 0);
    Test.assertEqual(zones.peakSeconds(), 0);
    Test.assert(zones.peakZone() == null);

    for (var i = 0; i < 10; i++) { zones.sample(3); }
    for (var i = 0; i < 4; i++) { zones.sample(5); }
    for (var i = 0; i < 6; i++) { zones.sample(null); }   // sensor acquiring
    zones.sample(0);                                       // out of range
    zones.sample(9);

    Test.assertEqual(zones.secondsIn(3), 10);
    Test.assertEqual(zones.secondsIn(5), 4);
    Test.assertEqual(zones.secondsIn(1), 0);
    Test.assertEqual(zones.secondsIn(0), 0);
    Test.assertEqual(zones.secondsIn(6), 0);
    Test.assertEqual(zones.total(), 14);
    Test.assertEqual(zones.sampled(), 22);
    Test.assert(zones.peakZone() == 3);
    Test.assertEqual(zones.peakSeconds(), 10);
    return true;
}

//! Draw every exercise-state icon, at a menu-sized canvas.
//!
//! Each state takes a different drawing path — disc, ring, polygon, bars — and
//! a Monkey C runtime error in any of them aborts the app rather than raising
//! something catchable. Running them all is the only way to know they work.
(:test)
function testStateIconsDraw(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;
    }
    var size = TestSupport.screenSize();
    var states = [EX_NOT_STARTED, EX_ACTIVE, EX_PENDING, EX_COMPLETED, EX_SKIPPED]
        as Array<ExerciseState>;
    for (var i = 0; i < states.size(); i++) {
        var icon = new StateIcon(states[i], size / 5);
        icon.setLocation(size / 20, size / 4);
        icon.draw(dc);
        // And at a size small enough that the guards have to bite.
        var tiny = new StateIcon(states[i], 8);
        tiny.setLocation(0, 0);
        tiny.draw(dc);
        Theme.stateColor(states[i]);
    }
    return true;
}

//! The set list has no cursor: the active set is always the next incomplete
//! one. That is what keeps logging a set to a single press, so it is worth
//! pinning down.
(:test)
function testActiveSetIsAlwaysTheNextIncompleteOne(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    var a = TestSupport.exerciseOf(engine, "A");

    Test.assertEqual(a.completedSetCount(), 0);
    Test.assertEqual(a.currentSetNumber(), 1);

    engine.completeCurrentSet(10, 50.0, TestSupport.T0);
    Test.assertEqual(a.completedSetCount(), 1);
    Test.assertEqual(a.currentSetNumber(), 2);

    engine.completeCurrentSet(10, 55.0, TestSupport.T0 + 60);
    Test.assertEqual(a.completedSetCount(), 2);
    Test.assert(a.hasReachedTargetSets());

    // Undo reopens the row that was just closed, and nothing else moves.
    engine.undoLastSet();
    Test.assertEqual(a.completedSetCount(), 1);
    Test.assertEqual(a.currentSetNumber(), 2);
    // The first row still holds what was actually lifted.
    Test.assertEqual(a.sets[0].actualReps as Number, 10);
    Test.assertEqual(a.sets[0].actualWeight as Float, 50.0);
    return true;
}

//! Weights are carried as tenths of a kilogram so the editor can step in whole
//! kilograms without floating-point drift. The conversion has to survive the
//! values a gym actually uses, half-kilo plates included.
(:test)
function testWeightTenthsRoundTrip(logger as Test.Logger) as Boolean {
    var weights = [0.0, 1.0, 2.5, 20.0, 57.5, 100.0, 137.5, 300.0] as Array<Float>;
    for (var i = 0; i < weights.size(); i++) {
        Test.assertEqual(Tuning.toTenths(weights[i]) / 10.0, weights[i]);
    }

    // The editor's step comes from the athlete's settings now, so what has to
    // hold is that stepping up and back down lands exactly where it started,
    // whatever the step is.
    var step = Units.step();
    Test.assert(step > 0.0);
    var start = 57.5;
    Test.assertEqual((start + step) - step, start);
    return true;
}

//! Device capability reads must never use a symbol the device does not have.
//!
//! `DeviceSettings.fontScale` does not exist on a Fenix 6 Pro, and reading it
//! there raises "Symbol Not Found" — a Monkey C runtime error, which is not an
//! Exception and is not caught by the try/catch that was wrapped around it.
//! The app died on the first screen it drew. Nothing but running the code on
//! the device catches that, so it runs here.
(:test)
function testDeviceCapabilitiesAreSafeToRead(logger as Test.Logger) as Boolean {
    Test.assert(Device.screenSize() > 0);
    Test.assert(Device.fontScale() > 0.0);
    Test.assert(Device.stroke(8) >= 1);
    var tier = Device.tier();
    Test.assert(tier == Device.TIER_LEAN || tier == Device.TIER_RICH);
    Device.animates();
    Device.isHighRes();

    // And the settings underneath them, including the defaults that apply when
    // nothing has ever been written from the phone.
    Test.assert(Settings.restDefault() >= 10);
    Test.assert(Settings.weightStepTenths() >= 1);
    Test.assert(Units.step() > 0.0);
    Test.assert(Units.label().length() > 0);
    Settings.haptics();
    Settings.repCounter();

    // Kilograms in, kilograms out, whichever unit is being displayed.
    var kg = 57.5;
    Test.assert((Units.toKg(Units.fromKg(kg)) - kg).abs() < 0.01);
    return true;
}
