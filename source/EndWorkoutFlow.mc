import Toybox.Lang;
import Toybox.WatchUi;

//! Ending a workout.
//!
//! MVP requirement 13: the workout is never quietly considered complete while
//! exercises are unfinished or pending. If anything is left, the athlete has to
//! confirm explicitly; if everything is done, ending is a single press.
//!
//! The confirmation is a Menu2 rather than WatchUi.Confirmation because
//! Confirmation pops itself once its delegate returns, which fights RepFlow's
//! flat switchToView navigation. Menu2 leaves the transition fully under our
//! control and matches the rest of the app.
module EndWorkoutFlow {

    const ACTION_CONFIRM = "end_yes";
    const ACTION_CANCEL = "end_no";

    public function request() as Void {
        var engine = AppController.instance().engine();
        if (engine == null) {
            return;
        }
        var unfinished = engine.unfinishedExercises();
        if (unfinished.size() == 0) {
            // Nothing left to do — ending needs no extra press.
            AppController.instance().finishWorkout();
            return;
        }
        var title = unfinished.size().toString() + " " +
            (WatchUi.loadResource(Rez.Strings.UnfinishedWarning) as String);
        var menu = new WatchUi.Menu2({ :title => title });
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.Resume) as String, null, ACTION_CANCEL, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.ConfirmEnd) as String, null, ACTION_CONFIRM, {}));
        WatchUi.switchToView(menu, new EndWorkoutConfirmDelegate(), WatchUi.SLIDE_UP);
    }
}

class EndWorkoutConfirmDelegate extends WatchUi.Menu2InputDelegate {

    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        if (id.equals(EndWorkoutFlow.ACTION_CONFIRM)) {
            AppController.instance().finishWorkout();
            return;
        }
        _cancel();
    }

    public function onBack() as Void {
        _cancel();
    }

    //! Nothing was changed — put the athlete back where they were.
    private function _cancel() as Void {
        var engine = AppController.instance().engine();
        if (engine != null && engine.currentExercise() != null) {
            WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_DOWN);
        } else {
            WatchUi.switchToView(new WorkoutOverviewView(), new WorkoutOverviewDelegate(), WatchUi.SLIDE_DOWN);
        }
    }
}
