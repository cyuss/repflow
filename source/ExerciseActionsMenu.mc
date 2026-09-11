import Toybox.Lang;
import Toybox.WatchUi;

//! Short, flat action menu for the selected exercise (MENU / long press).
//!
//! Deliberately shallow: every entry performs its action immediately, there are
//! no sub-menus, and the list stays short enough to read mid-set.
module ExerciseActionsMenu {

    const ACTION_EDIT_REPS = "reps";
    const ACTION_EDIT_WEIGHT = "weight";
    const ACTION_SKIP_FOR_NOW = "defer";
    const ACTION_OVERVIEW = "overview";
    const ACTION_MARK_DONE = "done";
    const ACTION_UNDO_SET = "undo";
    const ACTION_END = "end";

    public function show(exercise as Exercise) as Void {
        var menu = new WatchUi.Menu2({ :title => exercise.name });
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.ActionEditReps) as String, null, ACTION_EDIT_REPS, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.ActionEditWeight) as String, null, ACTION_EDIT_WEIGHT, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.ActionSkipForNow) as String, null, ACTION_SKIP_FOR_NOW, {}));
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
        var engine = controller.engine();
        var id = item.getId() as String;

        if (id.equals(ExerciseActionsMenu.ACTION_EDIT_REPS)) {
            ValueEditor.editReps(_exercise);
            return;
        }
        if (id.equals(ExerciseActionsMenu.ACTION_EDIT_WEIGHT)) {
            ValueEditor.editWeight(_exercise);
            return;
        }
        if (id.equals(ExerciseActionsMenu.ACTION_SKIP_FOR_NOW)) {
            // PENDING — resumable, never counted as completed or abandoned.
            if (engine != null) {
                engine.deferExercise(_exercise.id);
                SessionRepository.saveActive(engine.getSession());
            }
            _showOverview();
            return;
        }
        if (id.equals(ExerciseActionsMenu.ACTION_OVERVIEW)) {
            _showOverview();
            return;
        }
        if (id.equals(ExerciseActionsMenu.ACTION_MARK_DONE)) {
            if (engine != null) {
                engine.forceCompleteExercise(_exercise.id);
                SessionRepository.saveActive(engine.getSession());
            }
            _showOverview();
            return;
        }
        if (id.equals(ExerciseActionsMenu.ACTION_UNDO_SET)) {
            if (engine != null) {
                engine.undoLastSet();
                controller.syncPendingValues(_exercise);
                SessionRepository.saveActive(engine.getSession());
            }
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
