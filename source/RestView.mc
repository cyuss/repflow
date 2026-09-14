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
//! **UP and DOWN page, exactly as they do while you are working.** The rest
//! screen is pages 0, 1 and 2 of the same three: the countdown, then the body,
//! then the session — the last two identical to the exercise screen's.
//!
//! That decision cost something, and it is worth naming. UP/DOWN used to add
//! and remove 15 seconds, and a watch has no spare buttons: paging and
//! adjusting cannot both live there. Adjusting lost, for two reasons.
//!
//! The first is consistency. Every native Garmin activity pages with UP/DOWN,
//! and so does RepFlow's own exercise screen. Having the same two buttons mean
//! something else the moment a timer starts is a trap you fall into once per
//! session, in the dark, mid-workout.
//!
//! The second is that adjusting stopped being the common case. Rest is per
//! exercise and editable on the watch, with a default in the settings; the
//! ad-hoc nudge is now the exception it always should have been. So it moved to
//! MENU, where every other occasional action in this app already lives.
//!
//! Buttons:
//!   START      rest is over, back to the exercise
//!   UP / DOWN  previous / next page
//!   MENU       rest actions — add or remove 15 s, skip, end workout
//!   BACK       workout overview — go do a different exercise instead
class RestView extends WatchUi.View {

    public function initialize() {
        View.initialize();
    }

    public function onHide() as Void {
        Marquee.stop();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var controller = AppController.instance();
        var page = controller.restPage();

        if (page == Tuning.PAGE_BODY) {
            var exercise = _next(controller);
            MetricPages.drawBody(dc, exercise != null
                ? (exercise as Exercise).name
                : WatchUi.loadResource(Rez.Strings.Rest) as String);
        } else if (page == Tuning.PAGE_WORKOUT) {
            var engine = controller.engine();
            if (engine != null) {
                MetricPages.drawWorkout(dc, engine as WorkoutEngine);
            }
        } else {
            _drawCountdown(dc, controller);
        }

        Theme.drawPageDots(dc, Tuning.REST_PAGE_COUNT, page);
        Marquee.endFrame();
    }

    private function _next(controller as AppController) as Exercise? {
        var engine = controller.engine();
        return engine != null ? engine.suggestNextExercise() : null;
    }

    //! Page 1 — the countdown, and what it is for.
    private function _drawCountdown(dc as Graphics.Dc, controller as AppController) as Void {
        var rest = controller.restTimer();
        var h = dc.getHeight();

        _drawProgressArc(dc, rest);

        // The countdown is the hero, but it was taking nearly half the glass:
        // a fixed 26% for the digits on top of its label and the air around
        // them, which left the two fields and the next-up block squeezed into
        // what remained. Two thirds of the screen for one number the athlete
        // glances at, and a third for everything they read.
        //
        // It now takes a fifth. The digits stay large — a fifth of a 260px
        // screen is still the number font — and the fields below get room to be
        // read rather than deciphered.
        var inset = _ringInset(dc);
        var y = h / 11;
        y = Theme.drawFittedWithin(dc, y, WatchUi.loadResource(Rez.Strings.Rest) as String,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.colorDim(),
            inset);

        var countdownTop = y + h / 60;
        var countdownHeight = (h * 20) / 100;
        var timerFont = Theme.pickFontFitting(dc, rest.format(), Theme.fontsHero(),
            (Theme.usableWidthWithin(dc, countdownTop + countdownHeight / 2, inset) * 80) / 100,
            countdownHeight);
        dc.setColor(rest.isRunning() ? Theme.colorText() : Theme.colorDone(),
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, countdownTop, timerFont, rest.format(),
            Graphics.TEXT_JUSTIFY_CENTER);

        // Advance past the digits, not past the line they nominally sit on: a
        // number font's descent is empty, and counting it here would leave a
        // finger's width of nothing under the countdown.
        var top = countdownTop + Theme.inkHeight(timerFont) + h / 60;
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
        var next = _next(controller);

        // What was done on this movement last time, but only before the first
        // set of it: once there is a set in this session, the planned load is
        // already the athlete's own and the older number is just noise.
        var lastLine = null as String?;
        if (next != null && (next as Exercise).completedSetCount() == 0) {
            lastLine = ExerciseActionsMenu.lastLine((next as Exercise).id);
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
        var dropColor = Theme.colorFaint();
        if (drop != null) {
            dropColor = drop >= 12 ? Theme.colorDone() : Theme.colorWarm();
        }

        FieldGrid.drawPair(dc, top, fieldBottom - top,
            LiveMetrics.format(hr),
            WatchUi.loadResource(Rez.Strings.FieldHr) as String,
            hr != null ? Theme.colorHr() : Theme.colorFaint(),
            dropText,
            WatchUi.loadResource(Rez.Strings.FieldRecovery) as String,
            dropColor);

        if (next == null) {
            return;
        }
        var exercise = next as Exercise;

        FieldGrid.drawRule(dc, fieldBottom);
        var y = fieldBottom + h / 44;
        // Measured at the line's baseline and against the ring, not the glass:
        // this is the lowest text on the page and the chord closes fastest here.
        var nameFont = Theme.fontsBody()[0];
        y = Marquee.draw(dc, y, exercise.name, Theme.fontsBody(), Theme.colorText(),
            Theme.usableWidthWithin(dc, y + (dc.getFontHeight(nameFont) * 3) / 4,
                _ringInset(dc)));

        var detail = (exercise.completedSetCount() + 1).toString() + "/" +
            exercise.targetSets.toString() + "   " +
            exercise.plannedReps().toString() + " x " +
            Theme.formatPlannedWeight(exercise.plannedWeight()) + " " +
            Units.label();
        y = Theme.drawFittedWithin(dc, y, detail,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.colorAccent(),
            _ringInset(dc));

        if (lastLine != null) {
            Theme.drawFittedWithin(dc, y, lastLine as String,
                [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.colorDim(),
                _ringInset(dc));
        }
    }

    //! Distance from the glass to the outside of the countdown ring.
    private const RING_MARGIN = 5;

    //! How far in from the glass the ring's inner edge sits, plus air.
    //!
    //! Text on this page is bounded by the ring, not by the bezel. The ring is
    //! the frame the countdown lives in, and a line crossing it reads as a
    //! rendering fault rather than as two layers — which is exactly what a
    //! long exercise name scrolling along the bottom used to do.
    private function _ringInset(dc as Graphics.Dc) as Number {
        return RING_MARGIN + Device.stroke(27) / 2 + dc.getHeight() / 36;
    }

    //! Thin arc that drains as the rest elapses — readable at a glance.
    //!
    //! The **track** is drawn whatever the mode, because it is the frame this
    //! screen's text is laid out inside and the layout must not move when the
    //! athlete switches modes. What changes is the arc on top of it: an open
    //! rest has no target, so there is no proportion to fill and none is drawn.
    //! An empty ring is the honest picture of "resting, no target".
    private function _drawProgressArc(dc as Graphics.Dc, rest as RestTimer) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var radius = (w < h ? w : h) / 2 - RING_MARGIN;
        var cx = w / 2;
        var cy = h / 2;
        var sweep = (360.0 * (1.0 - rest.progress())).toNumber();

        dc.setPenWidth(Device.stroke(27));
        dc.setColor(Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, radius);
        if (rest.duration() > 0 && sweep > 0) {
            dc.setColor(Theme.colorAccent(), Graphics.COLOR_TRANSPARENT);
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

    //! UP / DOWN page, the same way they do on the exercise screen.
    public function onPreviousPage() as Boolean {
        AppController.instance().turnRestPage(-1);
        WatchUi.requestUpdate();
        return true;
    }

    public function onNextPage() as Boolean {
        AppController.instance().turnRestPage(1);
        WatchUi.requestUpdate();
        return true;
    }

    public function onMenu() as Boolean {
        RestActionsMenu.show();
        return true;
    }

    //! BACK — rest is over, the same as START.
    //!
    //! Two buttons for one action, deliberately. BACK is LAP, and LAP during a
    //! Garmin activity moves to the next thing; START is where this app had it
    //! before. Neither is wrong and an athlete mid-session should not have to
    //! remember which.
    //!
    //! The exercise list, which BACK used to open, is on MENU — one press
    //! further, and it no longer competes with the gesture for "done".
    public function onBack() as Boolean {
        AppController.instance().endRest();
        return true;
    }
}

//! What you can do to a rest that is already running.
//!
//! This exists because UP and DOWN now page. Everything here was reachable
//! before; it is reachable in one more press and, in exchange, the two buttons
//! an athlete presses most mean the same thing on every screen in the app.
module RestActionsMenu {

    const ACTION_ADD = "add";
    const ACTION_SUB = "sub";
    const ACTION_SKIP = "skip";
    const ACTION_END = "end";
    const ACTION_MODE = "mode";
    const ACTION_OVERVIEW = "overview";

    public function show() as Void {
        var rest = AppController.instance().restTimer();
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(Rez.Strings.Rest) as String
        });
        // The exercise list first: it is what this menu is opened for most,
        // now that BACK means "rest is over" rather than "show me the list".
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.Exercises) as String, null,
            ACTION_OVERVIEW, {}));
        // Switch the rest between a countdown and an open clock from here, not
        // only from the settings screen: which one you want is a decision about
        // the gym you are standing in, and it changes between sets.
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.RestMode) as String,
            AppSettingsMenu.restModeLabel(), ACTION_MODE, {}));
        // Adding and removing time is meaningless without a target, so an open
        // rest does not offer it. An entry that does nothing is worse than one
        // that is not there.
        if (!rest.isOpen()) {
            // The current duration is the subtitle, so the menu answers "how
            // long is this rest" before the athlete has changed anything.
            menu.addItem(new WatchUi.MenuItem(
                "+ " + Tuning.REST_STEP.toString() + " s",
                Theme.formatDuration(rest.duration()), ACTION_ADD, {}));
            menu.addItem(new WatchUi.MenuItem(
                "- " + Tuning.REST_STEP.toString() + " s", null, ACTION_SUB, {}));
        }
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SkipRest) as String, null, ACTION_SKIP, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.ActionEndWorkout) as String, null,
            ACTION_END, {}));
        WatchUi.switchToView(menu, new RestActionsDelegate(), WatchUi.SLIDE_UP);
    }
}

class RestActionsDelegate extends WatchUi.Menu2InputDelegate {

    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var controller = AppController.instance();
        var id = item.getId() as String;

        if (id.equals(RestActionsMenu.ACTION_ADD)) {
            controller.restTimer().extend(Tuning.REST_STEP);
            // Straight back to the countdown: adding time is a thing you do
            // while watching the number it changes.
            _back();
            return;
        }
        if (id.equals(RestActionsMenu.ACTION_SUB)) {
            controller.restTimer().extend(-Tuning.REST_STEP);
            _back();
            return;
        }
        if (id.equals(RestActionsMenu.ACTION_OVERVIEW)) {
            WatchUi.switchToView(new WorkoutOverviewView(),
                new WorkoutOverviewDelegate(), WatchUi.SLIDE_LEFT);
            return;
        }
        if (id.equals(RestActionsMenu.ACTION_MODE)) {
            controller.switchRestMode();
            _back();
            return;
        }
        if (id.equals(RestActionsMenu.ACTION_SKIP)) {
            controller.endRest();
            return;
        }
        if (id.equals(RestActionsMenu.ACTION_END)) {
            EndWorkoutFlow.request();
            return;
        }
    }

    public function onBack() as Void {
        _back();
    }

    private function _back() as Void {
        WatchUi.switchToView(new RestView(), new RestDelegate(), WatchUi.SLIDE_DOWN);
    }
}
