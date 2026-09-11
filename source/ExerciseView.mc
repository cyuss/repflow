import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.System;

//! The screen the athlete spends the workout on.
//!
//!     Lat Pulldown
//!     Set 2 / 4
//!        55 kg
//!      10 reps
//!     COMPLETE SET
//!
//! Buttons:
//!   START      complete the set (one press — the common case)
//!   UP / DOWN  weight +/- 2.5 kg
//!   BACK       workout overview (pick any exercise)
//!   MENU       exercise actions (edit reps, skip for now, end workout, ...)
class ExerciseView extends WatchUi.View {

    public function initialize() {
        View.initialize();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var engine = AppController.instance().engine();
        var exercise = engine != null ? engine.currentExercise() : null;
        if (exercise == null) {
            _drawNoExercise(dc);
            return;
        }
        _drawExercise(dc, exercise);
    }

    private function _drawNoExercise(dc as Graphics.Dc) as Void {
        Theme.drawFitted(
            dc, (dc.getHeight() * 0.45).toNumber(), "No exercise selected",
            [Graphics.FONT_SMALL, Graphics.FONT_TINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_DIM, (dc.getWidth() * 0.9).toNumber()
        );
    }

    private function _drawExercise(dc as Graphics.Dc, exercise as Exercise) as Void {
        var controller = AppController.instance();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var maxW = (w * 0.86).toNumber();

        // Exercise name
        Theme.drawFitted(
            dc, (h * 0.10).toNumber(), exercise.name,
            [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_TEXT, maxW
        );

        // Set X / Y
        var setLine = (WatchUi.loadResource(Rez.Strings.SetLabel) as String) + " " +
            exercise.currentSetNumber().toString() + " / " + exercise.targetSets.toString();
        Theme.drawFitted(
            dc, (h * 0.26).toNumber(), setLine,
            [Graphics.FONT_SMALL, Graphics.FONT_TINY] as Array<Graphics.FontDefinition>,
            Theme.stateColor(exercise.state), maxW
        );

        // The two editable numbers, side by side and dominant.
        _drawValues(dc, controller);

        // Dominant action
        Theme.drawFitted(
            dc, (h * 0.80).toNumber(), WatchUi.loadResource(Rez.Strings.CompleteSet) as String,
            [Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_ACCENT, maxW
        );

        _drawSetDots(dc, exercise, (h * 0.92).toNumber());
    }

    //! Weight is the value UP/DOWN edits, so it is drawn larger and in accent.
    private function _drawValues(dc as Graphics.Dc, controller as AppController) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var y = (h * 0.40).toNumber();

        var weightText = Theme.formatWeight(controller.pendingWeight());
        var bigFonts = [Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_LARGE] as Array<Graphics.FontDefinition>;
        var fh = Theme.drawFitted(dc, y, weightText, bigFonts, Theme.COLOR_TEXT, (w * 0.7).toNumber());

        Theme.drawFitted(
            dc, y + fh - (h * 0.02).toNumber(), WatchUi.loadResource(Rez.Strings.Kg) as String,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_DIM, w
        );

        var repsText = controller.pendingReps().toString() + " " +
            (WatchUi.loadResource(Rez.Strings.Reps) as String);
        Theme.drawFitted(
            dc, (h * 0.655).toNumber(), repsText,
            [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_DIM, (w * 0.8).toNumber()
        );
    }

    //! One dot per target set, filled once performed. Glanceable progress.
    private function _drawSetDots(dc as Graphics.Dc, exercise as Exercise, y as Number) as Void {
        var total = exercise.targetSets;
        if (total <= 0 || total > 10) {
            return;
        }
        var done = exercise.completedSetCount();
        var spacing = 12;
        var startX = dc.getWidth() / 2 - ((total - 1) * spacing) / 2;
        for (var i = 0; i < total; i++) {
            if (i < done) {
                dc.setColor(Theme.COLOR_DONE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(startX + i * spacing, y, 4);
            } else {
                dc.setColor(Theme.COLOR_SKIPPED, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(startX + i * spacing, y, 4);
            }
        }
    }
}

class ExerciseDelegate extends WatchUi.BehaviorDelegate {

    public function initialize() {
        BehaviorDelegate.initialize();
    }

    //! START — one press completes the set. This is the hot path.
    public function onSelect() as Boolean {
        AppController.instance().completeSet();
        return true;
    }

    public function onPreviousPage() as Boolean {
        AppController.instance().adjustWeight(1);
        WatchUi.requestUpdate();
        return true;
    }

    public function onNextPage() as Boolean {
        AppController.instance().adjustWeight(-1);
        WatchUi.requestUpdate();
        return true;
    }

    //! BACK — workout overview is always one press away.
    public function onBack() as Boolean {
        WatchUi.switchToView(new WorkoutOverviewView(), new WorkoutOverviewDelegate(), WatchUi.SLIDE_RIGHT);
        return true;
    }

    public function onMenu() as Boolean {
        var engine = AppController.instance().engine();
        if (engine == null) {
            return true;
        }
        var exercise = engine.currentExercise();
        if (exercise == null) {
            return true;
        }
        ExerciseActionsMenu.show(exercise);
        return true;
    }

    //! Touch devices: tapping the lower half opens the reps editor. Optional —
    //! every action here is reachable with buttons alone.
    public function onTap(event as WatchUi.ClickEvent) as Boolean {
        var coords = event.getCoordinates();
        var controller = AppController.instance();
        var engine = controller.engine();
        if (engine == null) {
            return false;
        }
        var exercise = engine.currentExercise();
        if (exercise == null) {
            return false;
        }
        var screenHeight = System.getDeviceSettings().screenHeight;
        if (coords[1] > screenHeight * 0.58) {
            ValueEditor.editReps(exercise);
            return true;
        }
        return false;
    }
}
