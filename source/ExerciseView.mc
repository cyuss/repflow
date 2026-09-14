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
//! Buttons, following the watch's own activity screens rather than inventing a
//! scheme of their own:
//!
//!   BACK       log the set — this is the LAP button, and on a Garmin mid
//!              activity LAP means "that piece is done, move on". One press.
//!   START      open the set first, to change reps, load or effort before
//!              logging it. START then logs.
//!   UP / DOWN  previous / next data screen
//!   MENU       everything else, the exercise list included
//!
//! BACK used to open the exercise list and START used to open the set. Both
//! worked and neither matched the reflex: an athlete who has used a Garmin
//! workout reaches for BACK when a set is finished, and got the list.
//!
//! The list moved to MENU rather than losing its place, because "select any
//! exercise at any time" is what this app is for — it is one press further away
//! and it is the first item, under the cursor the moment the menu opens.
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
        Marquee.stop();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var controller = AppController.instance();
        var engine = controller.engine();
        var exercise = engine != null ? engine.currentExercise() : null;

        if (exercise == null) {
            Theme.drawFitted(dc, dc.getHeight() / 2 - 20, "No exercise selected",
                Theme.fontsBody(), Theme.colorDim());
            return;
        }

        // Progress on the rim belongs to the **exercise**, not to one of its
        // pages. It used to be drawn inside the set page, so glancing at your
        // heart rate between sets took away the one thing that said how much of
        // the exercise was left. Drawn first, for every page, in the same place
        // on each — the rim means the same thing wherever you are.
        var done = exercise.completedSetCount();
        var target = exercise.targetSets;
        Theme.drawProgressRing(dc,
            (target > 0 ? done.toFloat() / target.toFloat() : 0.0) * Animator.value(),
            Theme.colorDone());
        var inset = Theme.progressRingInset(dc);

        var page = controller.exercisePage();
        if (page == Tuning.PAGE_BODY) {
            MetricPages.drawBody(dc, exercise.name, inset);
        } else if (page == Tuning.PAGE_WORKOUT) {
            MetricPages.drawWorkout(dc, engine as WorkoutEngine, inset);
        } else {
            _drawSetPage(dc, controller, exercise);
        }
        Theme.drawPageDots(dc, Tuning.PAGE_COUNT, page);
        Marquee.endFrame();
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

        // No action button. START logs the set, and a button saying so was only
        // repeating what the athlete already knows while eating the space the
        // readouts and the load needed.
        // Sets done and the time of day: the two things you glance at rather
        // than read. Uncaptioned on purpose — a fraction beside a wall clock
        // cannot be mistaken for it, and the captioned pair above is where the
        // reading happens.
        //
        // Lifted off the very bottom: this row carries two readings side by
        // side instead of one centred, and the outer ends of a pair sit where
        // the glass has already curved in. h/22 put their descenders under the
        // bezel — visible in a screenshot, invisible to every other check.
        var clockHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var clockTop = h - clockHeight - h / 14;
        Theme.drawClockWith(dc, clockTop,
            exercise.currentSetNumber().toString() + "/" +
                exercise.targetSets.toString(),
            Theme.colorAccent());

        var top = Theme.drawHeartRateGauge(dc, h / 14);
        top = Marquee.draw(dc, top + h / 60, exercise.name,
            [Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.colorText(), Theme.usableWidth(dc, top + h / 60));
        top += h / 40;
        FieldGrid.drawRule(dc, top);
        top += 1;

        var bandTop = _drawSecondaryBand(dc, clockTop - h / 60, controller, exercise);
        _drawLoad(dc, top, bandTop - h / 50, controller);

    }

    //! The two clocks, as captioned data fields. Returns the y where this band
    //! starts.
    //!
    //!      0:17       4:18
    //!      SET       TIMER
    //!
    //! Three spans matter while a set is happening, and they are all different:
    //! how long **this set** has run, how long the **movement** has taken across
    //! its sets and rests, and how far through it you are. The set clock was the
    //! one nobody could see — the exercise timer keeps running through every
    //! rest, so it answers a question about the last ten minutes rather than
    //! about the bar in your hands.
    //!
    //! Only two of the three are here. Three columns of this band are 51px each
    //! on a Fenix 6 Pro and "12:34" needs 54 — measured in
    //! testExerciseBandFitsThree, not guessed — so a third would have shrunk all
    //! of them. The set count went to the bottom line instead: it is the one of
    //! the three that is also drawn on the progress ring, so it is the one that
    //! loses least by being smaller.
    //!
    //! The two clocks sit together because they are the same kind of thing,
    //! which is what makes the difference between them legible. Captioning one
    //! "SET" and the other "SETS" — an earlier attempt — put a duration and a
    //! fraction side by side under near-identical words, and nothing about that
    //! reads at arm's length.
    private function _drawSecondaryBand(
        dc as Graphics.Dc,
        bottom as Number,
        controller as AppController,
        exercise as Exercise
    ) as Number {
        var h = dc.getHeight();
        var setTime = Theme.formatDuration(controller.setSeconds());
        var exerciseTime = Theme.formatDuration(controller.exerciseSeconds());

        var bandHeight = Theme.miniFieldHeight(dc);
        var top = bottom - bandHeight;
        var bandWidth = Theme.bandWidth(dc, top, bandHeight);
        var bandLeft = (dc.getWidth() - bandWidth) / 2;
        FieldGrid.drawRule(dc, top - h / 50);

        // The live one is at full contrast and the context one is dimmed, so a
        // glance lands on the set before it lands on the movement.
        Theme.drawMiniField(dc, bandLeft + bandWidth / 4, top, setTime,
            (WatchUi.loadResource(Rez.Strings.SetLabel) as String).toUpper(),
            Theme.colorText());
        Theme.drawMiniField(dc, bandLeft + (bandWidth * 3) / 4, top, exerciseTime,
            WatchUi.loadResource(Rez.Strings.FieldTimer) as String,
            Theme.colorDim());
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
        var repsColor = Theme.colorAccent();
        if (counted != null && (counted as Number) > 0) {
            repsText = (counted as Number).toString();
            repsColor = Theme.colorWarm();
        }

        FieldGrid.drawPair(dc, top + inset, height,
            Theme.formatPlannedWeight(controller.pendingWeight()),
            Units.label().toUpper(),
            Theme.colorText(),
            repsText,
            WatchUi.loadResource(Rez.Strings.FieldReps) as String,
            repsColor);
    }

}

class ExerciseDelegate extends WatchUi.BehaviorDelegate {

    public function initialize() {
        BehaviorDelegate.initialize();
    }

    //! START — open the set before logging it, for when something changed:
    //! fewer reps than planned, a different load, an effort worth recording.
    //! START again logs it. BACK logs it without asking.
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

    //! BACK — the set is done. This is the LAP button and that is what LAP
    //! means during an activity on this watch.
    //!
    //! Logged as planned, with whatever the wrist counted if it was counting.
    //! Nothing to confirm: the values are on screen, the athlete has been
    //! looking at them, and a set logged wrongly is undone from the menu.
    public function onBack() as Boolean {
        var controller = AppController.instance();
        var engine = controller.engine();
        if (engine == null || engine.currentExercise() == null) {
            return true;
        }
        controller.applyCountedReps();
        controller.completeSet();
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
