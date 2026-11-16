import Toybox.Lang;
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
//!   just glance-preview           the glance, full screen, to design it
//!   ... demo=1                    with a demo year of sessions
(:analytics)
module DevLaunch {

    const NORMAL = 0;
    const ANALYTICS = 1;
    const GLANCE_PREVIEW = 2;

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

//! The glance, drawn full screen inside a frame the size of a glance row, so
//! its layout can be worked on without switching the simulator's glance mode.
//! It is not a test of the glance's memory limit — only the real glance mode
//! (`just glance`) is.
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
}
