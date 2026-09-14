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
    //! Epoch second the current rest began, or 0 when not resting.
    private var _restBeganAt as Number;
    //! True once this rest has announced itself as over.
    //!
    //! A rest can end two ways — the countdown reaching zero, or the athlete
    //! pressing START — and both mean "back under the bar". So both buzz, with
    //! the same pattern, and this is what stops the athlete who was already
    //! watching the countdown from being buzzed twice half a second apart.
    //!
    //! It also gives open rest a buzz it could not otherwise have: there is no
    //! zero to reach, so the press is the only moment there is.
    private var _restSignalled as Boolean;
    //! How long the athlete actually rested before the set about to be logged.
    //!
    //! Measured wall-clock from entering the rest screen to leaving it, not
    //! read off the countdown: a timer that expires while the athlete is still
    //! queueing for the rack understates the rest, and one that is skipped
    //! early overstates it. Zero for the first set of a session, and for a
    //! superset taken straight through.
    //!
    //! It exists because a RepFlow lap covers the rest *and* the set, so
    //! without this number nothing downstream can separate the two. See
    //! docs/garmin-strength-integration-poc.md.
    private var _restedSec as Number;
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
    //! What was beaten this session, in the order it happened.
    //!
    //! `[exercise name, History.RECORD_*, reps, weightKg]` per entry, kept so
    //! the recap can name them. A count alone says "2 records" and leaves the
    //! athlete to work out which lift and by what — which is the whole of what
    //! they want to know.
    //!
    //! Only the **best** record per movement is kept: beating your weight three
    //! times in one session is one story, not three.
    private var _records as Array;
    //! Weight/reps the athlete has dialled in for the set about to be performed.
    //!
    //! The weight is nullable, and null is not zero: it means the routine sets
    //! no target and the athlete has not touched the stepper. Logging a zero
    //! there would write a fabricated load into their history.
    private var _pendingWeight as Float?;
    private var _pendingReps as Number;
    //! The effort rating for the set being confirmed, or null for unrated.
    //!
    //! Cleared after every set rather than carried forward: a load is inherited
    //! because the next set is probably the same weight, and an effort rating
    //! is not, because the next set is probably harder. Carrying it would put a
    //! number the athlete never gave into their history.
    private var _pendingRpe as Float?;
    //! Which data screen the exercise view is showing. Lives here rather than on
    //! the view so it survives rest screens and menu round-trips.
    private var _exercisePage as Number;
    //! Which of the rest screen's three pages is showing. Kept here for the
    //! same reason as the exercise page: it has to survive a trip through the
    //! rest actions menu.
    private var _restPage as Number;
    //! Epoch seconds when the current exercise was selected, for the on-screen
    //! exercise timer. Garmin owns the activity clock; this one answers a
    //! different question — how long have I been on THIS exercise.
    private var _exerciseStartedAt as Number;
    //! Epoch second the set now under way began, or 0 when none is.
    //!
    //! A set begins when the athlete is back in front of the exercise able to
    //! lift: the rest ended, or they picked the exercise. It ends when the set
    //! is logged. That is a different span from the exercise timer, which runs
    //! across every set and every rest on the movement — and the difference is
    //! exactly what the athlete cannot see any other way.
    private var _setBeganAt as Number;

    public function initialize() {
        _engine = null;
        _recorder = new GarminRecorder();
        _rest = new RestTimer();
        _restBeganAt = 0;
        _restedSec = 0;
        _restSignalled = false;
        _ticker = null;
        _zones = new ZoneTracker();
        _recovery = new RecoveryTracker();
        _reps = new RepCounter();
        _counting = false;
        _batteryStart = null;
        _bests = {} as Dictionary;
        _bestRecord = History.RECORD_NONE;
        _recordCount = 0;
        _records = [] as Array;
        _pendingWeight = null;
        _pendingReps = 0;
        _pendingRpe = null;
        _exercisePage = 0;
        _restPage = 0;
        _exerciseStartedAt = 0;
        _setBeganAt = 0;
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

    //! What was beaten this session. See _records.
    public function records() as Array {
        return _records;
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

    //! The load about to be logged, or null when the athlete has not set one.
    public function pendingWeight() as Float? {
        return _pendingWeight;
    }

    public function pendingRpe() as Float? {
        return _pendingRpe;
    }

    public function pendingReps() as Number {
        return _pendingReps;
    }

    public function exercisePage() as Number {
        return _exercisePage;
    }

    //! Seconds spent on the exercise currently selected.
    public function exerciseSeconds() as Number {
        return _since(_exerciseStartedAt);
    }

    //! Seconds spent on the set now under way, or 0 between sets.
    public function setSeconds() as Number {
        return _since(_setBeganAt);
    }

    //! Seconds since an epoch second, or 0 when it was never set.
    //!
    //! A negative answer means the clock moved backwards under us — a time zone
    //! crossing, a GPS fix correcting the watch mid-session. Zero is the honest
    //! reading of that; a negative duration is not.
    private function _since(began as Number) as Number {
        if (began <= 0) {
            return 0;
        }
        var elapsed = now() - began;
        return elapsed > 0 ? elapsed : 0;
    }

    //! Page through the exercise data screens, wrapping at both ends.
    public function restPage() as Number {
        return _restPage;
    }

    public function turnRestPage(delta as Number) as Void {
        var count = Tuning.REST_PAGE_COUNT;
        _restPage = (_restPage + delta + count) % count;
    }

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
        // No set is under way: a session opens on the exercise list, and the
        // set clock starts when an exercise is actually chosen.
        _setBeganAt = 0;
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
        _setBeganAt = now();
        _startTicker();
    }

    //! Pre-fill the editable weight/reps from the exercise's inheritance rules.
    //!
    //! **An inherited load is never rounded.** It used to be snapped to the step
    //! grid of the displayed unit, which reads better — but on a statute watch
    //! that is a kg to lb to kg round trip, and it rewrites a routine's 20.0 kg
    //! as 19.96 kg before a single rep is performed. The athlete never touched
    //! it, so nothing may change it.
    //!
    //! Rounding happens where the athlete actually chooses a value, in
    //! `adjustWeight`: what they dialled is on the grid, and what they inherited
    //! is exactly what was inherited.
    public function syncPendingValues(exercise as Exercise) as Void {
        var weight = exercise.plannedWeight();

        // Before the first set of a movement, last session's load beats the
        // template's. A routine that says "-" for the weight — which is most of
        // them, because the load is the part that changes — would otherwise
        // open on zero every single week.
        //
        // Only the load. The repetitions stay the plan's: the plan is the
        // prescription, and the load is what the athlete found it took.
        if (exercise.completedSetCount() == 0) {
            var last = History.lastPerformance(_bests, exercise.id);
            if (last != null) {
                weight = (last as Array)[0] as Float;
            } else {
                // Nothing on this watch yet — the first session after an
                // import, or the first on a new watch. Hevy remembers even
                // then, and it is the same athlete's own number.
                var fromHevy = HevySync.lastFromHevy(exercise.hevyId);
                if (fromHevy != null) {
                    var w = (fromHevy as Array)[0];
                    if (w instanceof Float) {
                        weight = w as Float;
                    } else if (w instanceof Number) {
                        weight = (w as Number).toFloat();
                    }
                }
            }
        }

        _pendingWeight = weight;
        _pendingReps = exercise.plannedReps();
        _pendingRpe = null;
    }

    public function selectExercise(exerciseId as String) as Boolean {
        var engine = _engine;
        if (engine == null) {
            return false;
        }
        if (!engine.selectExercise(exerciseId)) {
            return false;
        }
        // Choosing an exercise is the other way off the rest screen, and the
        // wait is over the moment it happens.
        _closeRest();
        var ex = engine.currentExercise();
        if (ex != null) {
            syncPendingValues(ex);
        }
        _exerciseStartedAt = now();
        _setBeganAt = now();
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
        // Touching the stepper is what turns "no target" into a number. Until
        // then it stays null; from here on it is the athlete's own value.
        var current = _pendingWeight == null ? 0.0 : _pendingWeight as Float;
        var shown = Units.fromKg(current) + deltaSteps * step;
        var snapped = Math.round(shown / step) * step;
        if (snapped < 0.0) {
            snapped = 0.0;
        }
        _pendingWeight = Units.toKg(snapped.toFloat());
    }

    public function setWeight(weight as Float?) as Void {
        if (weight == null) {
            _pendingWeight = null;
            return;
        }
        _pendingWeight = (weight as Float) < 0.0 ? 0.0 : weight;
    }

    //! Step the effort rating up or down Hevy's ladder. See Rpe.
    public function adjustRpe(direction as Number) as Void {
        _pendingRpe = Rpe.step(_pendingRpe, direction);
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
        _setBeganAt = now();
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
        var rpe = _pendingRpe;
        var setNumber = exercise.completedSetCount() + 1;
        engine.completeCurrentSet(reps, weight, rpe, at);
        // The lap carries what the set was, so Garmin Connect's lap table reads
        // as a set list rather than as a row of anonymous split times.
        _recorder.markSet(exercise.name, setNumber, reps, weight, rpe, _restedSec);
        // Attribute a rest interval to exactly one set.
        _restedSec = 0;
        // The set is over. Its clock restarts when the next one begins.
        _setBeganAt = 0;
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
            _noteRecord(exercise.name, record, reps, weight);
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

    //! Begin the rest, in whichever shape the athlete has chosen.
    //!
    //! `durationSec` is ignored in open mode. It is still passed because the
    //! caller does not need to know which mode is in force, and because
    //! switching back mid-rest has to find the duration still there.
    public function startRest(durationSec as Number) as Void {
        if (Settings.restMode() == Tuning.REST_OPEN) {
            _rest.startOpen();
        } else {
            _rest.start(durationSec);
        }
        _restBeganAt = now();
        _restSignalled = false;
        _recovery.startRest();
        _restPage = 0;
        updateRepCounting();
        _startTicker();   // already running during a workout; harmless to re-arm
        WatchUi.switchToView(new RestView(), new RestDelegate(), WatchUi.SLIDE_UP);
    }

    //! Switch between a countdown and an open clock, mid-rest.
    //!
    //! The new mode becomes the default for the rest of the session and for
    //! every session after it — someone who reaches for this has decided how
    //! they want to train, not just how they want this one gap to behave.
    //!
    //! The rest already under way is restarted in the new shape rather than
    //! converted. Time already rested is kept: `_restBeganAt` is untouched, so
    //! the interval written to the FIT still measures from when the athlete
    //! actually stopped lifting.
    public function switchRestMode() as Void {
        var open = Settings.restMode() == Tuning.REST_OPEN;
        Settings.setRestMode(open ? Tuning.REST_TIMED : Tuning.REST_OPEN);
        // A rest that has already finished is not restarted in the other shape.
        // The setting is changed for the next one; putting a fresh countdown on
        // a screen the athlete is about to leave would be a surprise.
        if (!_rest.isRunning()) {
            return;
        }
        var began = _restBeganAt;
        if (open) {
            var exercise = _engine == null ? null : (_engine as WorkoutEngine).currentExercise();
            var seconds = exercise == null ? Settings.restDefault() : exercise.restDuration;
            if (seconds <= 0) {
                seconds = Settings.restDefault();
            }
            _rest.start(seconds);
        } else {
            _rest.startOpen();
        }
        _restBeganAt = began;
        WatchUi.requestUpdate();
    }

    //! Keep the best record this movement set today, replacing a lesser one.
    //!
    //! A lifter who beats their weight on set 2 and again on set 4 has one
    //! achievement with a better number, not two achievements. Listing both
    //! would make the recap longer and less true.
    private function _noteRecord(
        name as String,
        kind as Number,
        reps as Number,
        weightKg as Float?
    ) as Void {
        for (var i = 0; i < _records.size(); i++) {
            var row = _records[i] as Array;
            if (!(row[0] as String).equals(name)) {
                continue;
            }
            // A heavier record beats a lighter one of the same kind, and a
            // better kind beats any of a lesser one — see History.RECORD_*.
            var better = kind > (row[1] as Number);
            if (kind == (row[1] as Number) && weightKg != null) {
                var had = row[3] as Float?;
                better = had == null || (weightKg as Float) > (had as Float);
            }
            if (better) {
                _records[i] = [name, kind, reps, weightKg] as Array;
            }
            return;
        }
        _records.add([name, kind, reps, weightKg] as Array);
    }

    //! Say the rest is over, once per rest.
    private function _signalRestOver() as Void {
        if (_restSignalled) {
            return;
        }
        _restSignalled = true;
        Haptics.restOver();
    }

    //! Has this rest already announced itself? For the tests, which cannot
    //! observe a vibration.
    public function restOverSignalled() as Boolean {
        return _restSignalled;
    }

    //! Stop counting rest, and remember how much of it there was.
    //!
    //! Called from every way out of the rest screen, not just the timer
    //! finishing: an athlete who leaves to pick a different exercise has
    //! stopped resting, and leaving the interval open would charge the wait to
    //! whatever set is logged next.
    private function _closeRest() as Void {
        if (_restBeganAt == 0) {
            return;
        }
        var elapsed = now() - _restBeganAt;
        _restedSec = elapsed > 0 ? elapsed : 0;
        _restBeganAt = 0;
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
            // Reached zero exactly on this tick.
            _signalRestOver();
        }
        WatchUi.requestUpdate();
    }

    //! Leave the rest screen and get back to work.
    //!
    //! If the exercise just finished, move on to whatever is next rather than
    //! returning to a completed list — that is the flow Hevy has, and it saves
    //! the athlete a trip through the overview after every exercise.
    public function endRest() as Void {
        // Leaving the rest screen for the bar is the same event as the
        // countdown running out, whether the athlete waited for it or not — and
        // in open rest it is the only moment there is.
        _signalRestOver();
        _rest.skip();
        _closeRest();
        _setBeganAt = now();
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
        var startedAt = engine.getSession().startedAt;
        _engine = null;

        // Read once, here, rather than from a draw call: the recap pages are
        // repainted on every tick and Storage is not free.
        var weekly = History.volumeForWeek(finishedAt);
        // Captured while the recording is still open: see RecapMetrics.
        var metrics = RecapMetrics.capture(_batteryStart, _recovery.best());
        var view = new WorkoutSummaryView(summary, workout, _zones, weekly,
            _records, metrics, save);
        WatchUi.switchToView(view, new WorkoutSummaryDelegate(view), WatchUi.SLIDE_UP);

        // Closing the recording and queueing the session for Hevy happen after
        // the recap is on screen, not before it.
        //
        // This whole method runs inside a menu's selection callback, and the
        // screen does not repaint until it returns. Writing the FIT file — or
        // deleting it — is the slowest thing the app ever does, and with the
        // history writes in front of it the end of a workout was a visible
        // stall on the menu the athlete had just pressed. It looked like the
        // press had not registered, which is exactly the moment to press again.
        //
        // Neither of these feeds the recap, so neither has to be waited for.
        _closing = save ? CLOSE_SAVE : CLOSE_DISCARD;
        _closingMetrics = metrics;
        _closingWorkout = workout;
        _closingStartedAt = startedAt;
        _closingFinishedAt = finishedAt;
        _armCloser();
    }

    //! Nothing to close, the recording is being saved, or it is being dropped.
    private static const CLOSE_NONE = 0;
    private static const CLOSE_SAVE = 1;
    private static const CLOSE_DISCARD = 2;

    private var _closing as Number = CLOSE_NONE;
    private var _closingWorkout as Workout?;
    //! What Garmin measured, for Hevy's description. Captured with the recap.
    private var _closingMetrics as RecapMetrics?;
    private var _closingStartedAt as Number = 0;
    private var _closingFinishedAt as Number = 0;
    private var _closer as Timer.Timer?;

    //! Run the slow half of finishing, one tick after the recap is drawn.
    private function _armCloser() as Void {
        if (_closer == null) {
            _closer = new Timer.Timer();
        }
        (_closer as Timer.Timer).start(method(:onClose), 50, false);
    }

    //! Is a recording still waiting to be closed? For the tests, which cannot
    //! observe a FIT file.
    public function closingIsPending() as Boolean {
        return _closing != CLOSE_NONE;
    }

    //! The slow half of finishing a workout. Public because a Timer needs it.
    //!
    //! Safe to lose: if the app is killed between the recap appearing and this
    //! running, the session is already in the history and the recording is
    //! closed by `onAppStop` — which is where a dangling recording gets dealt
    //! with anyway, because one left open blocks the watch's sleep tracking.
    public function onClose() as Void {
        var closing = _closing;
        _closing = CLOSE_NONE;
        if (closing == CLOSE_NONE) {
            return;
        }

        if (closing == CLOSE_SAVE) {
            _recorder.stopAndSave();
        } else {
            _recorder.stopAndDiscard();
        }

        // Discarding is about the Garmin recording, not about the training.
        // A session the athlete performed is logged to Hevy either way — it is
        // queued first, so a phone in a locker costs nothing.
        var workout = _closingWorkout;
        if (workout != null) {
            HevySync.sendSession(workout as Workout, _closingStartedAt,
                _closingFinishedAt, _closingMetrics);
        }
        _closingWorkout = null;
    }

    //! Write the Garmin activity and return to the workout list.

    //! Persist the session now. Used after an edit that changed nothing in the
    //! engine but should still survive an app restart.
    public function persistNow() as Void {
        _persist();
    }

    //! Called from RepFlowApp.onStop — never lose a workout to a backgrounded app.
    //! Called from RepFlowApp.onStop — never lose a workout to a backgrounded app.
    //!
    //! **The recording must never be left running.** A watch with an activity in
    //! progress does not track sleep, so an athlete who swipes out of RepFlow
    //! mid-workout and goes to bed loses the whole night. The FIT file is
    //! therefore closed on every path out: saved if any set was logged, since a
    //! short strength activity is better than a lost one, and discarded when
    //! nothing was performed.
    //!
    //! This costs nothing on resume. A recording cannot be reattached after a
    //! restart in any case — see docs/API_LIMITATIONS.md — so resumeWorkout was
    //! already starting a fresh one.
    public function onAppStop() as Void {
        stopTicker();
        _stopRepCounting();
        _persist();

        // An answer already given wins. If the athlete pressed Save or Discard
        // and the app is closing before the deferred half ran, honour what they
        // chose rather than re-deciding it from the set count — a workout
        // discarded on purpose must not be saved because it happened to contain
        // sets.
        if (_closing != CLOSE_NONE) {
            onClose();
            return;
        }

        var engine = _engine;
        var logged = false;
        if (engine != null) {
            logged = engine.summary(now()).completedSets > 0;
        }
        if (logged) {
            _recorder.stopAndSave();
        } else {
            _recorder.stopAndDiscard();
        }
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    //! Read the records in before the first set, so comparing one is free.
    private function _loadHistory() as Void {
        _bests = History.loadBests();
        _bestRecord = History.RECORD_NONE;
        _recordCount = 0;
        _records = [] as Array;
    }

    private function _persist() as Void {
        var engine = _engine;
        if (engine != null && engine.getSession().state == SESSION_ACTIVE) {
            SessionRepository.saveActive(engine.getSession());
        }
    }

}

