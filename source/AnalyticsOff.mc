import Toybox.Lang;
import Toybox.WatchUi;

//! Analytics, absent: the build for products too small to hold it (see
//! monkey.jungle and AnalyticsHooks.mc). Same names, nothing behind them.
(:noAnalytics)
module AnalyticsHooks {

    const ENABLED = false;

    public function onAppStart(now as Number) as Void {
    }

    public function devView() as [WatchUi.Views, WatchUi.InputDelegates] or Null {
        return null;
    }

    public function fromGlance() as [WatchUi.Views, WatchUi.InputDelegates] or Null {
        return null;
    }

    public function overview() as [WatchUi.Views, WatchUi.InputDelegates] or Null {
        return null;
    }

    public function openOverview() as Void {
    }

    public function onSessionSaved(
        session as WorkoutSession,
        summary as SessionSummary,
        workout as Workout,
        at as Number
    ) as Void {
    }
}

//! These products have no glance for watch apps; the class only has to exist.
(:glance :noAnalytics)
class RepFlowGlanceView extends WatchUi.GlanceView {

    public function initialize() {
        GlanceView.initialize();
    }
}
