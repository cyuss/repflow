import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! Shown immediately after a set is completed.
//!
//!     REST
//!     01:30
//!     Next
//!     Lat Pulldown · Set 2/4
//!     10 x 55 kg
//!
//! Buttons:
//!   START      skip rest and go straight back to the exercise
//!   UP / DOWN  add / remove 15 s
//!   BACK       workout overview — go do a different exercise instead
class RestView extends WatchUi.View {

    public function initialize() {
        View.initialize();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var controller = AppController.instance();
        var rest = controller.restTimer();
        var w = dc.getWidth();
        var h = dc.getHeight();

        _drawProgressArc(dc, rest);

        Theme.drawFitted(
            dc, (h * 0.13).toNumber(), WatchUi.loadResource(Rez.Strings.Rest) as String,
            [Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_DIM, (w * 0.9).toNumber()
        );

        Theme.drawFitted(
            dc, (h * 0.26).toNumber(), rest.format(),
            [Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_LARGE] as Array<Graphics.FontDefinition>,
            rest.isRunning() ? Theme.COLOR_TEXT : Theme.COLOR_DONE, (w * 0.75).toNumber()
        );

        _drawNextUp(dc, controller);
    }

    //! What comes next, so the athlete can plan while resting.
    private function _drawNextUp(dc as Graphics.Dc, controller as AppController) as Void {
        var engine = controller.engine();
        if (engine == null) {
            return;
        }
        var next = engine.suggestNextExercise();
        if (next == null) {
            return;
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var maxW = (w * 0.82).toNumber();

        Theme.drawFitted(
            dc, (h * 0.58).toNumber(), WatchUi.loadResource(Rez.Strings.NextLabel) as String,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_DIM, maxW
        );

        Theme.drawFitted(
            dc, (h * 0.66).toNumber(), next.name,
            [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_TEXT, maxW
        );

        var detail = (WatchUi.loadResource(Rez.Strings.SetLabel) as String) + " " +
            next.currentSetNumber().toString() + "/" + next.targetSets.toString() +
            "   " + next.plannedReps().toString() + " x " + Theme.formatWeight(next.plannedWeight()) +
            (WatchUi.loadResource(Rez.Strings.Kg) as String);
        Theme.drawFitted(
            dc, (h * 0.79).toNumber(), detail,
            [Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_ACCENT, maxW
        );
    }

    //! Thin arc that drains as the rest elapses — readable at a glance.
    private function _drawProgressArc(dc as Graphics.Dc, rest as RestTimer) as Void {
        if (rest.duration() <= 0) {
            return;
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var radius = (w < h ? w : h) / 2 - 4;
        var cx = w / 2;
        var cy = h / 2;
        var sweep = (360.0 * (1.0 - rest.progress())).toNumber();
        dc.setPenWidth(6);
        dc.setColor(Theme.COLOR_SKIPPED, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, radius);
        if (sweep > 0) {
            dc.setColor(Theme.COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 90, (90 - sweep + 360) % 360);
        }
        dc.setPenWidth(1);
    }
}

class RestDelegate extends WatchUi.BehaviorDelegate {

    public function initialize() {
        BehaviorDelegate.initialize();
    }

    //! START — rest is over, back to the exercise.
    public function onSelect() as Boolean {
        AppController.instance().endRest();
        return true;
    }

    public function onPreviousPage() as Boolean {
        AppController.instance().restTimer().extend(Tuning.REST_STEP);
        WatchUi.requestUpdate();
        return true;
    }

    public function onNextPage() as Boolean {
        AppController.instance().restTimer().extend(-Tuning.REST_STEP);
        WatchUi.requestUpdate();
        return true;
    }

    //! BACK — go pick a different exercise while resting. This is what makes
    //! supersets and "the machine is busy" work.
    public function onBack() as Boolean {
        var controller = AppController.instance();
        controller.stopTicker();
        controller.restTimer().skip();
        WatchUi.switchToView(new WorkoutOverviewView(), new WorkoutOverviewDelegate(), WatchUi.SLIDE_RIGHT);
        return true;
    }

    public function onMenu() as Boolean {
        var engine = AppController.instance().engine();
        if (engine == null) {
            return true;
        }
        var exercise = engine.currentExercise();
        if (exercise != null) {
            ExerciseActionsMenu.show(exercise);
        }
        return true;
    }
}
