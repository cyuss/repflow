import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Timer;
import Toybox.Time;
import Toybox.Attention;
import Toybox.System;
import Toybox.Math;

//! Wires the workout engine, the rest timer, Garmin recording and persistence
//! together, and owns screen transitions.
//!
//! The views stay dumb: they render state and forward button presses here.
//! Nothing below this class knows about ActivityRecording or Storage.
class AppController {

    private static var _instance as AppController?;

    private var _engine as WorkoutEngine?;
    private var _recorder as GarminRecorder;
    private var _rest as RestTimer;
    private var _ticker as Timer.Timer?;
    //! Time in heart rate zone, counted off the same 1 Hz tick. Garmin shows
    //! this at the end of its own activities and gives no API to read it back.
    private var _zones as ZoneTracker;
    //! Weight/reps the athlete has dialled in for the set about to be performed.
    private var _pendingWeight as Float;
    private var _pendingReps as Number;
    //! Which data screen the exercise view is showing. Lives here rather than on
    //! the view so it survives rest screens and menu round-trips.
    private var _exercisePage as Number;
    //! Epoch seconds when the current exercise was selected, for the on-screen
    //! exercise timer. Garmin owns the activity clock; this one answers a
    //! different question — how long have I been on THIS exercise.
    private var _exerciseStartedAt as Number;

    public function initialize() {
        _engine = null;
        _recorder = new GarminRecorder();
        _rest = new RestTimer();
        _ticker = null;
        _zones = new ZoneTracker();
        _pendingWeight = 0.0;
        _pendingReps = 0;
        _exercisePage = 0;
        _exerciseStartedAt = 0;
    }

    public static function instance() as AppController {
        var i = _instance;
        if (i == null) {
            i = new AppController();
            _instance = i;
        }
        return i;
    }

    // ------------------------------------------------------------------
    // Accessors
    // ------------------------------------------------------------------

    public function engine() as WorkoutEngine? {
        return _engine;
    }

    public function zoneTracker() as ZoneTracker {
        return _zones;
    }

    public function restTimer() as RestTimer {
        return _rest;
    }

    public function recorder() as GarminRecorder {
        return _recorder;
    }

    public function pendingWeight() as Float {
        return _pendingWeight;
    }

    public function pendingReps() as Number {
        return _pendingReps;
    }

    public function exercisePage() as Number {
        return _exercisePage;
    }

    //! Seconds spent on the exercise currently selected.
    public function exerciseSeconds() as Number {
        if (_exerciseStartedAt <= 0) {
            return 0;
        }
        var elapsed = now() - _exerciseStartedAt;
        return elapsed > 0 ? elapsed : 0;
    }

    //! Page through the exercise data screens, wrapping at both ends.
    public function turnExercisePage(delta as Number) as Void {
        var count = Tuning.PAGE_COUNT;
        _exercisePage = (_exercisePage + delta + count) % count;
    }

    public static function now() as Number {
        return Time.now().value();
    }

    // ------------------------------------------------------------------
    // Session lifecycle
    // ------------------------------------------------------------------

    //! Begin a fresh session for a built-in workout template.
    public function startWorkout(workout as Workout) as Void {
        var session = new WorkoutSession(workout, now());
        _engine = new WorkoutEngine(session);
        _zones = new ZoneTracker();
        _exerciseStartedAt = now();
        _recorder.start(workout.name);
        _startTicker();
        _persist();
    }

    //! Adopt a session restored from storage after an interrupted workout.
    //! The Garmin recording cannot be reattached — see docs/API_LIMITATIONS.md —
    //! so a new recording is started for the remainder of the workout.
    public function resumeWorkout(session as WorkoutSession) as Void {
        _engine = new WorkoutEngine(session);
        _zones = new ZoneTracker();
        _recorder.start(session.workout.name);
        var ex = session.currentExercise();
        if (ex != null) {
            syncPendingValues(ex);
        }
        _exerciseStartedAt = now();
        _startTicker();
    }

    //! Pre-fill the editable weight/reps from the exercise's inheritance rules.
    public function syncPendingValues(exercise as Exercise) as Void {
        _pendingWeight = exercise.plannedWeight();
        _pendingReps = exercise.plannedReps();
    }

    public function selectExercise(exerciseId as String) as Boolean {
        var engine = _engine;
        if (engine == null) {
            return false;
        }
        if (!engine.selectExercise(exerciseId)) {
            return false;
        }
        var ex = engine.currentExercise();
        if (ex != null) {
            syncPendingValues(ex);
        }
        _exerciseStartedAt = now();
        _exercisePage = Tuning.PAGE_SET;
        _startTicker();
        _persist();
        return true;
    }

    // ------------------------------------------------------------------
    // Editing the upcoming set
    // ------------------------------------------------------------------

    //! Move the load by `deltaSteps` presses of UP or DOWN.
    //!
    //! The arithmetic happens in whatever unit the athlete reads, then converts
    //! back to the kilograms everything is stored in. Stepping in kilos and
    //! displaying pounds would walk the shown number off every round value.
    //!
    //! Snapping to the step grid is what makes holding the button land on 60
    //! and 65 rather than on 62.5 and 67.5 after one odd starting weight.
    public function adjustWeight(deltaSteps as Number) as Void {
        var step = Units.step();
        if (step <= 0.0) {
            step = 1.0;
        }
        var shown = Units.fromKg(_pendingWeight) + deltaSteps * step;
        var snapped = Math.round(shown / step) * step;
        if (snapped < 0.0) {
            snapped = 0.0;
        }
        _pendingWeight = Units.toKg(snapped.toFloat());
    }

    public function setWeight(weight as Float) as Void {
        _pendingWeight = weight < 0.0 ? 0.0 : weight;
    }

    public function adjustReps(delta as Number) as Void {
        _pendingReps += delta;
        if (_pendingReps < 0) {
            _pendingReps = 0;
        }
    }

    public function setReps(reps as Number) as Void {
        _pendingReps = reps < 0 ? 0 : reps;
    }

    // ------------------------------------------------------------------
    // Exercise actions
    //
    // These wrap the engine transitions that the action menu offers, so that
    // persistence stays in this layer and the views never touch storage.
    // ------------------------------------------------------------------

    //! "Skip for now" — the machine is busy. Stays PENDING and resumable.
    public function deferExercise(exerciseId as String) as Boolean {
        var engine = _engine;
        if (engine == null || !engine.deferExercise(exerciseId)) {
            return false;
        }
        _persist();
        return true;
    }

    //! Declare an exercise finished before its target sets were reached.
    public function forceCompleteExercise(exerciseId as String) as Boolean {
        var engine = _engine;
        if (engine == null || !engine.forceCompleteExercise(exerciseId)) {
            return false;
        }
        _persist();
        return true;
    }

    //! Undo the last completed set of the selected exercise.
    public function undoLastSet() as Boolean {
        var engine = _engine;
        if (engine == null || !engine.undoLastSet()) {
            return false;
        }
        var ex = engine.currentExercise();
        if (ex != null) {
            syncPendingValues(ex);
        }
        _exerciseStartedAt = now();
        _exercisePage = Tuning.PAGE_SET;
        _startTicker();
        _persist();
        return true;
    }

    // ------------------------------------------------------------------
    // Completing a set
    // ------------------------------------------------------------------

    //! Record the set, mark a FIT lap, persist, then show the rest screen.
    public function completeSet() as Void {
        var engine = _engine;
        if (engine == null) {
            return;
        }
        var exercise = engine.currentExercise();
        if (exercise == null) {
            return;
        }
        engine.completeCurrentSet(_pendingReps, _pendingWeight, now());
        _recorder.markSet();
        _recorder.updateTotals(engine.summary(now()));
        syncPendingValues(exercise);
        _persist();
        Haptics.setLogged();
        // Always return to the set page: the next thing the athlete does is the
        // next set, not read metrics.
        _exercisePage = Tuning.PAGE_SET;
        var rest = exercise.restDuration;
        if (rest <= 0) {
            rest = Settings.restDefault();
        }
        startRest(rest);
    }

    // ------------------------------------------------------------------
    // Rest timer
    // ------------------------------------------------------------------

    public function startRest(durationSec as Number) as Void {
        _rest.start(durationSec);
        _startTicker();   // already running during a workout; harmless to re-arm
        WatchUi.switchToView(new RestView(), new RestDelegate(), WatchUi.SLIDE_UP);
    }

    private function _startTicker() as Void {
        if (_ticker == null) {
            _ticker = new Timer.Timer();
        }
        (_ticker as Timer.Timer).start(method(:onTick), 1000, true);
    }

    public function stopTicker() as Void {
        var t = _ticker;
        if (t != null) {
            t.stop();
        }
    }

    //! 1 Hz tick. Drives the rest countdown, and keeps the exercise timer and
    //! the live metric pages moving while the athlete is working.
    public function onTick() as Void {
        if (_engine != null) {
            _zones.sample(LiveMetrics.heartRateZone());
        }
        if (_rest.isRunning() && _rest.tick()) {
            // Reached zero exactly on this tick — notify once.
            Haptics.restOver();
        }
        WatchUi.requestUpdate();
    }

    //! Leave the rest screen and get back to work.
    //!
    //! If the exercise just finished, move on to whatever is next rather than
    //! returning to a completed list — that is the flow Hevy has, and it saves
    //! the athlete a trip through the overview after every exercise.
    public function endRest() as Void {
        _rest.skip();

        var engine = _engine;
        if (engine != null) {
            var current = engine.currentExercise();
            if (current != null && current.hasReachedTargetSets()) {
                var next = engine.suggestNextExercise();
                if (next != null && !next.id.equals(current.id)) {
                    selectExercise(next.id);
                }
            }
        }
        WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }

    // ------------------------------------------------------------------
    // Finishing
    // ------------------------------------------------------------------

    //! Close the session and show the summary. Does not save the FIT file yet —
    //! the athlete confirms that on the summary screen.
    //! End the workout and show the recap.
    //!
    //! `save` is the athlete's answer to the Garmin-style stop menu, taken
    //! *before* this is called — the recap is a recap, not a second decision.
    //! That is why it no longer carries a SAVE button.
    public function finishWorkout(save as Boolean) as Void {
        var engine = _engine;
        if (engine == null) {
            return;
        }
        stopTicker();
        var summary = engine.finishWorkout(now());
        _recorder.updateTotals(summary);
        SessionRepository.appendHistory(engine.getSession(), summary);
        SessionRepository.clearActive();

        // Take what the recap needs before the engine is released: stopping the
        // recording drops it, and the per-exercise breakdown reads from it.
        var workout = engine.getWorkout();

        if (save) {
            _recorder.stopAndSave();
        } else {
            _recorder.stopAndDiscard();
        }
        _engine = null;

        var view = new WorkoutSummaryView(summary, workout, _zones, save);
        WatchUi.switchToView(view, new WorkoutSummaryDelegate(view), WatchUi.SLIDE_UP);
    }

    //! Write the Garmin activity and return to the workout list.

    //! Persist the session now. Used after an edit that changed nothing in the
    //! engine but should still survive an app restart.
    public function persistNow() as Void {
        _persist();
    }

    //! Called from RepFlowApp.onStop — never lose a workout to a backgrounded app.
    public function onAppStop() as Void {
        stopTicker();
        _persist();
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private function _persist() as Void {
        var engine = _engine;
        if (engine != null && engine.getSession().state == SESSION_ACTIVE) {
            SessionRepository.saveActive(engine.getSession());
        }
    }

}

