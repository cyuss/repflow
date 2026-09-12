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
//!   |  (heart) 132  ###   |    |         132         |
//!   |      Seated Row     |    |          HR         |
//!   | ------------------- |    +----------+----------+
//!   |    60    |    10    |    |   128    |   210    |
//!   |    KG    |   REPS   |    |  AVG HR  |   KCAL   |
//!   | ------------------- |    +----------+----------+
//!   |  0:42    |   1/4    |    |        12:34        |
//!   |  TIMER   |   SET    |    |         TIME        |
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

    //! Counting repetitions means the accelerometer at 25 Hz, so it runs only
    //! while this screen is actually in front of the athlete.
    public function onShow() as Void {
        AppController.instance().updateRepCounting();
        // The ring sweeps out to where the exercise actually is. Nothing moves
        // on the devices that cannot spare the frames — see Animator.
        Animator.start(280);
    }

    public function onHide() as Void {
        AppController.instance().updateRepCounting();
        Animator.stop();
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
    //! Laid out the way a native Garmin activity screen is: heart rate behind a
    //! heart at the top, the thing you are actually doing in the middle at full
    //! size, and small labelled readouts along the bottom.
    //!
    //!      (heart) 132  ###      live HR and its zone
    //!        Lat Pulldown
    //!      -----------------
    //!        55    |    10     the load, two aligned cells
    //!        KG    |   REPS
    //!      -----------------
    //!       TIMER  |   SET     secondary readouts
    //!       0:42   |   1/4
    //!
    //! The set counter lives in the bottom band rather than the header, because
    //! repeating it in both wasted a line — and on a 260x260 screen a line is
    //! the difference between a big number and a cramped one.
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
            (target > 0 ? done.toFloat() / target.toFloat() : 0.0) * Animator.value(),
            Theme.COLOR_DONE);

        // No action button. START logs the set, and a button saying so was only
        // repeating what the athlete already knows while eating the space the
        // readouts and the load needed.
        var clockHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var clockTop = h - clockHeight - h / 22;
        Theme.drawClock(dc, clockTop);

        var top = Theme.drawHeartRateGauge(dc, h / 14);
        top = Theme.drawFitted(dc, top + h / 60, exercise.name,
            [Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_TEXT);
        top += h / 40;
        FieldGrid.drawRule(dc, top);
        top += 1;

        var bandTop = _drawSecondaryBand(dc, clockTop - h / 60, controller, exercise);
        _drawLoad(dc, top, bandTop - h / 50, controller);

    }

    //! The secondary readouts: exercise timer and set counter, as captioned
    //! data fields. Returns the y where this band starts.
    private function _drawSecondaryBand(
        dc as Graphics.Dc,
        bottom as Number,
        controller as AppController,
        exercise as Exercise
    ) as Number {
        var h = dc.getHeight();
        var timer = Theme.formatDuration(controller.exerciseSeconds());
        var sets = exercise.currentSetNumber().toString() + "/" +
            exercise.targetSets.toString();

        var bandHeight = Theme.miniFieldHeight(dc);
        var top = bottom - bandHeight;
        var bandWidth = Theme.bandWidth(dc, top, bandHeight);
        var bandLeft = (dc.getWidth() - bandWidth) / 2;
        FieldGrid.drawRule(dc, top - h / 50);

        Theme.drawMiniField(dc, bandLeft + bandWidth / 4, top, timer,
            WatchUi.loadResource(Rez.Strings.FieldTimer) as String, Theme.COLOR_TEXT);
        Theme.drawMiniField(dc, bandLeft + (bandWidth * 3) / 4, top, sets,
            (WatchUi.loadResource(Rez.Strings.SetLabel) as String).toUpper(),
            Theme.COLOR_ACCENT);
        return top - h / 50;
    }

    //! The load: weight and reps as two aligned cells sharing one band.
    //!
    //! It used to be a big weight with the reps floating under it. That stacked
    //! two unrelated-looking numbers, pushed the block against the rules above
    //! and below, and looked nothing like the editor the athlete opens one press
    //! later. Two captioned cells with a divider give each value its own room,
    //! align their baselines, and make the reading screen and the editing screen
    //! the same screen.
    private function _drawLoad(
        dc as Graphics.Dc,
        top as Number,
        bottom as Number,
        controller as AppController
    ) as Void {
        var available = bottom - top;
        if (available <= 0) {
            return;
        }
        // Breathing room top and bottom, so the cells never sit on the hairlines
        // that frame them.
        var inset = dc.getHeight() / 36;
        var height = available - inset * 2;
        if (height <= 0) {
            height = available;
            inset = 0;
        }
        // When the wrist is counting, the reps cell shows what it has counted
        // rather than what was planned — because that is the number START is
        // about to put in front of the athlete. It is shown in the warm colour
        // so it is visibly a measurement rather than the plan.
        var counted = controller.countedReps();
        var repsText = controller.pendingReps().toString();
        var repsColor = Theme.COLOR_ACCENT;
        if (counted != null && (counted as Number) > 0) {
            repsText = (counted as Number).toString();
            repsColor = Theme.COLOR_WARM;
        }

        FieldGrid.drawPair(dc, top + inset, height,
            Theme.formatWeight(controller.pendingWeight()),
            Units.label().toUpper(),
            Theme.COLOR_TEXT,
            repsText,
            WatchUi.loadResource(Rez.Strings.FieldReps) as String,
            repsColor);
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
        var bottom = h - h / 13;

        var timer = LiveMetrics.timerSeconds();

        var edge = FieldGrid.edgeHeight(top, bottom);
        var middleTop = top + edge;
        var bottomTop = bottom - edge;

        Theme.drawHeartRateField(dc, top, edge,
            WatchUi.loadResource(Rez.Strings.FieldHr) as String);

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

        var bottom = h - h / 13;
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

    //! START — the set is done. Hand control back before the rest timer takes
    //! the screen: the values recorded should be the ones actually performed.
    //! One more press of START logs them unchanged, so the hot path stays short.
    public function onSelect() as Boolean {
        var engine = AppController.instance().engine();
        if (engine == null) {
            return true;
        }
        var exercise = engine.currentExercise();
        if (exercise == null) {
            return true;
        }
        // Whatever the wrist counted becomes the value the editor opens on.
        AppController.instance().applyCountedReps();
        SetEditor.confirm(exercise);
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
