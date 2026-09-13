import Toybox.Lang;
import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.System;

//! Owns every interaction with Garmin's activity recording.
//!
//! RepFlow owns the workout; Garmin owns the activity. Keeping that boundary in
//! one small class means the workout engine never depends on ActivityRecording,
//! and the app still runs (without a FIT file) on a device where the module or
//! the Fit permission is unavailable.
//!
//! What the public Connect IQ API actually supports is documented in
//! docs/API_LIMITATIONS.md — in short: RepFlow can record a genuine
//! strength-training activity and attach developer FIT fields to it, but it
//! cannot write Garmin's native per-set `set` FIT messages.
//!
//! So the activity that reaches Garmin Connect is built from two things:
//!
//!   * **One lap per set**, which is the closest supported equivalent to a
//!     native set message. Garmin Connect shows laps in a table with their own
//!     duration and heart rate, so the shape of the session is already there.
//!   * **Developer fields on every lap** — exercise, set number, reps, load —
//!     which is what turns that table from "lap 7, 0:42" into "Bench Press,
//!     set 3, 8 reps at 70 kg". Developer fields are shown by Garmin Connect
//!     and by the phone app alongside Garmin's own.
//!
//! `createField` also takes a `:nativeNum`, which would map a developer field
//! onto a native FIT field and make Garmin Connect treat it as its own. The FIT
//! profile that defines those numbers does not ship with the Connect IQ SDK, so
//! using it would mean guessing a field number. It stays unused until the
//! number can be verified against Garmin's published FIT profile on a real
//! device. See docs/API_LIMITATIONS.md.
class GarminRecorder {

    // Developer FIT field ids. Stable — changing them breaks historical
    // activities, because Garmin Connect keys a field's history by this number.
    private const FIELD_SETS = 0;
    private const FIELD_REPS = 1;
    private const FIELD_VOLUME = 2;
    private const FIELD_LAP_EXERCISE = 10;
    private const FIELD_LAP_SET = 11;
    private const FIELD_LAP_REPS = 12;
    private const FIELD_LAP_WEIGHT = 13;
    private const FIELD_LAP_REST = 14;
    private const FIELD_LAP_RPE = 15;

    //! Longest exercise name written to a lap. A string field has to declare a
    //! size, and the name that comes back out of this field is what the
    //! backend in `backend/` matches against Garmin's exercise enum — so a
    //! truncation here is a mis-identified exercise there.
    //!
    //! RepFlow's own catalogue tops out at 21 ("Bulgarian Split Squat"), but
    //! imported names are longer: Hevy's "Triceps Extension (Cable)" is 25 and
    //! was being cut to "Triceps Extension (Cable". 40 covers every name in the
    //! athlete's routines with room to spare, and costs 16 bytes per lap.
    private const EXERCISE_NAME_MAX = 40;

    private var _session as ActivityRecording.Session?;
    private var _setsField as FitContributor.Field?;
    private var _repsField as FitContributor.Field?;
    private var _volumeField as FitContributor.Field?;
    private var _lapExerciseField as FitContributor.Field?;
    private var _lapSetField as FitContributor.Field?;
    private var _lapRepsField as FitContributor.Field?;
    private var _lapWeightField as FitContributor.Field?;
    private var _lapRestField as FitContributor.Field?;
    private var _lapRpeField as FitContributor.Field?;
    private var _started as Boolean;

    public function initialize() {
        _session = null;
        _setsField = null;
        _repsField = null;
        _volumeField = null;
        _lapExerciseField = null;
        _lapSetField = null;
        _lapRepsField = null;
        _lapWeightField = null;
        _lapRestField = null;
        _lapRpeField = null;
        _started = false;
    }

    //! True when this device exposes activity recording at all.
    public static function isAvailable() as Boolean {
        return (Toybox has :ActivityRecording);
    }

    //! Create and start a strength-training session.
    //! Returns false when recording is unavailable — the workout still runs.
    public function start(workoutName as String) as Boolean {
        if (!isAvailable() || _session != null) {
            return false;
        }
        try {
            var session = ActivityRecording.createSession({
                :name => workoutName,
                :sport => Activity.SPORT_TRAINING,
                :subSport => Activity.SUB_SPORT_STRENGTH_TRAINING
            });
            _session = session;
            _createFields(session);
            _started = session.start();
            return _started;
        } catch (e) {
            _session = null;
            _started = false;
            return false;
        }
    }

    //! Summary-level developer fields, so Garmin Connect shows RepFlow's numbers
    //! alongside Garmin's own (duration, HR, calories).
    private function _createFields(session as ActivityRecording.Session) as Void {
        try {
            _setsField = session.createField(
                "repflow_sets", FIELD_SETS, FitContributor.DATA_TYPE_UINT16,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "sets" }
            );
            _repsField = session.createField(
                "repflow_reps", FIELD_REPS, FitContributor.DATA_TYPE_UINT16,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "reps" }
            );
            _volumeField = session.createField(
                "repflow_volume", FIELD_VOLUME, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "kg" }
            );

            // Per-lap, so the lap table in Garmin Connect reads as a set list.
            _lapExerciseField = session.createField(
                "exercise", FIELD_LAP_EXERCISE, FitContributor.DATA_TYPE_STRING,
                { :mesgType => FitContributor.MESG_TYPE_LAP, :count => EXERCISE_NAME_MAX }
            );
            _lapSetField = session.createField(
                "set", FIELD_LAP_SET, FitContributor.DATA_TYPE_UINT16,
                { :mesgType => FitContributor.MESG_TYPE_LAP }
            );
            _lapRepsField = session.createField(
                "reps", FIELD_LAP_REPS, FitContributor.DATA_TYPE_UINT16,
                { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "reps" }
            );
            _lapWeightField = session.createField(
                "weight", FIELD_LAP_WEIGHT, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "kg" }
            );
            // How long the athlete rested before this set. A RepFlow lap is
            // closed when a set is logged, so it spans the rest *plus* the
            // set; without this number the two cannot be told apart after the
            // fact, and Garmin Connect's work/rest split has nothing to read.
            _lapRestField = session.createField(
                "rest", FIELD_LAP_REST, FitContributor.DATA_TYPE_UINT16,
                { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "s" }
            );
            // How hard the set felt. FIT has no native field for it — Garmin
            // Connect's own strength activity records reps and load and nothing
            // about effort — so it travels as RepFlow's own.
            _lapRpeField = session.createField(
                "rpe", FIELD_LAP_RPE, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_LAP }
            );
        } catch (e) {
            // Developer fields are a bonus; the activity itself still records.
            _setsField = null;
            _repsField = null;
            _volumeField = null;
            _lapExerciseField = null;
            _lapSetField = null;
            _lapRepsField = null;
            _lapWeightField = null;
            _lapRestField = null;
            _lapRpeField = null;
        }
    }

    //! Push the running totals into the FIT session message.
    public function updateTotals(summary as SessionSummary) as Void {
        try {
            if (_setsField != null) {
                (_setsField as FitContributor.Field).setData(summary.completedSets);
            }
            if (_repsField != null) {
                (_repsField as FitContributor.Field).setData(summary.totalReps);
            }
            if (_volumeField != null) {
                (_volumeField as FitContributor.Field).setData(summary.totalVolume);
            }
        } catch (e) {
            // ignore — never let telemetry break a workout
        }
    }

    //! Close a lap for the set that was just performed, carrying what it was.
    //!
    //! The values are written **before** `addLap`, because a lap-scoped
    //! developer field is recorded into the lap message at the moment the lap
    //! is closed. The name is truncated rather than rejected: a lap that says
    //! "Bulgarian Split Squa" is better than one that says nothing.
    //!
    //! The whole thing is best-effort. A failure here must never cost the
    //! athlete the set — RepFlow's own record of it has already been written.
    public function markSet(
        exerciseName as String,
        setNumber as Number,
        reps as Number,
        weightKg as Float?,
        rpe as Float?,
        restSeconds as Number
    ) as Boolean {
        var session = _session;
        if (session == null || !_started) {
            return false;
        }
        try {
            if (_lapExerciseField != null) {
                var name = exerciseName;
                if (name.length() > EXERCISE_NAME_MAX) {
                    var cut = name.substring(0, EXERCISE_NAME_MAX);
                    name = cut == null ? "" : cut;
                }
                (_lapExerciseField as FitContributor.Field).setData(name);
            }
            if (_lapSetField != null) {
                (_lapSetField as FitContributor.Field).setData(setNumber);
            }
            if (_lapRepsField != null) {
                (_lapRepsField as FitContributor.Field).setData(reps);
            }
            // A set with no load leaves the field unwritten rather than
            // recording a zero, which would read as "lifted nothing".
            if (_lapWeightField != null && weightKg != null) {
                (_lapWeightField as FitContributor.Field).setData(weightKg as Float);
            }
            // An unrated set leaves the field unwritten. Writing a zero would
            // put "RPE 0" in the lap table, which is not a rating.
            if (_lapRpeField != null && rpe != null) {
                (_lapRpeField as FitContributor.Field).setData(rpe as Float);
            }
            // Zero is a real answer here — the first set of a session, or a
            // superset taken straight through — so unlike the load it is
            // written rather than left out.
            if (_lapRestField != null && restSeconds >= 0) {
                (_lapRestField as FitContributor.Field).setData(restSeconds);
            }
        } catch (e) {
            // Carry on: the lap itself is worth more than the labels on it.
        }
        try {
            return session.addLap();
        } catch (e) {
            return false;
        }
    }

    //! There is no pause/resume on ActivityRecording.Session: stop() then
    //! start() is the supported way to pause the timer without ending the FIT
    //! file. See docs/API_LIMITATIONS.md.
    public function pause() as Boolean {
        var session = _session;
        if (session == null || !_started) {
            return false;
        }
        try {
            var ok = session.stop();
            _started = !ok;
            return ok;
        } catch (e) {
            return false;
        }
    }

    public function resume() as Boolean {
        var session = _session;
        if (session == null || _started) {
            return false;
        }
        try {
            _started = session.start();
            return _started;
        } catch (e) {
            return false;
        }
    }

    public function isRecording() as Boolean {
        var session = _session;
        if (session == null) {
            return false;
        }
        try {
            return session.isRecording();
        } catch (e) {
            return false;
        }
    }

    //! Stop and write the FIT file. Garmin syncs it as a strength activity.
    public function stopAndSave() as Boolean {
        var session = _session;
        if (session == null) {
            return false;
        }
        try {
            session.stop();
            var ok = session.save();
            _clear();
            return ok;
        } catch (e) {
            _clear();
            return false;
        }
    }

    //! Stop and throw the recording away (nothing reaches Garmin Connect).
    public function stopAndDiscard() as Boolean {
        var session = _session;
        if (session == null) {
            return false;
        }
        try {
            session.stop();
            var ok = session.discard();
            _clear();
            return ok;
        } catch (e) {
            _clear();
            return false;
        }
    }

    private function _clear() as Void {
        _session = null;
        _setsField = null;
        _repsField = null;
        _volumeField = null;
        _lapExerciseField = null;
        _lapSetField = null;
        _lapRepsField = null;
        _lapWeightField = null;
        _started = false;
    }
}
