import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! RepFlow — your workout, your order.
//!
//! A flexible strength-training watch app: pick any exercise at any time, defer
//! an occupied machine and come back to it, without losing workout state.
//!
//! **The same class starts the glance**, in a few dozen kilobytes with only
//! `:glance` code loaded — hence the annotation, and hence onStart and onStop
//! doing nothing that needs the rest of the app. Everything the full app needs
//! at start-up happens in getInitialView, which the glance never calls.
(:glance)
class RepFlowApp extends Application.AppBase {

    //! True once the full app is running — never in the glance.
    private var _foreground as Boolean = false;
    private var _fromGlance as Boolean = false;

    public function initialize() {
        AppBase.initialize();
    }

    public function onStart(state as Dictionary?) as Void {
        var flag = state != null ? (state as Dictionary)[:launchedFromGlance] as Object? : null;
        _fromGlance = flag instanceof Boolean && (flag as Boolean);
    }

    //! The glance, on devices that have glances for watch apps (Connect IQ 4
    //! and later). A Fenix 6 never calls this.
    public function getGlanceView() as [WatchUi.GlanceView] or [WatchUi.GlanceView, WatchUi.GlanceViewDelegate] or Null {
        return [new RepFlowGlanceView()];
    }

    //! The phone wrote new settings. Drop the cached copies so the next read
    //! picks them up; nothing else has to know.
    //! RepFlow's own settings, opened by the watch.
    //!
    //! Whether the watch offers a Settings entry for an app in its list is the
    //! firmware's decision, not the app's — so this cannot be the only way in,
    //! and MENU on the workout picker opens the same menu.
    (:typecheck(disableGlanceCheck))
    public function getSettingsView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] or Null {
        var menu = AppSettingsMenu.build();
        return [menu, new AppSettingsDelegate(true, menu)];
    }

    //! Settings changed — either the athlete's, written from the phone, or the
    //! watch's own. Drop every cached answer so the next read picks them up;
    //! nothing else in the app has to know.
    (:typecheck(disableGlanceCheck))
    public function onSettingsChanged() as Void {
        Settings.invalidate();
        WatchUi.requestUpdate();
    }

    //! Persist whatever is in progress. The app may be backgrounded at any time.
    //! Not in the glance: there is no workout there, and no AppController.
    (:typecheck(disableGlanceCheck))
    public function onStop(state as Dictionary?) as Void {
        if (!_foreground) {
            return;
        }
        AppController.instance().onAppStop();
    }

    //! Never called in the glance, so free to reach the whole app.
    (:typecheck(disableGlanceCheck))
    public function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _foreground = true;
        // Anything Hevy has not confirmed gets another try, quietly. The gym
        // case is a phone in a locker: the send fails, the workout stays
        // queued, and the next time the app opens it goes.
        HevySync.sendOldestPending();
        AnalyticsHooks.onAppStart(AppController.now());

        // A simulator build asked to open somewhere else (see DevLaunch).
        var dev = AnalyticsHooks.devView();
        if (dev != null) {
            return dev;
        }
        // An interrupted workout takes priority over the workout picker.
        var restored = SessionRepository.loadActive();
        if (restored != null) {
            AppController.instance().resumeWorkout(restored);
            if (restored.currentExerciseId != null) {
                return [new ExerciseView(), new ExerciseDelegate()];
            }
            return [new WorkoutOverviewView(), new WorkoutOverviewDelegate()];
        }
        // The glance's figures are a tap away from their detail.
        if (_fromGlance) {
            var analytics = AnalyticsHooks.overview();
            if (analytics != null) {
                return analytics;
            }
        }
        var listView = new WorkoutListView();
        return [listView, new WorkoutListDelegate(listView)];
    }
}

//! Convenience accessor used by the views.
function getApp() as RepFlowApp {
    return Application.getApp() as RepFlowApp;
}
