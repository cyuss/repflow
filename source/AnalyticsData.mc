import Toybox.Lang;
import Toybox.Application.Storage;

//! The figures Analytics shows, from the two places sessions come from.
//!
//!   RepFlow   SessionLog — every set, every exercise, measured.
//!   Garmin    the watch's activity history — a date and a duration, nothing
//!             more (see NativeActivities). Cached here, because the
//!             history the firmware hands back is not guaranteed to reach as
//!             far as a year.
//!
//! **A session is counted once.** RepFlow records a real Garmin activity, so
//! every RepFlow session is also in the watch's history; anything within
//! NativeActivities.MATCH_SECONDS of a logged RepFlow start is dropped from the
//! Garmin side before it is stored.
//!
//! **Missing is not zero.** A Garmin session contributes to counts and time,
//! never to volume, sets or reps — it has none that the watch will give. The
//! screens say so wherever a Garmin session is part of a total.
(:analytics)
module AnalyticsData {

    const KEY_NATIVE = "nat";

    const SRC_REPFLOW = 0;
    const SRC_GARMIN = 1;

    // Fields of a unified entry.
    const E_START = 0;
    const E_DURATION = 1;
    const E_SOURCE = 2;
    const E_RECORD = 3;     //! the SessionLog record, or null for Garmin

    const DAY = 86400;
    //! Kept a little past a year, matching SessionLog.MAX_MONTHS.
    const KEEP_SECONDS = 400 * 86400;
    //! How close two Garmin starts must be to be the same activity.
    const SAME_ACTIVITY_SECONDS = 60;
    //! RepFlow sessions the glance is handed, in days.
    const GLANCE_DAYS = 15;

    // ------------------------------------------------------------------
    // Garmin sessions
    // ------------------------------------------------------------------

    //! Bring the cached Garmin sessions up to date with the watch's history.
    public function refreshNative(now as Number) as Void {
        var since = now - KEEP_SECONDS;
        var fresh = NativeActivities.trainingSince(since);
        var merged = mergeNative(loadNative(), fresh,
            startsOf(SessionLog.since(since)), since);
        try {
            Storage.setValue(KEY_NATIVE, merged as Storage.ValueType);
        } catch (e) {
        }
    }

    //! The cache, updated by what the watch reports now. Pure, so it is tested.
    //!
    //!  * anything matching a RepFlow session is RepFlow's, not Garmin's
    //!  * anything older than `since` has aged out
    //!  * anything the cache holds inside the span the watch just reported,
    //!    but the watch no longer reports, was deleted — it goes too
    //!  * older cached sessions stay: the watch may simply not reach that far
    //!
    //! An empty report changes nothing but the ageing: a device that answers
    //! with no history must not wipe a year of it.
    public function mergeNative(
        cache as Array,
        fresh as Array<Array<Number>>,
        repflowStarts as Array<Number>,
        since as Number
    ) as Array<Array<Number>> {
        var oldestFresh = null;
        var freshStarts = [] as Array<Number>;
        for (var i = 0; i < fresh.size(); i++) {
            var s = fresh[i][0];
            freshStarts.add(s);
            if (oldestFresh == null || s < (oldestFresh as Number)) {
                oldestFresh = s;
            }
        }

        var out = [] as Array<Array<Number>>;
        var outStarts = [] as Array<Number>;
        for (var i = 0; i < cache.size(); i++) {
            var c = cache[i] as Object?;
            if (!_isPair(c)) {
                continue;
            }
            var start = (c as Array)[0] as Number;
            if (start < since || NativeActivities.matches(start, repflowStarts)) {
                continue;
            }
            if (oldestFresh != null && start >= (oldestFresh as Number)
                    && !_near(start, freshStarts, SAME_ACTIVITY_SECONDS)) {
                continue;
            }
            out.add([start, (c as Array)[1] as Number] as Array<Number>);
            outStarts.add(start);
        }
        for (var i = 0; i < fresh.size(); i++) {
            var start = fresh[i][0];
            if (start < since || NativeActivities.matches(start, repflowStarts)) {
                continue;
            }
            if (_near(start, outStarts, SAME_ACTIVITY_SECONDS)) {
                continue;
            }
            out.add([start, fresh[i][1]] as Array<Number>);
            outStarts.add(start);
        }
        _sortByStart(out);
        return out;
    }

    public function loadNative() as Array {
        try {
            var raw = Storage.getValue(KEY_NATIVE);
            if (raw instanceof Array) {
                return raw as Array;
            }
        } catch (e) {
        }
        return [] as Array;
    }

    // ------------------------------------------------------------------
    // Both sources together
    // ------------------------------------------------------------------

    //! Every session since `since`, newest first: [start, seconds, source,
    //! record-or-null].
    public function sessions(since as Number) as Array<Array> {
        return unify(SessionLog.since(since), loadNative(), since);
    }

    //! The two sources as one list, newest first. Pure, so it is tested.
    //!
    //! The Garmin side is filtered against the RepFlow side again here, not
    //! only when the cache was written: a session logged after the cache was
    //! last refreshed would otherwise be counted twice until the next refresh.
    public function unify(records as Array, natives as Array, since as Number) as Array<Array> {
        var out = [] as Array<Array>;
        var starts = [] as Array<Number>;
        for (var i = 0; i < records.size(); i++) {
            var r = records[i] as Array;
            var start = r[SessionLog.R_START] as Number;
            if (start < since) {
                continue;
            }
            starts.add(start);
            out.add([start, r[SessionLog.R_DURATION], SRC_REPFLOW, r] as Array);
        }
        for (var i = 0; i < natives.size(); i++) {
            var n = natives[i] as Object?;
            if (!_isPair(n)) {
                continue;
            }
            var start = (n as Array)[0] as Number;
            if (start < since || NativeActivities.matches(start, starts)) {
                continue;
            }
            out.add([start, (n as Array)[1], SRC_GARMIN, null] as Array);
        }
        // Newest first: insertion sort, the lists are short and nearly sorted.
        for (var i = 1; i < out.size(); i++) {
            var j = i;
            while (j > 0 && (out[j][E_START] as Number) > (out[j - 1][E_START] as Number)) {
                var swap = out[j];
                out[j] = out[j - 1];
                out[j - 1] = swap;
                j--;
            }
        }
        return out;
    }

    //! Totals over [from, to).
    public function statsBetween(entries as Array<Array>, from as Number, to as Number) as PeriodStats {
        var s = new PeriodStats();
        for (var i = 0; i < entries.size(); i++) {
            var e = entries[i];
            var start = e[E_START] as Number;
            if (start < from || start >= to) {
                continue;
            }
            s.count++;
            s.duration += e[E_DURATION] as Number;
            if ((e[E_SOURCE] as Number) == SRC_GARMIN) {
                s.garmin++;
                continue;
            }
            s.repflow++;
            var r = e[E_RECORD] as Array;
            s.volume += r[SessionLog.R_VOLUME] as Number;
            s.sets += r[SessionLog.R_SETS] as Number;
            s.reps += r[SessionLog.R_REPS] as Number;
        }
        return s;
    }

    // ------------------------------------------------------------------
    // What the glance reads
    // ------------------------------------------------------------------

    //! Hand the glance the little it cannot work out for itself.
    //!
    //! The glance runs in a few dozen kilobytes and cannot afford to read the
    //! log, so it is given the last two weeks of RepFlow sessions as
    //! [start, kg, seconds] and the most recent session's name. It counts the
    //! Garmin side itself, live, so a native session shows up without RepFlow
    //! having been opened since.
    public function writeGlanceCache(now as Number) as Void {
        var recent = SessionLog.since(now - GLANCE_DAYS * DAY);
        var rf = [] as Array;
        for (var i = 0; i < recent.size(); i++) {
            var r = recent[i] as Array;
            rf.add([r[SessionLog.R_START], r[SessionLog.R_VOLUME], r[SessionLog.R_DURATION]] as Array);
        }
        var lastStart = 0;
        var lastName = "";
        // The newest session may be older than the two weeks above.
        var back = recent.size() > 0 ? recent : SessionLog.since(now - 62 * DAY);
        if (back.size() > 0) {
            var last = back[back.size() - 1] as Array;
            lastStart = last[SessionLog.R_START] as Number;
            lastName = last[SessionLog.R_NAME] as String;
        }
        var cache = {} as Dictionary<String, Storage.ValueType>;
        cache["rf"] = rf as Storage.ValueType;
        cache["ls"] = lastStart;
        cache["ln"] = lastName;
        cache["imp"] = Units.imperial();
        try {
            Storage.setValue(AnalyticsKeys.GLANCE, cache as Storage.ValueType);
        } catch (e) {
        }
    }

    // ------------------------------------------------------------------

    public function startsOf(rows as Array) as Array<Number> {
        var out = [] as Array<Number>;
        for (var i = 0; i < rows.size(); i++) {
            var r = rows[i] as Array;
            out.add(r[0] as Number);
        }
        return out;
    }

    function _isPair(value as Object?) as Boolean {
        if (!(value instanceof Array)) {
            return false;
        }
        var a = value as Array;
        if (a.size() != 2) {
            return false;
        }
        var first = a[0] as Object?;
        var second = a[1] as Object?;
        return (first instanceof Number) && (second instanceof Number);
    }

    function _near(start as Number, starts as Array<Number>, slack as Number) as Boolean {
        for (var i = 0; i < starts.size(); i++) {
            if ((start - starts[i]).abs() <= slack) {
                return true;
            }
        }
        return false;
    }

    function _sortByStart(rows as Array<Array<Number>>) as Void {
        for (var i = 1; i < rows.size(); i++) {
            var j = i;
            while (j > 0 && rows[j][0] < rows[j - 1][0]) {
                var swap = rows[j];
                rows[j] = rows[j - 1];
                rows[j - 1] = swap;
                j--;
            }
        }
    }
}

//! Totals for one period.
(:analytics)
class PeriodStats {
    public var count as Number = 0;
    public var repflow as Number = 0;
    public var garmin as Number = 0;
    //! Seconds.
    public var duration as Number = 0;
    //! Whole kilograms, RepFlow sessions only.
    public var volume as Number = 0;
    public var sets as Number = 0;
    public var reps as Number = 0;

    public function initialize() {
    }
}
