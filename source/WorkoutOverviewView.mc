import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! The heart of "select any exercise at any time".
//!
//!     BACK + TRICEPS
//!     ✓ Lat Pulldown       4/4
//!     ! Seated Row         0/4
//!     ● Face Pull          2/4
//!     ○ Triceps Pushdown   0/4
//!
//! Built on WatchUi.Menu2 so scrolling, touch and button input all behave the
//! way the rest of the watch does, at no memory cost of our own.
class WorkoutOverviewView extends WatchUi.Menu2 {

    public function initialize() {
        var engine = AppController.instance().engine();
        var title = "Workout";
        if (engine != null) {
            title = engine.getWorkout().name;
        }
        Menu2.initialize({ :title => title });
        _populate(engine);
    }

    private function _populate(engine as WorkoutEngine?) as Void {
        if (engine == null) {
            return;
        }
        var list = engine.getWorkout().exercises;
        for (var i = 0; i < list.size(); i++) {
            var ex = list[i];
            var label = ExerciseStateUtil.glyph(ex.state) + " " + ex.name;
            var sub = ex.completedSetCount().toString() + "/" + ex.targetSets.toString() +
                "   " + Theme.formatWeight(ex.plannedWeight()) + (WatchUi.loadResource(Rez.Strings.Kg) as String);
            addItem(new WatchUi.MenuItem(label, sub, ex.id, {}));
        }
        // End the workout from the bottom of the list — no nested menu needed.
        addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.ActionEndWorkout) as String,
            null,
            ITEM_END_WORKOUT,
            {}
        ));
    }

    public static const ITEM_END_WORKOUT = "__end__";
}

class WorkoutOverviewDelegate extends WatchUi.Menu2InputDelegate {

    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        if (id.equals(WorkoutOverviewView.ITEM_END_WORKOUT)) {
            EndWorkoutFlow.request();
            return;
        }
        // Any exercise, any time — including completed and skipped ones.
        if (AppController.instance().selectExercise(id)) {
            WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_LEFT);
        }
    }

    //! BACK returns to training rather than dropping out of the workout: the
    //! selected exercise, else the next sensible one, else the end-of-workout
    //! flow. The overview is never a dead end.
    public function onBack() as Void {
        var controller = AppController.instance();
        var engine = controller.engine();
        if (engine == null) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return;
        }
        if (engine.currentExercise() != null) {
            WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_LEFT);
            return;
        }
        var next = engine.suggestNextExercise();
        if (next != null && controller.selectExercise(next.id)) {
            WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_LEFT);
            return;
        }
        EndWorkoutFlow.request();
    }
}
