import Toybox.Lang;
import Toybox.WatchUi;

//! Everything the rest of RepFlow asks of Analytics, in one place.
//!
//! Analytics is excluded on the two products too small to hold it — a Fenix 6
//! and 6S have 128 KB for a watch app, and RepFlow with Analytics is past that
//! (see monkey.jungle). The rest of the app calls these hooks and nothing
//! else, so that build swaps this module for the empty one in
//! AnalyticsOff.mc and every caller compiles unchanged.
(:analytics)
module AnalyticsHooks {

    const ENABLED = true;

    //! The session log takes over from the old summaries once, and the glance's
    //! figures are brought up to date. Cheap after the first run: a flag read
    //! and two months of the log.
    public function onAppStart(now as Number) as Void {
        SessionLog.migrateLegacy();
        if (DevLaunch.DEMO) {
            DevLaunch.seedDemo(now);
        }
        AnalyticsData.writeGlanceCache(now);
    }

    //! The screen a simulator build was asked to open on, or null.
    public function devView() as [WatchUi.Views, WatchUi.InputDelegates] or Null {
        if (DevLaunch.MODE == DevLaunch.GLANCE_PREVIEW) {
            return [new GlancePreviewView(), new GlancePreviewDelegate()];
        }
        if (DevLaunch.MODE == DevLaunch.ANALYTICS) {
            return overview();
        }
        return null;
    }

    public function overview() as [WatchUi.Views, WatchUi.InputDelegates] or Null {
        var view = new AnalyticsView();
        return [view, new AnalyticsDelegate(view)];
    }

    public function openOverview() as Void {
        AnalyticsNav.overview(WatchUi.SLIDE_LEFT);
    }

    //! A saved session: logged whole, and the glance told.
    public function onSessionSaved(
        session as WorkoutSession,
        summary as SessionSummary,
        workout as Workout,
        at as Number
    ) as Void {
        SessionLog.appendSession(session, summary, workout);
        AnalyticsData.writeGlanceCache(at);
    }
}
