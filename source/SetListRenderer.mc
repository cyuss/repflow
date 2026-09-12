import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! The exercise as a list of its sets — the Hevy-on-Apple-Watch model.
//!
//!   ┌──────────────────────┐
//!   │     Lat Pulldown     │
//!   │ ──────────────────── │
//!   │  ✓ 1    10 × 55      │   done      (green)
//!   │  ✓ 2    10 × 55      │
//!   │ ▸ 3     10 × 57.5    │   active    (accent, outlined)
//!   │   4     10 × 57.5    │   upcoming  (dim)
//!   │ ──────────────────── │
//!   │       LOG SET        │
//!   └──────────────────────┘
//!
//! Why a list rather than one big "current set" panel: it answers the two
//! questions an athlete actually has mid-exercise — what did I just lift, and
//! how many sets are left — without pressing anything. A single-set panel
//! answers neither.
//!
//! There is no cursor to move. The **active set is always the next incomplete
//! one**, so START logs it and the list advances on its own, exactly as Hevy
//! does. That keeps the one-press promise intact.
//!
//! Rows are windowed around the active set, so an exercise with more sets than
//! fit still shows the one that matters plus its neighbours.
module SetListRenderer {

    //! Draw the set list between `top` and `bottom`.
    public function draw(
        dc as Graphics.Dc,
        top as Number,
        bottom as Number,
        exercise as Exercise,
        pendingReps as Number,
        pendingWeight as Float
    ) as Void {
        var total = exercise.targetSets;
        var done = exercise.completedSetCount();
        // Past the target the athlete is adding extra sets; show them too.
        if (done >= total) {
            total = done + 1;
        }

        var available = bottom - top;
        var rowHeight = _rowHeight(dc, available, total);
        var visible = available / rowHeight;
        if (visible < 1) {
            visible = 1;
        }
        if (visible > total) {
            visible = total;
        }

        var first = _windowStart(done, total, visible);
        var y = top + (available - visible * rowHeight) / 2;

        for (var i = first; i < first + visible && i < total; i++) {
            _drawRow(dc, y, rowHeight, exercise, i, done, pendingReps, pendingWeight);
            y += rowHeight;
        }
    }

    //! Rows large enough to read, but never so large that fewer than three fit
    //! when there are three or more sets.
    function _rowHeight(dc as Graphics.Dc, available as Number, total as Number) as Number {
        var comfortable = dc.getFontHeight(Graphics.FONT_SMALL) + available / 24;
        var needed = total > 0 ? available / total : available;
        var height = needed < comfortable ? needed : comfortable;
        var minimum = dc.getFontHeight(Graphics.FONT_XTINY) + 2;
        return height < minimum ? minimum : height;
    }

    //! Keep the active set in view, with context above and below it.
    function _windowStart(active as Number, total as Number, visible as Number) as Number {
        if (total <= visible) {
            return 0;
        }
        var start = active - visible / 2;
        if (start < 0) {
            start = 0;
        }
        if (start + visible > total) {
            start = total - visible;
        }
        return start;
    }

    function _drawRow(
        dc as Graphics.Dc,
        y as Number,
        height as Number,
        exercise as Exercise,
        index as Number,
        done as Number,
        pendingReps as Number,
        pendingWeight as Float
    ) as Void {
        var isDone = index < done;
        var isActive = index == done;

        var width = Theme.usableWidth(dc, y + height / 2);
        var left = (dc.getWidth() - width) / 2;

        var reps = pendingReps;
        var weight = pendingWeight;
        if (isDone) {
            var set = exercise.sets[index];
            var actualReps = set.actualReps;
            var actualWeight = set.actualWeight;
            if (actualReps != null) {
                reps = actualReps;
            }
            if (actualWeight != null) {
                weight = actualWeight;
            }
        }

        var color = Theme.COLOR_SKIPPED;
        if (isDone) {
            color = Theme.COLOR_DONE;
        } else if (isActive) {
            color = Theme.COLOR_ACCENT;
        }

        // The active row is outlined rather than filled: an outline keeps the
        // text at full contrast, which matters on an 8-bit MIP display.
        if (isActive) {
            dc.setColor(Theme.COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(left, y + 1, width, height - 2, (height - 2) / 2);
        }

        var font = isActive ? Graphics.FONT_SMALL : Graphics.FONT_XTINY;
        if (dc.getFontHeight(font) > height - 2) {
            font = Graphics.FONT_XTINY;
        }
        var textY = y + (height - dc.getFontHeight(font)) / 2;
        var padding = width / 12;

        // Left: a status glyph and the set number.
        var marker = isDone ? "+" : (index + 1).toString();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + padding, textY, font, marker, Graphics.TEXT_JUSTIFY_LEFT);

        // Right: what was lifted, or what is planned.
        var detail = reps.toString() + " x " + Theme.formatWeight(weight);
        dc.setColor(isDone ? Theme.COLOR_DIM : (isActive ? Theme.COLOR_TEXT : Theme.COLOR_SKIPPED),
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + width - padding, textY, font, detail, Graphics.TEXT_JUSTIFY_RIGHT);
    }
}
