import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Timer;

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

    //! What the athlete chose, waiting for the menu to get out of the way.
    const CHOICE_NONE = 0;
    const CHOICE_RESUME = 1;
    const CHOICE_SAVE = 2;
    const CHOICE_DISCARD = 3;

    var _choice as Number = CHOICE_NONE;
    var _defer as Timer.Timer? = null;
    var _callbacks as EndWorkoutCallbacks = new EndWorkoutCallbacks();

    //! Act on the choice **after** this menu's callback has returned.
    //!
    //! Switching views from inside `Menu2InputDelegate.onSelect` leaves the
    //! menu's own layer on screen: the recap drew its header and the word
    //! "Discard" stayed painted across the middle of it — photographed on a
    //! real watch. The system owns that layer and only tears it down once the
    //! callback is done with it.
    //!
    //! So the choice is recorded, the callback returns, and a timer one tick
    //! later does the navigation. By then the menu is gone and the view
    //! underneath is ours to replace.
    public function choose(choice as Number) as Void {
        _choice = choice;
        if (_defer == null) {
            _defer = new Timer.Timer();
        }
        (_defer as Timer.Timer).start(_callbacks.method(:onChosen), 20, false);
    }

    //! Carry out whatever was chosen. Called from the deferring timer.
    public function act() as Void {
        var choice = _choice;
        _choice = CHOICE_NONE;

        if (choice == CHOICE_SAVE) {
            AppController.instance().finishWorkout(true);
            return;
        }
        if (choice == CHOICE_DISCARD) {
            AppController.instance().finishWorkout(false);
            return;
        }
        if (choice == CHOICE_RESUME) {
            resume();
        }
    }

    //! Nothing was changed — put the athlete back where they were.
    public function resume() as Void {
        var engine = AppController.instance().engine();
        if (engine != null && engine.currentExercise() != null) {
            WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(),
                WatchUi.SLIDE_DOWN);
        } else {
            WatchUi.switchToView(new WorkoutOverviewView(),
                new WorkoutOverviewDelegate(), WatchUi.SLIDE_DOWN);
        }
    }

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
            EndWorkoutFlow.choose(EndWorkoutFlow.CHOICE_SAVE);
            return;
        }
        if (id.equals(EndWorkoutFlow.ACTION_DISCARD)) {
            EndWorkoutFlow.choose(EndWorkoutFlow.CHOICE_DISCARD);
            return;
        }
        EndWorkoutFlow.choose(EndWorkoutFlow.CHOICE_RESUME);
    }

    //! BACK is "I did not mean to stop" — never an answer to save or discard.
    public function onBack() as Void {
        EndWorkoutFlow.choose(EndWorkoutFlow.CHOICE_RESUME);
    }
}

//! A module cannot hand a Timer one of its own functions — `method()` needs a
//! receiver and a module has none. This class is that receiver.
class EndWorkoutCallbacks {

    public function initialize() {
    }

    public function onChosen() as Void {
        EndWorkoutFlow.act();
    }
}
