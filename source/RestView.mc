import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! Shown immediately after a set is completed.
//!
//!   +---------------------+
//!   |        REST         |   <- draining arc around the rim
//!   |       01:30         |
//!   +----------+----------+
//!   |   132    |   -18    |
//!   |    HR    |   REC    |   beats below this rest's peak
//!   +----------+----------+
//!   | Lat Pulldown  3/4   |   what is next, so you can plan
//!   | 10 x 55 KG          |
//!   | LAST 52 KG x 10 x 4 |   only before the first set of it
//!   +---------------------+
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
        var h = dc.getHeight();

        _drawProgressArc(dc, rest);

        // The countdown is the hero: it owns the top third outright.
        var y = h / 9;
        y = Theme.drawFitted(dc, y, WatchUi.loadResource(Rez.Strings.Rest) as String,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.COLOR_DIM);

        var countdownTop = y + h / 60;
        var countdownHeight = (h * 26) / 100;
        var timerFont = Theme.pickFontFitting(dc, rest.format(), Theme.fontsHero(),
            (Theme.usableWidth(dc, countdownTop + countdownHeight / 2) * 80) / 100,
            countdownHeight);
        dc.setColor(rest.isRunning() ? Theme.COLOR_TEXT : Theme.COLOR_DONE,
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, countdownTop, timerFont, rest.format(),
            Graphics.TEXT_JUSTIFY_CENTER);

        var top = countdownTop + dc.getFontHeight(timerFont) + h / 60;
        FieldGrid.drawRule(dc, top);
        top += 1;

        _drawFields(dc, top, controller);
    }

    //! A field band, then what is coming next.
    private function _drawFields(
        dc as Graphics.Dc,
        top as Number,
        controller as AppController
    ) as Void {
        var h = dc.getHeight();
        var engine = controller.engine();
        var next = engine != null ? engine.suggestNextExercise() : null;

        // What was done on this movement last time, but only before the first
        // set of it: once there is a set in this session, the planned load is
        // already the athlete's own and the older number is just noise.
        var lastLine = null as String?;
        if (next != null && next.completedSetCount() == 0) {
            lastLine = ExerciseActionsMenu.lastLine(next.id);
        }

        // Reserve the bottom for "next up" only when there is one.
        var bottom = h - h / 14;
        var nextHeight = 0;
        if (next != null) {
            nextHeight = lastLine != null ? (h * 30) / 100 : (h * 22) / 100;
        }
        var fieldBottom = bottom - nextHeight;

        var hr = LiveMetrics.heartRate();

        // Beats below this rest's peak. It replaces a set count that the block
        // underneath already carries, and unlike that count it changes while
        // you watch it — which is the only reason to look at a rest screen.
        var drop = controller.recovery().drop();
        var dropText = drop == null ? LiveMetrics.NO_VALUE : "-" + drop.toString();
        var dropColor = Theme.COLOR_SKIPPED;
        if (drop != null) {
            dropColor = drop >= 12 ? Theme.COLOR_DONE : Theme.COLOR_WARM;
        }

        FieldGrid.drawPair(dc, top, fieldBottom - top,
            LiveMetrics.format(hr),
            WatchUi.loadResource(Rez.Strings.FieldHr) as String,
            hr != null ? Theme.COLOR_HR : Theme.COLOR_SKIPPED,
            dropText,
            WatchUi.loadResource(Rez.Strings.FieldRecovery) as String,
            dropColor);

        if (next == null) {
            return;
        }

        FieldGrid.drawRule(dc, fieldBottom);
        var y = fieldBottom + h / 44;
        y = Theme.drawFitted(dc, y, next.name, Theme.fontsBody(), Theme.COLOR_TEXT);

        var detail = (next.completedSetCount() + 1).toString() + "/" +
            next.targetSets.toString() + "   " +
            next.plannedReps().toString() + " x " +
            Theme.formatWeight(next.plannedWeight()) + " " +
            Units.label();
        y = Theme.drawFitted(dc, y, detail,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.COLOR_ACCENT);

        if (lastLine != null) {
            Theme.drawFitted(dc, y, lastLine as String,
                [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.COLOR_DIM);
        }
    }

    //! Thin arc that drains as the rest elapses — readable at a glance.
    private function _drawProgressArc(dc as Graphics.Dc, rest as RestTimer) as Void {
        if (rest.duration() <= 0) {
            return;
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var radius = (w < h ? w : h) / 2 - 5;
        var cx = w / 2;
        var cy = h / 2;
        var sweep = (360.0 * (1.0 - rest.progress())).toNumber();

        dc.setPenWidth(7);
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
        WatchUi.switchToView(new WorkoutOverviewView(), new WorkoutOverviewDelegate(),
            WatchUi.SLIDE_RIGHT);
        return true;
    }

    //! MENU edits the set you are about to do. Deciding "next one at 57.5" is
    //! what a rest is for, so it costs one press, not two.
    public function onMenu() as Boolean {
        var engine = AppController.instance().engine();
        if (engine == null) {
            return true;
        }
        var exercise = engine.currentExercise();
        if (exercise != null) {
            SetEditor.open(exercise, Tuning.RETURN_REST);
        }
        return true;
    }
}
