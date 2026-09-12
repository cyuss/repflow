import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Timer;
import Toybox.Time;
import Toybox.Attention;
import Toybox.System;
import Toybox.Math;
import Toybox.Sensor;

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
    //! Beats dropped between sets, off the same tick as the zone chart.
    private var _recovery as RecoveryTracker;
    //! Repetitions counted from the wrist, when the athlete has asked for it.
    private var _reps as RepCounter;
    //! True while the accelerometer listener is registered.
    private var _counting as Boolean;
    //! Garmin's Body Battery when the workout started, for the recap. Read
    //! once, because a session is what moves it and a per-tick read would cost
    //! a sensor-history query every second for a number that changes hourly.
    private var _batteryStart as Number?;
    //! Every movement's records, loaded once at the start of a workout and
    //! written back once at the end. Comparing in memory is what lets a record
    //! buzz the instant it is set without a storage write on the hot path.
    private var _bests as Dictionary;
    //! The best thing that happened this session, for the recap.
    private var _bestRecord as Number;
    private var _recordCount as Number;
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
        _recovery = new RecoveryTracker();
        _reps = new RepCounter();
        _counting = false;
        _batteryStart = null;
        _bests = {} as Dictionary;
        _bestRecord = History.RECORD_NONE;
        _recordCount = 0;
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

    public function recovery() as RecoveryTracker {
        return _recovery;
    }

    public function bodyBatteryStart() as Number? {
        return _batteryStart;
    }

    //! Repetitions counted so far in this set, or null when nothing is counting.
    //!
    //! Null rather than zero when the counter is off or has seen no samples:
    //! "not counting" and "counted none" are different, and showing a confident
    //! 0 for the first would be a lie.
    public function countedReps() as Number? {
        if (!_counting || _reps.samplesSeen() == 0) {
            return null;
        }
        return _reps.count();
    }

    //! Take the counted repetitions as the value to log, and start again.
    //!
    //! Called the instant the athlete says the set is over, so the editor opens
    //! showing what was counted. They confirm or correct it with the press they
    //! were making anyway — the count is never written on its own.
    public function applyCountedReps() as Void {
        var counted = countedReps();
        if (counted != null && counted > 0) {
            _pendingReps = counted as Number;
        }
        _reps.reset();
    }

    //! Start or stop counting, from whatever just changed.
    //!
    //! One place decides, because four things can change the answer — the
    //! setting, the rest timer, the visible page and whether a workout is
    //! running — and a listener left registered would drain the battery at
    //! 25 Hz for the rest of the day.
    public function updateRepCounting() as Void {
        var wanted = Settings.repCounter() &&
            _engine != null &&
            !_rest.isRunning() &&
            _exercisePage == Tuning.PAGE_SET;
        if (wanted == _counting) {
            return;
        }
        if (wanted) {
            _startRepCounting();
        } else {
            _stopRepCounting();
        }
    }

    private function _startRepCounting() as Void {
        if (!(Sensor has :registerSensorDataListener)) {
            return;
        }
        try {
            Sensor.registerSensorDataListener(method(:onAccelData), {
                :period => 1,
                :accelerometer => {
                    :enabled => true,
                    :sampleRate => RepCounter.SAMPLE_RATE
                }
            });
            _reps.reset();
            _counting = true;
        } catch (e) {
            // Not every device delivers high-frequency accelerometer data.
            _counting = false;
        }
    }

    private function _stopRepCounting() as Void {
        if (!_counting) {
            return;
        }
        _counting = false;
        try {
            if (Sensor has :unregisterSensorDataListener) {
                Sensor.unregisterSensorDataListener();
            }
        } catch (e) {
            // nothing useful to do
        }
    }

    //! Accelerometer batch. Kept as short as possible: this runs at 1 Hz with
    //! 25 samples in it, on top of everything else the watch is doing.
    public function onAccelData(data as Sensor.SensorData) as Void {
        if (!_counting) {
            return;
        }
        var accel = data.accelerometerData;
        if (accel == null) {
            return;
        }
        if (_reps.feed(accel.x, accel.y, accel.z) > 0) {
            WatchUi.requestUpdate();
        }
    }

    //! Records as they stood when this workout began, plus anything set since.
    public function bests() as Dictionary {
        return _bests;
    }

    //! The strongest record set this session, and how many fell.
    public function bestRecord() as Number {
        return _bestRecord;
    }

    public function recordCount() as Number {
        return _recordCount;
    }

    //! What was done on this movement in the last session that touched it.
    public function lastPerformance(exerciseId as String) as Array? {
        return History.lastPerformance(_bests, exerciseId);
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
        // Counting runs only while the set page is showing.
        updateRepCounting();
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
        _recovery = new RecoveryTracker();
        _batteryStart = LiveMetrics.bodyBattery();
        _loadHistory();
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
        _loadHistory();
        _recorder.start(session.workout.name);
        var ex = session.currentExercise();
        if (ex != null) {
            syncPendingValues(ex);
        }
        _exerciseStartedAt = now();
        _startTicker();
    }

    //! Pre-fill the editable weight/reps from the exercise's inheritance rules.
    //! Pre-fill the editable weight/reps from the exercise's inheritance rules.
    //!
    //! The load is snapped to the step grid of whatever unit the athlete reads.
    //! A 55 kg template default is 121.3 lb, and a plan that opens on 121.3
    //! looks like a measurement rather than a suggestion. What was actually
    //! lifted is never snapped — only what is about to be.
    public function syncPendingValues(exercise as Exercise) as Void {
        _pendingWeight = Units.snap(exercise.plannedWeight());
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
        updateRepCounting();
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

    //! Add an exercise the plan did not have (4.6).
    public function addExercise(exercise as Exercise) as Boolean {
        var engine = _engine;
        if (engine == null || !engine.addExercise(exercise)) {
            return false;
        }
        _persist();
        return true;
    }

    //! Swap one exercise for another (4.5) — the machine is taken for good.
    public function substituteExercise(exerciseId as String, replacement as Exercise) as Boolean {
        var engine = _engine;
        if (engine == null || !engine.substituteExercise(exerciseId, replacement)) {
            return false;
        }
        _persist();
        return true;
    }

    //! One more set than the plan asked for (2.6).
    public function addSet(exerciseId as String) as Boolean {
        var engine = _engine;
        if (engine == null || !engine.addSet(exerciseId)) {
            return false;
        }
        var ex = engine.currentExercise();
        if (ex != null && ex.id.equals(exerciseId)) {
            syncPendingValues(ex);
        }
        _persist();
        return true;
    }

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
        updateRepCounting();
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
        var at = now();
        var reps = _pendingReps;
        var weight = _pendingWeight;
        var setNumber = exercise.completedSetCount() + 1;
        engine.completeCurrentSet(reps, weight, at);
        // The lap carries what the set was, so Garmin Connect's lap table reads
        // as a set list rather than as a row of anonymous split times.
        _recorder.markSet(exercise.name, setNumber, reps, weight);
        _recorder.updateTotals(engine.summary(at));
        syncPendingValues(exercise);
        _persist();

        // A record is the one thing in a session worth interrupting for, so it
        // gets its own pattern rather than the ordinary "set logged" tap.
        var record = History.recordSet(_bests, exercise.id, reps, weight, at);
        if (record != History.RECORD_NONE) {
            _recordCount++;
            if (record > _bestRecord) {
                _bestRecord = record;
            }
            Haptics.record();
        } else {
            Haptics.setLogged();
        }
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
        _recovery.startRest();
        updateRepCounting();
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
            var hr = LiveMetrics.heartRate();
            _zones.sample(LiveMetrics.zoneFor(hr));
            _recovery.sample(hr);
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
        _recovery.endRest();
        updateRepCounting();

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
        _stopRepCounting();
        var finishedAt = now();
        var summary = engine.finishWorkout(finishedAt);
        _recorder.updateTotals(summary);
        SessionRepository.appendHistory(engine.getSession(), summary);
        // Records and the week's volume are written once, here, never mid-set.
        History.commitSession(_bests, engine.getWorkout(), finishedAt);
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

        // Read once, here, rather than from a draw call: the recap pages are
        // repainted on every tick and Storage is not free.
        var weekly = History.volumeForWeek(finishedAt);
        var view = new WorkoutSummaryView(summary, workout, _zones, weekly,
            _recordCount, _batteryStart, _recovery.best(), save);
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
        _stopRepCounting();
        _persist();
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    //! Read the records in before the first set, so comparing one is free.
    private function _loadHistory() as Void {
        _bests = History.loadBests();
        _bestRecord = History.RECORD_NONE;
        _recordCount = 0;
    }

    private function _persist() as Void {
        var engine = _engine;
        if (engine != null && engine.getSession().state == SESSION_ACTIVE) {
            SessionRepository.saveActive(engine.getSession());
        }
    }

}

