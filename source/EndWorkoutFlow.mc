import Toybox.Lang;
import Toybox.WatchUi;

//! Ending a workout — the stop menu.
//!
//! Modelled on what a Fenix does when you press STOP during an activity: one
//! menu, three answers, no hidden state.
//!
//!     Back + Triceps          (or "2 exercises unfinished")
//!       Keep training
//!       Save
//!       Discard
//!
//! The menu is always shown. Save and discard are real, opposite outcomes for
//! the Garmin recording, and a decision that destroys a recording is not one to
//! infer from context. It used to be taken afterwards, on the recap screen,
//! where a SAVE button sat doing nothing the athlete had asked for.
//!
//! MVP requirement 13 — never quietly treat a workout as complete while work is
//! left — is kept: with anything unfinished the title says how much, and "Keep
//! training" is the first item, so the default press is the safe one. With
//! everything done, saving is first.
//!
//! It is a Menu2 rather than WatchUi.Confirmation because Confirmation pops
//! itself once its delegate returns, which fights RepFlow's flat switchToView
//! navigation. Menu2 leaves the transition fully under our control.
module EndWorkoutFlow {

    const ACTION_RESUME = "end_resume";
    const ACTION_SAVE = "end_save";
    const ACTION_DISCARD = "end_discard";

    public function request() as Void {
        var engine = AppController.instance().engine();
        if (engine == null) {
            return;
        }
        var unfinished = engine.unfinishedExercises();
        var title = unfinished.size() > 0
            ? unfinished.size().toString() + " " +
                (WatchUi.loadResource(Rez.Strings.UnfinishedWarning) as String)
            : engine.getWorkout().name;

        var menu = new WatchUi.Menu2({ :title => title });
        var resume = new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.Resume) as String, null, ACTION_RESUME, {});
        var save = new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SaveActivity) as String, null, ACTION_SAVE, {});

        // Whichever answer is the safe one for this workout goes first, because
        // the first item is the one already under the cursor.
        if (unfinished.size() > 0) {
            menu.addItem(resume);
            menu.addItem(save);
        } else {
            menu.addItem(save);
            menu.addItem(resume);
        }
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.DiscardActivity) as String, null,
            ACTION_DISCARD, {}));

        WatchUi.switchToView(menu, new EndWorkoutConfirmDelegate(), WatchUi.SLIDE_UP);
    }
}

class EndWorkoutConfirmDelegate extends WatchUi.Menu2InputDelegate {

    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        if (id.equals(EndWorkoutFlow.ACTION_SAVE)) {
            AppController.instance().finishWorkout(true);
            return;
        }
        if (id.equals(EndWorkoutFlow.ACTION_DISCARD)) {
            AppController.instance().finishWorkout(false);
            return;
        }
        _cancel();
    }

    //! BACK is "I did not mean to stop" — never an answer to save or discard.
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
