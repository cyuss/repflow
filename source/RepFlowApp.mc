import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! RepFlow — your workout, your order.
//!
//! A flexible strength-training watch app: pick any exercise at any time, defer
//! an occupied machine and come back to it, without losing workout state.
class RepFlowApp extends Application.AppBase {

    public function initialize() {
        AppBase.initialize();
    }

    //! Anything Hevy has not confirmed gets another try, quietly.
    //!
    //! The gym case is a phone in a locker: the send fails, the workout stays
    //! queued, and the next time the app opens — which is the next session, with
    //! the phone in a pocket — it goes. The athlete is never asked to remember.
    public function onStart(state as Dictionary?) as Void {
        HevySync.sendOldestPending();
    }

    //! The phone wrote new settings. Drop the cached copies so the next read
    //! picks them up; nothing else has to know.
    //! RepFlow's own settings, opened by the watch.
    //!
    //! Whether the watch offers a Settings entry for an app in its list is the
    //! firmware's decision, not the app's — so this cannot be the only way in,
    //! and MENU on the workout picker opens the same menu.
    public function getSettingsView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] or Null {
        return [AppSettingsMenu.build(), new AppSettingsDelegate(true)];
    }

    //! Settings changed — either the athlete's, written from the phone, or the
    //! watch's own. Drop every cached answer so the next read picks them up;
    //! nothing else in the app has to know.
    public function onSettingsChanged() as Void {
        Settings.invalidate();
        WatchUi.requestUpdate();
    }

    //! Persist whatever is in progress. The app may be backgrounded at any time.
    public function onStop(state as Dictionary?) as Void {
        AppController.instance().onAppStop();
    }

    public function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        // An interrupted workout takes priority over the workout picker.
        var restored = SessionRepository.loadActive();
        if (restored != null) {
            AppController.instance().resumeWorkout(restored);
            if (restored.currentExerciseId != null) {
                return [new ExerciseView(), new ExerciseDelegate()];
            }
            return [new WorkoutOverviewView(), new WorkoutOverviewDelegate()];
        }
        var listView = new WorkoutListView();
        return [listView, new WorkoutListDelegate(listView)];
    }
}

//! Convenience accessor used by the views.
function getApp() as RepFlowApp {
    return Application.getApp() as RepFlowApp;
}
