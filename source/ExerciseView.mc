import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.System;

//! The screen the athlete spends the workout on.
//!
//! Laid out as a Garmin data-field grid — bands of big value + small caption,
//! separated by hairlines — and paged with UP/DOWN like any native activity.
//!
//!   SET                  BODY / WORKOUT
//!   +-------------+      +---------------+
//!   | Lat Pulldown|      |      132      |   full width: a wide value, and
//!   |  SET 2 / 4  |      |       HR      |   the narrow top of the circle
//!   +------+------+      +-------+-------+
//!   |  55  |  10  |      |  128  |  210  |   split: only in the middle, where
//!   |WEIGHT| REPS |      | AVG HR|  KCAL |   the glass is widest
//!   +------+------+      +-------+-------+
//!   | COMPLETE SET|      |     12:34     |
//!   +-------------+      |      TIME     |
//!                        +---------------+
//!
//! Only the middle band is ever split into columns, and wide values
//! ("1:02:34", "3.2 t") always take a full-width band — that is what the
//! geometry of a round display allows. See FieldGrid.
//!
//! Buttons:
//!   START      complete the set (one press, from any page)
//!   UP / DOWN  previous / next data screen
//!   BACK       workout overview (pick any exercise)
//!   MENU       exercise actions — edit weight and reps live here
class ExerciseView extends WatchUi.View {

    //! The page constants live in Tuning: Monkey C does not expose a class-level
    //! `const` through the class name, and AppController needs them too.
    //!
    //! Which data screen is showing is held on the controller rather than here,
    //! so it survives rest screens and menu round-trips.
    public function initialize() {
        View.initialize();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var controller = AppController.instance();
        var engine = controller.engine();
        var exercise = engine != null ? engine.currentExercise() : null;

        if (exercise == null) {
            Theme.drawFitted(dc, dc.getHeight() / 2 - 20, "No exercise selected",
                Theme.fontsBody(), Theme.COLOR_DIM);
            return;
        }

        var page = controller.exercisePage();
        if (page == Tuning.PAGE_BODY) {
            _drawBodyPage(dc, exercise);
        } else if (page == Tuning.PAGE_WORKOUT) {
            _drawWorkoutPage(dc, engine as WorkoutEngine);
        } else {
            _drawSetPage(dc, controller, exercise);
        }
        Theme.drawPageDots(dc, Tuning.PAGE_COUNT, page);
    }

    //! Just a title and a rule. Used by the metric pages, where the set counter
    //! is redundant and the space is worth more as field height — on a 260x260
    //! screen it is the difference between a readable field and a cramped one.
    private function _drawCompactHeader(dc as Graphics.Dc, title as String) as Number {
        var h = dc.getHeight();
        var y = Theme.drawFitted(dc, h / 14, title, Theme.fontsTitle(), Theme.COLOR_TEXT);
        y += h / 44;
        FieldGrid.drawRule(dc, y);
        return y + 1;
    }

    //! Exercise name and set counter, above a rule. Returns the y where the
    //! field grid can start.
    private function _drawHeader(dc as Graphics.Dc, exercise as Exercise) as Number {
        var h = dc.getHeight();
        var y = h / 14;

        y = Theme.drawFitted(dc, y, exercise.name, Theme.fontsTitle(), Theme.COLOR_TEXT);

        var setLine = (WatchUi.loadResource(Rez.Strings.SetLabel) as String).toUpper() + " " +
            exercise.currentSetNumber().toString() + " / " + exercise.targetSets.toString();
        y = Theme.drawFitted(dc, y + h / 80, setLine,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.stateColor(exercise.state));

        // Progress dots only where there is room to spare. On a 260x260 screen
        // the set counter above already says it, and the space is worth more.
        if (h >= 400) {
            y = Theme.drawSetDots(dc, y + h / 60, exercise.targetSets,
                exercise.completedSetCount());
        }

        y += h / 40;
        FieldGrid.drawRule(dc, y);
        return y + 1;
    }

    //! Page 1 — the load and the reps, as two fields side by side.
    private function _drawSetPage(
        dc as Graphics.Dc,
        controller as AppController,
        exercise as Exercise
    ) as Void {
        var actionTop = Theme.drawActionBar(
            dc, WatchUi.loadResource(Rez.Strings.CompleteSet) as String, Theme.COLOR_ACCENT);
        var top = _drawHeader(dc, exercise);
        var bottom = actionTop - dc.getHeight() / 60;

        FieldGrid.drawPair(dc, top, bottom - top,
            Theme.formatWeight(controller.pendingWeight()),
            WatchUi.loadResource(Rez.Strings.FieldWeight) as String,
            Theme.COLOR_TEXT,
            controller.pendingReps().toString(),
            WatchUi.loadResource(Rez.Strings.FieldReps) as String,
            Theme.COLOR_TEXT);
    }

    //! Page 2 — live Garmin metrics, in Garmin's four-field round layout:
    //! a full-width band, a split middle, a full-width band.
    //!
    //! Heart rate leads because it is the number worth a glance mid-set, and
    //! the elapsed time sits full width at the bottom because "1:02:34" is far
    //! too wide for half a cell on a round screen.
    private function _drawBodyPage(dc as Graphics.Dc, exercise as Exercise) as Void {
        var h = dc.getHeight();
        var top = _drawCompactHeader(dc, exercise.name);
        var bottom = h - h / 11;

        var hr = LiveMetrics.heartRate();
        var timer = LiveMetrics.timerSeconds();

        var edge = FieldGrid.edgeHeight(top, bottom);
        var middleTop = top + edge;
        var bottomTop = bottom - edge;

        FieldGrid.drawSingle(dc, top, edge,
            LiveMetrics.format(hr),
            WatchUi.loadResource(Rez.Strings.FieldHr) as String,
            hr != null ? Theme.COLOR_HR : Theme.COLOR_SKIPPED);

        FieldGrid.drawRule(dc, middleTop);
        FieldGrid.drawPair(dc, middleTop, bottomTop - middleTop,
            LiveMetrics.format(LiveMetrics.averageHeartRate()),
            WatchUi.loadResource(Rez.Strings.FieldAvgHr) as String,
            Theme.COLOR_TEXT,
            LiveMetrics.format(LiveMetrics.calories()),
            WatchUi.loadResource(Rez.Strings.FieldKcal) as String,
            Theme.COLOR_TEXT);

        FieldGrid.drawRule(dc, bottomTop);
        FieldGrid.drawSingle(dc, bottomTop, edge,
            timer != null ? Theme.formatDuration(timer) : LiveMetrics.NO_VALUE,
            WatchUi.loadResource(Rez.Strings.FieldTime) as String,
            Theme.COLOR_TEXT);
    }

    //! Page 3 — what the session has accumulated so far, same round layout.
    //! Volume leads full width ("3.2 t", "12 450 kg"); sets and reps are short
    //! enough to share the middle.
    private function _drawWorkoutPage(dc as Graphics.Dc, engine as WorkoutEngine) as Void {
        var h = dc.getHeight();
        var summary = engine.summary(AppController.now());

        var top = _drawCompactHeader(dc, engine.getWorkout().name);

        var done = 0;
        var list = engine.getWorkout().exercises;
        for (var i = 0; i < list.size(); i++) {
            if (list[i].state == EX_COMPLETED) {
                done++;
            }
        }

        var bottom = h - h / 11;
        var edge = FieldGrid.edgeHeight(top, bottom);
        var middleTop = top + edge;
        var bottomTop = bottom - edge;

        FieldGrid.drawSingle(dc, top, edge,
            Theme.formatVolume(summary.totalVolume),
            WatchUi.loadResource(Rez.Strings.FieldVolume) as String,
            Theme.COLOR_ACCENT);

        FieldGrid.drawRule(dc, middleTop);
        FieldGrid.drawPair(dc, middleTop, bottomTop - middleTop,
            summary.completedSets.toString(),
            WatchUi.loadResource(Rez.Strings.FieldSets) as String,
            Theme.COLOR_TEXT,
            summary.totalReps.toString(),
            WatchUi.loadResource(Rez.Strings.FieldReps) as String,
            Theme.COLOR_TEXT);

        FieldGrid.drawRule(dc, bottomTop);
        FieldGrid.drawSingle(dc, bottomTop, edge,
            done.toString() + "/" + summary.exerciseCount.toString(),
            WatchUi.loadResource(Rez.Strings.FieldExercises) as String,
            Theme.COLOR_TEXT);
    }
}

class ExerciseDelegate extends WatchUi.BehaviorDelegate {

    public function initialize() {
        BehaviorDelegate.initialize();
    }

    //! START — one press completes the set, from whichever page is showing.
    //! This is the hot path and must never grow a confirmation.
    public function onSelect() as Boolean {
        AppController.instance().completeSet();
        return true;
    }

    //! UP / DOWN page through the data screens, as they do in every native
    //! Garmin activity. Weight and reps are edited from the MENU.
    public function onPreviousPage() as Boolean {
        AppController.instance().turnExercisePage(-1);
        WatchUi.requestUpdate();
        return true;
    }

    public function onNextPage() as Boolean {
        AppController.instance().turnExercisePage(1);
        WatchUi.requestUpdate();
        return true;
    }

    //! BACK — workout overview is always one press away.
    public function onBack() as Boolean {
        WatchUi.switchToView(new WorkoutOverviewView(), new WorkoutOverviewDelegate(),
            WatchUi.SLIDE_RIGHT);
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

    //! Touch devices get a shortcut straight into the editors: tap the left
    //! field for weight, the right one for reps. Optional — everything here
    //! works with buttons alone.
    public function onTap(event as WatchUi.ClickEvent) as Boolean {
        var controller = AppController.instance();
        if (controller.exercisePage() != Tuning.PAGE_SET) {
            return false;
        }
        var engine = controller.engine();
        if (engine == null) {
            return false;
        }
        var exercise = engine.currentExercise();
        if (exercise == null) {
            return false;
        }
        var coords = event.getCoordinates();
        var settings = System.getDeviceSettings();
        // Only the field band responds; the header and action bar do not.
        if (coords[1] < settings.screenHeight * 0.30 ||
            coords[1] > settings.screenHeight * 0.78) {
            return false;
        }
        if (coords[0] < settings.screenWidth / 2) {
            ValueEditor.editWeight(exercise);
        } else {
            ValueEditor.editReps(exercise);
        }
        return true;
    }
}
