import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.System;

//! Edit the weight and the reps of the upcoming set, on one screen.
//!
//!        (heart) 132
//!            SET 2 / 4
//!                +
//!      ┌────────┐ ┌──────┐
//!      │   60   │ │  10  │
//!      │   KG   │ │ REPS │
//!      └────────┘ └──────┘
//!                -
//!      RPE  ▮▮▮▮▮▯▯▯   8.5
//!            ● ● ○ ○
//!
//! **The RPE row is only there while confirming a set**, because an effort
//! rating is something you give a set you have done, not a target you set for
//! one you have not. Planning a set shows two fields; confirming one shows
//! three.
//!
//! It costs no presses. START still logs in one, from any field — the athlete
//! who does not rate sets never touches it, and an unrated set records no
//! rating rather than a middling one.
//!
//! The focused cell is outlined in the accent colour; UP/DOWN change it, START
//! moves on and confirms on the last one, BACK steps back. That is exactly the
//! interaction model of `WatchUi.Picker`, which is what a Garmin owner expects.
//!
//! The + and - sit above and below the focused cell because that is where the
//! buttons are: press the top button, the number goes up. They are drawn from
//! rectangles rather than typed, so no device's font set can turn them into
//! "?" boxes — the Fenix 6 Pro did exactly that to Unicode glyphs.
//!
//! There is no line of button hints. "START LOG - BACK SWAP" told the athlete
//! what the two signs and the outline already say, and it cost the values the
//! height they needed. The exercise name is gone for the same reason: the screen
//! underneath is showing it.
//!
//! It is *not* built on Picker, and that is deliberate: a three-column Picker
//! does not fit a 260x260 screen — the reps column rendered off the right edge —
//! and its own theming painted the background white over ours. Verified in the
//! simulator. Drawing it here costs one small view and renders correctly on
//! every target.
class SetEditorView extends WatchUi.View {

    private var _exercise as Exercise;
    private var _focus as Number;
    private var _returnTo as Number;
    private var _mode as Number;
    //! System.getTimer() at the last load adjustment, for hold detection.
    private var _lastAdjustMs as Number;
    //! How many presses into the current hold we are. Resets on any pause.
    private var _heldPresses as Number;

    public function initialize(exercise as Exercise, returnTo as Number, mode as Number) {
        View.initialize();
        _exercise = exercise;
        _returnTo = returnTo;
        _mode = mode;
        _lastAdjustMs = 0;
        _heldPresses = 0;
        // Confirming a set starts on the reps: the load is usually what was
        // planned, the reps are what actually came out.
        _focus = mode == Tuning.EDITOR_CONFIRM_LOG
            ? Tuning.FOCUS_REPS
            : Tuning.FOCUS_WEIGHT;
    }

    //! How many steps this press should move the load.
    private function _coarseFactor() as Number {
        var ramp = Tuning.COARSE_STEPS;
        var at = _heldPresses;
        if (at >= ramp.size()) {
            at = ramp.size() - 1;
        }
        return ramp[at];
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
    //!
    //! Presses arriving faster than a person taps are a held button, and the
    //! load accelerates — but gradually. The multiplier walks up
    //! Tuning.COARSE_STEPS, so the first repeat still moves one step and the
    //! athlete feels it build. Jumping straight to five meant two accidental
    //! quick presses added ten kilos to the bar.
    //!
    //! Only the load accelerates. Reps live between about 1 and 30, where a
    //! multiplied jump overshoots more often than it helps.
    public function adjust(direction as Number) as Void {
        var controller = AppController.instance();
        if (_focus == Tuning.FOCUS_RPE) {
            controller.adjustRpe(direction);
            _lastAdjustMs = 0;
            _heldPresses = 0;
            WatchUi.requestUpdate();
            return;
        }
        if (_focus == Tuning.FOCUS_REPS) {
            controller.adjustReps(direction);
            _lastAdjustMs = 0;
            _heldPresses = 0;
        } else {
            var now = System.getTimer();
            var held = _lastAdjustMs != 0 &&
                (now - _lastAdjustMs) < Tuning.COARSE_WINDOW_MS;
            _lastAdjustMs = now;
            // A gap resets the ramp, so a deliberate single press is always a
            // single step however fast the last burst was.
            _heldPresses = held ? _heldPresses + 1 : 0;
            controller.adjustWeight(direction * _coarseFactor());
        }
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var controller = AppController.instance();
        var h = dc.getHeight();
        var confirming = _mode == Tuning.EDITOR_CONFIRM_LOG;

        // The live zone gauge takes the line the exercise name used to have.
        // The name is on the screen this one slid up from; the heart rate is
        // not, and mid-set it is the one number worth a glance.
        // Larger than the exercise screen's: this screen has the room, and at
        // the top of a round display a caption-sized reading is unreadable.
        var y = Theme.drawHeartRateGaugeAt(dc, h / 14, Graphics.FONT_TINY);

        var title = confirming
            ? (WatchUi.loadResource(Rez.Strings.SetLabel) as String).toUpper() + " " +
                _exercise.currentSetNumber().toString() + " / " +
                _exercise.targetSets.toString()
            : WatchUi.loadResource(Rez.Strings.NextSet) as String;
        y = Theme.drawFitted(dc, y + h / 60, title,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.colorAccent());

        // Sets done so far, as dots: the progression, without a sentence.
        Theme.drawSetDots(dc, h - h / 9, _exercise.targetSets,
            _exercise.completedSetCount());

        // A band for the + above the cells and one for the - below them.
        //
        // A ninth of the screen each, for a sign drawn at half that. The two
        // of them were taking a fifth of the page to hold two small marks,
        // and the cost landed on the values between them: a cell that loses
        // eighteen pixels loses a font size, and this is the screen where the
        // athlete is looking straight at the number they are changing.
        var signBand = h / 11;
        var bottom = h - h / 6;
        var cellsTop = y + signBand;
        var cellsBottom = bottom - signBand;

        // Confirming a set gives up a slice of the cells to the effort row.
        // Planning one keeps the whole band, because there is nothing to rate.
        var rpeHeight = confirming ? (h * 13) / 100 : 0;
        cellsBottom -= rpeHeight;

        var focusCx = _drawCells(dc, cellsTop, cellsBottom, controller);

        var signSize = (signBand * 62) / 100;
        Theme.drawSign(dc, focusCx, y + signBand / 2, signSize, true, Theme.colorAccent());
        Theme.drawSign(dc, focusCx, cellsBottom + signBand / 2, signSize, false,
            Theme.colorAccent());

        if (confirming) {
            _drawRpe(dc, bottom - rpeHeight, rpeHeight, controller.pendingRpe());
        }
    }

    //! The effort row: a label, a ladder, and the number.
    //!
    //!      RPE   ▁▂▃▄▅▆▇█   8.5
    //!
    //! A ladder rather than a third boxed cell. Two cells with one more below
    //! them is a grid with a widow in it, and RPE is not the same kind of thing
    //! as a load or a rep count: those are measurements, this is a judgement on
    //! a fixed ladder of eight rungs. A bar shows which rung — the actual
    //! question — and a bare number does not.
    //!
    //! Three things do the work:
    //!
    //!   * the bars **grow from a common baseline**, so the ladder reads as a
    //!     climb. Centred bars of rising height read as a pile instead;
    //!   * their ends are **rounded**, which at eight pixels wide is the whole
    //!     difference between a designed mark and a row of teeth;
    //!   * the colour **climbs with the effort** — accent through warm to hot —
    //!     so RPE 9.5 is not the same blue as RPE 7. That is the same language
    //!     the heart rate zones already speak on the metrics page.
    private function _drawRpe(
        dc as Graphics.Dc,
        top as Number,
        height as Number,
        value as Float?
    ) as Void {
        var focused = _focus == Tuning.FOCUS_RPE;
        var band = Theme.bandWidth(dc, top, height);
        var outline = (dc.getWidth() - band) / 2;

        // The outline is the field; the content sits inside it with air on
        // either side. Text hard against a border reads as an overflow.
        var pad = band / 14;
        var left = outline + pad;
        var width = band - pad * 2;

        var font = Graphics.FONT_XTINY;
        var fontHeight = dc.getFontHeight(font);
        var textTop = top + (height - fontHeight) / 2;

        var label = WatchUi.loadResource(Rez.Strings.FieldRpe) as String;
        var labelWidth = dc.getTextWidthInPixels(label, font);
        // Reserve the widest reading, so the ladder does not shuffle sideways
        // as the rating goes from "8" to "8.5".
        var valueWidth = dc.getTextWidthInPixels("10.5", font);
        var gap = width / 12;
        var tint = Rpe.color(value);

        dc.setColor(focused ? Theme.colorAccent() : Theme.colorDim(),
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, textTop, font, label, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(tint, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + width, textTop, font, Rpe.format(value),
            Graphics.TEXT_JUSTIFY_RIGHT);

        var ladderLeft = left + labelWidth + gap;
        var ladderWidth = (left + width - valueWidth - gap) - ladderLeft;
        if (ladderWidth > Rpe.size() * 3) {
            _drawLadder(dc, ladderLeft, top + height, ladderWidth, height, value);
        }

        if (focused) {
            // The same outline the focused cell gets, so "this is what UP and
            // DOWN move" means one thing on this screen.
            dc.setPenWidth(3);
            dc.setColor(Theme.colorAccent(), Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(outline, top, band, height, height / 2);
            dc.setPenWidth(1);
        }
    }

    //! One bar per rung, rising from a shared baseline, lit up to the rating.
    private function _drawLadder(
        dc as Graphics.Dc,
        left as Number,
        baseline as Number,
        width as Number,
        height as Number,
        value as Float?
    ) as Void {
        var count = Rpe.size();
        var lit = Rpe.indexOf(value) + 1;    // -1 becomes 0: nothing lit
        var pitch = width / count;
        var barWidth = (pitch * 58) / 100;
        if (barWidth < 2) {
            barWidth = 2;
        }
        var tallest = (height * 58) / 100;
        var shortest = (tallest * 40) / 100;
        var foot = baseline - height / 6;

        for (var i = 0; i < count; i++) {
            var barHeight = shortest + ((tallest - shortest) * i) / (count - 1);
            if (barHeight < 2) {
                barHeight = 2;
            }
            // An unlit rung is still a rung: faint, not absent, so the ladder
            // keeps its length and the lit part is read as a proportion of it.
            dc.setColor(i < lit ? Rpe.colorAt(i) : Theme.colorFaint(),
                Graphics.COLOR_TRANSPARENT);
            Theme.fillBar(dc, left + i * pitch + (pitch - barWidth) / 2,
                foot - barHeight, barWidth, barHeight);
        }
    }

    private function _drawCells(
        dc as Graphics.Dc,
        top as Number,
        bottom as Number,
        controller as AppController
    ) as Number {
        var height = bottom - top;
        if (height <= 0) {
            return dc.getWidth() / 2;
        }
        var width = Theme.bandWidth(dc, top, height);
        var left = (dc.getWidth() - width) / 2;
        var half = width / 2;

        _drawCell(dc, left, top, half, height,
            Theme.formatPlannedWeight(controller.pendingWeight()),
            Units.label().toUpper(),
            _focus == Tuning.FOCUS_WEIGHT);

        _drawCell(dc, left + half, top, half, height,
            controller.pendingReps().toString(),
            WatchUi.loadResource(Rez.Strings.FieldReps) as String,
            _focus == Tuning.FOCUS_REPS);

        // The effort row spans the screen, so its + and - belong on the centre
        // line rather than over one of the two cells.
        if (_focus == Tuning.FOCUS_RPE) {
            return dc.getWidth() / 2;
        }
        return _focus == Tuning.FOCUS_REPS ? left + half + half / 2 : left + half / 2;
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
            dc.setColor(Theme.colorAccent(), Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(x + inset, y, width - inset * 2, height, height / 4);
            dc.setPenWidth(1);
        }
        FieldGrid.drawCell(dc, x, y + pad, width, height - pad * 2, value, caption,
            focused ? Theme.colorText() : Theme.colorDim());
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

    //! BACK cycles the fields: reps -> weight -> effort -> reps.
    //!
    //! Cycling rather than paging, because START logs from wherever you are.
    //! The athlete who never rates a set presses START and is done; the one who
    //! does presses BACK twice. Neither pays for the other.
    public function onBack() as Boolean {
        var focus = _view.focus();
        var next = Tuning.FOCUS_REPS;
        if (focus == Tuning.FOCUS_REPS) {
            next = Tuning.FOCUS_WEIGHT;
        } else if (focus == Tuning.FOCUS_WEIGHT) {
            next = Tuning.FOCUS_RPE;
        }
        _view.setFocus(next);
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
