import Toybox.Lang;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Math;

//! Shared drawing constants and layout helpers.
//!
//! RepFlow draws its screens in code rather than from XML layouts: the screens
//! are simple, and code scales cleanly from a 240x240 Fenix 6 Pro to a 466x466
//! Fenix 9 Pro 51 mm without a per-device layout file for each one.
//!
//! Everything here places text from a *measured* cursor rather than from fixed
//! percentage positions, so two lines can never collide or crowd each other on a
//! screen size that was not anticipated. Each draw call returns the y coordinate
//! just below what it drew; callers add the gap they want.
module Theme {

    const COLOR_BG = Graphics.COLOR_BLACK;
    const COLOR_TEXT = Graphics.COLOR_WHITE;
    const COLOR_DIM = Graphics.COLOR_LT_GRAY;
    const COLOR_ACCENT = 0x00A8E8;      // RepFlow blue
    const COLOR_DONE = Graphics.COLOR_GREEN;
    const COLOR_PENDING = Graphics.COLOR_ORANGE;
    const COLOR_SKIPPED = Graphics.COLOR_DK_GRAY;
    const COLOR_HR = 0xFF4444;

    //! Colour used for an exercise state in lists and headers.
    public function stateColor(state as ExerciseState) as Number {
        switch (state) {
            case EX_COMPLETED:
                return COLOR_DONE;
            case EX_ACTIVE:
                return COLOR_ACCENT;
            case EX_PENDING:
                return COLOR_PENDING;
            case EX_SKIPPED:
                return COLOR_SKIPPED;
            default:
                return COLOR_DIM;
        }
    }

    // ------------------------------------------------------------------
    // Font ladders, largest first. pickFont walks down until the text fits.
    // Built on demand rather than held as module constants so they cost no
    // memory on screens that do not use them.
    // ------------------------------------------------------------------

    public function fontsHero() as Array<Graphics.FontDefinition> {
        return [
            Graphics.FONT_NUMBER_THAI_HOT,
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_MILD
        ] as Array<Graphics.FontDefinition>;
    }

    public function fontsBig() as Array<Graphics.FontDefinition> {
        return [
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_MILD,
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM
        ] as Array<Graphics.FontDefinition>;
    }

    public function fontsTitle() as Array<Graphics.FontDefinition> {
        return [
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ] as Array<Graphics.FontDefinition>;
    }

    public function fontsBody() as Array<Graphics.FontDefinition> {
        return [
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ] as Array<Graphics.FontDefinition>;
    }

    public function fontsLabel() as Array<Graphics.FontDefinition> {
        return [
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ] as Array<Graphics.FontDefinition>;
    }

    // ------------------------------------------------------------------
    // Layout primitives
    // ------------------------------------------------------------------

    public function clear(dc as Graphics.Dc) as Void {
        dc.setColor(COLOR_TEXT, COLOR_BG);
        dc.clear();
    }

    //! Widest usable width at a given vertical position.
    //!
    //! On a round screen the usable width narrows towards the top and bottom,
    //! so a line that fits at the centre will clip against the bezel near the
    //! edges. This returns the chord of the display at that height, inset by a
    //! margin.
    public function usableWidth(dc as Graphics.Dc, y as Number) as Number {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cy = h / 2;
        if (cy <= 0) {
            return w;
        }
        var dy = (y - cy).abs().toFloat() / cy.toFloat();
        if (dy > 0.92) {
            dy = 0.92;
        }
        var chord = w * Math.sqrt(1.0 - dy * dy);
        return (chord * 0.92).toNumber();
    }

    //! Pick the largest font from a ladder whose rendering fits `maxWidth`.
    public function pickFont(
        dc as Graphics.Dc,
        text as String,
        fonts as Array<Graphics.FontDefinition>,
        maxWidth as Number
    ) as Graphics.FontDefinition {
        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getTextWidthInPixels(text, fonts[i]) <= maxWidth) {
                return fonts[i];
            }
        }
        return fonts[fonts.size() - 1];
    }

    //! Draw centred text with its TOP at `y`. Returns the y just below it.
    public function drawFitted(
        dc as Graphics.Dc,
        y as Number,
        text as String,
        fonts as Array<Graphics.FontDefinition>,
        color as Number
    ) as Number {
        var font = pickFont(dc, text, fonts, usableWidth(dc, y));
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        return y + dc.getFontHeight(font);
    }

    //! A big number with its unit set alongside it and bottom-aligned to the
    //! number, rather than floating underneath it:
    //!
    //!      55 kg
    //!
    //! Returns the y just below the number.
    public function drawValueWithUnit(
        dc as Graphics.Dc,
        y as Number,
        value as String,
        unit as String,
        fonts as Array<Graphics.FontDefinition>,
        valueColor as Number,
        unitColor as Number
    ) as Number {
        var maxWidth = usableWidth(dc, y);
        var unitFont = Graphics.FONT_TINY;
        var unitText = unit.length() > 0 ? " " + unit : "";
        var unitWidth = unitText.length() > 0
            ? dc.getTextWidthInPixels(unitText, unitFont)
            : 0;

        var valueFont = pickFont(dc, value, fonts, maxWidth - unitWidth);
        var valueWidth = dc.getTextWidthInPixels(value, valueFont);
        var valueHeight = dc.getFontHeight(valueFont);

        var left = (dc.getWidth() - (valueWidth + unitWidth)) / 2;
        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, y, valueFont, value, Graphics.TEXT_JUSTIFY_LEFT);

        if (unitText.length() > 0) {
            var unitHeight = dc.getFontHeight(unitFont);
            // Sit the unit near the number's baseline, not its bounding box.
            var unitY = y + valueHeight - unitHeight - (valueHeight / 8);
            dc.setColor(unitColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(left + valueWidth, unitY, unitFont, unitText,
                Graphics.TEXT_JUSTIFY_LEFT);
        }
        return y + valueHeight;
    }

    //! A labelled metric row — dim label on the left, value on the right:
    //!
    //!   HEART RATE              132
    public function drawMetricRow(
        dc as Graphics.Dc,
        y as Number,
        label as String,
        value as String,
        valueColor as Number
    ) as Number {
        var w = dc.getWidth();
        var labelFont = Graphics.FONT_XTINY;
        var labelHeight = dc.getFontHeight(labelFont);
        var maxWidth = usableWidth(dc, y + labelHeight / 2);
        var left = (w - maxWidth) / 2;

        var valueFont = pickFont(dc, value, fontsBody(), (maxWidth * 55) / 100);
        var valueHeight = dc.getFontHeight(valueFont);
        var rowHeight = labelHeight > valueHeight ? labelHeight : valueHeight;

        dc.setColor(COLOR_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, y + (rowHeight - labelHeight) / 2, labelFont, label,
            Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + maxWidth, y + (rowHeight - valueHeight) / 2, valueFont, value,
            Graphics.TEXT_JUSTIFY_RIGHT);

        return y + rowHeight;
    }

    //! The one dominant action, in a rounded band across the bottom.
    //! Returns the y of the top of the band, so callers know where content ends.
    public function drawActionBar(dc as Graphics.Dc, text as String, color as Number) as Number {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var font = Graphics.FONT_XTINY;
        var fh = dc.getFontHeight(font);
        var padding = (h / 40) + 4;
        var barHeight = fh + padding * 2;
        var top = h - barHeight - (h / 16);
        var barWidth = usableWidth(dc, top + barHeight / 2);

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((w - barWidth) / 2, top, barWidth, barHeight, barHeight / 2);
        dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, top + padding, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        return top;
    }

    //! Garmin-style page indicator down the right edge.
    public function drawPageDots(dc as Graphics.Dc, count as Number, active as Number) as Void {
        if (count <= 1) {
            return;
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var spacing = (h / 24).toNumber();
        if (spacing < 10) {
            spacing = 10;
        }
        var radius = spacing / 4;
        if (radius < 2) {
            radius = 2;
        }
        var x = w - (w / 22) - radius;
        var startY = h / 2 - ((count - 1) * spacing) / 2;
        for (var i = 0; i < count; i++) {
            dc.setColor(i == active ? COLOR_ACCENT : COLOR_SKIPPED, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, startY + i * spacing, i == active ? radius + 1 : radius);
        }
    }

    //! One dot per target set, filled once performed. Glanceable progress.
    //! Returns the y just below the row.
    public function drawSetDots(
        dc as Graphics.Dc,
        y as Number,
        total as Number,
        done as Number
    ) as Number {
        if (total <= 0 || total > 12) {
            return y;
        }
        var spacing = (dc.getWidth() / 16).toNumber();
        if (spacing < 11) {
            spacing = 11;
        }
        var radius = spacing / 3;
        var startX = dc.getWidth() / 2 - ((total - 1) * spacing) / 2;
        for (var i = 0; i < total; i++) {
            if (i < done) {
                dc.setColor(COLOR_DONE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(startX + i * spacing, y + radius, radius);
            } else {
                dc.setColor(COLOR_SKIPPED, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(startX + i * spacing, y + radius, radius);
            }
        }
        return y + radius * 2;
    }

    // ------------------------------------------------------------------
    // Formatting
    // ------------------------------------------------------------------

    //! Format a weight without a pointless trailing ".0": 55 / 57.5
    public function formatWeight(weight as Float) as String {
        // Work in tenths as integers: Math.floor/round return Double, and
        // comparing those against a Float trips the type checker.
        var tenths = Math.round(weight * 10.0).toNumber();
        var whole = tenths / 10;
        var frac = tenths % 10;
        if (frac == 0) {
            return whole.toString();
        }
        return whole.toString() + "." + frac.toString();
    }

    //! "1:05:23" or "42:07"
    public function formatDuration(seconds as Number) as String {
        var h = seconds / 3600;
        var m = (seconds % 3600) / 60;
        var s = seconds % 60;
        if (h > 0) {
            return h.format("%d") + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.format("%d") + ":" + s.format("%02d");
    }

    //! Large volumes read better without every digit: 3.2 t above a tonne.
    public function formatVolume(kg as Float) as String {
        if (kg >= 1000.0) {
            var tenths = Math.round(kg / 100.0).toNumber();
            return (tenths / 10).toString() + "." + (tenths % 10).toString() + " t";
        }
        return formatWeight(kg) + " kg";
    }
}
