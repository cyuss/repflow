import Toybox.Lang;
import Toybox.Time;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Application;

//! How the app opens, for testing in the simulator.
//!
//! These two constants are rewritten by scripts/build.sh for the length of one
//! build when REPFLOW_LAUNCH / REPFLOW_DEMO are set, and put back afterwards —
//! the same mechanism as the Hevy key. A release build refuses to run with
//! either set, so a shipped app always opens normally.
//!
//!   just sim-analytics            open straight on Analytics
//!   just sim-glance               the glance, centred at its real size
//!   just sim-recap                the end-of-workout recap of a full session
//!   ... demo=1                    with a demo year of sessions
(:analytics)
module DevLaunch {

    const NORMAL = 0;
    const ANALYTICS = 1;
    const GLANCE_PREVIEW = 2;
    const RECAP = 3;

    //! Rewritten by scripts/build.sh. Never edit by hand.
    const MODE = 0;
    //! Rewritten by scripts/build.sh. Never edit by hand.
    const DEMO = false;

    //! Replace the session log and the Garmin cache with a believable spread
    //! of sessions over the last ten weeks. Simulator only: it overwrites.
    public function seedDemo(now as Number) as Void {
        var day = 86400;
        var names = ["Push Day", "Pull Day", "Legs"] as Array<String>;
        var records = [] as Array;
        var natives = [] as Array<Array<Number>>;
        // Ten weeks on real weekdays: RepFlow on Monday morning, Wednesday and
        // Friday evening, a Garmin session most Saturdays. The load creeps up
        // week on week, and one week in four is lighter, as a deload would be.
        var week = NativeActivities.weekStart(now);
        var plan = [[0, 7 * 3600 + 1800], [2, 18 * 3600], [4, 18 * 3600]] as Array<Array<Number>>;
        for (var w = 9; w >= 0; w--) {
            var monday = week - w * 7 * day;
            var light = w % 4 == 2;
            for (var p = 0; p < plan.size(); p++) {
                var at = monday + plan[p][0] * day + plan[p][1];
                if (at > now) {
                    continue;
                }
                var sets = light ? 11 : 15 + (p + w) % 3;
                var kg = (light ? 3800 : 5400) + (9 - w) * 120 + p * 250;
                records.add([at, 3300 + (p + w) % 4 * 420, sets, sets * 9, kg, 5,
                    names[p],
                    [Muscle.CHEST, kg / 2, Muscle.TRICEPS, kg / 4, Muscle.SHOULDERS, kg / 4] as Array<Number>,
                    [
                        ["Bench Press", 4, 32, 800 + (9 - w) * 25],
                        ["Incline Dumbbell Press", 3, 30, 300],
                        ["Lateral Raise", 4, 48, 100],
                        ["Triceps Pushdown", 3, 30, 250],
                        ["Overhead Triceps Extension", 3, 30, 200]
                    ] as Array] as Array);
            }
            var saturday = monday + 5 * day + 10 * 3600;
            if (saturday <= now && w % 3 != 1) {
                natives.add([saturday, 2700 + (w % 3) * 300] as Array<Number>);
            }
        }
        SessionLog.replaceAll(records);
        try {
            Application.Storage.setValue(AnalyticsData.KEY_NATIVE,
                natives as Application.Storage.ValueType);
        } catch (e) {
        }
    }
}

//! The end-of-workout recap of a full session, with every page carrying
//! something: seven exercises, one cut short and one skipped, RPE on every
//! set, all five heart-rate zones, three records, a busy week and every
//! Garmin figure present. Nothing is saved or recorded — the recap is built
//! straight from an engine, as AppController builds it.
(:analytics)
module RecapDemo {

    public function build() as [WatchUi.Views, WatchUi.InputDelegates] {
        var t0 = Time.now().value() - 4600;
        var list = [
            _exercise("A", "Bench Press", 4, 8, 80.0, Muscle.CHEST),
            _exercise("B", "Incline Dumbbell Press", 3, 10, 30.0, Muscle.CHEST),
            _exercise("C", "Seated Cable Fly", 3, 12, 22.5, Muscle.CHEST),
            _exercise("D", "Overhead Press", 4, 8, 50.0, Muscle.SHOULDERS),
            _exercise("E", "Lateral Raise", 4, 15, 12.0, Muscle.SHOULDERS),
            _exercise("F", "Triceps Pushdown", 3, 12, 30.0, Muscle.TRICEPS),
            _exercise("G", "Overhead Triceps Extension", 3, 12, 22.5, Muscle.TRICEPS)
        ] as Array<Exercise>;
        var workout = new Workout("demo", "Push Day", list);
        var engine = new WorkoutEngine(new WorkoutSession(workout, t0));
        var t = t0;
        // [exercise, sets done, reps, kg, first RPE]
        var plan = [
            ["A", 4, 8, 82.5, 7.5],
            ["B", 3, 10, 32.0, 8.0],
            ["C", 3, 12, 22.5, 7.0],
            ["D", 4, 8, 50.0, 8.0],
            ["E", 2, 15, 12.0, 8.5],
            ["F", 3, 12, 32.5, 8.0]
        ] as Array<Array>;
        for (var i = 0; i < plan.size(); i++) {
            var row = plan[i];
            engine.selectExercise(row[0] as String);
            for (var s = 0; s < (row[1] as Number); s++) {
                t += 150;
                engine.completeCurrentSet(row[2] as Number, row[3] as Float,
                    (row[4] as Float) + s * 0.5, t);
            }
        }
        engine.selectExercise("G");
        engine.skipExercise("G");
        var summary = engine.finishWorkout(t0 + 4520);

        var zones = new ZoneTracker();
        var seconds = [540, 1320, 1680, 760, 220] as Array<Number>;
        for (var z = 0; z < seconds.size(); z++) {
            for (var k = 0; k < seconds[z]; k++) {
                zones.sample(z + 1);
            }
        }
        var weekly = new [Muscle.COUNT] as Array<Number>;
        for (var m = 0; m < Muscle.COUNT; m++) {
            weekly[m] = 0;
        }
        weekly[Muscle.CHEST] = 9840;
        weekly[Muscle.BACK] = 8120;
        weekly[Muscle.SHOULDERS] = 4310;
        weekly[Muscle.TRICEPS] = 2650;
        weekly[Muscle.BICEPS] = 1720;
        weekly[Muscle.QUADS] = 11200;
        weekly[Muscle.HAMSTRINGS] = 3900;
        var records = [
            ["Bench Press", History.RECORD_WEIGHT, 8, 82.5] as Array,
            ["Triceps Pushdown", History.RECORD_1RM, 12, 41.3] as Array,
            ["Incline Dumbbell Press", History.RECORD_VOLUME, 10, 960.0] as Array
        ] as Array;
        var metrics = new RecapMetrics(486, 124, 168, 81, 32);
        metrics.batteryEnd = 63;
        metrics.trainingEffect = 3.4;
        var view = new WorkoutSummaryView(summary, workout, zones, weekly, records, metrics, true);
        return [view, new WorkoutSummaryDelegate(view)];
    }

    function _exercise(
        id as String,
        name as String,
        sets as Number,
        reps as Number,
        kg as Float,
        muscle as Number
    ) as Exercise {
        var e = new Exercise(id, name, sets, reps, kg, 90);
        e.muscle = muscle;
        return e;
    }
}

//! The glance, drawn full screen inside a frame the size of a glance row, so
//! its layout can be worked on without switching the simulator's glance mode.
//! It is not a test of the glance's memory limit — only the real glance mode
//! (`just glance-memory`) is.
(:analytics)
class GlancePreviewView extends WatchUi.View {

    public function initialize() {
        View.initialize();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var w = dc.getWidth();
        var h = dc.getHeight();
        // The glance's own drawing area, at its real size: a Fenix 9 Pro
        // 47 mm hands the glance 349 x 130 (logged from the simulator's glance
        // mode). Scaled with the screen for other sizes. The card around it
        // is the glance loop's row.
        var gw = (w * 349) / 454;
        var gh = (h * 130) / 454;
        var gx = (w - gw) / 2;
        var gy = (h - gh) / 2;
        var pad = h / 40;
        var radius = gh / 5;
        dc.setColor(0x141414, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(gx - pad, gy - pad, gw + pad * 2, gh + pad * 2, radius);
        dc.setColor(0x2A2A2A, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(gx - pad, gy - pad, gw + pad * 2, gh + pad * 2, radius);
        dc.setColor(Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, gy - pad * 2 - dc.getFontHeight(Graphics.FONT_XTINY), Graphics.FONT_XTINY,
            "GLANCE PREVIEW", Graphics.TEXT_JUSTIFY_CENTER);
        if (dc has :setClip) {
            dc.setClip(gx - pad, gy - pad, gw + pad * 2, gh + pad * 2);
        }
        GlanceDraw.draw(dc, gx, gy, gw, gh);
        if (dc has :clearClip) {
            dc.clearClip();
        }
    }
}

(:analytics)
class GlancePreviewDelegate extends WatchUi.BehaviorDelegate {

    public function initialize() {
        BehaviorDelegate.initialize();
    }

    //! START opens what the glance would: Analytics.
    public function onSelect() as Boolean {
        AnalyticsNav.overview(WatchUi.SLIDE_LEFT);
        return true;
    }

    //! And so does a tap on it, as on a touch watch's glance loop.
    public function onTap(event as WatchUi.ClickEvent) as Boolean {
        return onSelect();
    }
}
