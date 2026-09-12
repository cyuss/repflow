import Toybox.Lang;
import Toybox.Math;
import Toybox.Application.Storage;

//! What the athlete did before: last performance, personal records, and the
//! week's volume per muscle group.
//!
//! Sessions were already being written to history when a workout ended, and
//! nothing ever read them back — so the app could not answer "what did I lift
//! last time", which is the most consulted number in any lifting app and the
//! thing every other progression feature depends on.
//!
//! **Two stores, both keyed by movement, both bounded.**
//!
//!   KEY_BESTS   movementId -> a flat array of seven numbers. One row per
//!               movement ever performed, capped, oldest-touched evicted.
//!   KEY_WEEKS   week index -> volume per muscle group. Eight weeks kept.
//!
//! Movement, not exercise: `ExerciseCatalogue.movementId` strips the "#2" that
//! distinguishes a second round of curls in the same session, so both rounds
//! feed one progression.
//!
//! **Nothing here is written during a set.** The bests are loaded once when a
//! workout starts, compared in memory as sets are logged — which is what makes
//! a record buzz the instant it happens — and written back once at the end.
//! Storage on the hot path would cost frames the athlete would feel.
module History {

    const KEY_BESTS = "bests";
    const KEY_WEEKS = "weeks";

    //! Movements tracked. Beyond this, the least recently performed is dropped:
    //! Application.Storage is finite and one oversized value fails the write.
    const MAX_MOVEMENTS = 120;
    //! Weeks of muscle volume kept.
    const MAX_WEEKS = 8;
    const WEEK_SECONDS = 604800;

    // Fields of a bests row.
    const B_LAST_WEIGHT = 0;    //! kg, tenths
    const B_LAST_REPS = 1;
    const B_LAST_SETS = 2;
    const B_LAST_AT = 3;        //! epoch seconds
    const B_BEST_WEIGHT = 4;    //! kg, tenths
    const B_BEST_1RM = 5;       //! kg, tenths
    const B_BEST_VOLUME = 6;    //! kg, whole
    const B_FIELDS = 7;

    // What kind of record a set just set. Ordered by how much it is worth
    // interrupting a workout for.
    const RECORD_NONE = 0;
    const RECORD_VOLUME = 1;
    const RECORD_1RM = 2;
    const RECORD_WEIGHT = 3;

    // ------------------------------------------------------------------
    // Estimation
    // ------------------------------------------------------------------

    //! Epley: what one rep would weigh, from a set of several.
    //!
    //! It is what makes a set of ten comparable with a set of three, which is
    //! the only way to tell whether a month of training went anywhere. It is an
    //! estimate and the app says so by never calling it a maximum.
    public function estimated1RM(reps as Number, weightKg as Float) as Float {
        if (reps <= 0 || weightKg <= 0.0) {
            return 0.0;
        }
        if (reps == 1) {
            return weightKg;
        }
        return weightKg * (1.0 + reps.toFloat() / 30.0);
    }

    function _tenths(kg as Float) as Number {
        return Math.round(kg * 10.0).toNumber();
    }

    function _kg(tenths as Number) as Float {
        return tenths.toFloat() / 10.0;
    }

    // ------------------------------------------------------------------
    // The bests store
    // ------------------------------------------------------------------

    //! Every movement's row, or an empty dictionary. Never throws.
    public function loadBests() as Dictionary {
        var raw = null;
        try {
            raw = Storage.getValue(KEY_BESTS);
        } catch (e) {
            return {} as Dictionary;
        }
        if (!(raw instanceof Dictionary)) {
            return {} as Dictionary;
        }
        // Validate before use, for the reason documented in SessionSnapshot: a
        // Monkey C runtime error on a bad row is not catchable.
        var out = {} as Dictionary;
        var keys = (raw as Dictionary).keys();
        for (var i = 0; i < keys.size(); i++) {
            var key = keys[i];
            if (!(key instanceof String)) {
                continue;
            }
            var row = (raw as Dictionary).get(key);
            if (_isValidRow(row)) {
                out.put(key, row);
            }
        }
        return out;
    }

    function _isValidRow(row as Object?) as Boolean {
        if (!(row instanceof Array)) {
            return false;
        }
        var a = row as Array;
        if (a.size() != B_FIELDS) {
            return false;
        }
        for (var i = 0; i < B_FIELDS; i++) {
            if (!(a[i] instanceof Number)) {
                return false;
            }
        }
        return true;
    }

    public function saveBests(bests as Dictionary) as Boolean {
        try {
            Storage.setValue(KEY_BESTS, _evict(bests) as Storage.ValueType);
            return true;
        } catch (e) {
            return false;
        }
    }

    //! Drop the least recently performed movements once there are too many.
    function _evict(bests as Dictionary) as Dictionary {
        var keys = bests.keys();
        if (keys.size() <= MAX_MOVEMENTS) {
            return bests;
        }
        // Find the cut-off timestamp by repeatedly removing the oldest. With a
        // cap of 120 and a handful of movements per session this runs rarely
        // and over a small list.
        var trimmed = bests;
        while (trimmed.keys().size() > MAX_MOVEMENTS) {
            var oldestKey = null;
            var oldestAt = 0;
            var ks = trimmed.keys();
            for (var i = 0; i < ks.size(); i++) {
                var row = trimmed.get(ks[i]) as Array;
                var at = row[B_LAST_AT] as Number;
                if (oldestKey == null || at < oldestAt) {
                    oldestKey = ks[i];
                    oldestAt = at;
                }
            }
            if (oldestKey == null) {
                break;
            }
            trimmed.remove(oldestKey);
        }
        return trimmed;
    }

    public function rowFor(bests as Dictionary, movementId as String) as Array? {
        var row = bests.get(movementId);
        return _isValidRow(row) ? row as Array : null;
    }

    //! What was done on this movement last time: [weightKg, reps, sets, at].
    public function lastPerformance(bests as Dictionary, exerciseId as String) as Array? {
        var row = rowFor(bests, ExerciseCatalogue.movementId(exerciseId));
        if (row == null || (row[B_LAST_SETS] as Number) <= 0) {
            return null;
        }
        return [
            _kg(row[B_LAST_WEIGHT] as Number),
            row[B_LAST_REPS] as Number,
            row[B_LAST_SETS] as Number,
            row[B_LAST_AT] as Number
        ] as Array;
    }

    //! Does this set beat anything on record? Does not modify the store.
    //!
    //! The heaviest single set is reported ahead of an estimated maximum, and
    //! that ahead of volume, because that is the order a lifter cares about
    //! them — and because only one thing can be announced at a time.
    public function classify(
        bests as Dictionary,
        exerciseId as String,
        reps as Number,
        weightKg as Float?
    ) as Number {
        // A bodyweight set has no load to beat. Counting it as a record would
        // announce one on every push-up.
        if (weightKg == null || reps <= 0 || (weightKg as Float) <= 0.0) {
            return RECORD_NONE;
        }
        var row = rowFor(bests, ExerciseCatalogue.movementId(exerciseId));
        if (row == null) {
            // A movement's first ever set is not a record. Everything would be.
            return RECORD_NONE;
        }
        var kg = weightKg as Float;
        if (_tenths(kg) > (row[B_BEST_WEIGHT] as Number)) {
            return RECORD_WEIGHT;
        }
        if (_tenths(estimated1RM(reps, kg)) > (row[B_BEST_1RM] as Number)) {
            return RECORD_1RM;
        }
        if (Math.round(kg * reps).toNumber() > (row[B_BEST_VOLUME] as Number)) {
            return RECORD_VOLUME;
        }
        return RECORD_NONE;
    }

    //! Fold a performed set into the in-memory bests, and say what it beat.
    public function recordSet(
        bests as Dictionary,
        exerciseId as String,
        reps as Number,
        weightKg as Float?,
        at as Number
    ) as Number {
        var kind = classify(bests, exerciseId, reps, weightKg);
        if (weightKg == null) {
            return kind;      // nothing to fold in; bodyweight leaves no best
        }
        var movement = ExerciseCatalogue.movementId(exerciseId);
        var row = rowFor(bests, movement);
        if (row == null) {
            row = [0, 0, 0, 0, 0, 0, 0] as Array;
        }
        var kg = weightKg as Float;
        var w = _tenths(kg);
        var e1rm = _tenths(estimated1RM(reps, kg));
        var volume = Math.round(kg * reps).toNumber();

        if (w > (row[B_BEST_WEIGHT] as Number)) { row[B_BEST_WEIGHT] = w; }
        if (e1rm > (row[B_BEST_1RM] as Number)) { row[B_BEST_1RM] = e1rm; }
        if (volume > (row[B_BEST_VOLUME] as Number)) { row[B_BEST_VOLUME] = volume; }
        bests.put(movement, row);
        return kind;
    }

    //! Close a session: every movement's "last time" becomes this session's.
    //!
    //! Done at the end rather than per set so "last: 60 x 10, 10, 8" describes a
    //! whole session, and so nothing writes to storage while the athlete lifts.
    public function commitSession(bests as Dictionary, workout as Workout, at as Number) as Void {
        var list = workout.exercises;
        for (var i = 0; i < list.size(); i++) {
            var ex = list[i];
            var done = ex.completedSetCount();
            if (done == 0) {
                continue;
            }
            var last = ex.lastCompletedSet();
            if (last == null) {
                continue;
            }
            var movement = ExerciseCatalogue.movementId(ex.id);
            var row = rowFor(bests, movement);
            if (row == null) {
                row = [0, 0, 0, 0, 0, 0, 0] as Array;
            }
            var actualWeight = last.actualWeight;
            var actualReps = last.actualReps;
            row[B_LAST_WEIGHT] = _tenths(actualWeight == null ? 0.0 : actualWeight as Float);
            row[B_LAST_REPS] = actualReps == null ? 0 : actualReps as Number;
            row[B_LAST_SETS] = done;
            row[B_LAST_AT] = at;
            bests.put(movement, row);
        }
        saveBests(bests);
        _commitWeek(workout, at);
    }

    // ------------------------------------------------------------------
    // Weekly volume per muscle group
    // ------------------------------------------------------------------

    public function weekIndex(at as Number) as Number {
        return at / WEEK_SECONDS;
    }

    public function loadWeeks() as Dictionary {
        var raw = null;
        try {
            raw = Storage.getValue(KEY_WEEKS);
        } catch (e) {
            return {} as Dictionary;
        }
        if (!(raw instanceof Dictionary)) {
            return {} as Dictionary;
        }
        var out = {} as Dictionary;
        var keys = (raw as Dictionary).keys();
        for (var i = 0; i < keys.size(); i++) {
            var key = keys[i];
            var row = (raw as Dictionary).get(key);
            if (!(key instanceof Number) || !(row instanceof Array)) {
                continue;
            }
            if ((row as Array).size() != Muscle.COUNT) {
                continue;
            }
            var ok = true;
            for (var j = 0; j < Muscle.COUNT; j++) {
                if (!((row as Array)[j] instanceof Number)) {
                    ok = false;
                    break;
                }
            }
            if (ok) {
                out.put(key, row);
            }
        }
        return out;
    }

    //! Volume per muscle for the week containing `at`, in whole kilograms.
    public function volumeForWeek(at as Number) as Array<Number> {
        var weeks = loadWeeks();
        var row = weeks.get(weekIndex(at));
        var out = new [Muscle.COUNT] as Array<Number>;
        for (var i = 0; i < Muscle.COUNT; i++) {
            out[i] = 0;
        }
        if (!(row instanceof Array) || (row as Array).size() != Muscle.COUNT) {
            return out;
        }
        for (var i = 0; i < Muscle.COUNT; i++) {
            var v = (row as Array)[i];
            out[i] = (v instanceof Number) ? v as Number : 0;
        }
        return out;
    }

    function _commitWeek(workout as Workout, at as Number) as Void {
        var weeks = loadWeeks();
        var index = weekIndex(at);
        var row = weeks.get(index);
        var totals = new [Muscle.COUNT] as Array<Number>;
        for (var i = 0; i < Muscle.COUNT; i++) {
            totals[i] = 0;
        }
        if (row instanceof Array && (row as Array).size() == Muscle.COUNT) {
            for (var i = 0; i < Muscle.COUNT; i++) {
                var v = (row as Array)[i];
                totals[i] = (v instanceof Number) ? v as Number : 0;
            }
        }

        var list = workout.exercises;
        for (var i = 0; i < list.size(); i++) {
            var ex = list[i];
            var m = ex.muscle;
            if (!Muscle.isValid(m)) {
                m = Muscle.OTHER;
            }
            totals[m] += Math.round(ex.totalVolume()).toNumber();
        }
        weeks.put(index, totals as Object);

        // Keep only the most recent weeks.
        var keys = weeks.keys();
        while (keys.size() > MAX_WEEKS) {
            var oldest = null;
            for (var i = 0; i < keys.size(); i++) {
                var k = keys[i] as Number;
                if (oldest == null || k < (oldest as Number)) {
                    oldest = k;
                }
            }
            if (oldest == null) {
                break;
            }
            weeks.remove(oldest);
            keys = weeks.keys();
        }

        try {
            Storage.setValue(KEY_WEEKS, weeks as Storage.ValueType);
        } catch (e) {
            // History is a convenience; never interrupt a workout for it.
        }
    }

    public function clear() as Void {
        try {
            Storage.deleteValue(KEY_BESTS);
            Storage.deleteValue(KEY_WEEKS);
        } catch (e) {
            // nothing useful to do
        }
    }
}
