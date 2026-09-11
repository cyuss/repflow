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
        var w = dc.getWidth();
        var h = dc.getHeight();
        var workout = _workouts[_index];

        Theme.drawFitted(
            dc, (h * 0.14).toNumber(), WatchUi.loadResource(Rez.Strings.ChooseWorkout) as String,
            [Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_DIM, (w * 0.9).toNumber()
        );

        Theme.drawFitted(
            dc, (h * 0.34).toNumber(), workout.name,
            [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_TEXT, (w * 0.88).toNumber()
        );

        Theme.drawFitted(
            dc, (h * 0.55).toNumber(), workout.exercises.size().toString() + " exercises",
            [Graphics.FONT_SMALL, Graphics.FONT_TINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_ACCENT, (w * 0.9).toNumber()
        );

        _drawDots(dc, (h * 0.78).toNumber());

        Theme.drawFitted(
            dc, (h * 0.85).toNumber(), "START",
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_DIM, (w * 0.9).toNumber()
        );
    }

    //! Position indicator — one dot per available workout.
    private function _drawDots(dc as Graphics.Dc, y as Number) as Void {
        var n = _workouts.size();
        var spacing = 14;
        var startX = dc.getWidth() / 2 - ((n - 1) * spacing) / 2;
        for (var i = 0; i < n; i++) {
            dc.setColor(i == _index ? Theme.COLOR_ACCENT : Theme.COLOR_SKIPPED, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(startX + i * spacing, y, i == _index ? 4 : 3);
        }
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
            WatchUi.switchToView(new WorkoutOverviewView(), new WorkoutOverviewDelegate(), WatchUi.SLIDE_LEFT);
        }
        return true;
    }
}
