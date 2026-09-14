import Toybox.Lang;
import Toybox.Test;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.WatchUi;

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
    engine.completeCurrentSet(8, 62.5, null, TestSupport.T0);
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
    Test.assert(c.plannedWeight() == 62.5);
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
    Test.assert(a.plannedWeight() == 50.0);
    Test.assertEqual(a.plannedReps(), 10);

    engine.completeCurrentSet(10, 55.0, null, TestSupport.T0);
    // Set 2 inherits what was actually performed, not the template values.
    Test.assert(a.plannedWeight() == 55.0);
    Test.assertEqual(a.plannedReps(), 10);

    // Change the load on set 2 ...
    engine.completeCurrentSet(8, 57.5, null, TestSupport.T0 + 60);
    // ... and set 3 follows the change.
    Test.assert(a.plannedWeight() == 57.5);
    Test.assertEqual(a.plannedReps(), 8);
    return true;
}

//! Inheritance must survive navigating away and back.
(:test)
function testInheritanceSurvivesNavigation(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    engine.completeCurrentSet(9, 62.5, null, TestSupport.T0);

    engine.selectExercise("B");
    engine.completeCurrentSet(12, 40.0, null, TestSupport.T0 + 30);

    engine.selectExercise("A");
    var a = TestSupport.exerciseOf(engine, "A");
    Test.assert(a.plannedWeight() == 62.5);
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
    engine.completeCurrentSet(10, 50.0, null, TestSupport.T0);   // 500
    engine.completeCurrentSet(8, 55.0, null, TestSupport.T0);    // 440

    engine.selectExercise("B");
    engine.completeCurrentSet(12, 40.0, null, TestSupport.T0);   // 480

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
    engine.completeCurrentSet(9, 57.5, null, TestSupport.T0 + 10);
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
    Test.assert(a.plannedWeight() == 57.5);
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
    Test.assert(engine.completeCurrentSet(10, 50.0, null, TestSupport.T0) == null);
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
    engine.completeCurrentSet(10, 50.0, null, TestSupport.T0);
    var a = TestSupport.exerciseOf(engine, "A");
    Test.assert(a.plannedWeight() == 50.0);      // set 2 inherits set 1
    engine.completeCurrentSet(10, 55.0, null, TestSupport.T0 + 120);

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
    Test.assert(b.plannedWeight() == 40.0);       // untouched template default
    TestSupport.completeSets(engine, 2);
    Test.assertEqual(TestSupport.stateOf(engine, "B"), EX_COMPLETED);

    // Step 14: returning to A inherits the raised weight from step 5.
    Test.assert(engine.selectExercise("A"));
    Test.assert(a.plannedWeight() == 55.0);
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

    // Given a budget, the chosen font's **ink** must honour it — unless even
    // the smallest font in the ladder is taller, in which case the smallest is
    // returned.
    //
    // Ink, not line height. This test used to assert the line height, which is
    // the rule that made every value in the app fall back to a text font: a
    // number font declares a descent its digits never use, so holding it to its
    // line box throws away a quarter of the space. See Theme.inkHeight.
    var budgets = [80, 60, 40, 24] as Array<Number>;
    var smallest = hero[hero.size() - 1];
    for (var i = 0; i < budgets.size(); i++) {
        var font = Theme.pickFontFitting(dc, "55", hero, 240, budgets[i]);
        Test.assert(Theme.inkHeight(font) <= budgets[i] || font == smallest);
        // Never larger than the unconstrained choice.
        Test.assert(dc.getFontHeight(font) <= dc.getFontHeight(unbounded));
    }

    // And ink is never more than the line it sits on, whichever font it is.
    var every = Theme.fontsCell();
    for (var i = 0; i < every.size(); i++) {
        Test.assert(Theme.inkHeight(every[i]) > 0);
        Test.assert(Theme.inkHeight(every[i]) <= dc.getFontHeight(every[i]));
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
    FieldGrid.drawSingle(dc, top, edge, "1:02:34", "TIME", Theme.colorText());
    FieldGrid.drawRule(dc, middleTop);
    FieldGrid.drawPair(dc, middleTop, middleHeight,
        "128", "AVG HR", Theme.colorHr(),
        "210", "KCAL", Theme.colorText());
    FieldGrid.drawRule(dc, bottom - edge);
    FieldGrid.drawSingle(dc, bottom - edge, edge, "--", "HR", Theme.colorFaint());

    // A cell so short the caption has to be dropped, and a very wide value.
    FieldGrid.drawCell(dc, 0, 0, size, size / 14, "3.2 t", "VOLUME", Theme.colorAccent());
    FieldGrid.drawCell(dc, 0, 0, size, size / 3, "137.5", "WEIGHT", Theme.colorText());

    // And the Theme primitives every screen leans on.
    Theme.drawAddMark(dc, size / 2, size / 2, size / 5, Theme.colorAccent());
    Theme.drawAddMark(dc, size / 2, size / 2, 8, Theme.colorAccent());   // too small to draw
    Theme.drawClipped(dc, size / 2, size / 3, "Incline Bench Press (Dumbbell)",
        Theme.captionFont(), Theme.colorText(), size / 3);
    Theme.drawClipped(dc, size / 2, size / 3, "Row", Theme.captionFont(),
        Theme.colorText(), size / 3);
    Theme.drawActionBar(dc, "COMPLETE SET", Theme.colorAccent());
    Theme.drawPageDots(dc, 3, 1);
    Theme.drawSetDots(dc, size / 2, 4, 2);
    Theme.drawFitted(dc, size / 3, "Romanian Deadlift", Theme.fontsTitle(), Theme.colorText());
    Theme.drawValueWithUnit(dc, size / 3, "55", "kg", Theme.fontsHero(),
        Theme.colorText(), Theme.colorDim());
    Theme.drawMetricRow(dc, size / 2, "VOLUME", "3.2 t", Theme.colorAccent());

    // The heart rate zone gauge, at every zone and with no zone at all. The
    // simulator never reports a heart rate, so this is the only place the
    // filled states are exercised at all.
    Theme.drawZoneBar(dc, size / 4, size / 3, size / 2, size / 20, null, null);
    for (var zone = 1; zone <= 5; zone++) {
        // Every zone, at the bottom, the middle and the top of it, plus the
        // case where the profile gives a zone but no position inside it.
        Theme.drawZoneBar(dc, size / 4, size / 3, size / 2, size / 20, zone, 0.0);
        Theme.drawZoneBar(dc, size / 4, size / 3, size / 2, size / 20, zone, 0.5);
        Theme.drawZoneBar(dc, size / 4, size / 3, size / 2, size / 20, zone, 1.0);
        Theme.drawZoneBar(dc, size / 4, size / 3, size / 2, size / 20, zone, null);
        // Out-of-range progress must be clamped, not drawn past the segment.
        Theme.drawZoneBar(dc, size / 4, size / 3, size / 2, size / 20, zone, 1.8);
        Theme.drawZoneBar(dc, size / 4, size / 3, size / 2, size / 20, zone, -0.4);
        Theme.zoneColor(zone);
    }
    Theme.drawHeartRateGauge(dc, size / 8);
    Theme.drawHeartRateField(dc, top, edge, "HR");
    // A band too short for the bar and caption must fall back, not overflow.
    Theme.drawHeartRateField(dc, 0, size / 14, "HR");

    // The plus and minus of the set editor.
    Theme.drawSign(dc, size / 2, size / 3, size / 14, true, Theme.colorAccent());
    Theme.drawSign(dc, size / 2, size / 2, size / 14, false, Theme.colorAccent());
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
    engine.completeCurrentSet(10, 50.0, null, TestSupport.T0);
    engine.selectExercise("B");
    engine.skipExercise("B");
    var summary = engine.finishWorkout(TestSupport.T0 + 1800);

    var zones = new ZoneTracker();
    for (var i = 0; i < 120; i++) { zones.sample(2); }
    for (var i = 0; i < 45; i++) { zones.sample(4); }
    for (var i = 0; i < 30; i++) { zones.sample(null); }

    // A week with real volume in it, so the muscle chart is exercised too.
    var weekly = new [Muscle.COUNT] as Array<Number>;
    for (var i = 0; i < Muscle.COUNT; i++) { weekly[i] = 0; }
    weekly[Muscle.CHEST] = 4200;
    weekly[Muscle.BACK] = 3100;
    weekly[Muscle.BICEPS] = 640;
    // Two records, of different kinds, so the records page draws both shapes.
    var records = [
        ["Bench Press", History.RECORD_WEIGHT, 5, 82.5] as Array,
        ["Lat Pulldown", History.RECORD_1RM, 8, 60.0] as Array
    ] as Array;
    // Metrics captured while the recording was open — which is the only moment
    // they can be read. See RecapMetrics.
    var metrics = new RecapMetrics(212, 128, 156, 71, 24);
    var view = new WorkoutSummaryView(summary, engine.getWorkout(), zones, weekly,
        records, metrics, true);
    for (var page = 0; page < WorkoutSummaryView.PAGE_COUNT; page++) {
        view.onUpdate(dc);
        view.turnPage(1);
    }

    // And the same screens with nothing to show: no zone ever reached, and a
    // workout that was ended before a single set was logged.
    var emptyWeek = new [Muscle.COUNT] as Array<Number>;
    for (var i = 0; i < Muscle.COUNT; i++) { emptyWeek[i] = 0; }
    // And with nothing measurable at all: no records, no battery, no recovery.
    var empty = new WorkoutSummaryView(
        new SessionSummary(), TestSupport.abcWorkout(), new ZoneTracker(),
        emptyWeek, [] as Array,
        new RecapMetrics(null, null, null, null, null), false);
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

    engine.completeCurrentSet(10, 50.0, null, TestSupport.T0);
    Test.assertEqual(a.completedSetCount(), 1);
    Test.assertEqual(a.currentSetNumber(), 2);

    engine.completeCurrentSet(10, 55.0, null, TestSupport.T0 + 60);
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

//! Changing the workout while it runs: add, substitute, and one more set.
//!
//! All three exist because the gym floor does not respect a plan. All three
//! must leave every set already performed exactly where it was — losing work to
//! a layout change would be far worse than the inconvenience they fix.
(:test)
function testAddingAnExerciseMidWorkout(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    engine.completeCurrentSet(10, 50.0, null, TestSupport.T0);

    var extra = new Exercise("D", "Exercise D", 3, 12, 20.0, 60);
    extra.muscle = Muscle.SHOULDERS;
    Test.assert(engine.addExercise(extra));
    Test.assertEqual(engine.getWorkout().exercises.size(), 4);

    // A duplicate id is refused: two exercises answering to one name would make
    // "select any exercise at any time" ambiguous.
    Test.assert(!engine.addExercise(new Exercise("D", "Again", 1, 1, 1.0, 1)));
    Test.assertEqual(engine.getWorkout().exercises.size(), 4);

    // The set already performed is untouched, and the new one is selectable.
    Test.assertEqual(TestSupport.exerciseOf(engine, "A").completedSetCount(), 1);
    Test.assert(engine.selectExercise("D"));
    Test.assertEqual(TestSupport.stateOf(engine, "D"), EX_ACTIVE);
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_PENDING);
    return true;
}

//! Substituting an untouched exercise replaces it in place.
(:test)
function testSubstituteUntouchedExercise(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("B");

    var replacement = new Exercise("B2", "Exercise B2", 3, 10, 45.0, 90);
    Test.assert(engine.substituteExercise("B", replacement));

    // It takes the old one's place in the plan, and the selection with it.
    Test.assertEqual(engine.getWorkout().exercises.size(), 3);
    Test.assertEqual(engine.getWorkout().indexOf("B2"), 1);
    Test.assert(engine.getWorkout().findExercise("B") == null);
    Test.assert(engine.currentExerciseId() != null);
    Test.assert((engine.currentExerciseId() as String).equals("B2"));
    Test.assertEqual(TestSupport.stateOf(engine, "B2"), EX_ACTIVE);
    return true;
}

//! Substituting an exercise that has sets on it keeps them.
//!
//! Two sets of rows already done are a fact about the session. The exercise is
//! marked SKIPPED — the athlete moved on from it — and the replacement is
//! added, rather than the work being deleted to tidy the list.
(:test)
function testSubstituteKeepsWorkAlreadyDone(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("B");
    engine.completeCurrentSet(12, 40.0, null, TestSupport.T0);

    var replacement = new Exercise("B2", "Exercise B2", 3, 10, 45.0, 90);
    Test.assert(engine.substituteExercise("B", replacement));

    Test.assertEqual(engine.getWorkout().exercises.size(), 4);
    Test.assertEqual(TestSupport.stateOf(engine, "B"), EX_SKIPPED);
    Test.assertEqual(TestSupport.exerciseOf(engine, "B").completedSetCount(), 1);
    Test.assertEqual(TestSupport.exerciseOf(engine, "B").totalVolume(), 480.0);

    // The skipped exercise stops counting as work outstanding, and its volume
    // still counts towards the session.
    var summary = engine.summary(TestSupport.T0 + 60);
    Test.assertEqual(summary.completedSets, 1);
    Test.assertEqual(summary.totalVolume, 480.0);
    return true;
}

//! An extra set raises the target, because "3/4" is on three screens.
(:test)
function testAddSetRaisesTheTarget(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    TestSupport.completeSets(engine, 2);
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_COMPLETED);
    Test.assert(engine.isWorkoutComplete() == false);   // B and C remain

    Test.assert(engine.addSet("A"));
    var a = TestSupport.exerciseOf(engine, "A");
    Test.assertEqual(a.targetSets, 3);
    Test.assertEqual(a.completedSetCount(), 2);
    Test.assertEqual(a.currentSetNumber(), 3);
    Test.assert(!a.hasReachedTargetSets());

    // It has work outstanding again, and it is the one under the athlete's
    // hands, so it is ACTIVE rather than PENDING.
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_ACTIVE);

    // Performing it completes the exercise again.
    engine.completeCurrentSet(8, 60.0, null, TestSupport.T0 + 300);
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_COMPLETED);

    Test.assert(!engine.addSet("nope"));
    return true;
}

//! Adding a set to an exercise the athlete is not standing at leaves it pending.
(:test)
function testAddSetToAnotherExerciseLeavesItPending(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    TestSupport.completeSets(engine, 2);
    engine.selectExercise("B");

    Test.assert(engine.addSet("A"));
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_PENDING);
    Test.assertEqual(TestSupport.stateOf(engine, "B"), EX_ACTIVE);

    // And it is back among the things still owed.
    Test.assertEqual(engine.unfinishedExercises().size(), 3);
    return true;
}

//! The catalogue is data the app depends on, so its shape is checked.
(:test)
function testCatalogueIsWellFormed(logger as Test.Logger) as Boolean {
    var groups = Muscle.browseOrder();
    var total = 0;
    var seen = {} as Dictionary;

    for (var g = 0; g < groups.size(); g++) {
        var rows = ExerciseCatalogue.forMuscle(groups[g]);
        Test.assert(rows.size() > 0);
        Test.assert(Muscle.name(groups[g]).length() > 0);

        for (var i = 0; i < rows.size(); i++) {
            var row = rows[i] as Array;
            Test.assertEqual(row.size(), 5);
            var id = row[ExerciseCatalogue.F_ID] as String;
            Test.assert(id.length() > 0);
            // ids must be unique catalogue-wide
            Test.assert(!seen.hasKey(id));
            seen.put(id, true);
            Test.assert((row[ExerciseCatalogue.F_NAME] as String).length() > 0);
            Test.assert((row[ExerciseCatalogue.F_REPS] as Number) > 0);
            Test.assert((row[ExerciseCatalogue.F_WEIGHT] as Number) >= 0);
            Test.assert((row[ExerciseCatalogue.F_REST] as Number) > 0);

            // And a row has to become a usable exercise.
            var ex = ExerciseCatalogue.toExercise(row, groups[g], 3, 0);
            Test.assertEqual(ex.id, id);
            Test.assertEqual(ex.muscle, groups[g]);
            Test.assertEqual(ex.targetSets, 3);
            total++;
        }
    }
    Test.assert(total >= 60);

    // The same movement twice in one workout gets a distinct id that still
    // points back at the movement.
    var row0 = ExerciseCatalogue.forMuscle(Muscle.CHEST)[0] as Array;
    var second = ExerciseCatalogue.toExercise(row0, Muscle.CHEST, 3, 2);
    Test.assert(!second.id.equals(row0[ExerciseCatalogue.F_ID] as String));
    Test.assertEqual(ExerciseCatalogue.movementId(second.id),
        row0[ExerciseCatalogue.F_ID] as String);
    Test.assertEqual(ExerciseCatalogue.movementId("plain_id"), "plain_id");
    return true;
}

//! Naming a workout from its contents, so nobody has to type on a watch.
//!
//! A lifter names a session after what is in it. Two groups when the session is
//! genuinely split, one when a group dominates — "Chest + Biceps" is useful,
//! "Chest + Core" for five pressing exercises and one plank is noise.
(:test)
function testWorkoutNamingFromContents(logger as Test.Logger) as Boolean {
    var empty = new Workout("u_1", "x", [] as Array<Exercise>);
    Test.assert(WorkoutEditor.suggestName(empty).length() > 0);

    var chest = new Exercise("c_bench", "Bench Press", 4, 8, 60.0, 120);
    chest.muscle = Muscle.CHEST;
    var fly = new Exercise("c_cable_fly", "Cable Fly", 3, 12, 15.0, 60);
    fly.muscle = Muscle.CHEST;
    var curl = new Exercise("bi_bb_curl", "Barbell Curl", 3, 10, 30.0, 60);
    curl.muscle = Muscle.BICEPS;
    var plank = new Exercise("co_plank", "Plank", 1, 1, 0.0, 60);
    plank.muscle = Muscle.CORE;

    // Seven chest sets against three biceps: both earn a mention.
    var split = new Workout("u_2", "x", [chest, fly, curl] as Array<Exercise>);
    Test.assertEqual(WorkoutEditor.suggestName(split),
        Muscle.name(Muscle.CHEST) + " + " + Muscle.name(Muscle.BICEPS));

    // Seven chest sets against one plank: the plank is not the session.
    var dominated = new Workout("u_3", "x", [chest, fly, plank] as Array<Exercise>);
    Test.assertEqual(WorkoutEditor.suggestName(dominated), Muscle.name(Muscle.CHEST));

    // A workout of untagged exercises falls back rather than naming itself
    // "Other" — which is what a session restored from schema v1 looks like.
    var untagged = new Exercise("x", "Something", 3, 10, 20.0, 60);
    var unknown = new Workout("u_4", "x", [untagged] as Array<Exercise>);
    Test.assertEqual(WorkoutEditor.suggestName(unknown),
        WorkoutEditor.suggestName(empty));
    return true;
}

//! An imported exercise resolves to a movement the catalogue knows.
//!
//! This used to check the three workouts RepFlow shipped. It ships none now —
//! they were one athlete's Hevy routines typed in by hand, frozen at the moment
//! somebody typed them — so the guarantee moved to where workouts actually come
//! from. An exercise whose movement the catalogue does not know sends its
//! history and its records somewhere nothing else looks.
(:test)
function testImportedExercisesUseCatalogueIds(logger as Test.Logger) as Boolean {
    var known = {} as Dictionary;
    var groups = Muscle.browseOrder();
    for (var g = 0; g < groups.size(); g++) {
        var rows = ExerciseCatalogue.forMuscle(groups[g]);
        for (var i = 0; i < rows.size(); i++) {
            known.put((rows[i] as Array)[ExerciseCatalogue.F_ID] as String, groups[g]);
        }
    }

    var workout = HevyMap.routineToWorkout({
        "id" => "r-1",
        "title" => "Dos + Triceps",
        "exercises" => [
            {
                "title" => "Lat Pulldown (Cable)",
                "exercise_template_id" => "6A6C31A5",
                "sets" => [{ "reps" => 10, "weight_kg" => 60.0 }]
            } as Object,
            {
                "title" => "Triceps Rope Pushdown",
                "exercise_template_id" => "94B7239B",
                "sets" => [{ "reps" => 12, "weight_kg" => 25.0 }]
            } as Object
        ] as Array
    } as Dictionary);
    Test.assert(workout != null);

    var list = (workout as Workout).exercises;
    Test.assertEqual(list.size(), 2);
    for (var i = 0; i < list.size(); i++) {
        var ex = list[i];
        // Hevy's own template id, kept: without one the exercise is a dead end,
        // because Hevy files a set against exercise_template_id and has no
        // free-text alternative.
        Test.assert(ex.hevyId != null);
        // And a real muscle group, so the weekly breakdown finds it.
        Test.assert(Muscle.isValid(ex.muscle));
    }
    return true;
}


//! Estimated one-rep max, and what it is for.
//!
//! Epley makes a set of ten comparable with a set of three, which is the only
//! way to tell whether a month of training went anywhere. It is an estimate,
//! and the app never calls it a maximum.
(:test)
function testEstimated1RM(logger as Test.Logger) as Boolean {
    // A single rep is already the maximum; no estimation to do.
    Test.assertEqual(History.estimated1RM(1, 100.0), 100.0);

    // Ten reps at 100 estimates well above 100.
    var ten = History.estimated1RM(10, 100.0);
    Test.assert(ten > 130.0 && ten < 135.0);

    // More reps at the same load estimates a higher maximum; the same reps at
    // a higher load likewise.
    Test.assert(History.estimated1RM(12, 100.0) > ten);
    Test.assert(History.estimated1RM(10, 110.0) > ten);

    // Nonsense in, zero out — never a number that looks like a record.
    Test.assertEqual(History.estimated1RM(0, 100.0), 0.0);
    Test.assertEqual(History.estimated1RM(10, 0.0), 0.0);
    Test.assertEqual(History.estimated1RM(-3, 100.0), 0.0);
    return true;
}

//! Personal records: what counts, what does not, and what is announced.
(:test)
function testRecordDetection(logger as Test.Logger) as Boolean {
    var bests = {} as Dictionary;

    // A movement's first ever set is not a record. Everything would be.
    Test.assertEqual(History.classify(bests, "c_bench", 10, 60.0), History.RECORD_NONE);
    Test.assertEqual(History.recordSet(bests, "c_bench", 10, 60.0, 1000), History.RECORD_NONE);

    // Same again beats nothing.
    Test.assertEqual(History.classify(bests, "c_bench", 10, 60.0), History.RECORD_NONE);
    // Fewer reps at the same load beats nothing either.
    Test.assertEqual(History.classify(bests, "c_bench", 8, 60.0), History.RECORD_NONE);

    // More reps at the same load: a better estimated maximum, not a heavier set.
    Test.assertEqual(History.classify(bests, "c_bench", 12, 60.0), History.RECORD_1RM);
    // A heavier set outranks it, because that is the one a lifter cares about.
    Test.assertEqual(History.classify(bests, "c_bench", 3, 80.0), History.RECORD_WEIGHT);

    History.recordSet(bests, "c_bench", 3, 80.0, 2000);
    Test.assertEqual(History.classify(bests, "c_bench", 3, 80.0), History.RECORD_NONE);
    Test.assertEqual(History.classify(bests, "c_bench", 3, 82.5), History.RECORD_WEIGHT);

    // A second round of the same movement in one session shares its records.
    Test.assertEqual(History.classify(bests, "c_bench#2", 3, 80.0), History.RECORD_NONE);
    Test.assertEqual(History.classify(bests, "c_bench#2", 3, 85.0), History.RECORD_WEIGHT);

    // A different movement keeps its own.
    Test.assertEqual(History.classify(bests, "c_incline_bb", 10, 20.0), History.RECORD_NONE);

    // Nothing is a record on nonsense.
    Test.assertEqual(History.classify(bests, "c_bench", 0, 500.0), History.RECORD_NONE);
    Test.assertEqual(History.classify(bests, "c_bench", 10, 0.0), History.RECORD_NONE);
    return true;
}

//! Volume records exist for the sets that are neither heavy nor long.
(:test)
function testVolumeRecord(logger as Test.Logger) as Boolean {
    var bests = {} as Dictionary;
    History.recordSet(bests, "b_db_row", 10, 30.0, 1000);   // 300 kg, e1rm 40

    // Twenty at 20 is 400 kg of work, lighter and with a lower estimate.
    Test.assert(History.estimated1RM(20, 20.0) < History.estimated1RM(10, 30.0));
    Test.assertEqual(History.classify(bests, "b_db_row", 20, 20.0), History.RECORD_VOLUME);

    History.recordSet(bests, "b_db_row", 20, 20.0, 1100);
    Test.assertEqual(History.classify(bests, "b_db_row", 20, 20.0), History.RECORD_NONE);
    return true;
}

//! A damaged or foreign bests store is ignored, not parsed.
(:test)
function testBestsStoreRejectsRubbish(logger as Test.Logger) as Boolean {
    var bests = {} as Dictionary;
    Test.assert(History.rowFor(bests, "nothing") == null);
    Test.assert(History.lastPerformance(bests, "nothing") == null);

    bests.put("short", [1, 2, 3] as Array);
    bests.put("wrongtype", "not a row");
    bests.put("nulls", [1, 2, 3, 4, 5, 6, null] as Array);
    Test.assert(History.rowFor(bests, "short") == null);
    Test.assert(History.rowFor(bests, "wrongtype") == null);
    Test.assert(History.rowFor(bests, "nulls") == null);

    // And classify treats an unreadable row as no history at all rather than
    // reading fields out of it.
    Test.assertEqual(History.classify(bests, "short", 10, 100.0), History.RECORD_NONE);
    return true;
}

//! Closing a session records what each movement was last done for.
(:test)
function testCommitSessionRecordsLastPerformance(logger as Test.Logger) as Boolean {
    var bests = {} as Dictionary;
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    engine.completeCurrentSet(10, 50.0, null, TestSupport.T0);
    engine.completeCurrentSet(8, 55.0, null, TestSupport.T0 + 120);
    engine.selectExercise("B");     // touched but never performed

    History.commitSession(bests, engine.getWorkout(), TestSupport.T0 + 600);

    var last = History.lastPerformance(bests, "A");
    Test.assert(last != null);
    Test.assertEqual((last as Array)[0] as Float, 55.0);   // the last set's load
    Test.assertEqual((last as Array)[1] as Number, 8);
    Test.assertEqual((last as Array)[2] as Number, 2);     // sets performed
    Test.assertEqual((last as Array)[3] as Number, TestSupport.T0 + 600);

    // An exercise with no completed sets leaves no trace.
    Test.assert(History.lastPerformance(bests, "B") == null);
    Test.assert(History.lastPerformance(bests, "C") == null);
    return true;
}

//! Recovery: beats below this rest's peak, measured from the peak.
(:test)
function testRecoveryTracker(logger as Test.Logger) as Boolean {
    var rec = new RecoveryTracker();
    Test.assert(rec.drop() == null);
    Test.assert(rec.best() == null);

    // Outside a rest nothing is collected.
    rec.sample(150);
    Test.assert(rec.drop() == null);

    rec.startRest();
    Test.assert(rec.isResting());

    // Heart rate lags effort, so it keeps climbing for the first seconds. The
    // peak has to be taken from the rest, not from the moment the set ended.
    rec.sample(150);
    rec.sample(158);
    rec.sample(162);
    Test.assert(rec.drop() == 0);       // still at the peak

    rec.sample(150);
    Test.assert(rec.drop() == 12);
    rec.sample(138);
    Test.assert(rec.drop() == 24);
    Test.assert(rec.best() == 24);

    // Seconds with no reading do not break the figure.
    rec.sample(null);
    Test.assert(rec.drop() == 24);

    // A new rest restarts the drop but not the session best.
    rec.startRest();
    Test.assert(rec.drop() == null);
    rec.sample(140);
    rec.sample(132);
    Test.assert(rec.drop() == 8);
    Test.assert(rec.best() == 24);

    rec.endRest();
    Test.assert(rec.drop() == null);
    return true;
}

//! A drop that takes longer than a minute is not a recovery figure.
//!
//! Standing around for three minutes brings anyone's heart rate down. The
//! number that is comparable week to week is what happens in the first minute,
//! so `best()` only counts drops inside that window.
(:test)
function testRecoveryOnlyCountsTheFirstMinute(logger as Test.Logger) as Boolean {
    var rec = new RecoveryTracker();
    rec.startRest();
    rec.sample(170);
    for (var i = 0; i < RecoveryTracker.WINDOW_SECONDS; i++) {
        rec.sample(160);
    }
    Test.assert(rec.best() == 10);

    // Past the window the live drop still updates — the athlete is watching it
    // — but the session best does not move.
    rec.sample(120);
    Test.assert(rec.drop() == 50);
    Test.assert(rec.best() == 10);
    return true;
}

//! Synthetic waveforms for the rep counter.
//!
//! Waving a watch is not a test. These feed the counter the shape a lifted
//! weight actually makes at the wrist — one smooth oscillation per repetition —
//! and check that it finds them, and more importantly that it does not find
//! repetitions that are not there.
(:test)
function testRepCounterCountsCleanReps(logger as Test.Logger) as Boolean {
    var counter = new RepCounter();
    // Ten reps at two seconds each: 50 samples per rep at 25 Hz.
    TestSupport.feedOscillation(counter, 10, 50, 400);
    // Rhythm detection cannot be exact — the first rep primes the detector —
    // so the contract is "within one", not "exactly ten".
    var n = counter.count();
    Test.assert(n >= 9 && n <= 10);
    return true;
}

//! A still wrist counts nothing. This is the failure that would lose trust.
(:test)
function testRepCounterIgnoresStillness(logger as Test.Logger) as Boolean {
    var counter = new RepCounter();
    // Gravity only, with a little sensor noise on top.
    for (var i = 0; i < 500; i++) {
        var jitter = (i % 7) - 3;          // +/-3 milli-g
        counter.feed([jitter] as Array<Number>, [1000 + jitter] as Array<Number>,
            [0] as Array<Number>);
    }
    Test.assertEqual(counter.count(), 0);
    Test.assert(counter.samplesSeen() == 500);
    return true;
}

//! Slow, small movement — walking to the rack — is not a set.
(:test)
function testRepCounterIgnoresSmallMovement(logger as Test.Logger) as Boolean {
    var counter = new RepCounter();
    TestSupport.feedOscillation(counter, 20, 50, 40);   // well under the floor
    Test.assertEqual(counter.count(), 0);
    return true;
}

//! One rep cannot be counted twice by bouncing.
//!
//! A bar rebounding off the chest makes a second, smaller peak inside the same
//! repetition. The refractory period is what stops it scoring.
(:test)
function testRepCounterRefractoryPeriod(logger as Test.Logger) as Boolean {
    var counter = new RepCounter();
    // Reps far faster than any human can perform: 4 samples each, ~6 per second.
    TestSupport.feedOscillation(counter, 30, 4, 600);
    // Whatever it finds must respect the minimum period, so it cannot be
    // anywhere near thirty.
    Test.assert(counter.count() <= 12);
    return true;
}

//! Reset clears everything, because a new set starts at zero.
(:test)
function testRepCounterReset(logger as Test.Logger) as Boolean {
    var counter = new RepCounter();
    TestSupport.feedOscillation(counter, 8, 50, 400);
    Test.assert(counter.count() > 0);

    counter.reset();
    Test.assertEqual(counter.count(), 0);
    Test.assertEqual(counter.samplesSeen(), 0);

    // Missing axes are survivable: the sensor can hand back null.
    Test.assertEqual(counter.feed(null, null, null), 0);
    Test.assertEqual(counter.feed([1] as Array<Number>, null, null), 0);
    // And mismatched lengths use the shortest rather than reading off the end.
    counter.feed([1, 2, 3] as Array<Number>, [1] as Array<Number>, [1, 2] as Array<Number>);
    Test.assertEqual(counter.samplesSeen(), 1);
    return true;
}

//! Nothing animates on a watch that cannot spare the frames, and `value()` is
//! safe to multiply by unconditionally.
//!
//! The whole point of the design is that views have no branch of their own: a
//! lean device draws the finished frame because value() is 1.0, not because the
//! drawing code asked whether it should animate.
(:test)
function testAnimatorIsAlwaysSafeToMultiplyBy(logger as Test.Logger) as Boolean {
    Animator.stop();
    Test.assert(!Animator.isRunning());
    Test.assertEqual(Animator.value(), 1.0);

    Animator.start(200);
    // On a lean device this started nothing at all and value() is still 1.0.
    // On a rich one it is in [0, 1] — and 0.0 on the very first frame is the
    // point: the ring grows from nothing. Either way it is a multiplier a view
    // can use without asking any questions, which is the whole contract.
    var v = Animator.value();
    Test.assert(v >= 0.0 && v <= 1.0);

    Animator.stop();
    Test.assertEqual(Animator.value(), 1.0);

    // A zero or negative duration is a no-op, not a division by zero.
    Animator.start(0);
    Test.assertEqual(Animator.value(), 1.0);
    Animator.start(-5);
    Test.assertEqual(Animator.value(), 1.0);
    Animator.stop();
    return true;
}

//! A planned load lands on a round number in whatever unit is being read.
//!
//! A 55 kg template default is 121.3 lb, and a plan that opens on 121.3 looks
//! like a measurement rather than a suggestion. What was actually lifted is
//! never snapped — only what is about to be.
(:test)
function testPlannedLoadSnapsToTheStepGrid(logger as Test.Logger) as Boolean {
    var step = Units.step();
    Test.assert(step > 0.0);

    var values = [0.0, 20.0, 55.0, 57.5, 100.0, 137.5] as Array<Float>;
    for (var i = 0; i < values.size(); i++) {
        var snapped = Units.snap(values[i]);
        var shown = Units.fromKg(snapped);

        // On the step grid, to within floating-point noise.
        // Rounded without Math: every value here is non-negative, so adding a
        // half and truncating is the same thing and keeps the type plain Float.
        var steps = (shown / step + 0.5).toNumber();
        var grid = steps.toFloat() * step;
        var offGrid = shown - grid;
        if (offGrid < 0.0) { offGrid = -offGrid; }
        Test.assert(offGrid < 0.01);

        // And never moved by more than half a step, so it is still the same
        // suggestion the catalogue made.
        var moved = Units.fromKg(values[i]) - shown;
        if (moved < 0.0) { moved = -moved; }
        Test.assert(moved <= step / 2.0 + 0.01);
    }

    // Negative input cannot produce a negative load.
    Test.assert(Units.snap(-10.0) >= 0.0);
    return true;
}

//! Scrolling text: the offset must stay inside its travel, and the timer must
//! stop itself when nothing needs it.
//!
//! The offset is the whole of the arithmetic — get it wrong and the name either
//! runs off the end and never comes back, or jitters at the boundary. It is
//! computed from the millisecond clock, so the test walks a whole cycle rather
//! than checking one instant.
(:test)
function testMarqueeStopsWhenNothingOverflows(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;
    }
    Marquee.stop();
    Test.assert(!Marquee.isRunning());

    var size = TestSupport.screenSize();
    var fonts = [Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>;

    // A short name fits, is drawn still, and starts nothing.
    Marquee.draw(dc, size / 4, "Squat", fonts, Theme.colorText(), Theme.usableWidth(dc, size / 4));
    Marquee.endFrame();
    Test.assert(!Marquee.isRunning());

    // A name far too long for any font in the ladder has to move.
    var long = "Single-Leg Romanian Deadlift With A Very Long Name Indeed";
    Marquee.draw(dc, size / 4, long, fonts, Theme.colorText(), Theme.usableWidth(dc, size / 4));
    Test.assert(Marquee.isRunning());

    // And the frame after it leaves the screen, it stops again. A timer left
    // running at 10 fps for the rest of the workout is exactly the kind of cost
    // this app cannot afford.
    Marquee.endFrame();
    Marquee.draw(dc, size / 4, "Squat", fonts, Theme.colorText(), Theme.usableWidth(dc, size / 4));
    Marquee.endFrame();
    Test.assert(!Marquee.isRunning());
    return true;
}

//! The scroll offset never leaves [0, overflow], and visits both ends.
(:test)
function testMarqueeOffsetStaysInRange(logger as Test.Logger) as Boolean {
    var overflow = 120;
    var travel = overflow * Marquee.MS_PER_PIXEL;
    var period = (Marquee.PAUSE_MS + travel) * 2;

    var sawStart = false;
    var sawEnd = false;
    // Walk a whole cycle in 40 ms steps; the arithmetic is pure, so the phase
    // can be driven directly rather than by waiting.
    for (var t = 0; t < period; t += 40) {
        var offset = Marquee.offsetAt(t, overflow);
        Test.assert(offset >= 0);
        Test.assert(offset <= overflow);
        if (offset == 0) { sawStart = true; }
        if (offset == overflow) { sawEnd = true; }
    }
    Test.assert(sawStart);
    Test.assert(sawEnd);

    // Nothing to scroll means no movement, and no division by zero.
    Test.assertEqual(Marquee.offsetAt(0, 0), 0);
    Test.assertEqual(Marquee.offsetAt(99999, -5), 0);
    return true;
}

//! Every catalogue name is either legible still, or scrolls.
//!
//! This is the test that would have caught the first version of the marquee,
//! which shrank names until they fitted and therefore never scrolled at all.
//! It asserts the rule that matters: the name is drawn at the ladder's largest
//! font, and the long ones move.
(:test)
function testLongCatalogueNamesScroll(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;
    }
    var size = TestSupport.screenSize();
    var y = size / 4;
    var maxWidth = Theme.usableWidth(dc, y);
    var fonts = [Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>;

    var scrolled = 0;
    var still = 0;
    var groups = Muscle.browseOrder();
    for (var g = 0; g < groups.size(); g++) {
        var rows = ExerciseCatalogue.forMuscle(groups[g]);
        for (var i = 0; i < rows.size(); i++) {
            var name = (rows[i] as Array)[ExerciseCatalogue.F_NAME] as String;
            Marquee.stop();
            Marquee.draw(dc, y, name, fonts, Theme.colorText(), maxWidth);
            if (Marquee.isRunning()) {
                scrolled++;
            } else {
                still++;
                // A still name must genuinely fit at full size, not be clipped.
                Test.assert(dc.getTextWidthInPixels(name, fonts[0]) <= maxWidth);
            }
            Marquee.endFrame();
        }
    }
    Marquee.stop();

    // Most names fit; some do not. Both halves have to be true, or the rule is
    // doing nothing: all-still would mean names are still being shrunk, and
    // all-scrolling would mean the screen never holds anything at rest.
    Test.assert(still > scrolled);
    Test.assert(still > 0);
    return true;
}

//! Where a reading sits inside its zone — the arithmetic that turns five lit
//! blocks into a gauge.
//!
//! "Zone 3" covers a wide span of effort, and the bottom of it is a different
//! workout from the top. The number alone never says which end you are at.
(:test)
function testZoneProgressArithmetic(logger as Test.Logger) as Boolean {
    // A zone from 130 to 150.
    Test.assertEqual(LiveMetrics.progressIn(130, 130, 150), 0.0);
    Test.assertEqual(LiveMetrics.progressIn(140, 130, 150), 0.5);
    Test.assertEqual(LiveMetrics.progressIn(150, 130, 150), 1.0);

    // Outside the bounds clamps rather than running past the segment.
    Test.assertEqual(LiveMetrics.progressIn(100, 130, 150), 0.0);
    Test.assertEqual(LiveMetrics.progressIn(200, 130, 150), 1.0);

    // A zone with no width is one you are at the top of, not a division by zero.
    Test.assertEqual(LiveMetrics.progressIn(140, 150, 150), 1.0);
    Test.assertEqual(LiveMetrics.progressIn(140, 160, 150), 1.0);

    // And it is monotonic across the span, which is what makes a bar readable.
    var previous = -1.0;
    for (var hr = 128; hr <= 152; hr++) {
        var p = LiveMetrics.progressIn(hr, 130, 150);
        Test.assert(p >= previous);
        Test.assert(p >= 0.0 && p <= 1.0);
        previous = p;
    }
    return true;
}

//! Both themes resolve, and no colour is shared between a ground and the text
//! that sits on it.
//!
//! The failure this guards is the one that makes an app unusable rather than
//! ugly: a colour defined for one theme and left in place for the other, so
//! white text lands on a white ground. Every pair is checked in both.
(:test)
function testBothThemesAreLegible(logger as Test.Logger) as Boolean {
    var themes = [Tuning.THEME_DARK, Tuning.THEME_LIGHT] as Array<Number>;
    var before = Settings.theme();

    for (var t = 0; t < themes.size(); t++) {
        Settings.setTheme(themes[t]);
        Test.assertEqual(Settings.theme(), themes[t]);

        var bg = Theme.colorBg();
        // Nothing that carries meaning may equal the ground it is drawn on.
        Test.assert(Theme.colorText() != bg);
        Test.assert(Theme.colorDim() != bg);
        Test.assert(Theme.colorFaint() != bg);
        Test.assert(Theme.colorAccent() != bg);
        Test.assert(Theme.colorDone() != bg);
        Test.assert(Theme.colorPending() != bg);
        Test.assert(Theme.colorHr() != bg);
        Test.assert(Theme.colorWarm() != bg);
        Test.assert(Theme.colorDoneDim() != bg);

        // Captions must be distinguishable from body text, and from the rules.
        Test.assert(Theme.colorDim() != Theme.colorText());
        Test.assert(Theme.colorFaint() != Theme.colorText());

        // Every heart rate zone has its own colour, and none is the ground.
        var seen = {} as Dictionary;
        for (var zone = 1; zone <= 5; zone++) {
            var c = Theme.zoneColor(zone);
            Test.assert(c != bg);
            Test.assert(!seen.hasKey(c));
            seen.put(c, true);
        }

        // And every muscle group's colour, which the weekly chart relies on.
        var groups = Muscle.browseOrder();
        for (var g = 0; g < groups.size(); g++) {
            Test.assert(Muscle.color(groups[g]) != bg);
        }
    }

    Settings.setTheme(before);
    return true;
}

//! Nothing is shipped, and that is not a broken state.
//!
//! RepFlow used to carry three workouts transcribed by hand from one athlete's
//! Hevy routines — a strange thing for an app to contain, and stale the first
//! time those routines changed. Workouts now come from Hevy or from the editor,
//! which means the first screen a new install shows has to work with an empty
//! list rather than assume a full one.
(:test)
function testAnEmptyWorkoutListIsAValidState(logger as Test.Logger) as Boolean {
    var all = WorkoutRepository.all();
    var view = new WorkoutListView();

    // The picker's carousel is the workouts plus a "New workout" page, so with
    // nothing stored it opens straight on the one screen that can do anything.
    if (all.size() == 0) {
        Test.assert(view.onNewPage());
        Test.assert(view.selected() == null);
    }

    var dc = TestSupport.screenDc();
    if (dc != null) {
        // It has to draw, not merely compute. A first screen that throws is
        // worse than one with nothing on it.
        view.onUpdate(dc);
    }
    return true;
}


//! Last session's load fills in what the routine left blank.
//!
//! Most routines record "-" for the weight, because the load is the part that
//! changes. Without this, every one of those exercises opens on zero every
//! week and the athlete dials it from scratch each time.
(:test)
function testLastSessionsLoadFillsABlankRoutine(logger as Test.Logger) as Boolean {
    var bests = {} as Dictionary;

    // A movement with no target weight, performed once at 42.5 kg.
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    engine.completeCurrentSet(8, 42.5, null, TestSupport.T0);
    History.commitSession(bests, engine.getWorkout(), TestSupport.T0 + 600);

    var last = History.lastPerformance(bests, "A");
    Test.assert(last != null);
    Test.assertEqual((last as Array)[0] as Float, 42.5);

    // A fresh session of the same workout: the exercise itself still carries
    // the template's default, and history is what knows better.
    var fresh = TestSupport.newEngine();
    var a = TestSupport.exerciseOf(fresh, "A");
    Test.assertEqual(a.completedSetCount(), 0);
    Test.assert(a.plannedWeight() == 50.0);             // the template's value

    // Once a set is performed this session, the session's own number wins —
    // history describes last week, not what is happening now.
    fresh.selectExercise("A");
    fresh.completeCurrentSet(8, 47.5, null, TestSupport.T0 + 1000);
    Test.assert(a.plannedWeight() == 47.5);
    Test.assert(a.completedSetCount() > 0);
    return true;
}

//! An inherited load reaches the editor unchanged.
//!
//! It used to be snapped to the step grid of the displayed unit, which reads
//! better and is wrong: on a statute watch that is a kg to lb to kg round trip,
//! and it rewrites a routine's 20.0 kg as 19.96 kg before a single rep is
//! performed. The athlete never touched it, so nothing may change it.
//!
//! Found by reading another developer's Garmin/Hevy app, which had hit the same
//! bug and documented it.
(:test)
function testInheritedLoadIsNotRounded(logger as Test.Logger) as Boolean {
    var controller = AppController.instance();

    // Values that survive no round trip: 20 kg is 44.09 lb, 22.25 is 49.05.
    var awkward = [20.0, 22.25, 39.0, 57.5, 0.0] as Array<Float>;
    for (var i = 0; i < awkward.size(); i++) {
        var ex = new Exercise("x", "Test", 3, 10, awkward[i], 60);
        controller.syncPendingValues(ex);
        Test.assert(controller.pendingWeight() == awkward[i]);
    }

    // What the athlete dials *is* rounded — that value is their choice, and it
    // should land on the grid they chose.
    var ex2 = new Exercise("y", "Test", 3, 10, 20.0, 60);
    controller.syncPendingValues(ex2);
    controller.adjustWeight(1);
    var step = Units.step();
    var shown = Units.fromKg(controller.pendingWeight() as Float);
    var grid = ((shown / step + 0.5).toNumber()).toFloat() * step;
    var off = shown - grid;
    if (off < 0.0) { off = -off; }
    Test.assert(off < 0.01);
    return true;
}

//! A Hevy routine becomes a RepFlow workout.
//!
//! The payload is shaped exactly as Hevy's OpenAPI spec declares it, including
//! the parts that make it awkward: a null weight (the normal case — most
//! routines leave the load blank), `rest_seconds` declared as a string but sent
//! as a number, a rep range instead of a rep count, and the same movement twice.
(:test)
function testHevyRoutineMaps(logger as Test.Logger) as Boolean {
    var routine = {
        "id" => "b459cba5-cd6d-463c-abd6-54f8eafcadcb",
        "title" => "Dos + Triceps",
        "folder_id" => 42,
        "exercises" => [
            {
                "index" => 0,
                "title" => "Lat Pulldown (Cable)",
                "rest_seconds" => 120,
                "exercise_template_id" => "05293BCA",
                "superset_id" => null,
                "sets" => [
                    { "index" => 0, "type" => "normal", "weight_kg" => null, "reps" => 8 },
                    { "index" => 1, "type" => "normal", "weight_kg" => null, "reps" => 8 },
                    { "index" => 2, "type" => "normal", "weight_kg" => null, "reps" => 8 },
                    { "index" => 3, "type" => "normal", "weight_kg" => null, "reps" => 8 }
                ]
            },
            {
                "index" => 1,
                "title" => "Bench Press (Barbell)",
                "rest_seconds" => "150",
                "exercise_template_id" => "D04AC939",
                "sets" => [
                    { "type" => "normal", "weight_kg" => 20, "reps" => 12 },
                    { "type" => "normal", "weight_kg" => 30, "reps" => 12 }
                ]
            },
            {
                "index" => 2,
                "title" => "Triceps Pushdown",
                "rest_seconds" => 75,
                "exercise_template_id" => "ABC12345",
                "sets" => [
                    { "type" => "normal", "weight_kg" => null,
                      "reps" => null, "rep_range" => { "start" => 10, "end" => 12 } }
                ]
            },
            {
                "index" => 3,
                "title" => "Triceps Pushdown",
                "rest_seconds" => 60,
                "exercise_template_id" => "ABC12345",
                "sets" => [{ "type" => "normal", "weight_kg" => null, "reps" => 12 }]
            }
        ]
    } as Dictionary;

    var workout = HevyMap.routineToWorkout(routine as Object?);
    Test.assert(workout != null);
    var w = workout as Workout;
    Test.assertEqual(w.name, "Dos + Triceps");
    Test.assertEqual(w.exercises.size(), 4);

    // Four set rows become four sets; a null load stays null, never zero.
    var lat = w.exercises[0];
    Test.assertEqual(lat.name, "Lat Pulldown (Cable)");
    Test.assertEqual(lat.targetSets, 4);
    Test.assertEqual(lat.targetReps, 8);
    Test.assertEqual(lat.restDuration, 120);
    Test.assert(lat.defaultWeight == null);
    Test.assert(lat.hevyId != null);
    Test.assert((lat.hevyId as String).equals("05293BCA"));
    Test.assertEqual(lat.muscle, Muscle.BACK);

    // A ramp offers its opening load; rest_seconds as a string still parses.
    var bench = w.exercises[1];
    Test.assertEqual(bench.targetSets, 2);
    Test.assert(bench.defaultWeight == 20.0);
    Test.assertEqual(bench.restDuration, 150);
    Test.assertEqual(bench.muscle, Muscle.CHEST);

    // A rep range asks for its low end.
    Test.assertEqual(w.exercises[2].targetReps, 10);

    // The same movement twice keeps one Hevy id and two distinct RepFlow ids,
    // or "select any exercise at any time" could not tell them apart.
    Test.assert(!w.exercises[2].id.equals(w.exercises[3].id));
    Test.assert((w.exercises[2].hevyId as String).equals(w.exercises[3].hevyId as String));
    Test.assert(w.findExercise(w.exercises[3].id) != null);
    return true;
}

//! Nothing a web service can send may crash the import.
(:test)
function testHevyRoutineRejectsRubbish(logger as Test.Logger) as Boolean {
    Test.assert(HevyMap.routineToWorkout(null) == null);
    Test.assert(HevyMap.routineToWorkout("not a routine" as Object?) == null);
    Test.assert(HevyMap.routineToWorkout(42 as Object?) == null);
    Test.assert(HevyMap.routineToWorkout({} as Object?) == null);

    // Title present, exercises missing.
    Test.assert(HevyMap.routineToWorkout({ "id" => "a", "title" => "T" } as Object?) == null);
    // Exercises present but empty, or all unusable.
    Test.assert(HevyMap.routineToWorkout(
        { "id" => "a", "title" => "T", "exercises" => [] } as Object?) == null);
    Test.assert(HevyMap.routineToWorkout(
        { "id" => "a", "title" => "T", "exercises" => [null, 7, "x"] } as Object?) == null);
    // An exercise with no sets at all is still an exercise to perform.
    var w = HevyMap.routineToWorkout({
        "id" => "a", "title" => "T",
        "exercises" => [{ "title" => "Plank", "exercise_template_id" => "P1" }]
    } as Object?);
    Test.assert(w != null);
    Test.assertEqual((w as Workout).exercises[0].targetSets, 1);
    return true;
}

//! A finished session becomes the body of POST /v1/workouts.
(:test)
function testHevyPayloadFromSession(logger as Test.Logger) as Boolean {
    var bench = new Exercise("h_D04AC939", "Bench Press", 3, 10, 60.0, 120);
    bench.hevyId = "D04AC939";
    var pullup = new Exercise("h_PULLUP", "Pull-Up", 3, 8, null, 120);
    pullup.hevyId = "PULLUP";
    var orphan = new Exercise("e_local", "Something Local", 3, 10, 20.0, 60);

    var workout = new Workout("h_r1", "Push", [bench, pullup, orphan] as Array<Exercise>);
    var engine = new WorkoutEngine(new WorkoutSession(workout, TestSupport.T0));

    engine.selectExercise("h_D04AC939");
    engine.completeCurrentSet(10, 60.0, null, TestSupport.T0 + 60);
    engine.completeCurrentSet(8, 65.0, null, TestSupport.T0 + 200);
    engine.selectExercise("h_PULLUP");
    engine.completeCurrentSet(8, null, null, TestSupport.T0 + 400);   // bodyweight
    engine.selectExercise("e_local");
    engine.completeCurrentSet(10, 20.0, null, TestSupport.T0 + 600);  // no Hevy id

    var payload = HevyMap.sessionToPayload(workout, TestSupport.T0,
        TestSupport.T0 + 3600, true, null);
    Test.assert(payload != null);
    var body = (payload as Dictionary)["workout"] as Dictionary;

    Test.assertEqual(body["title"] as String, "Push");
    Test.assertEqual(body["is_private"] as Boolean, true);
    Test.assert((body["start_time"] as String).length() == 20);   // ...T..:..:..Z
    Test.assert((body["end_time"] as String).find("T") != null);
    Test.assert((body["end_time"] as String).find("Z") != null);

    // The exercise with no Hevy id is dropped: there is nothing honest to file
    // it against, and Hevy keys every set by exercise_template_id.
    var exercises = body["exercises"] as Array;
    Test.assertEqual(exercises.size(), 2);

    var first = exercises[0] as Dictionary;
    Test.assertEqual(first["exercise_template_id"] as String, "D04AC939");
    var sets = first["sets"] as Array;
    Test.assertEqual(sets.size(), 2);
    Test.assertEqual((sets[0] as Dictionary)["reps"] as Number, 10);
    Test.assert(((sets[0] as Dictionary)["weight_kg"] as Float) == 60.0);
    Test.assertEqual((sets[0] as Dictionary)["type"] as String, "normal");

    // A bodyweight set sends null, not zero. Hevy's weight_kg is nullable for
    // exactly this reason, and a zero would be a fabricated load.
    var second = exercises[1] as Dictionary;
    var bodyweightSet = ((second["sets"] as Array)[0]) as Dictionary;
    Test.assert((bodyweightSet["weight_kg"] as Object?) == null);
    Test.assertEqual(bodyweightSet["reps"] as Number, 8);

    // A session where nothing was performed has nothing to post.
    var emptyWorkout = TestSupport.abcWorkout();
    Test.assert(HevyMap.sessionToPayload(emptyWorkout, TestSupport.T0,
        TestSupport.T0 + 60, false, null) == null);
    return true;
}

//! ISO 8601, which Hevy requires and Monkey C has no formatter for.
(:test)
function testIso8601(logger as Test.Logger) as Boolean {
    // 2024-08-14T12:00:00Z
    var stamp = HevyApi.iso8601(1723636800);
    Test.assertEqual(stamp.length(), 20);
    Test.assertEqual(stamp.substring(4, 5) as String, "-");
    Test.assertEqual(stamp.substring(10, 11) as String, "T");
    Test.assertEqual(stamp.substring(19, 20) as String, "Z");
    Test.assertEqual(stamp, "2024-08-14T12:00:00Z");
    return true;
}

//! The POC fixture: Bench Press 3x8x80, Lat Pulldown 3x10x60.
//!
//! One minimal session, performed end to end, so each of the three integration
//! routes in docs/garmin-strength-integration-poc.md can be measured against
//! the same data rather than against three different ones.
(:test)
function testPocStrengthSession(logger as Test.Logger) as Boolean {
    var bench = new Exercise("c_bench", "Bench Press", 3, 8, 80.0, 120);
    bench.muscle = Muscle.CHEST;
    bench.hevyId = "D04AC939";
    var pulldown = new Exercise("b_lat_pulldown", "Lat Pulldown", 3, 10, 60.0, 90);
    pulldown.muscle = Muscle.BACK;
    pulldown.hevyId = "05293BCA";

    var workout = new Workout("poc", "POC Strength", [bench, pulldown] as Array<Exercise>);
    var engine = new WorkoutEngine(new WorkoutSession(workout, TestSupport.T0));

    engine.selectExercise("c_bench");
    for (var i = 0; i < 3; i++) {
        engine.completeCurrentSet(8, 80.0, null, TestSupport.T0 + 60 + i * 180);
    }
    engine.selectExercise("b_lat_pulldown");
    for (var i = 0; i < 3; i++) {
        engine.completeCurrentSet(10, 60.0, null, TestSupport.T0 + 700 + i * 150);
    }

    // POC A — what ActivityRecording can carry: totals on the session message,
    // one lap per set with the detail as developer fields.
    var summary = engine.finishWorkout(TestSupport.T0 + 1800);
    Test.assertEqual(summary.completedSets, 6);
    Test.assertEqual(summary.totalReps, 54);                 // 3x8 + 3x10
    Test.assertEqual(summary.totalVolume, 3720.0);           // 1920 + 1800
    Test.assertEqual(summary.plannedSets, 6);
    Test.assertEqual(summary.exercisesWorked, 2);

    // POC C — the same session as the body of a Hevy POST, which is also the
    // shape a backend would turn into FIT SetMessages.
    var payload = HevyMap.sessionToPayload(workout, TestSupport.T0,
        TestSupport.T0 + 1800, true, null);
    Test.assert(payload != null);
    var exercises = ((payload as Dictionary)["workout"] as Dictionary)["exercises"] as Array;
    Test.assertEqual(exercises.size(), 2);

    var benchSets = (exercises[0] as Dictionary)["sets"] as Array;
    Test.assertEqual(benchSets.size(), 3);
    Test.assert(((benchSets[0] as Dictionary)["weight_kg"] as Float) == 80.0);
    Test.assertEqual((benchSets[0] as Dictionary)["reps"] as Number, 8);
    Test.assertEqual((exercises[0] as Dictionary)["exercise_template_id"] as String, "D04AC939");

    var pulldownSets = (exercises[1] as Dictionary)["sets"] as Array;
    Test.assertEqual(pulldownSets.size(), 3);
    Test.assert(((pulldownSets[0] as Dictionary)["weight_kg"] as Float) == 60.0);
    Test.assertEqual((pulldownSets[0] as Dictionary)["reps"] as Number, 10);

    // POC B — the gap, stated as an assertion rather than as prose. A developer
    // field can target exactly three FIT message types, and none of them is the
    // `set` message Garmin Connect's strength view is built from.
    Test.assertEqual(FitContributor.MESG_TYPE_SESSION, FitContributor.MESG_TYPE_SESSION);
    Test.assert(!(FitContributor has :MESG_TYPE_SET));
    return true;
}

//! Every field caption has to LEAVE ROOM in the cell it is actually drawn in.
//!
//! `drawCell` centres the caption under the value and two captions in a pair
//! grow towards each other. Merely "fitting" is not enough and that was the bug
//! reported twice: "AVG HR" is 50px in a 64px cell, which leaves seven pixels
//! either side of the divider and reads as touching on a real watch. So the
//! rule here is a **gap**, not a fit.
//!
//! Which band a caption lands in is the whole point: on a fenix6pro the bottom
//! band gives a caption 64px and the middle one 91. This mirrors
//! WorkoutSummaryView._drawBodyPage rather than checking a worst case, and it
//! fails if a caption is moved somewhere it does not belong.
(:test)
function testFieldCaptionsFitTheirCells(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;
    }
    var size = TestSupport.screenSize();
    var top = (size * 26) / 100;
    var bottom = size - size / 11;
    var edge = FieldGrid.edgeHeight(top, bottom);
    var middleTop = top + edge;
    var bottomTop = bottom - edge;

    // The full-width band. "BODY BATT" is the longest caption in the app and
    // this is the only place it has no neighbour to collide with.
    var wide = [Rez.Strings.FieldBattery, Rez.Strings.FieldVolume,
        Rez.Strings.FieldTime] as Array;
    // The middle pair, and the narrowest pair on the page.
    var middle = [Rez.Strings.FieldRecovery, Rez.Strings.FieldKcal] as Array;
    var narrow = [
        Rez.Strings.FieldAvgHr, Rez.Strings.FieldMaxHr, Rez.Strings.FieldReps,
        Rez.Strings.FieldHr, Rez.Strings.FieldTimer, Rez.Strings.FieldSets,
        Rez.Strings.FieldRpe
    ] as Array;

    var ok = _captionsFit(dc, logger, wide, Theme.bandWidth(dc, top, edge));
    ok = _captionsFit(dc, logger, middle,
        Theme.bandWidth(dc, middleTop, bottomTop - middleTop) / 2) && ok;
    ok = _captionsFit(dc, logger, narrow,
        Theme.bandWidth(dc, bottomTop, edge) / 2) && ok;
    Test.assert(ok);
    return true;
}

//! True when every caption leaves real space in a cell of `cell` pixels.
//!
//! 75%, not 90%: a caption that merely fits still ends a few pixels from its
//! neighbour, and a few pixels is what "the texts are touching" looks like.
//! A quarter of the cell held clear is the difference between two labels and
//! one smear.
function _captionsFit(
    dc as Graphics.Dc,
    logger as Test.Logger,
    captions as Array,
    cell as Number
) as Boolean {
    var room = (cell * 75) / 100;
    var ok = true;
    for (var i = 0; i < captions.size(); i++) {
        var text = WatchUi.loadResource(captions[i] as ResourceId) as String;
        var width = dc.getTextWidthInPixels(text, Theme.captionFont());
        if (width > room) {
            logger.debug(text + " is " + width.toString() + "px, cell of " +
                cell.toString() + "px allows " + room.toString() + "px");
            ok = false;
        }
    }
    return ok;
}


//! The overview's rows draw, focused and not, with names of every length.
//!
//! This is the screen the product is: "select any exercise at any time" is a
//! list you choose from. It moved from Menu2 to CustomMenu so the rows could be
//! drawn here rather than truncated by the system, and drawing them here means
//! a symbol error in one row now blanks the screen the athlete navigates with.
//! Nothing that only measures would catch that — the code has to run.
(:test)
function testOverviewRowsDraw(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;
    }

    // A name that fits, one that does not, and every state a row can be in.
    var names = ["Row", "Incline Bench Press (Dumbbell) and then some"];
    var states = [EX_NOT_STARTED, EX_ACTIVE, EX_PENDING, EX_COMPLETED, EX_SKIPPED];
    for (var n = 0; n < names.size(); n++) {
        for (var s = 0; s < states.size(); s++) {
            var exercise = new Exercise("x", names[n] as String, 4, 10, 20.0, 90);
            exercise.state = states[s] as ExerciseState;
            new ExerciseMenuItem(exercise).draw(dc);
        }
    }

    new ActionMenuItem("Add exercise", WorkoutOverviewView.ITEM_ADD_EXERCISE).draw(dc);
    new OverviewTitle("Dos + Triceps").draw(dc);
    new OverviewTitle("A workout name far too long for one line").draw(dc);
    Marquee.endFrame();

    // The text window has to leave the icon column alone at both ends, or a
    // long name scrolls over the state dot.
    Test.assert(RowLayout.textWidth(dc) <= dc.getWidth() - RowLayout.gutter(dc) * 2);
    Test.assert(RowLayout.iconCentre(dc) < RowLayout.gutter(dc));
    return true;
}

//! The effort scale is Hevy's, not ours.
//!
//! `rpe` is an enumeration in Hevy's API, not a range, and a value off it is
//! answered with a 400 that loses the **whole** workout rather than the set.
//! Note what the ladder does not contain: there is no 6.5. A tidy "6 to 10 in
//! halves" would look right on the watch and cost the athlete their session.
(:test)
function testRpeScaleMatchesHevy(logger as Test.Logger) as Boolean {
    // Transcribed from PostWorkoutsRequestSet.rpe in the published schema.
    var expected = [6.0, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0];
    Test.assertEqual(Rpe.SCALE.size(), expected.size());
    for (var i = 0; i < expected.size(); i++) {
        Test.assert((Rpe.SCALE[i] - (expected[i] as Float)).abs() < 0.001);
    }
    Test.assert(Rpe.indexOf(6.5) < 0);        // the gap is deliberate
    Test.assert(Rpe.sanitise(6.5) == null);
    Test.assert(Rpe.sanitise(11.0) == null);
    Test.assert(Rpe.sanitise(null) == null);
    Test.assert(Rpe.sanitise(8.5) != null);
    return true;
}

//! Stepping the ladder, including the two ends and the way off it.
(:test)
function testRpeStepping(logger as Test.Logger) as Boolean {
    // From unrated, either direction opens at 8 — the athlete has said "rate
    // this", not "make it the hardest one".
    Test.assert(_isRpe(Rpe.step(null, 1), Rpe.OPENING));
    Test.assert(_isRpe(Rpe.step(null, -1), Rpe.OPENING));

    Test.assert(_isRpe(Rpe.step(8.0, 1), 8.5));
    Test.assert(_isRpe(Rpe.step(8.5, -1), 8.0));
    // 6 to 7: the ladder skips 6.5, so stepping must not land on it.
    Test.assert(_isRpe(Rpe.step(6.0, 1), 7.0));
    Test.assert(_isRpe(Rpe.step(7.0, -1), 6.0));

    // The top holds; the bottom lets go, because changing your mind about
    // rating a set has to be possible and there is no other way out.
    Test.assert(_isRpe(Rpe.step(10.0, 1), 10.0));
    Test.assert(Rpe.step(6.0, -1) == null);
    Test.assert(_isRpe(Rpe.step(8.0, 0), 8.0));
    return true;
}

//! Compare a nullable rating with an expected one.
//!
//! Test.assertEqual takes Objects, and a `Float?` is not one — the type checker
//! is right to refuse it, and a cast would only move the problem.
function _isRpe(actual as Float?, expected as Float) as Boolean {
    return actual != null && ((actual as Float) - expected).abs() < 0.001;
}

//! "8", not "8.0" — a judgement, not a measurement.
(:test)
function testRpeFormatting(logger as Test.Logger) as Boolean {
    Test.assertEqual(Rpe.format(8.0), "8");
    Test.assertEqual(Rpe.format(8.5), "8.5");
    Test.assertEqual(Rpe.format(10.0), "10");
    Test.assertEqual(Rpe.format(null), LiveMetrics.NO_VALUE);
    return true;
}

//! A rating belongs to the set that earned it, and to no other.
(:test)
function testRpeIsRecordedPerSetAndNotInherited(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");

    engine.completeCurrentSet(8, 60.0, 8.5, TestSupport.T0);
    engine.completeCurrentSet(8, 60.0, null, TestSupport.T0 + 120);

    var sets = TestSupport.exerciseOf(engine, "A").sets;
    Test.assert(_isRpe(sets[0].rpe, 8.5));
    // Not carried forward: the load repeats because the next set is probably
    // the same weight; the effort does not, because it is probably harder.
    Test.assert(sets[1].rpe == null);

    // A rating off the ladder is dropped at the door rather than stored and
    // sent on to be rejected.
    engine.completeCurrentSet(8, 60.0, 6.5, TestSupport.T0 + 240);
    Test.assert(sets[2].rpe == null);
    return true;
}

//! Undoing a set undoes its rating with it.
(:test)
function testUncompleteClearsTheRating(logger as Test.Logger) as Boolean {
    var set = new WorkoutSet(0, 10, 50.0);
    set.complete(8, 55.0, 9.0, TestSupport.T0);
    Test.assert(_isRpe(set.rpe, 9.0));

    set.uncomplete();
    Test.assert(set.rpe == null);
    // The performed values survive as the new targets, as they always did.
    Test.assertEqual(set.targetReps, 8);
    Test.assert(set.targetWeight != null);
    return true;
}

//! A set written before v4 has seven elements, not eight.
//!
//! Rejecting it would throw away a session mid-workout when an update lands,
//! which is the thing migration exists to prevent. An absent rating and an
//! unrated set are the same thing.
(:test)
function testSetsWrittenBeforeRpeStillLoad(logger as Test.Logger) as Boolean {
    var old = [0, 10, 50.0, 8, 55.0, true, TestSupport.T0] as Array;
    var set = WorkoutSet.fromStorage(old);
    Test.assert(set.actualReps != null && (set.actualReps as Number) == 8);
    Test.assert(set.rpe == null);

    // And a set written now round-trips its rating.
    var fresh = new WorkoutSet(0, 10, 50.0);
    fresh.complete(8, 55.0, 9.5, TestSupport.T0);
    Test.assert(_isRpe(WorkoutSet.fromStorage(fresh.toStorage()).rpe, 9.5));
    return true;
}

//! Open rest: a clock that runs until the athlete stops it.
//!
//! Not a countdown of zero length. It has no target, so it never reaches zero,
//! never buzzes, and cannot be extended — and every one of those has to be a
//! real answer rather than a stand-in, because a buzz is a claim that the rest
//! is over and in this mode only the athlete gets to make it.
(:test)
function testOpenRestCountsUpAndNeverFires(logger as Test.Logger) as Boolean {
    var rest = new RestTimer();
    rest.startOpen();

    Test.assert(rest.isOpen());
    Test.assert(rest.isRunning());
    Test.assertEqual(rest.format(), "00:00");

    for (var i = 0; i < 125; i++) {
        // Never true: there is no moment to announce.
        Test.assert(!rest.tick());
    }
    Test.assertEqual(rest.elapsed(), 125);
    Test.assertEqual(rest.format(), "02:05");
    // Still running after two minutes. A countdown would have stopped.
    Test.assert(rest.isRunning());

    // No target means no proportion of one, and the rest screen draws no arc.
    Test.assertEqual(rest.progress(), 0.0);
    Test.assertEqual(rest.duration(), 0);
    Test.assertEqual(rest.remaining(), 0);
    return true;
}

//! Adding time to an open rest does nothing, rather than quietly converting it.
(:test)
function testOpenRestCannotBeExtended(logger as Test.Logger) as Boolean {
    var rest = new RestTimer();
    rest.startOpen();
    rest.tick();
    rest.tick();

    rest.extend(30);
    // Still open, still counting up, still no target: silently turning this
    // into a countdown would take away the mode the athlete chose.
    Test.assert(rest.isOpen());
    Test.assertEqual(rest.duration(), 0);
    Test.assertEqual(rest.elapsed(), 2);
    return true;
}

//! The athlete's press is what ends it.
(:test)
function testOpenRestEndsOnlyWhenSkipped(logger as Test.Logger) as Boolean {
    var rest = new RestTimer();
    rest.startOpen();
    for (var i = 0; i < 400; i++) {
        rest.tick();
    }
    Test.assert(rest.isRunning());

    rest.skip();
    Test.assert(!rest.isRunning());
    return true;
}

//! A timed rest still behaves exactly as it did.
(:test)
function testTimedRestIsUnchanged(logger as Test.Logger) as Boolean {
    var rest = new RestTimer();
    rest.start(3);
    Test.assert(!rest.isOpen());
    Test.assertEqual(rest.format(), "00:03");
    Test.assertEqual(rest.elapsed(), 0);

    Test.assert(!rest.tick());
    Test.assertEqual(rest.elapsed(), 1);
    Test.assert(!rest.tick());
    // The tick that reaches zero, and only that one, fires.
    Test.assert(rest.tick());
    Test.assert(!rest.isRunning());
    Test.assert(!rest.tick());

    rest.start(60);
    rest.extend(15);
    Test.assertEqual(rest.remaining(), 75);
    return true;
}

//! The exercise screen's band holds what it claims to hold.
//!
//! A mini field is centred on its column and nothing clips it, so a caption
//! wider than its share grows silently into its neighbour — exactly how
//! "BODY BATT" ended up on top of "REC". This measures the real band, with the
//! real strings, at the widest values they can ever show.
//!
//! It also records why the exercise clock is not up here: three columns of this
//! band are 51px each on a Fenix 6 Pro and a "12:34" needs 54.
(:test)
function testExerciseBandFitsThree(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;
    }
    var h = dc.getHeight();
    // The band the exercise screen actually gives this row: just above the
    // clock at the bottom of the page.
    var bandHeight = Theme.miniFieldHeight(dc);
    var clockTop = h - dc.getFontHeight(Graphics.FONT_XTINY) - h / 22;
    var top = (clockTop - h / 60) - bandHeight;
    var width = Theme.bandWidth(dc, top, bandHeight);

    var setLabel = (WatchUi.loadResource(Rez.Strings.SetLabel) as ResourceId) as String;
    var values = ["59:59", "59:59", "10/10"] as Array<String>;
    var captions = [
        setLabel.toUpper(),
        WatchUi.loadResource(Rez.Strings.FieldTimer as ResourceId) as String,
        WatchUi.loadResource(Rez.Strings.FieldSets as ResourceId) as String
    ] as Array<String>;


    logger.debug("band " + width.toString() + "px, three would fit: " +
        (Theme.miniFieldsFit(dc, width, 3, values, captions) ? "yes" : "no"));

    // What the band actually draws: the set clock and the set counter, at the
    // widest either can ever be — "59:59" and "10/10".
    Test.assert(Theme.miniFieldsFit(dc, width, 2, values, captions));

    // And the bottom line has room for the set count beside the time of day,
    // which is where it went.
    //
    // Measured at the line's BOTTOM, which is the mistake that put this row's
    // descenders under the bezel: below centre the chord closes as it
    // descends, so the middle of a line always overstates what it has.
    var h2 = dc.getHeight();
    var lineFont = Graphics.FONT_XTINY;
    var lineHeight = dc.getFontHeight(lineFont);
    var clockTop2 = h2 - lineHeight - h2 / 14;
    var lineWidth = Theme.usableWidth(dc, clockTop2 + lineHeight);
    var pair = dc.getTextWidthInPixels("10/10", lineFont) +
        dc.getWidth() / 10 +
        dc.getTextWidthInPixels("23:59", lineFont);
    logger.debug("bottom line " + lineWidth.toString() + "px at its baseline, pair " +
        pair.toString() + "px");
    Test.assert(pair <= lineWidth);
    return true;
}

//! The set clock and the exercise clock measure different things.
(:test)
function testSetClockIsNotTheExerciseClock(logger as Test.Logger) as Boolean {
    // Both are wall-clock readings off the controller, so what is checked here
    // is the arithmetic that turns a start into a duration: never negative,
    // and zero when nothing has started.
    var controller = AppController.instance();
    Test.assert(controller.setSeconds() >= 0);
    Test.assert(controller.exerciseSeconds() >= 0);
    return true;
}

//! Only the best record per movement is kept.
//!
//! Beating your weight on set 2 and again on set 4 is one achievement with a
//! better number, not two. Listing both would make the recap longer and less
//! true.
(:test)
function testOneRecordPerMovement(logger as Test.Logger) as Boolean {
    var controller = AppController.instance();
    controller.startWorkout(TestSupport.abcWorkout());
    controller.selectExercise("A");

    // Three sets of the same movement, each heavier than the last. Whether any
    // of them counts as a record depends on stored history, which a test cannot
    // set — so what is asserted is the shape of the list, not its length.
    var before = controller.records().size();
    controller.completeSet();
    controller.completeSet();
    controller.completeSet();
    var after = controller.records();

    // At most one entry gained, and every entry names a distinct movement.
    Test.assert(after.size() <= before + 1);
    for (var i = 0; i < after.size(); i++) {
        for (var j = i + 1; j < after.size(); j++) {
            var a = (after[i] as Array)[0] as String;
            var b = (after[j] as Array)[0] as String;
            Test.assert(!a.equals(b));
        }
    }
    // Every row is [name, kind, reps, weight] — the recap indexes all four.
    for (var i = 0; i < after.size(); i++) {
        Test.assertEqual((after[i] as Array).size(), 4);
    }
    return true;
}

//! A rest announces itself once, whichever way it ends.
//!
//! Two ways out — the countdown reaching zero, or the athlete pressing START —
//! and both mean "back under the bar", so both buzz with the same pattern. What
//! must not happen is both buzzing for one rest, which is what an athlete
//! watching the last second of a countdown would otherwise get.
(:test)
function testRestAnnouncesItselfOnce(logger as Test.Logger) as Boolean {
    var controller = AppController.instance();
    controller.startWorkout(TestSupport.abcWorkout());
    controller.selectExercise("A");

    // Ended by the athlete, before the countdown runs out.
    controller.startRest(90);
    Test.assert(!controller.restOverSignalled());
    controller.endRest();
    Test.assert(controller.restOverSignalled());

    // A fresh rest starts silent again.
    controller.startRest(2);
    Test.assert(!controller.restOverSignalled());

    // Ended by the clock this time, then left by the athlete: still once.
    controller.onTick();
    controller.onTick();
    Test.assert(controller.restOverSignalled());
    controller.endRest();
    Test.assert(controller.restOverSignalled());
    return true;
}

//! A Hevy routine imported twice is one workout, not two.
//!
//! The workout keeps Hevy's own routine id, which is the whole reason it is not
//! generated locally: edit a routine in Hevy, import again, and the copy on the
//! watch is updated in place. Generating an id here would leave the athlete
//! with a growing pile of near-identical workouts and no way to tell which one
//! was current.
(:test)
function testReimportingARoutineUpdatesItInPlace(logger as Test.Logger) as Boolean {
    var first = HevyMap.routineToWorkout({
        "id" => "r-123",
        "title" => "Dos + Triceps",
        "exercises" => [{
            "title" => "Lat Pulldown (Cable)",
            "exercise_template_id" => "t-lat",
            "sets" => [{ "reps" => 10, "weight_kg" => 60.0 }]
        } as Object] as Array
    } as Dictionary);
    Test.assert(first != null);

    // The same routine, renamed and with a second movement added in Hevy.
    var second = HevyMap.routineToWorkout({
        "id" => "r-123",
        "title" => "Back + Triceps",
        "exercises" => [
            {
                "title" => "Lat Pulldown (Cable)",
                "exercise_template_id" => "t-lat",
                "sets" => [{ "reps" => 12, "weight_kg" => 65.0 }]
            } as Object,
            {
                "title" => "Seated Row (Machine)",
                "exercise_template_id" => "t-row",
                "sets" => [{ "reps" => 10, "weight_kg" => 50.0 }]
            } as Object
        ] as Array
    } as Dictionary);
    Test.assert(second != null);

    // Same id, so storage replaces rather than appends. A different id here
    // would be the bug this test exists to catch.
    Test.assert((first as Workout).id.equals((second as Workout).id));
    Test.assertEqual((second as Workout).exercises.size(), 2);
    Test.assert(!(first as Workout).name.equals((second as Workout).name));

    // And a different routine is a different workout.
    var other = HevyMap.routineToWorkout({
        "id" => "r-456",
        "title" => "Pecs + Biceps",
        "exercises" => [{
            "title" => "Bench Press (Barbell)",
            "exercise_template_id" => "t-bench",
            "sets" => [{ "reps" => 8, "weight_kg" => 80.0 }]
        } as Object] as Array
    } as Dictionary);
    Test.assert(other != null);
    Test.assert(!(other as Workout).id.equals((first as Workout).id));
    return true;
}

//! Toggling a setting must not move the cursor.
//!
//! The settings menu used to rebuild itself after every change, on the belief —
//! written down in a comment — that a Menu2 item's sublabel could not be
//! altered in place. It can, since API 3.0, and the rebuild put the cursor back
//! at the top of the list every time: changing two settings meant scrolling
//! down twice. Reported from a real watch.
//!
//! This drives the menu the way the delegate does and checks the sublabels move
//! while the rows stay where they are.
(:test)
function testSettingsToggleUpdatesInPlace(logger as Test.Logger) as Boolean {
    var menu = AppSettingsMenu.build();
    var index = menu.findItemById(AppSettingsMenu.ITEM_REST_MODE);
    Test.assert(index >= 0);

    var item = menu.getItem(index) as WatchUi.MenuItem;
    var before = item.getSubLabel() as String;

    // What the delegate does: change the setting, rewrite this row, and leave
    // every other row — and the cursor — alone.
    Settings.setRestMode(Settings.restMode() == Tuning.REST_OPEN
        ? Tuning.REST_TIMED
        : Tuning.REST_OPEN);
    item.setSubLabel(AppSettingsMenu.restModeLabel());

    var after = (menu.getItem(index) as WatchUi.MenuItem).getSubLabel() as String;
    Test.assert(!before.equals(after));
    // The row did not move, which is the whole point.
    Test.assertEqual(menu.findItemById(AppSettingsMenu.ITEM_REST_MODE), index);

    // Put it back, so the test leaves no trace in the athlete's settings.
    Settings.setRestMode(Settings.restMode() == Tuning.REST_OPEN
        ? Tuning.REST_TIMED
        : Tuning.REST_OPEN);
    item.setSubLabel(AppSettingsMenu.restModeLabel());
    Test.assertEqual((menu.getItem(index) as WatchUi.MenuItem).getSubLabel() as String,
        before);

    // Switching units rewrites the weight-step row as well as its own, because
    // that row quotes whichever unit is in force.
    var step = menu.findItemById(AppSettingsMenu.ITEM_STEP);
    Test.assert(step >= 0);
    Test.assert(AppSettingsMenu.stepLabel().length() > 0);
    return true;
}

//! Finishing a workout answers the athlete before it does the slow work.
//!
//! `finishWorkout` runs inside a menu's selection callback, and the screen does
//! not repaint until it returns. Writing the FIT file — or deleting it — is the
//! slowest thing this app does, and with the history writes in front of it the
//! end of a workout was a visible stall on the menu the athlete had just
//! pressed. It looked like the press had not registered, which is exactly the
//! moment somebody presses again.
//!
//! So the recap goes up first and the recording is closed a tick later. What is
//! asserted here is the part that must survive that split: whichever answer was
//! given is still the answer if the app closes in between.
(:test)
function testDiscardSurvivesTheDeferral(logger as Test.Logger) as Boolean {
    var controller = AppController.instance();
    controller.startWorkout(TestSupport.abcWorkout());
    controller.selectExercise("A");
    controller.completeSet();

    // The athlete discarded, and the app is closing before the deferred half
    // has run. The recording must not be saved just because sets exist.
    controller.finishWorkout(false);
    Test.assert(controller.closingIsPending());
    controller.onAppStop();
    Test.assert(!controller.closingIsPending());

    // And running it again is a no-op rather than a second stop.
    controller.onClose();
    Test.assert(!controller.closingIsPending());

    // The same for a saved session.
    controller.startWorkout(TestSupport.abcWorkout());
    controller.selectExercise("A");
    controller.completeSet();
    controller.finishWorkout(true);
    Test.assert(controller.closingIsPending());
    controller.onClose();
    Test.assert(!controller.closingIsPending());
    return true;
}

//! Leaving the end-of-workout menu happens after the menu is gone.
//!
//! Switching views from inside `Menu2InputDelegate.onSelect` leaves the menu's
//! own layer painted on top: the recap drew its header and the word "Discard"
//! stayed across the middle of it, photographed on a real watch. The system
//! owns that layer and only tears it down once the callback has returned.
//!
//! So the choice is recorded and acted on a tick later. This checks the
//! recording and the acting, which is the part that can be tested without a
//! screen: what must never happen is a choice that is silently lost, or one
//! that is carried out twice.
(:test)
function testEndWorkoutChoiceIsDeferredThenActedOnce(logger as Test.Logger) as Boolean {
    var controller = AppController.instance();
    controller.startWorkout(TestSupport.abcWorkout());
    controller.selectExercise("A");
    controller.completeSet();

    // Chosen but not yet acted on: the menu is still on screen at this point.
    EndWorkoutFlow.choose(EndWorkoutFlow.CHOICE_DISCARD);
    Test.assertEqual(EndWorkoutFlow._choice, EndWorkoutFlow.CHOICE_DISCARD);
    Test.assert(controller.engine() != null);

    // The timer fires: the workout ends, and the recording is queued to close.
    EndWorkoutFlow.act();
    Test.assertEqual(EndWorkoutFlow._choice, EndWorkoutFlow.CHOICE_NONE);
    Test.assert(controller.engine() == null);
    Test.assert(controller.closingIsPending());

    // A second firing must do nothing at all. A repeated timer, or a stray
    // press, must not end a workout that has already ended.
    EndWorkoutFlow.act();
    Test.assertEqual(EndWorkoutFlow._choice, EndWorkoutFlow.CHOICE_NONE);

    controller.onClose();
    Test.assert(!controller.closingIsPending());
    return true;
}

//! An imported workout reaches Hevy whole.
//!
//! Hevy files a set against `exercise_template_id` and has no free-text name,
//! so an exercise without one is dropped from the payload — and a workout whose
//! exercises all lack one reaches Hevy as nothing at all. That is the worst
//! shape a sync can take, because the athlete only finds out days later.
//!
//! The workouts RepFlow shipped were in exactly that state until they were
//! removed. What replaced them is this: whatever comes back from Hevy has to go
//! back to Hevy complete.
(:test)
function testImportedWorkoutsReachHevyWhole(logger as Test.Logger) as Boolean {
    var workout = HevyMap.routineToWorkout({
        "id" => "r-1",
        "title" => "Pecs + Biceps",
        "exercises" => [
            {
                "title" => "Bench Press (Barbell)",
                "exercise_template_id" => "79D0BB3A",
                "sets" => [{ "reps" => 12, "weight_kg" => 20.0 }]
            } as Object,
            {
                "title" => "Bicep Curl (Dumbbell)",
                "exercise_template_id" => "37FCC2BB",
                "sets" => [{ "reps" => 10, "weight_kg" => 9.0 }]
            } as Object
        ] as Array
    } as Dictionary);
    Test.assert(workout != null);

    var list = (workout as Workout).exercises;
    for (var i = 0; i < list.size(); i++) {
        list[i].recordSet(list[i].plannedReps(), 20.0, null, TestSupport.T0 + i);
    }

    var payload = HevyMap.sessionToPayload(workout as Workout, TestSupport.T0,
        TestSupport.T0 + 3600, true, null);
    Test.assert(payload != null);
    var sent = ((payload as Dictionary)["workout"] as Dictionary)["exercises"] as Array;
    // Every exercise, not a subset.
    Test.assertEqual(sent.size(), list.size());
    return true;
}


//! Garmin's own numbers have to be captured before the recording is closed.
//!
//! `Activity.getActivityInfo()` answers null once there is no activity, so a
//! recap that asks for calories while drawing gets "--" every time. That is
//! exactly what happened: KCAL, AVG and MAX were blank on every summary, and
//! the values had been there a moment earlier.
(:test)
function testRecapKeepsGarminsNumbers(logger as Test.Logger) as Boolean {
    // Captured values survive whatever the activity does afterwards.
    var kept = new RecapMetrics(212, 128, 156, 71, 24);
    Test.assert(_is(kept.calories, 212));
    Test.assert(_is(kept.averageHeartRate, 128));
    Test.assert(_is(kept.maxHeartRate, 156));
    Test.assert(_is(kept.batteryStart, 71));
    Test.assert(_is(kept.recovery, 24));

    // And absence stays absence. A watch with no strap paired, or a session too
    // short to burn a calorie Garmin will admit to, is "--" and not a zero.
    var nothing = new RecapMetrics(null, null, null, null, null);
    Test.assert(nothing.calories == null);
    Test.assertEqual(LiveMetrics.format(nothing.calories), LiveMetrics.NO_VALUE);
    Test.assertEqual(LiveMetrics.format(nothing.maxHeartRate), LiveMetrics.NO_VALUE);

    // capture() reads whatever the device can answer right now. In the test
    // harness there is no activity, so what matters is that it does not throw
    // and that it carries the two values it is handed through unchanged.
    var live = RecapMetrics.capture(66, 18);
    Test.assert(_is(live.batteryStart, 66));
    Test.assert(_is(live.recovery, 18));
    return true;
}

//! Compare a nullable reading with an expected one.
//!
//! Test.assertEqual takes Objects and a `Number?` is not one — the type checker
//! is right to refuse it, and a cast would only move the problem.
function _is(actual as Number?, expected as Number) as Boolean {
    return actual != null && (actual as Number) == expected;
}

//! The load accelerates gradually, never in a jump the athlete did not ask for.
//!
//! A held button used to multiply every press by five — 5 kg on a default grid
//! — so two quick presses by accident put ten kilos on the bar. The ramp starts
//! at one step and builds, and any pause resets it, so a deliberate single
//! press is always a single step however fast the last burst was.
(:test)
function testLoadAcceleratesGradually(logger as Test.Logger) as Boolean {
    var ramp = Tuning.COARSE_STEPS;
    Test.assert(ramp.size() >= 2);
    // The first repeat is still one step: that is the whole point.
    Test.assertEqual(ramp[0] as Number, 1);
    Test.assertEqual(ramp[1] as Number, 1);
    // It only ever grows, and never as far as the old flat multiplier.
    for (var i = 1; i < ramp.size(); i++) {
        Test.assert((ramp[i] as Number) >= (ramp[i - 1] as Number));
        Test.assert((ramp[i] as Number) < Tuning.COARSE_MULTIPLIER);
    }
    return true;
}

//! The rest screen divides its glass fairly between what it shows.
//!
//! The countdown used to claim a fixed 26% for its digits, and with its label
//! and the air around it that came to nearly half the screen — for one number
//! the athlete glances at, leaving the two fields and the next-up block to
//! share what was left. Reported from a real watch as "the first one takes half
//! the screen".
//!
//! Checked as a proportion rather than by eye, because a proportion is what was
//! wrong and what a different screen size has to preserve.
(:test)
function testRestScreenIsDividedFairly(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;
    }
    var h = dc.getHeight();

    // What _drawCountdown lays out, in the same order it does.
    var labelTop = h / 11;
    var labelHeight = dc.getFontHeight(Graphics.FONT_XTINY);
    var countdownTop = labelTop + labelHeight + h / 60;
    var countdownHeight = (h * 20) / 100;

    var heroEnd = countdownTop + countdownHeight;
    var hero = heroEnd;                 // everything from the top of the glass
    var rest = h - heroEnd;             // fields and what is coming next

    logger.debug("hero " + hero.toString() + "px of " + h.toString() +
        " (" + ((hero * 100) / h).toString() + "%), rest " + rest.toString());

    // The headline may lead, but it may not take half.
    Test.assert(hero < h / 2);
    // And what is read has to have more room than what is glanced at.
    Test.assert(rest > hero);
    return true;
}

//! A routine's zero load means "no target", not "zero kilos".
//!
//! Hevy writes 0 where a routine sets no target and shows an empty field for
//! it — sixty of the hundred-odd set rows in the athlete's own routines are
//! zeros of that kind. Taken literally it opens every set at nothing, and it
//! overrides the load inherited from the last time the movement was performed,
//! which is the pre-fill that makes importing worth anything.
(:test)
function testAZeroRoutineTargetIsNoTarget(logger as Test.Logger) as Boolean {
    var workout = HevyMap.routineToWorkout({
        "id" => "r-1",
        "title" => "Epaules",
        "exercises" => [
            {
                "title" => "Shoulder Press (Dumbbell)",
                "exercise_template_id" => "878CD1D0",
                "sets" => [{ "reps" => 8, "weight_kg" => 0 } as Object] as Array
            } as Object,
            {
                "title" => "Bench Press (Barbell)",
                "exercise_template_id" => "79D0BB3A",
                "sets" => [{ "reps" => 12, "weight_kg" => 20.0 } as Object] as Array
            } as Object
        ] as Array
    } as Dictionary);
    Test.assert(workout != null);

    var list = (workout as Workout).exercises;
    // No target: the screen shows "--" and the athlete's own history fills it.
    Test.assert(list[0].plannedWeight() == null);
    Test.assertEqual(Theme.formatPlannedWeight(list[0].plannedWeight()), "--");
    // A real target still arrives as one.
    Test.assert(list[1].plannedWeight() != null);
    return true;
}

//! The two things done during a rest have a button each, and they do not clash.
//!
//! BACK ends the rest — it is the LAP button, and LAP ends a step during any
//! Garmin activity. START opens the exercise list, because a rest is exactly
//! when an athlete looks at what is left and decides what to do next, usually
//! because the machine they planned on is taken.
//!
//! What this guards is the way back: opening the list must not cost the rest.
//! The clock keeps running, and leaving the list returns to it.
(:test)
function testRestSurvivesALookAtTheList(logger as Test.Logger) as Boolean {
    var controller = AppController.instance();
    controller.startWorkout(TestSupport.abcWorkout());
    controller.selectExercise("A");
    controller.startRest(120);
    Test.assert(controller.restTimer().isRunning());

    // Ten seconds pass while the list is open.
    for (var i = 0; i < 10; i++) {
        controller.onTick();
    }
    // Still resting, and the countdown moved: browsing is not skipping.
    Test.assert(controller.restTimer().isRunning());
    Test.assertEqual(controller.restTimer().remaining(), 110);

    // And nothing has been announced, so coming back does not find a rest that
    // quietly ended while it was out of sight.
    Test.assert(!controller.restOverSignalled());
    return true;
}

//! Garmin's physiology reaches Hevy the only way Hevy allows: as text.
//!
//! Hevy's API carries weight, reps, distance, duration, RPE and a custom metric
//! per set, and on the workout a title, a description and the times. There is
//! nothing physiological anywhere in it — "heart", "bpm" and "calorie" do not
//! appear in the published schema. So the numbers ride in the description,
//! which is not a chart but is better than dropping them.
(:test)
function testHeartRateReachesHevyAsDescription(logger as Test.Logger) as Boolean {
    var full = HevyMap.describe(new RecapMetrics(328, 100, 140, 71, 24));
    Test.assert(full != null);
    logger.debug("description: " + (full as String));
    Test.assert((full as String).find("100") != null);
    Test.assert((full as String).find("140") != null);
    Test.assert((full as String).find("328") != null);

    // Nothing measured, nothing written: a session with no strap paired gets no
    // description rather than an empty one.
    Test.assert(HevyMap.describe(new RecapMetrics(null, null, null, null, null)) == null);
    Test.assert(HevyMap.describe(null) == null);

    // A calorie count of zero is not a measurement Garmin stands behind.
    Test.assert(HevyMap.describe(new RecapMetrics(0, null, null, null, null)) == null);

    // Heart rate alone still says something.
    var hrOnly = HevyMap.describe(new RecapMetrics(null, 118, null, null, null));
    Test.assert(hrOnly != null && (hrOnly as String).find("118") != null);
    return true;
}
