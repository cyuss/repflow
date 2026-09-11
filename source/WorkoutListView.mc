import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! First screen: pick a workout.
//!
//! One workout fills the screen at a time so it stays readable at arm's length.
//! UP/DOWN cycles, START begins.
class WorkoutListView extends WatchUi.View {

    private var _workouts as Array<Workout>;
    private var _index as Number;

    public function initialize() {
        View.initialize();
        _workouts = WorkoutRepository.all();
        _index = 0;
    }

    public function selected() as Workout {
        return _workouts[_index];
    }

    public function move(delta as Number) as Void {
        var n = _workouts.size();
        _index = (_index + delta + n) % n;
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var h = dc.getHeight();
        var workout = _workouts[_index];
        var gap = h / 30;

        var actionTop = Theme.drawActionBar(dc, "START", Theme.COLOR_ACCENT);

        var y = h / 8;
        y = Theme.drawFitted(dc, y, WatchUi.loadResource(Rez.Strings.AppName) as String,
            Theme.fontsLabel(), Theme.COLOR_ACCENT);
        y += gap;
        y = Theme.drawFitted(dc, y, WatchUi.loadResource(Rez.Strings.ChooseWorkout) as String,
            Theme.fontsLabel(), Theme.COLOR_DIM);

        // Centre the workout name in the space between the header and the
        // action bar, rather than pinning it to a fixed fraction of the screen.
        var nameFont = Theme.pickFont(dc, workout.name, Theme.fontsTitle(),
            Theme.usableWidth(dc, h / 2));
        var nameHeight = dc.getFontHeight(nameFont);
        var countText = workout.exercises.size().toString() + " exercises";
        var countHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var blockHeight = nameHeight + gap + countHeight;
        var blockTop = y + ((actionTop - y) - blockHeight) / 2;
        if (blockTop < y) {
            blockTop = y;
        }

        var afterName = Theme.drawFitted(dc, blockTop, workout.name,
            Theme.fontsTitle(), Theme.COLOR_TEXT);
        Theme.drawFitted(dc, afterName + gap, countText,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.COLOR_DIM);

        Theme.drawPageDots(dc, _workouts.size(), _index);
    }
}

class WorkoutListDelegate extends WatchUi.BehaviorDelegate {

    private var _view as WorkoutListView;

    public function initialize(view as WorkoutListView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onNextPage() as Boolean {
        _view.move(1);
        return true;
    }

    public function onPreviousPage() as Boolean {
        _view.move(-1);
        return true;
    }

    //! START — begin the highlighted workout on its first exercise.
    public function onSelect() as Boolean {
        var controller = AppController.instance();
        var workout = _view.selected();
        controller.startWorkout(workout);
        if (workout.exercises.size() > 0) {
            controller.selectExercise(workout.exercises[0].id);
            WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_LEFT);
        } else {
            WatchUi.switchToView(new WorkoutOverviewView(), new WorkoutOverviewDelegate(),
                WatchUi.SLIDE_LEFT);
        }
        return true;
    }
}
