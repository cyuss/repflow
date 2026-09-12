import Toybox.Lang;
import Toybox.WatchUi;

//! Short, flat action menu for the selected exercise (MENU / long press).
//!
//! Deliberately shallow: every entry performs its action immediately, there are
//! no sub-menus, and the list stays short enough to read mid-set.
module ExerciseActionsMenu {

    const ACTION_EDIT_SET = "set";
    const ACTION_LAST = "last";
    const ACTION_SKIP_FOR_NOW = "defer";
    const ACTION_OVERVIEW = "overview";
    const ACTION_MARK_DONE = "done";
    const ACTION_ADD_SET = "addset";
    const ACTION_SUBSTITUTE = "sub";
    const ACTION_UNDO_SET = "undo";
    const ACTION_END = "end";

    //! "60 x 10 x 4" — what this movement was last done for.
    //!
    //! It is the number an athlete actually wants before deciding a load, and
    //! until now the app could not answer it. Absent for a movement never
    //! performed, rather than shown as zeroes.
    public function lastLine(exerciseId as String) as String? {
        var last = AppController.instance().lastPerformance(exerciseId);
        if (last == null) {
            return null;
        }
        return (WatchUi.loadResource(Rez.Strings.LastTime) as String) + "  " +
            Theme.formatWeight(last[0] as Float) + " " + Units.label() + " x " +
            (last[1] as Number).toString() + " x " + (last[2] as Number).toString();
    }

    public function show(exercise as Exercise) as Void {
        var menu = new WatchUi.Menu2({ :title => exercise.name });
        var last = lastLine(exercise.id);
        if (last != null) {
            menu.addItem(new WatchUi.MenuItem(last, null, ACTION_LAST, {}));
        }
        // Editing the set is the reason this menu is opened most often, so it
        // sits under the cursor the moment it appears.
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.EditSet) as String,
            exercise.plannedReps().toString() + " x " +
                Theme.formatPlannedWeight(exercise.plannedWeight()) + " " +
                Units.label(),
            ACTION_EDIT_SET, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.ActionSkipForNow) as String, null, ACTION_SKIP_FOR_NOW, {}));
        // The machine is taken for good, not just for now.
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.Substitute) as String, null, ACTION_SUBSTITUTE, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.AddSet) as String,
            (exercise.targetSets + 1).toString() + " x", ACTION_ADD_SET, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.ActionOverview) as String, null, ACTION_OVERVIEW, {}));
        if (exercise.completedSetCount() > 0) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.ActionMarkDone) as String, null, ACTION_MARK_DONE, {}));
            menu.addItem(new WatchUi.MenuItem("Undo last set", null, ACTION_UNDO_SET, {}));
        }
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.ActionEndWorkout) as String, null, ACTION_END, {}));
        WatchUi.switchToView(menu, new ExerciseActionsDelegate(exercise), WatchUi.SLIDE_UP);
    }
}

class ExerciseActionsDelegate extends WatchUi.Menu2InputDelegate {

    private var _exercise as Exercise;

    public function initialize(exercise as Exercise) {
        Menu2InputDelegate.initialize();
        _exercise = exercise;
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var controller = AppController.instance();
        var id = item.getId() as String;

        if (id.equals(ExerciseActionsMenu.ACTION_LAST)) {
            // It is a readout, not a control. Selecting it goes back to work.
            _backToExercise();
            return;
        }
        if (id.equals(ExerciseActionsMenu.ACTION_EDIT_SET)) {
            SetEditor.open(_exercise, Tuning.RETURN_EXERCISE);
            return;
        }
        if (id.equals(ExerciseActionsMenu.ACTION_SKIP_FOR_NOW)) {
            // PENDING — resumable, never counted as completed or abandoned.
            controller.deferExercise(_exercise.id);
            _showOverview();
            return;
        }
        if (id.equals(ExerciseActionsMenu.ACTION_SUBSTITUTE)) {
            ExercisePicker.open(ExercisePicker.FOR_SUBSTITUTE, _exercise.id);
            return;
        }
        if (id.equals(ExerciseActionsMenu.ACTION_ADD_SET)) {
            controller.addSet(_exercise.id);
            _backToExercise();
            return;
        }
        if (id.equals(ExerciseActionsMenu.ACTION_OVERVIEW)) {
            _showOverview();
            return;
        }
        if (id.equals(ExerciseActionsMenu.ACTION_MARK_DONE)) {
            controller.forceCompleteExercise(_exercise.id);
            _showOverview();
            return;
        }
        if (id.equals(ExerciseActionsMenu.ACTION_UNDO_SET)) {
            controller.undoLastSet();
            _backToExercise();
            return;
        }
        if (id.equals(ExerciseActionsMenu.ACTION_END)) {
            EndWorkoutFlow.request();
            return;
        }
    }

    public function onBack() as Void {
        _backToExercise();
    }

    private function _backToExercise() as Void {
        WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_DOWN);
    }

    private function _showOverview() as Void {
        WatchUi.switchToView(new WorkoutOverviewView(), new WorkoutOverviewDelegate(), WatchUi.SLIDE_LEFT);
    }
}
