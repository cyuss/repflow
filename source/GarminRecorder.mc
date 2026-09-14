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

    //! Longest session name handed to Garmin.
    //!
    //! 64 plain ASCII characters were verified to record without complaint on a
    //! fēnix 6 Pro. That is a measurement, not a documented limit — Garmin
    //! publishes none — so it is used as a ceiling rather than as a promise.
    private const SESSION_NAME_MAX = 64;

    //! Text that FIT can carry, with the accents folded rather than dropped.
    //!
    //! **A non-ASCII character in a session name can kill the app.** On a
    //! fēnix 6 Pro, `createSession` with "Épaules + Biceps + Triceps (~90 min)"
    //! fails with `Invalid Value: Failed invoking <symbol>` — and a Monkey C
    //! runtime error is not an Exception, so the `try` below does not catch it
    //! and the app dies at the very moment the athlete pressed start. The same
    //! string with a plain "E" records fine, as does a 64-character ASCII name,
    //! and as does a short accented one: the failure depends on the length as
    //! well as the character, which makes it worse than an outright refusal —
    //! it lets short names through and ambushes the long ones. Every string
    //! that leaves for Garmin is therefore folded, not just the ones that look
    //! risky.
    //!
    //! Folding rather than stripping, because "Epaules" is a French athlete's
    //! session and "paules" is nothing. Anything with no Latin equivalent is
    //! dropped: a name is better short than a name is unrecorded.
    //!
    //! It matters twice. The second is `EXERCISE_NAME_MAX`, which truncates by
    //! **character** into a field measured in **bytes** — "Développé couché" at
    //! the limit would overflow it. After folding the two counts are the same,
    //! which is what makes that truncation safe.
    public static function asciiSafe(text as String) as String {
        var chars = text.toCharArray();
        var out = "";
        for (var i = 0; i < chars.size(); i++) {
            var n = chars[i].toNumber();
            if (n >= 32 && n <= 126) {
                out += chars[i].toString();
            } else if (n >= 0xC0 && n <= 0xC5) { out += "A";
            } else if (n == 0xC6) { out += "AE";
            } else if (n == 0xC7) { out += "C";
            } else if (n >= 0xC8 && n <= 0xCB) { out += "E";
            } else if (n >= 0xCC && n <= 0xCF) { out += "I";
            } else if (n == 0xD1) { out += "N";
            } else if ((n >= 0xD2 && n <= 0xD6) || n == 0xD8) { out += "O";
            } else if (n >= 0xD9 && n <= 0xDC) { out += "U";
            } else if (n == 0xDD) { out += "Y";
            } else if (n == 0xDF) { out += "ss";
            } else if (n >= 0xE0 && n <= 0xE5) { out += "a";
            } else if (n == 0xE6) { out += "ae";
            } else if (n == 0xE7) { out += "c";
            } else if (n >= 0xE8 && n <= 0xEB) { out += "e";
            } else if (n >= 0xEC && n <= 0xEF) { out += "i";
            } else if (n == 0xF1) { out += "n";
            } else if ((n >= 0xF2 && n <= 0xF6) || n == 0xF8) { out += "o";
            } else if (n >= 0xF9 && n <= 0xFC) { out += "u";
            } else if (n == 0xFD || n == 0xFF) { out += "y";
            } else if (n == 0x152) { out += "OE";
            } else if (n == 0x153) { out += "oe";
            }
            // Everything else — emoji, Cyrillic, CJK — has no Latin reading and
            // is dropped rather than guessed at.
        }
        return out;
    }

    //! Fold, then cut to `max` characters. Safe to count in characters only
    //! because folding has already made one character one byte.
    public static function fitText(text as String, max as Number) as String {
        var folded = asciiSafe(text);
        if (folded.length() <= max) {
            return folded;
        }
        var cut = folded.substring(0, max);
        return cut == null ? "" : cut;
    }

    //! Create and start a strength-training session.
    //! Returns false when recording is unavailable — the workout still runs.
    public function start(workoutName as String) as Boolean {
        if (!isAvailable() || _session != null) {
            return false;
        }
        try {
            var name = fitText(workoutName, SESSION_NAME_MAX);
            if (name.length() == 0) {
                // A name of nothing but characters FIT cannot carry. The
                // activity is worth more than its title.
                name = "Strength";
            }
            var session = ActivityRecording.createSession({
                :name => name,
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
                (_lapExerciseField as FitContributor.Field).setData(
                    fitText(exerciseName, EXERCISE_NAME_MAX));
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
