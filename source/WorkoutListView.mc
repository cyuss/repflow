import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! First screen: pick a workout.
//!
//! One workout fills the screen at a time so it stays readable at arm's length.
//! UP/DOWN cycles, START begins, MENU edits.
//!
//! One page past the last workout is **New workout**, which is how an empty
//! session starts. It is a page rather than a menu entry because this screen is
//! a carousel, and a carousel that ends in "and one more thing you can do" is
//! how every Garmin activity picker already behaves.
class WorkoutListView extends WatchUi.View {

    private var _workouts as Array<Workout>;
    private var _index as Number;

    public function initialize() {
        View.initialize();
        _workouts = WorkoutRepository.all();
        _index = 0;
    }

    //! True when the cursor is on the "New workout" page rather than a workout.
    public function onNewPage() as Boolean {
        return _index >= _workouts.size();
    }

    public function selected() as Workout? {
        return onNewPage() ? null : _workouts[_index];
    }

    public function move(delta as Number) as Void {
        var n = _workouts.size() + 1;      // the carousel ends on New workout
        _index = (_index + delta + n) % n;
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var h = dc.getHeight();
        if (onNewPage()) {
            _drawNewPage(dc);
            Theme.drawPageDots(dc, _workouts.size() + 1, _index);
            return;
        }
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

        var afterName = Marquee.drawFitted(dc, blockTop, workout.name,
            Theme.fontsTitle(), Theme.COLOR_TEXT, Theme.usableWidth(dc, blockTop));
        Theme.drawFitted(dc, afterName + gap, countText,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.COLOR_DIM);

        Theme.drawPageDots(dc, _workouts.size() + 1, _index);
        Marquee.endFrame();
    }

    //! The last page: start from nothing and build as you go.
    private function _drawNewPage(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var actionTop = Theme.drawActionBar(dc, "START", Theme.COLOR_DONE);

        var y = h / 8;
        y = Theme.drawFitted(dc, y, WatchUi.loadResource(Rez.Strings.AppName) as String,
            Theme.fontsLabel(), Theme.COLOR_ACCENT);

        var label = WatchUi.loadResource(Rez.Strings.NewWorkout) as String;
        var labelFont = Theme.pickFont(dc, label, Theme.fontsTitle(),
            Theme.usableWidth(dc, h / 2));
        var labelHeight = dc.getFontHeight(labelFont);
        var signSize = h / 6;
        var gap = h / 22;
        var block = signSize + gap + labelHeight;
        var top = y + ((actionTop - y) - block) / 2;
        if (top < y) {
            top = y;
        }

        Theme.drawSign(dc, dc.getWidth() / 2, top + signSize / 2, signSize, true,
            Theme.COLOR_DONE);
        Theme.drawFitted(dc, top + signSize + gap, label,
            Theme.fontsTitle(), Theme.COLOR_TEXT);
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

    //! MENU edits. A built-in is a starting point, so editing one opens a copy
    //! the athlete owns rather than changing what ships with the app.
    public function onMenu() as Boolean {
        if (_view.onNewPage()) {
            WorkoutEditor.createNew();
            return true;
        }
        var workout = _view.selected() as Workout;
        if (WorkoutRepository.isCustom(workout.id)) {
            WorkoutEditor.edit(workout);
        } else {
            WorkoutEditor.edit(_copyOf(workout));
        }
        return true;
    }

    //! A fresh workout with the built-in's contents and an id of its own.
    private function _copyOf(workout as Workout) as Workout {
        var raw = workout.toStorage();
        var copy = Workout.fromStorage(raw);
        copy.id = WorkoutRepository.newCustomId(AppController.now());
        return copy;
    }

    //! START — begin the highlighted workout on its first exercise, or open the
    //! editor when the cursor is on the New workout page.
    public function onSelect() as Boolean {
        if (_view.onNewPage()) {
            WorkoutEditor.createNew();
            return true;
        }
        var controller = AppController.instance();
        var workout = _view.selected() as Workout;
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
