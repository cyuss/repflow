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

    public function onStart(state as Dictionary?) as Void {
    }

    //! The phone wrote new settings. Drop the cached copies so the next read
    //! picks them up; nothing else has to know.
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
