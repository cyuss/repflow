import Toybox.Lang;
import Toybox.Test;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Graphics;

//! Analytics: the session log, the Garmin side, and the two kept apart.
//!
//! The figures are only worth showing if a session is counted once and a
//! missing number is never read as a zero, so most of what follows is about
//! exactly that. The functions tested are the pure ones the screens use; the
//! storage around them is a thin wrapper.

//! A record carries what was performed, not what was planned.
(:test :analytics)
function testLogRecordIsWhatWasDone(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    var a = engine.getWorkout().findExercise("A") as Exercise;
    a.muscle = Muscle.CHEST;
    engine.selectExercise("A");
    engine.completeCurrentSet(10, 50.0, null, TestSupport.T0);
    engine.completeCurrentSet(8, 55.0, null, TestSupport.T0 + 120);
    // B is never touched; C is skipped. Neither may appear in the detail.
    engine.selectExercise("C");
    engine.skipExercise("C");
    var summary = engine.finishWorkout(TestSupport.T0 + 1800);
    var r = SessionLog.recordFor(TestSupport.T0, summary, engine.getWorkout());

    Test.assert(SessionLog.isRecord(r));
    Test.assertEqual(r[SessionLog.R_START] as Object, TestSupport.T0);
    Test.assertEqual(r[SessionLog.R_SETS] as Object, 2);
    Test.assertEqual(r[SessionLog.R_REPS] as Object, 18);
    Test.assertEqual(r[SessionLog.R_VOLUME] as Object, 940);       // 500 + 440

    var detail = r[SessionLog.R_DETAIL] as Array;
    Test.assertEqual(detail.size(), 1);
    var row = detail[0] as Array;
    Test.assertEqual(row[SessionLog.D_SETS] as Object, 2);
    Test.assertEqual(row[SessionLog.D_REPS] as Object, 18);
    Test.assertEqual(row[SessionLog.D_TOP_TENTHS] as Object, 550);  // the heavier set

    // Muscles are sparse: [group, kg], only groups with volume.
    var muscles = r[SessionLog.R_MUSCLES] as Array;
    Test.assertEqual(muscles.size(), 2);
    Test.assertEqual(muscles[0] as Object, Muscle.CHEST);
    Test.assertEqual(muscles[1] as Object, 940);
    return true;
}

//! The old twenty summaries come across with what they had, and nothing they
//! did not: no exercises, no muscles.
(:test :analytics)
function testLegacySummariesMigrate(logger as Test.Logger) as Boolean {
    var r = SessionLog.fromLegacy({
        "w" => "Push", "s" => 1700000000, "d" => 3600,
        "e" => 4, "c" => 16, "r" => 140, "v" => 5230.4
    });
    Test.assert(r != null);
    var record = r as Array;
    Test.assert(SessionLog.isRecord(record));
    Test.assertEqual(record[SessionLog.R_NAME] as Object, "Push");
    Test.assertEqual(record[SessionLog.R_VOLUME] as Object, 5230);
    Test.assertEqual((record[SessionLog.R_DETAIL] as Array).size() as Object, 0);
    Test.assertEqual((record[SessionLog.R_MUSCLES] as Array).size() as Object, 0);

    // Not a summary: refused, never guessed at.
    Test.assert(SessionLog.fromLegacy("nonsense") == null);
    Test.assert(SessionLog.fromLegacy({"w" => "No start"}) == null);
    Test.assert(!SessionLog.isRecord([1, 2, 3]));
    return true;
}

//! A RepFlow session is also in the watch's history, and must not come back
//! as a Garmin one.
(:test :analytics)
function testRepFlowSessionsAreNotCountedTwice(logger as Test.Logger) as Boolean {
    var t = TestSupport.T0;
    var record = SessionLog.fromLegacy({"w" => "Push", "s" => t, "d" => 3600,
        "e" => 3, "c" => 12, "r" => 100, "v" => 4000}) as Array;
    // The watch reports the RepFlow session (40 s later: the recording starts
    // a moment after the workout) and one real native session two days on.
    var natives = [[t + 40, 3550], [t + 2 * 86400, 2700]] as Array;
    var all = AnalyticsData.unify([record] as Array, natives, t - 86400);
    Test.assertEqual(all.size(), 2);
    // Newest first.
    Test.assertEqual(all[0][AnalyticsData.E_SOURCE] as Object, AnalyticsData.SRC_GARMIN);
    Test.assertEqual(all[1][AnalyticsData.E_SOURCE] as Object, AnalyticsData.SRC_REPFLOW);

    // The same rule when the cache is written.
    var merged = AnalyticsData.mergeNative([] as Array,
        [[t + 40, 3550], [t + 2 * 86400, 2700]] as Array<Array<Number>>, [t] as Array<Number>, t - 86400);
    Test.assertEqual(merged.size(), 1);
    Test.assertEqual(merged[0][0] as Object, t + 2 * 86400);
    return true;
}

//! The Garmin cache keeps what the watch can no longer reach, forgets what was
//! deleted, and is never wiped by an empty answer.
(:test :analytics)
function testNativeCacheMerge(logger as Test.Logger) as Boolean {
    var day = 86400;
    var t = TestSupport.T0;
    var since = t - 400 * day;
    var cache = [[t - 300 * day, 3000], [t - 10 * day, 2500], [t - 5 * day, 2600]] as Array;

    // The watch now reports back to t - 20 days, without the session of t - 5:
    // it was deleted. The one from t - 300 is older than the report reaches,
    // so it stays. A new one appears.
    var fresh = [[t - 20 * day, 2000], [t - 10 * day, 2500], [t - 1 * day, 2400]] as Array<Array<Number>>;
    var merged = AnalyticsData.mergeNative(cache, fresh, [] as Array<Number>, since);
    Test.assertEqual(merged.size(), 4);
    Test.assertEqual(merged[0][0] as Object, t - 300 * day);
    Test.assertEqual(merged[1][0] as Object, t - 20 * day);
    Test.assertEqual(merged[2][0] as Object, t - 10 * day);
    Test.assertEqual(merged[3][0] as Object, t - 1 * day);

    // An empty answer changes nothing.
    var kept = AnalyticsData.mergeNative(cache, [] as Array<Array<Number>>, [] as Array<Number>, since);
    Test.assertEqual(kept.size(), 3);

    // Ageing out still applies.
    var aged = AnalyticsData.mergeNative(cache, [] as Array<Array<Number>>, [] as Array<Number>, t - 100 * day);
    Test.assertEqual(aged.size(), 2);

    // A damaged entry is dropped, not trusted.
    var damaged = AnalyticsData.mergeNative([[t, "x"], "y", [t - day, 100]] as Array,
        [] as Array<Array<Number>>, [] as Array<Number>, since);
    Test.assertEqual(damaged.size(), 1);
    return true;
}

//! Volume, sets and reps come from RepFlow alone; Garmin adds to the count and
//! the time only.
(:test :analytics)
function testPeriodTotals(logger as Test.Logger) as Boolean {
    var t = TestSupport.T0;
    var a = SessionLog.fromLegacy({"w" => "A", "s" => t, "d" => 3600,
        "e" => 3, "c" => 12, "r" => 100, "v" => 4000}) as Array;
    var b = SessionLog.fromLegacy({"w" => "B", "s" => t + 86400, "d" => 1800,
        "e" => 2, "c" => 8, "r" => 60, "v" => 2000}) as Array;
    var all = AnalyticsData.unify([a, b] as Array, [[t + 2 * 86400, 2700]] as Array, t - 1);
    var s = AnalyticsData.statsBetween(all, t, t + 3 * 86400);
    Test.assertEqual(s.count, 3);
    Test.assertEqual(s.repflow, 2);
    Test.assertEqual(s.garmin, 1);
    Test.assertEqual(s.duration, 3600 + 1800 + 2700);
    Test.assertEqual(s.volume, 6000);
    Test.assertEqual(s.sets, 20);
    Test.assertEqual(s.reps, 160);

    // The period is half-open: a session at its end belongs to the next one.
    var first = AnalyticsData.statsBetween(all, t, t + 86400);
    Test.assertEqual(first.count, 1);
    return true;
}

//! Weeks start on Monday, local time; "yesterday" is a calendar day.
(:test :analytics)
function testAnalyticsCalendar(logger as Test.Logger) as Boolean {
    var now = Time.now().value();
    var week = NativeActivities.weekStart(now);
    Test.assert(week <= now && now - week < NativeActivities.WEEK);
    var info = Gregorian.info(new Time.Moment(week), Time.FORMAT_SHORT);
    Test.assertEqual(info.day_of_week as Object, 2);           // 1 is Sunday
    Test.assertEqual(info.hour as Object, 0);
    Test.assertEqual(info.min as Object, 0);

    var month = NativeActivities.monthStart(now);
    Test.assertEqual(Gregorian.info(new Time.Moment(month), Time.FORMAT_SHORT).day, 1);

    var today = NativeActivities.startOfDay(now);
    Test.assertEqual(NativeActivities.daysAgo(today + 60, now), 0);
    Test.assertEqual(NativeActivities.daysAgo(today - 60, now), 1);
    Test.assertEqual(NativeActivities.daysAgo(today - 3 * 86400 + 60, now), 3);
    Test.assertEqual(SessionLog.monthOf(month), SessionLog.monthOf(now));
    return true;
}

//! The glance formats volume without Theme or Units, which it cannot load.
//! It has to agree with them.
(:test :analytics)
function testGlanceVolumeMatchesTheApp(logger as Test.Logger) as Boolean {
    Test.assertEqual(GlanceDraw.volume(850, false), "850 kg");
    Test.assertEqual(GlanceDraw.volume(4230, false), "4.2 t");
    Test.assertEqual(GlanceDraw.volume(4260, false), "4.3 t");
    Test.assertEqual(GlanceDraw.volume(400, true), "881 lb");
    Test.assertEqual(GlanceDraw.volume(2000, true), "4.4k lb");
    return true;
}

//! Every Analytics screen draws, with a RepFlow session and a Garmin one —
//! a symbol error in a draw call blanks a screen, and only running it finds it.
(:test :analytics)
function testAnalyticsScreensDraw(logger as Test.Logger) as Boolean {
    var dc = TestSupport.screenDc();
    if (dc == null) {
        return true;
    }
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    engine.completeCurrentSet(10, 50.0, null, TestSupport.T0);
    var summary = engine.finishWorkout(TestSupport.T0 + 1800);
    var record = SessionLog.recordFor(TestSupport.T0, summary, engine.getWorkout());
    var entries = AnalyticsData.unify([record] as Array,
        [[TestSupport.T0 + 86400, 2700]] as Array, 0);

    for (var i = 0; i < entries.size(); i++) {
        var view = new AnalyticsSessionView(entries[i]);
        view.onUpdate(dc);
        view.scroll(1);
        view.onUpdate(dc);
        new AnalyticsSessionItem(entries[i], i).draw(dc);
    }
    new AnalyticsFilterItem().draw(dc);
    new AnalyticsHistoryMenu(entries);

    var overview = new AnalyticsView();
    for (var page = 0; page < AnalyticsView.PAGES; page++) {
        overview.onUpdate(dc);
        overview.turnPage(1);
    }

    GlanceDraw.draw(dc, 0, 0, dc.getWidth(), dc.getHeight() / 4);
    new GlancePreviewView().onUpdate(dc);
    Marquee.endFrame();
    return true;
}
