import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! Edit the weight and the reps of the upcoming set, on one screen.
//!
//!          NEXT SET
//!      ┌────────┐ ┌──────┐
//!      │  60    │ │  10  │
//!      │  KG    │ │ REPS │
//!      └────────┘ └──────┘
//!        + / - 2.5
//!        START = REPS
//!
//! The focused cell is outlined in the accent colour; UP/DOWN change it, START
//! moves on and confirms on the last one, BACK steps back. That is exactly the
//! interaction model of `WatchUi.Picker`, which is what a Garmin owner expects.
//!
//! It is *not* built on Picker, though, and that is deliberate: a three-column
//! Picker does not fit a 260x260 screen — the reps column rendered off the right
//! edge — and its own theming painted the background white over ours. Verified
//! in the simulator. Drawing it here costs one small view and renders correctly
//! on every target.
class SetEditorView extends WatchUi.View {

    private var _exercise as Exercise;
    private var _focus as Number;
    private var _returnTo as Number;
    private var _mode as Number;

    public function initialize(exercise as Exercise, returnTo as Number, mode as Number) {
        View.initialize();
        _exercise = exercise;
        _returnTo = returnTo;
        _mode = mode;
        // Confirming a set starts on the reps: the load is usually what was
        // planned, the reps are what actually came out.
        _focus = mode == Tuning.EDITOR_CONFIRM_LOG
            ? Tuning.FOCUS_REPS
            : Tuning.FOCUS_WEIGHT;
    }

    public function mode() as Number {
        return _mode;
    }

    public function returnTo() as Number {
        return _returnTo;
    }

    public function focus() as Number {
        return _focus;
    }

    public function exercise() as Exercise {
        return _exercise;
    }

    public function setFocus(focus as Number) as Void {
        _focus = focus;
        WatchUi.requestUpdate();
    }

    //! Nudge whichever value is focused.
    public function adjust(direction as Number) as Void {
        var controller = AppController.instance();
        if (_focus == Tuning.FOCUS_REPS) {
            controller.adjustReps(direction);
        } else {
            controller.adjustWeight(direction);
        }
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var controller = AppController.instance();
        var h = dc.getHeight();
        var confirming = _mode == Tuning.EDITOR_CONFIRM_LOG;

        var y = Theme.drawFitted(dc, h / 14, _exercise.name,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.COLOR_DIM);

        var title = confirming
            ? (WatchUi.loadResource(Rez.Strings.SetLabel) as String).toUpper() + " " +
                _exercise.currentSetNumber().toString() + " / " +
                _exercise.targetSets.toString()
            : WatchUi.loadResource(Rez.Strings.NextSet) as String;
        y = Theme.drawFitted(dc, y + h / 90, title,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.COLOR_ACCENT);

        var bottom = h;
        if (confirming) {
            // One press logs it; the pill says so.
            bottom = Theme.drawActionBar(
                dc, WatchUi.loadResource(Rez.Strings.LogSet) as String, Theme.COLOR_DONE);
            bottom -= h / 50;
        }

        var hintFont = Graphics.FONT_XTINY;
        var hintHeight = dc.getFontHeight(hintFont);
        var hintTop = confirming
            ? bottom - hintHeight - h / 60
            : h - hintHeight * 2 - h / 10;

        _drawCells(dc, y + h / 40, hintTop - h / 50, controller);

        var step = _focus == Tuning.FOCUS_REPS
            ? "- 1 +"
            : "- " + Theme.formatWeight(Tuning.WEIGHT_STEP) + " +";

        if (confirming) {
            // BACK swaps the field being edited here, because START is spent on
            // logging — that is what keeps a set to a single press when nothing
            // needs changing.
            Theme.drawFitted(dc, hintTop,
                step + "   " + (WatchUi.loadResource(Rez.Strings.HintSwap) as String),
                [hintFont] as Array<Graphics.FontDefinition>, Theme.COLOR_DIM);
            return;
        }

        var next = _focus == Tuning.FOCUS_REPS
            ? WatchUi.loadResource(Rez.Strings.HintConfirm) as String
            : WatchUi.loadResource(Rez.Strings.HintNextReps) as String;
        var hintY = Theme.drawFitted(dc, hintTop, step,
            [hintFont] as Array<Graphics.FontDefinition>, Theme.COLOR_TEXT);
        Theme.drawFitted(dc, hintY, next,
            [hintFont] as Array<Graphics.FontDefinition>, Theme.COLOR_DIM);
    }

    //! The two values, side by side, the focused one outlined.
    private function _drawCells(
        dc as Graphics.Dc,
        top as Number,
        bottom as Number,
        controller as AppController
    ) as Void {
        var height = bottom - top;
        if (height <= 0) {
            return;
        }
        var width = Theme.bandWidth(dc, top, height);
        var left = (dc.getWidth() - width) / 2;
        var half = width / 2;

        _drawCell(dc, left, top, half, height,
            Theme.formatWeight(controller.pendingWeight()),
            (WatchUi.loadResource(Rez.Strings.Kg) as String).toUpper(),
            _focus == Tuning.FOCUS_WEIGHT);

        _drawCell(dc, left + half, top, half, height,
            controller.pendingReps().toString(),
            WatchUi.loadResource(Rez.Strings.FieldReps) as String,
            _focus == Tuning.FOCUS_REPS);
    }

    private function _drawCell(
        dc as Graphics.Dc,
        x as Number,
        y as Number,
        width as Number,
        height as Number,
        value as String,
        caption as String,
        focused as Boolean
    ) as Void {
        var inset = width / 14;
        var pad = height / 12;
        if (focused) {
            // An outline rather than a fill: it keeps the number at full
            // contrast, which matters on the Fenix 6's 8-bit display. The
            // content is inset inside it so the caption does not sit on the line.
            dc.setPenWidth(3);
            dc.setColor(Theme.COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(x + inset, y, width - inset * 2, height, height / 4);
            dc.setPenWidth(1);
        }
        FieldGrid.drawCell(dc, x, y + pad, width, height - pad * 2, value, caption,
            focused ? Theme.COLOR_TEXT : Theme.COLOR_DIM);
    }
}

class SetEditorDelegate extends WatchUi.BehaviorDelegate {

    private var _view as SetEditorView;

    public function initialize(view as SetEditorView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onPreviousPage() as Boolean {
        _view.adjust(1);
        return true;
    }

    public function onNextPage() as Boolean {
        _view.adjust(-1);
        return true;
    }

    //! START advances to the reps, then confirms.
    public function onSelect() as Boolean {
        if (_view.focus() == Tuning.FOCUS_WEIGHT) {
            _view.setFocus(Tuning.FOCUS_REPS);
            return true;
        }
        _leave();
        return true;
    }

    //! BACK steps back to the weight, then leaves. Nothing here is destructive,
    //! so leaving keeps whatever was dialled in.
    public function onBack() as Boolean {
        if (_view.focus() == Tuning.FOCUS_REPS) {
            _view.setFocus(Tuning.FOCUS_WEIGHT);
            return true;
        }
        _leave();
        return true;
    }

    //! Go where the opener said, not to whatever happens to be underneath.
    //!
    //! Popping was wrong: the editor is reached from the actions menu, which is
    //! itself a screen, so popping landed back on the menu and START re-opened
    //! the editor in a loop.
    private function _leave() as Void {
        AppController.instance().persistNow();
        if (_view.returnTo() == Tuning.RETURN_REST) {
            WatchUi.switchToView(new RestView(), new RestDelegate(), WatchUi.SLIDE_DOWN);
        } else {
            WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_DOWN);
        }
    }
}

//! Open the editor for the set the athlete is about to perform.
//!
//! `returnTo` says where to go on the way out — see Tuning.RETURN_*.
module SetEditor {
    //! Dial in the set that is about to be performed.
    public function open(exercise as Exercise, returnTo as Number) as Void {
        var view = new SetEditorView(exercise, returnTo, Tuning.EDITOR_EDIT_NEXT);
        WatchUi.switchToView(view, new SetEditorDelegate(view), WatchUi.SLIDE_UP);
    }

    //! Confirm the set that was just performed, then log it.
    public function confirm(exercise as Exercise) as Void {
        var view = new SetEditorView(exercise, Tuning.RETURN_EXERCISE,
            Tuning.EDITOR_CONFIRM_LOG);
        WatchUi.switchToView(view, new SetConfirmDelegate(view), WatchUi.SLIDE_UP);
    }
}

//! The set has been performed; these buttons decide what gets recorded.
//!
//!   START      log it and start the rest — one press, nothing to change
//!   UP / DOWN  adjust the highlighted value
//!   BACK       swap between reps and weight
//!   MENU       abandon the set without logging it
class SetConfirmDelegate extends WatchUi.BehaviorDelegate {

    private var _view as SetEditorView;

    public function initialize(view as SetEditorView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onPreviousPage() as Boolean {
        _view.adjust(1);
        return true;
    }

    public function onNextPage() as Boolean {
        _view.adjust(-1);
        return true;
    }

    public function onSelect() as Boolean {
        AppController.instance().completeSet();
        return true;
    }

    public function onBack() as Boolean {
        _view.setFocus(_view.focus() == Tuning.FOCUS_REPS
            ? Tuning.FOCUS_WEIGHT
            : Tuning.FOCUS_REPS);
        return true;
    }

    //! Abandon: the set is not recorded, and the planned values are restored.
    public function onMenu() as Boolean {
        var controller = AppController.instance();
        controller.syncPendingValues(_view.exercise());
        WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_DOWN);
        return true;
    }
}
