import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.System;

//! The screen the athlete spends the workout on.
//!
//! Laid out as a Garmin data-field grid — bands of big value + small caption,
//! separated by hairlines — and paged with UP/DOWN like any native activity.
//!
//!   SET                        BODY / WORKOUT (data fields)
//!   +---------------------+    +---------------------+
//!   |      Seated Row     |    |         132         |
//!   |      SET 4 / 4      |    |          HR         |
//!   | ------------------- |    +----------+----------+
//!   |       60 KG         |    |   128    |   210    |
//!   |        x 10         |    |  AVG HR  |   KCAL   |
//!   | ------------------- |    +----------+----------+
//!   |      * * * o        |    |        12:34        |
//!   |     [ LOG SET ]     |    |         TIME        |
//!   +---------------------+    +---------------------+
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

    //! Just a title and a rule, for the metric pages.
    private function _drawCompactHeader(dc as Graphics.Dc, title as String) as Number {
        var h = dc.getHeight();
        var y = Theme.drawFitted(dc, h / 14, title, Theme.fontsTitle(), Theme.COLOR_TEXT);
        y += h / 44;
        FieldGrid.drawRule(dc, y);
        return y + 1;
    }

    //! Page 1 — the set you are about to do.
    //!
    //! Designed for a two-second glance mid-exercise, so it answers, in order of
    //! size: what am I lifting, how many reps, which set is this, how far in.
    //! A list of identical "10 x 60" rows answered none of those at a glance —
    //! everything was the same size, so nothing stood out.
    //!
    //!        Seated Row          who
    //!        SET 4 / 4           where
    //!      -------------
    //!          60 KG             WHAT — the hero
    //!          x 10
    //!      -------------
    //!         * * * o            progress
    //!        [ LOG SET ]
    private function _drawSetPage(
        dc as Graphics.Dc,
        controller as AppController,
        exercise as Exercise
    ) as Void {
        var h = dc.getHeight();
        var done = exercise.completedSetCount();
        var target = exercise.targetSets;

        // Progress on the rim: the one area a round screen gives away free.
        Theme.drawProgressRing(dc,
            target > 0 ? done.toFloat() / target.toFloat() : 0.0,
            Theme.COLOR_DONE);

        var actionTop = Theme.drawActionBar(
            dc, WatchUi.loadResource(Rez.Strings.LogSet) as String, Theme.COLOR_ACCENT);

        // --- who and where ------------------------------------------------
        var y = Theme.drawFitted(dc, h / 16, exercise.name,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.COLOR_DIM);

        var setLine = (WatchUi.loadResource(Rez.Strings.SetLabel) as String).toUpper() +
            " " + exercise.currentSetNumber().toString() + " / " + target.toString();
        y = Theme.drawFitted(dc, y + h / 90, setLine,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.COLOR_ACCENT);

        y += h / 50;
        FieldGrid.drawRule(dc, y);
        y += 1;

        // --- progress dots, anchored just above the action --------------
        var dotsHeight = h / 18;
        var dotsTop = actionTop - dotsHeight - h / 50;
        Theme.drawSetDots(dc, dotsTop, target, done);

        // --- the load: everything left between the rule and the dots -----
        _drawLoad(dc, y, dotsTop - h / 60, controller);
    }

    //! The weight, as large as the space allows, with the reps beneath it.
    private function _drawLoad(
        dc as Graphics.Dc,
        top as Number,
        bottom as Number,
        controller as AppController
    ) as Void {
        var available = bottom - top;
        var gap = dc.getHeight() / 60;

        var repsText = "x " + controller.pendingReps().toString();
        var repsFont = Theme.pickFontFitting(dc, repsText, Theme.fontsTitle(),
            Theme.bandWidth(dc, top, available), (available * 34) / 100);
        var repsHeight = dc.getFontHeight(repsFont);

        var weightText = Theme.formatWeight(controller.pendingWeight());
        var weightBudget = available - repsHeight - gap;

        var block = _weightHeight(dc, weightText, weightBudget, top) + gap + repsHeight;
        var y = top + (available - block) / 2;
        if (y < top) {
            y = top;
        }

        y = Theme.drawValueWithUnitCapped(dc, y, weightText,
            (WatchUi.loadResource(Rez.Strings.Kg) as String).toUpper(),
            Theme.fontsHero(), Theme.COLOR_TEXT, Theme.COLOR_DIM, weightBudget);

        dc.setColor(Theme.COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, y + gap, repsFont, repsText,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function _weightHeight(
        dc as Graphics.Dc,
        text as String,
        budget as Number,
        top as Number
    ) as Number {
        var font = Theme.pickFontFitting(dc, text, Theme.fontsHero(),
            (Theme.bandWidth(dc, top, budget) * 70) / 100, budget);
        return dc.getFontHeight(font);
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
            Theme.COLOR_HR,
            LiveMetrics.format(LiveMetrics.calories()),
            WatchUi.loadResource(Rez.Strings.FieldKcal) as String,
            Theme.COLOR_WARM);

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
            Theme.COLOR_DONE,
            summary.totalReps.toString(),
            WatchUi.loadResource(Rez.Strings.FieldReps) as String,
            Theme.COLOR_TEXT);

        FieldGrid.drawRule(dc, bottomTop);
        FieldGrid.drawSingle(dc, bottomTop, edge,
            done.toString() + "/" + summary.exerciseCount.toString(),
            WatchUi.loadResource(Rez.Strings.FieldExercises) as String,
            Theme.COLOR_DONE);
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

    //! Touch devices get a shortcut into the set editor: tap either field.
    //! Optional — everything here works with buttons alone.
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
        SetEditor.open(exercise, Tuning.RETURN_EXERCISE);
        return true;
    }
}
