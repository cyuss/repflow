import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.System;

//! The screen the athlete spends the workout on — a set of data screens paged
//! with UP/DOWN, the way every other Garmin activity behaves.
//!
//!   Page 1 — SET        the exercise, the load, the dominant action
//!   Page 2 — BODY       live Garmin metrics: heart rate, time, calories
//!   Page 3 — WORKOUT    session totals: sets, reps, volume, exercises
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
            _drawWorkoutPage(dc, engine as WorkoutEngine, exercise);
        } else {
            _drawSetPage(dc, controller, exercise);
        }
        Theme.drawPageDots(dc, Tuning.PAGE_COUNT, page);
    }

    // ------------------------------------------------------------------
    // Page 1 — the set
    // ------------------------------------------------------------------

    private function _drawSetPage(
        dc as Graphics.Dc,
        controller as AppController,
        exercise as Exercise
    ) as Void {
        var h = dc.getHeight();
        // Reserve the bottom band for the action, then lay content out above it.
        var actionTop = Theme.drawActionBar(
            dc, WatchUi.loadResource(Rez.Strings.CompleteSet) as String, Theme.COLOR_ACCENT);

        var gap = h / 40;
        var y = h / 11;

        // Exercise name.
        y = Theme.drawFitted(dc, y, exercise.name, Theme.fontsTitle(), Theme.COLOR_TEXT);
        y += gap;

        // Set X / Y, coloured by the exercise's state.
        var setLine = (WatchUi.loadResource(Rez.Strings.SetLabel) as String) + " " +
            exercise.currentSetNumber().toString() + " / " + exercise.targetSets.toString();
        y = Theme.drawFitted(dc, y, setLine, Theme.fontsLabel(), Theme.stateColor(exercise.state));
        y += gap;

        // Progress dots, one per target set.
        y = Theme.drawSetDots(dc, y, exercise.targetSets, exercise.completedSetCount());

        // The two numbers, centred in whatever room is left between here and
        // the action bar. Measuring the block first is what keeps the weight and
        // the reps from crowding each other on a small screen.
        var repsText = controller.pendingReps().toString();
        var repsUnit = WatchUi.loadResource(Rez.Strings.Reps) as String;
        var repsFont = Graphics.FONT_MEDIUM;
        var repsHeight = dc.getFontHeight(repsFont);

        var weightText = Theme.formatWeight(controller.pendingWeight());
        var weightFont = Theme.pickFont(dc, weightText, Theme.fontsHero(),
            (Theme.usableWidth(dc, h / 2) * 70) / 100);
        var weightHeight = dc.getFontHeight(weightFont);

        var innerGap = h / 30;
        var blockHeight = weightHeight + innerGap + repsHeight;
        var available = actionTop - y;
        var blockTop = y + (available - blockHeight) / 2;
        if (blockTop < y) {
            blockTop = y;
        }

        var afterWeight = Theme.drawValueWithUnit(
            dc, blockTop, weightText,
            WatchUi.loadResource(Rez.Strings.Kg) as String,
            Theme.fontsHero(), Theme.COLOR_TEXT, Theme.COLOR_DIM);

        _drawReps(dc, afterWeight + innerGap, repsText, repsUnit, repsFont);
    }

    //! Reps, with the unit beside the number in the same dim tone as "kg".
    private function _drawReps(
        dc as Graphics.Dc,
        y as Number,
        value as String,
        unit as String,
        font as Graphics.FontDefinition
    ) as Void {
        var unitFont = Graphics.FONT_XTINY;
        var unitText = " " + unit;
        var valueWidth = dc.getTextWidthInPixels(value, font);
        var unitWidth = dc.getTextWidthInPixels(unitText, unitFont);
        var left = (dc.getWidth() - (valueWidth + unitWidth)) / 2;
        var valueHeight = dc.getFontHeight(font);
        var unitHeight = dc.getFontHeight(unitFont);

        dc.setColor(Theme.COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, y, font, value, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Theme.COLOR_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + valueWidth, y + valueHeight - unitHeight - (valueHeight / 10),
            unitFont, unitText, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // ------------------------------------------------------------------
    // Page 2 — live Garmin metrics
    // ------------------------------------------------------------------

    private function _drawBodyPage(dc as Graphics.Dc, exercise as Exercise) as Void {
        var h = dc.getHeight();
        var gap = h / 32;
        var y = h / 10;

        y = Theme.drawFitted(dc, y, WatchUi.loadResource(Rez.Strings.PageBody) as String,
            Theme.fontsLabel(), Theme.COLOR_DIM);
        y += gap;

        // Heart rate is the number worth reading mid-set, so it gets the hero slot.
        var hr = LiveMetrics.heartRate();
        y = Theme.drawValueWithUnit(
            dc, y, LiveMetrics.format(hr),
            WatchUi.loadResource(Rez.Strings.Bpm) as String,
            Theme.fontsHero(),
            hr != null ? Theme.COLOR_HR : Theme.COLOR_SKIPPED,
            Theme.COLOR_DIM);
        y += gap + gap;

        var timer = LiveMetrics.timerSeconds();
        y = Theme.drawMetricRow(dc, y,
            WatchUi.loadResource(Rez.Strings.Duration) as String,
            timer != null ? Theme.formatDuration(timer) : LiveMetrics.NO_VALUE,
            Theme.COLOR_TEXT);
        y += gap;

        y = Theme.drawMetricRow(dc, y,
            WatchUi.loadResource(Rez.Strings.AvgHr) as String,
            LiveMetrics.format(LiveMetrics.averageHeartRate()),
            Theme.COLOR_TEXT);
        y += gap;

        Theme.drawMetricRow(dc, y,
            WatchUi.loadResource(Rez.Strings.Calories) as String,
            LiveMetrics.format(LiveMetrics.calories()),
            Theme.COLOR_TEXT);
    }

    // ------------------------------------------------------------------
    // Page 3 — what has been done so far
    // ------------------------------------------------------------------

    private function _drawWorkoutPage(
        dc as Graphics.Dc,
        engine as WorkoutEngine,
        exercise as Exercise
    ) as Void {
        var h = dc.getHeight();
        var gap = h / 32;
        var y = h / 10;
        var summary = engine.summary(AppController.now());

        y = Theme.drawFitted(dc, y, WatchUi.loadResource(Rez.Strings.PageWorkout) as String,
            Theme.fontsLabel(), Theme.COLOR_DIM);
        y += gap;

        y = Theme.drawValueWithUnit(
            dc, y, Theme.formatVolume(summary.totalVolume), "",
            Theme.fontsBig(), Theme.COLOR_ACCENT, Theme.COLOR_DIM);
        y = Theme.drawFitted(dc, y, WatchUi.loadResource(Rez.Strings.Volume) as String,
            Theme.fontsLabel(), Theme.COLOR_DIM);
        y += gap + gap;

        var done = 0;
        var list = engine.getWorkout().exercises;
        for (var i = 0; i < list.size(); i++) {
            if (list[i].state == EX_COMPLETED) {
                done++;
            }
        }

        y = Theme.drawMetricRow(dc, y,
            WatchUi.loadResource(Rez.Strings.Exercises) as String,
            done.toString() + "/" + summary.exerciseCount.toString(),
            Theme.COLOR_TEXT);
        y += gap;

        y = Theme.drawMetricRow(dc, y,
            WatchUi.loadResource(Rez.Strings.SetsDone) as String,
            summary.completedSets.toString(),
            Theme.COLOR_TEXT);
        y += gap;

        Theme.drawMetricRow(dc, y,
            WatchUi.loadResource(Rez.Strings.TotalReps) as String,
            summary.totalReps.toString(),
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

    //! Touch devices get a shortcut straight into the editors: tap the weight,
    //! or tap the reps. Optional — everything here works with buttons alone.
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
        var screenHeight = System.getDeviceSettings().screenHeight;
        if (coords[1] < screenHeight * 0.42 || coords[1] > screenHeight * 0.80) {
            return false;   // header and action bar are not edit targets
        }
        if (coords[1] < screenHeight * 0.64) {
            ValueEditor.editWeight(exercise);
        } else {
            ValueEditor.editReps(exercise);
        }
        return true;
    }
}
