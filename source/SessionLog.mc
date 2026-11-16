import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Application.Storage;

//! Every finished RepFlow session, kept on the watch for twelve months.
//!
//! This is what Analytics reads. SessionRepository's KEY_HISTORY was twenty
//! summaries with no exercises and no muscles in them, which is enough to say
//! "you trained" and nothing about what.
//!
//! **One Storage value per calendar month**, plus an index of the months held:
//!
//!   "logm"      [202610, 202611, ...]       months present, oldest first
//!   "L202611"   [record, record, ...]       that month's sessions
//!
//! Connect IQ bounds the size of a single stored value, and a year of sessions
//! with their exercises in one array would cross it on a heavy trainer. A month
//! is a few kilobytes at most, and the month a session belongs to is known from
//! its start, so an append touches exactly one value.
//!
//! **A record is a flat array**, not a dictionary — the same reason as
//! WorkoutSet.toStorage: keys cost bytes in every row.
//!
//!   R_START      epoch seconds, the session's start — also its identity
//!   R_DURATION   seconds
//!   R_SETS       completed sets
//!   R_REPS       completed reps
//!   R_VOLUME     whole kilograms
//!   R_EXERCISES  exercises with at least one set done
//!   R_NAME       the workout's name
//!   R_MUSCLES    [group, kg, group, kg, ...] — groups with volume only
//!   R_DETAIL     [[name, sets, reps, topKgTenths], ...] per exercise done
//!
//! Sessions migrated from the old summaries have empty R_MUSCLES and R_DETAIL:
//! that information was never stored, and inventing it is not an option.
(:analytics)
module SessionLog {

    const KEY_INDEX = "logm";
    const KEY_MIGRATED = "logv";
    const MONTH_PREFIX = "L";

    //! Months kept. The athlete agreed to six to twelve; twelve answers "same
    //! time last year" next year, which six never would.
    const MAX_MONTHS = 12;

    const R_START = 0;
    const R_DURATION = 1;
    const R_SETS = 2;
    const R_REPS = 3;
    const R_VOLUME = 4;
    const R_EXERCISES = 5;
    const R_NAME = 6;
    const R_MUSCLES = 7;
    const R_DETAIL = 8;
    const R_FIELDS = 9;

    // Fields of an R_DETAIL row.
    const D_NAME = 0;
    const D_SETS = 1;
    const D_REPS = 2;
    const D_TOP_TENTHS = 3;

    // ------------------------------------------------------------------
    // Writing
    // ------------------------------------------------------------------

    //! Log a finished session. Best effort: a storage failure must never cost
    //! the athlete the end of their workout.
    public function appendSession(
        session as WorkoutSession,
        summary as SessionSummary,
        workout as Workout
    ) as Boolean {
        return append(recordFor(session.startedAt, summary, workout));
    }

    //! The record for a session, built from what was actually performed.
    public function recordFor(
        startedAt as Number,
        summary as SessionSummary,
        workout as Workout
    ) as Array {
        var muscles = new [Muscle.COUNT] as Array<Number>;
        for (var m = 0; m < Muscle.COUNT; m++) {
            muscles[m] = 0;
        }
        var detail = [] as Array;
        var list = workout.exercises;
        for (var i = 0; i < list.size(); i++) {
            var ex = list[i];
            var done = ex.completedSetCount();
            if (done <= 0) {
                continue;
            }
            var kg = Math.round(ex.totalVolume()).toNumber();
            if (Muscle.isValid(ex.muscle)) {
                muscles[ex.muscle] += kg;
            }
            var top = 0.0;
            for (var s = 0; s < ex.sets.size(); s++) {
                var set = ex.sets[s];
                var w = set.actualWeight;
                if (set.completed && w != null && (w as Float) > top) {
                    top = w as Float;
                }
            }
            detail.add([ex.shortName(), done, ex.totalReps(),
                Math.round(top * 10.0).toNumber()] as Array);
        }
        var sparse = [] as Array<Number>;
        for (var m = 0; m < Muscle.COUNT; m++) {
            if (muscles[m] > 0) {
                sparse.add(m);
                sparse.add(muscles[m]);
            }
        }
        return [
            startedAt,
            summary.durationSec,
            summary.completedSets,
            summary.totalReps,
            Math.round(summary.totalVolume).toNumber(),
            summary.exercisesWorked,
            workout.name,
            sparse,
            detail
        ] as Array;
    }

    //! Write one record into its month. A record with the same start replaces
    //! the old one, so logging a session twice cannot count it twice.
    public function append(record as Array) as Boolean {
        if (!isRecord(record)) {
            return false;
        }
        try {
            var month = monthOf(record[R_START] as Number);
            var rows = _month(month);
            var replaced = false;
            for (var i = 0; i < rows.size(); i++) {
                var row = rows[i] as Array;
                if ((row[R_START] as Number) == (record[R_START] as Number)) {
                    rows[i] = record;
                    replaced = true;
                    break;
                }
            }
            if (!replaced) {
                rows.add(record);
            }
            Storage.setValue(MONTH_PREFIX + month.toString(), rows as Storage.ValueType);
            _indexAdd(month);
            return true;
        } catch (e) {
            return false;
        }
    }

    //! Bring the old twenty summaries across, once.
    //!
    //! Each becomes a record with no muscles and no exercises — the summaries
    //! never held them. The old key is left alone: other code still writes it,
    //! and the flag, not its absence, is what says this has run.
    public function migrateLegacy() as Void {
        try {
            if (Storage.getValue(KEY_MIGRATED) != null) {
                return;
            }
            var legacy = SessionRepository.loadHistory();
            for (var i = 0; i < legacy.size(); i++) {
                var record = fromLegacy(legacy[i] as Object?);
                if (record != null) {
                    append(record as Array);
                }
            }
            Storage.setValue(KEY_MIGRATED, 1);
        } catch (e) {
            // Tried again on the next start.
        }
    }

    //! One old summary as a record, or null when it is not one.
    public function fromLegacy(entry as Object?) as Array? {
        if (!(entry instanceof Dictionary)) {
            return null;
        }
        var d = entry as Dictionary;
        var start = d["s"];
        if (!(start instanceof Number)) {
            return null;
        }
        var name = d["w"];
        var volume = d["v"];
        var kg = 0;
        if (volume instanceof Float || volume instanceof Double) {
            kg = Math.round(volume as Float).toNumber();
        } else if (volume instanceof Number) {
            kg = volume as Number;
        }
        return [
            start,
            _number(d["d"] as Object?),
            _number(d["c"] as Object?),
            _number(d["r"] as Object?),
            kg,
            _number(d["e"] as Object?),
            name instanceof String ? name : "",
            [] as Array<Number>,
            [] as Array
        ] as Array;
    }

    //! Replace the whole log. For the simulator's demo data only.
    public function replaceAll(records as Array) as Void {
        var months = _index();
        for (var i = 0; i < months.size(); i++) {
            try {
                Storage.deleteValue(MONTH_PREFIX + months[i].toString());
            } catch (e) {
            }
        }
        try {
            Storage.deleteValue(KEY_INDEX);
        } catch (e) {
        }
        for (var i = 0; i < records.size(); i++) {
            append(records[i] as Array);
        }
    }

    // ------------------------------------------------------------------
    // Reading
    // ------------------------------------------------------------------

    //! Every record whose start is at or after `since`, oldest first.
    public function since(since as Number) as Array {
        var out = [] as Array;
        var first = monthOf(since);
        var months = _index();
        for (var i = 0; i < months.size(); i++) {
            if (months[i] < first) {
                continue;
            }
            var rows = _month(months[i]);
            for (var r = 0; r < rows.size(); r++) {
                var row = rows[r] as Object?;
                if (isRecord(row) && ((row as Array)[R_START] as Number) >= since) {
                    out.add(row);
                }
            }
        }
        return out;
    }

    //! A record that this build can read. Anything else is skipped, never
    //! trusted: a value written by a different layout would otherwise crash
    //! with an error `catch` cannot stop (docs/API_LIMITATIONS.md, section 9).
    public function isRecord(row as Object?) as Boolean {
        if (!(row instanceof Array)) {
            return false;
        }
        var a = row as Array;
        if (a.size() != R_FIELDS) {
            return false;
        }
        for (var i = R_START; i <= R_EXERCISES; i++) {
            if (!(a[i] instanceof Number)) {
                return false;
            }
        }
        var name = a[R_NAME] as Object?;
        var muscles = a[R_MUSCLES] as Object?;
        var detail = a[R_DETAIL] as Object?;
        return (name instanceof String) && (muscles instanceof Array) && (detail instanceof Array);
    }

    //! The month a moment falls in, local time, as yyyymm.
    public function monthOf(epoch as Number) as Number {
        var info = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_SHORT);
        return (info.year as Number) * 100 + (info.month as Number);
    }

    // ------------------------------------------------------------------

    function _month(month as Number) as Array {
        try {
            var raw = Storage.getValue(MONTH_PREFIX + month.toString());
            if (raw instanceof Array) {
                return raw as Array;
            }
        } catch (e) {
        }
        return [] as Array;
    }

    function _index() as Array<Number> {
        try {
            var raw = Storage.getValue(KEY_INDEX);
            if (raw instanceof Array) {
                var out = [] as Array<Number>;
                var a = raw as Array;
                for (var i = 0; i < a.size(); i++) {
                    if (a[i] instanceof Number) {
                        out.add(a[i] as Number);
                    }
                }
                return out;
            }
        } catch (e) {
        }
        return [] as Array<Number>;
    }

    //! Add a month to the index, keep it sorted, and drop the oldest months
    //! past MAX_MONTHS — deleting their values with them.
    function _indexAdd(month as Number) as Void {
        var months = _index();
        if (months.indexOf(month) < 0) {
            months.add(month);
            // Insertion: the new month is almost always the newest.
            for (var j = months.size() - 1; j > 0 && months[j] < months[j - 1]; j--) {
                var swap = months[j];
                months[j] = months[j - 1];
                months[j - 1] = swap;
            }
        }
        while (months.size() > MAX_MONTHS) {
            try {
                Storage.deleteValue(MONTH_PREFIX + months[0].toString());
            } catch (e) {
            }
            months = months.slice(1, null);
        }
        Storage.setValue(KEY_INDEX, months as Storage.ValueType);
    }

    function _number(value as Object?) as Number {
        if (value instanceof Number) {
            return value as Number;
        }
        if (value instanceof Float) {
            return (value as Float).toNumber();
        }
        return 0;
    }
}
