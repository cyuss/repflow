import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! Full-screen single-number editor: one huge number, UP/DOWN to change,
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
        var h = dc.getHeight();
        var gap = h / 30;
        var isWeight = _mode == ValueEditor.MODE_WEIGHT;

        var actionTop = Theme.drawActionBar(dc, "START = OK", Theme.COLOR_ACCENT);

        var y = h / 8;
        y = Theme.drawFitted(dc, y, _exercise.name, Theme.fontsLabel(), Theme.COLOR_DIM);
        y += gap;

        var title = isWeight
            ? WatchUi.loadResource(Rez.Strings.ActionEditWeight) as String
            : WatchUi.loadResource(Rez.Strings.ActionEditReps) as String;
        y = Theme.drawFitted(dc, y, title, Theme.fontsLabel(), Theme.COLOR_TEXT);

        var value = isWeight
            ? Theme.formatWeight(controller.pendingWeight())
            : controller.pendingReps().toString();
        var unit = isWeight
            ? WatchUi.loadResource(Rez.Strings.Kg) as String
            : WatchUi.loadResource(Rez.Strings.Reps) as String;

        // Centre the number in the room between the header and the action bar.
        var font = Theme.pickFont(dc, value, Theme.fontsHero(), Theme.usableWidth(dc, h / 2));
        var valueHeight = dc.getFontHeight(font);
        var top = y + ((actionTop - y) - valueHeight) / 2;
        if (top < y + gap) {
            top = y + gap;
        }
        Theme.drawValueWithUnit(dc, top, value, unit, Theme.fontsHero(),
            Theme.COLOR_ACCENT, Theme.COLOR_DIM);

        // The step size, so the athlete knows what a press is worth.
        var step = isWeight
            ? "+/- " + Theme.formatWeight(Tuning.WEIGHT_STEP)
            : "+/- 1";
        Theme.drawFitted(dc, actionTop - dc.getFontHeight(Graphics.FONT_XTINY) - gap, step,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.COLOR_SKIPPED);
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
        return _done();
    }

    //! BACK also accepts the value — there is nothing destructive to cancel,
    //! and an accidental press should not throw the athlete out of the workout.
    public function onBack() as Boolean {
        return _done();
    }

    private function _done() as Boolean {
        AppController.instance().persistNow();
        WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_RIGHT);
        return true;
    }
}
