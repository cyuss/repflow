import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! Full-screen single-number editor: one huge digit group, UP/DOWN to change,
//! START to confirm. No keyboard, no picker wheel, no tiny targets.
module ValueEditor {
    const MODE_REPS = 0;
    const MODE_WEIGHT = 1;

    public function editReps(exercise as Exercise) as Void {
        var view = new ValueEditorView(MODE_REPS, exercise);
        WatchUi.switchToView(view, new ValueEditorDelegate(view), WatchUi.SLIDE_LEFT);
    }

    public function editWeight(exercise as Exercise) as Void {
        var view = new ValueEditorView(MODE_WEIGHT, exercise);
        WatchUi.switchToView(view, new ValueEditorDelegate(view), WatchUi.SLIDE_LEFT);
    }
}

class ValueEditorView extends WatchUi.View {

    private var _mode as Number;
    private var _exercise as Exercise;

    public function initialize(mode as Number, exercise as Exercise) {
        View.initialize();
        _mode = mode;
        _exercise = exercise;
    }

    public function mode() as Number {
        return _mode;
    }

    public function exercise() as Exercise {
        return _exercise;
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var controller = AppController.instance();
        var w = dc.getWidth();
        var h = dc.getHeight();

        var title = _mode == ValueEditor.MODE_REPS
            ? WatchUi.loadResource(Rez.Strings.Reps) as String
            : WatchUi.loadResource(Rez.Strings.Kg) as String;
        Theme.drawFitted(
            dc, (h * 0.16).toNumber(), title,
            [Graphics.FONT_SMALL, Graphics.FONT_TINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_DIM, (w * 0.9).toNumber()
        );

        var value = _mode == ValueEditor.MODE_REPS
            ? controller.pendingReps().toString()
            : Theme.formatWeight(controller.pendingWeight());
        Theme.drawFitted(
            dc, (h * 0.36).toNumber(), value,
            [Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM] as Array<Graphics.FontDefinition>,
            Theme.COLOR_ACCENT, (w * 0.8).toNumber()
        );

        Theme.drawFitted(
            dc, (h * 0.84).toNumber(), "START = OK",
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_DIM, (w * 0.9).toNumber()
        );
    }
}

class ValueEditorDelegate extends WatchUi.BehaviorDelegate {

    private var _view as ValueEditorView;

    public function initialize(view as ValueEditorView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onPreviousPage() as Boolean {
        _adjust(1);
        return true;
    }

    public function onNextPage() as Boolean {
        _adjust(-1);
        return true;
    }

    private function _adjust(direction as Number) as Void {
        var controller = AppController.instance();
        if (_view.mode() == ValueEditor.MODE_REPS) {
            controller.adjustReps(direction);
        } else {
            controller.adjustWeight(direction);
        }
        WatchUi.requestUpdate();
    }

    //! Confirm and go straight back to training.
    public function onSelect() as Boolean {
        WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_RIGHT);
        return true;
    }

    //! BACK also accepts the value — there is nothing destructive to cancel,
    //! and an accidental press should not throw the athlete out of the workout.
    public function onBack() as Boolean {
        WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_RIGHT);
        return true;
    }
}
