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
    //! RepFlow blue. Chosen from Garmin's 64-colour palette (each channel one of
    //! 00/55/AA/FF) so it renders identically on an 8-bit MIP display like the
    //! Fenix 6 Pro instead of being snapped to an approximate neighbour.
    const COLOR_ACCENT = 0x00AAFF;
    const COLOR_DONE = Graphics.COLOR_GREEN;
    const COLOR_PENDING = Graphics.COLOR_ORANGE;
    const COLOR_SKIPPED = Graphics.COLOR_DK_GRAY;
    //! Also a palette colour, for the same reason.
    const COLOR_HR = 0xFF5555;
    //! Energy / calories.
    const COLOR_WARM = 0xFFAA00;
    //! Completed work.
    const COLOR_DONE_DIM = 0x00AA55;

    //! Colour used for an exercise state in lists and headers.
    public function stateColor(state as ExerciseState) as Number {
        switch (state) {
            case EX_COMPLETED:
                return COLOR_DONE;
            case EX_ACTIVE:
                return COLOR_WARM;
            case EX_PENDING:
                return COLOR_PENDING;
            case EX_SKIPPED:
                return COLOR_SKIPPED;
            default:
                return COLOR_DIM;
        }
    }

    //! The font small captions are set in.
    //!
    //! Garmin lets the wearer scale system text, and RepFlow cannot simply obey:
    //! it measures its own space and picks the largest font that fits, so there
    //! is nothing left to scale up on the big numbers. The captions are the part
    //! that *is* fixed, so they are the part that answers the setting — one step
    //! up when the wearer has asked for larger text.
    //!
    //! Callers pass the result through the same fitting arithmetic as before, so
    //! a caption that no longer leaves room for its value simply loses the
    //! contest and the value keeps the cell.
    public function captionFont() as Graphics.FontDefinition {
        return Device.fontScale() >= 1.2 ? Graphics.FONT_TINY : Graphics.FONT_XTINY;
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

    //! Ladder for a data field cell. Starts with the big number fonts and keeps
    //! going down into the text fonts, because a four-field layout on a 260x260
    //! screen leaves a band too short for even the smallest number font — and a
    //! value that does not fit its cell is worse than a smaller one.
    public function fontsCell() as Array<Graphics.FontDefinition> {
        return [
            Graphics.FONT_NUMBER_THAI_HOT,
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_MILD,
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
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
        // 0.88, not 0.92: at 0.92 text sat right against the curve of the glass.
        return (chord * 0.88).toNumber();
    }

    //! Usable width of a horizontal BAND, as opposed to a single line.
    //!
    //! A band spans a range of heights and the circle narrows towards its ends,
    //! so the safe width is the chord at whichever edge is furthest from the
    //! vertical centre. Using the chord at the band's middle is what pushed the
    //! action pill out past the bezel.
    public function bandWidth(dc as Graphics.Dc, top as Number, height as Number) as Number {
        var atTop = usableWidth(dc, top);
        var atBottom = usableWidth(dc, top + height);
        return atTop < atBottom ? atTop : atBottom;
    }

    //! Pick the largest font from a ladder whose rendering fits `maxWidth`.
    public function pickFont(
        dc as Graphics.Dc,
        text as String,
        fonts as Array<Graphics.FontDefinition>,
        maxWidth as Number
    ) as Graphics.FontDefinition {
        return pickFontFitting(dc, text, fonts, maxWidth, 0);
    }

    //! Pick the largest font that fits BOTH a width and a height budget.
    //!
    //! Width alone is not enough. A 260x260 Fenix 6 Pro has plenty of room
    //! across for a huge number font but nowhere near enough down the screen,
    //! so a width-only choice overflows whatever sits below it. Pass
    //! `maxHeight` 0 to ignore the height constraint.
    public function pickFontFitting(
        dc as Graphics.Dc,
        text as String,
        fonts as Array<Graphics.FontDefinition>,
        maxWidth as Number,
        maxHeight as Number
    ) as Graphics.FontDefinition {
        for (var i = 0; i < fonts.size(); i++) {
            var font = fonts[i];
            if (dc.getTextWidthInPixels(text, font) > maxWidth) {
                continue;
            }
            if (maxHeight > 0 && dc.getFontHeight(font) > maxHeight) {
                continue;
            }
            return font;
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
        return drawValueWithUnitCapped(dc, y, value, unit, fonts, valueColor, unitColor, 0);
    }

    //! As drawValueWithUnit, but the number may not exceed `maxHeight` pixels
    //! (0 for no limit). Use this whenever something is drawn below it.
    public function drawValueWithUnitCapped(
        dc as Graphics.Dc,
        y as Number,
        value as String,
        unit as String,
        fonts as Array<Graphics.FontDefinition>,
        valueColor as Number,
        unitColor as Number,
        maxHeight as Number
    ) as Number {
        var maxWidth = usableWidth(dc, y);
        var unitFont = Graphics.FONT_TINY;
        var unitText = unit.length() > 0 ? " " + unit : "";
        var unitWidth = unitText.length() > 0
            ? dc.getTextWidthInPixels(unitText, unitFont)
            : 0;

        var valueFont = pickFontFitting(dc, value, fonts, maxWidth - unitWidth, maxHeight);
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

    //! The one dominant action, as a pill across the bottom.
    //!
    //! Returns the y of the top of the pill, so callers know where their content
    //! has to stop.
    public function drawActionBar(dc as Graphics.Dc, text as String, color as Number) as Number {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var font = Graphics.FONT_XTINY;
        var fh = dc.getFontHeight(font);
        var padding = (h / 40) + 4;
        var barHeight = fh + padding * 2;
        var top = h - barHeight - (h * 13) / 100;

        // Width at the pill's NARROWEST edge — its bottom. Measuring at the
        // middle let the corners run past the glass.
        var maxWidth = bandWidth(dc, top, barHeight);

        // Never let the label overflow the pill: shrink it, then the pill hugs
        // the text rather than spanning the whole chord.
        var label = text;
        var textWidth = dc.getTextWidthInPixels(label, font);
        var hPadding = barHeight / 2;
        if (textWidth + hPadding * 2 > maxWidth) {
            label = text;   // FONT_XTINY is already the smallest sensible size
        }
        var barWidth = textWidth + hPadding * 2;
        if (barWidth > maxWidth) {
            barWidth = maxWidth;
        }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((w - barWidth) / 2, top, barWidth, barHeight, barHeight / 2);
        dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, top + padding, font, label, Graphics.TEXT_JUSTIFY_CENTER);
        return top;
    }

    //! A small heart, drawn rather than typed.
    //!
    //! Garmin's own activity screens put the heart rate behind a heart glyph.
    //! U+2665 is not in the Fenix 6 Pro's font set (it renders as a "?" box, the
    //! same trap as the overview's tick marks), so it is drawn from two circles
    //! and a triangle instead.
    public function drawHeart(
        dc as Graphics.Dc,
        cx as Number,
        cy as Number,
        size as Number,
        color as Number
    ) as Void {
        var r = size / 4;
        if (r < 2) {
            r = 2;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - r, cy - r / 2, r);
        dc.fillCircle(cx + r, cy - r / 2, r);
        dc.fillPolygon([
            [cx - r * 2, cy - r / 2],
            [cx + r * 2, cy - r / 2],
            [cx, cy + size / 2]
        ] as Array<[Numeric, Numeric]>);
    }

    //! Colour of a heart rate zone, following Garmin's own scale and taken from
    //! the 64-colour palette so it is exact on a MIP display.
    public function zoneColor(zone as Number?) as Number {
        if (zone == null) {
            return COLOR_SKIPPED;
        }
        switch (zone) {
            case 1: return 0x55AAAA;   // warm-up, teal
            case 2: return COLOR_ACCENT;
            case 3: return COLOR_DONE;
            case 4: return COLOR_WARM;
            case 5: return COLOR_HR;
            default: return COLOR_SKIPPED;
        }
    }

    //! The five-segment heart rate zone bar.
    //!
    //! Each segment carries its own zone's colour rather than all of them
    //! taking the current zone's, so the bar reads as a scale the athlete is
    //! climbing — teal, blue, green, amber, red — and not as a single block
    //! that changes hue. Segments above the current zone are drawn as a thin
    //! baseline: present, so the scale keeps its length, but quiet.
    //!
    //! A null zone means the device has no reading, or the profile has no zone
    //! thresholds. Nothing is filled — the gauge never guesses.
    public function drawZoneBar(
        dc as Graphics.Dc,
        left as Number,
        top as Number,
        width as Number,
        height as Number,
        zone as Number?
    ) as Void {
        var segments = 5;
        var gap = width / 24;
        if (gap < 2) {
            gap = 2;
        }
        var segWidth = (width - gap * (segments - 1)) / segments;
        if (segWidth < 2) {
            return;
        }
        var rest = height / 4;
        if (rest < 2) {
            rest = 2;
        }
        for (var i = 0; i < segments; i++) {
            var x = left + i * (segWidth + gap);
            if (zone != null && i < zone) {
                dc.setColor(zoneColor(i + 1), Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, top, segWidth, height);
            } else {
                dc.setColor(COLOR_SKIPPED, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, top + height - rest, segWidth, rest);
            }
        }
    }

    //! Heart rate as a compact one-line row: a heart, the number, the zone bar.
    //!
    //!   (heart) 132  #####
    //!
    //! Used as a header on the screens whose subject is something else.
    public function drawHeartRateGauge(dc as Graphics.Dc, top as Number) as Number {
        var hr = LiveMetrics.heartRate();
        var zone = LiveMetrics.heartRateZone();
        var font = Graphics.FONT_XTINY;
        var fontHeight = dc.getFontHeight(font);
        var text = LiveMetrics.format(hr);

        var heartSize = (fontHeight * 70) / 100;
        var gap = heartSize / 2;
        var textWidth = dc.getTextWidthInPixels(text, font);
        var barWidth = fontHeight * 3;

        var total = heartSize + gap + textWidth + gap * 2 + barWidth;
        var left = (dc.getWidth() - total) / 2;

        drawHeart(dc, left + heartSize / 2, top + fontHeight / 2, heartSize,
            hr != null ? COLOR_HR : COLOR_SKIPPED);

        dc.setColor(hr != null ? COLOR_TEXT : COLOR_SKIPPED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + heartSize + gap, top, font, text, Graphics.TEXT_JUSTIFY_LEFT);

        var barHeight = (fontHeight * 45) / 100;
        drawZoneBar(dc, left + heartSize + gap + textWidth + gap * 2,
            top + (fontHeight - barHeight) / 2, barWidth, barHeight, zone);
        return top + fontHeight;
    }

    //! Heart rate as a full data field: the number at field size, the zone bar
    //! beneath it, and a caption naming the zone.
    //!
    //!         132          coloured by zone
    //!      ## ## ## - -
    //!        HR  Z3
    //!
    //! This is the one field on the metric page worth more than a number. A
    //! bare "132 / HR" makes the athlete do the arithmetic against thresholds
    //! they cannot see; the bar answers "how hard am I working" at a glance,
    //! which is the actual question mid-set.
    public function drawHeartRateField(
        dc as Graphics.Dc,
        top as Number,
        height as Number,
        caption as String
    ) as Void {
        var hr = LiveMetrics.heartRate();
        var zone = LiveMetrics.heartRateZone();
        var text = LiveMetrics.format(hr);
        var color = hr == null
            ? COLOR_SKIPPED
            : (zone == null ? COLOR_HR : zoneColor(zone));

        var width = bandWidth(dc, top, height);
        var left = (dc.getWidth() - width) / 2;

        var captionFont = Graphics.FONT_XTINY;
        var captionHeight = dc.getFontHeight(captionFont);
        var gap = height / 14;
        var barHeight = height / 9;
        if (barHeight < 4) {
            barHeight = 4;
        }

        var valueArea = height - captionHeight - barHeight - gap * 2;
        if (valueArea < captionHeight) {
            // No room for the full treatment; fall back to a plain field.
            FieldGrid.drawCell(dc, left, top, width, height, text, caption, color);
            return;
        }

        var valueFont = pickFontFitting(dc, text, fontsCell(), (width * 80) / 100, valueArea);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, top + (valueArea - dc.getFontHeight(valueFont)) / 2,
            valueFont, text, Graphics.TEXT_JUSTIFY_CENTER);

        var barWidth = (width * 62) / 100;
        drawZoneBar(dc, (dc.getWidth() - barWidth) / 2, top + valueArea + gap,
            barWidth, barHeight, zone);

        var label = zone != null ? caption + "   Z" + zone.toString() : caption;
        dc.setColor(COLOR_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, top + height - captionHeight, captionFont, label,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! A small minus or plus, drawn from rectangles rather than typed, so it
    //! cannot fall foul of a device's font set.
    public function drawSign(
        dc as Graphics.Dc,
        cx as Number,
        cy as Number,
        size as Number,
        plus as Boolean,
        color as Number
    ) as Void {
        var thickness = size / 4;
        if (thickness < 2) {
            thickness = 2;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - size / 2, cy - thickness / 2, size, thickness);
        if (plus) {
            dc.fillRectangle(cx - thickness / 2, cy - size / 2, thickness, size);
        }
    }

    //! A small labelled field: a value with its caption underneath, both small.
    //! Used for the secondary readouts along the bottom of a screen, the way a
    //! native Garmin activity screen does it.
    public function drawMiniField(
        dc as Graphics.Dc,
        cx as Number,
        top as Number,
        value as String,
        caption as String,
        valueColor as Number
    ) as Number {
        var valueFont = Graphics.FONT_TINY;
        var capFont = captionFont();
        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, top, valueFont, value, Graphics.TEXT_JUSTIFY_CENTER);
        var y = top + dc.getFontHeight(valueFont);
        dc.setColor(COLOR_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, capFont, caption, Graphics.TEXT_JUSTIFY_CENTER);
        return y + dc.getFontHeight(capFont);
    }

    //! Height drawMiniField needs.
    public function miniFieldHeight(dc as Graphics.Dc) as Number {
        return dc.getFontHeight(Graphics.FONT_TINY) + dc.getFontHeight(captionFont());
    }

    //! Time of day, small and dim, in the strip below the action bar.
    //!
    //! Native Garmin activity screens keep the clock there, and on a round
    //! display that strip is otherwise dead space — too narrow for content, too
    //! tall to ignore.
    public function drawClock(dc as Graphics.Dc, top as Number) as Void {
        var now = System.getClockTime();
        var text = now.hour.format("%02d") + ":" + now.min.format("%02d");
        dc.setColor(COLOR_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, top, Graphics.FONT_XTINY, text,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! A ring around the rim showing progress from 0.0 to 1.0.
    //!
    //! The rim is the one area of a round display a field grid cannot use, so it
    //! is free real estate for the single most glanceable thing on the screen —
    //! how far through the exercise, or through the rest, the athlete is.
    public function drawProgressRing(
        dc as Graphics.Dc,
        progress as Float,
        color as Number
    ) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var radius = (w < h ? w : h) / 2 - 5;
        var cx = w / 2;
        var cy = h / 2;

        dc.setPenWidth(5);
        dc.setColor(COLOR_SKIPPED, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, radius);

        if (progress <= 0.0) {
            dc.setPenWidth(1);
            return;
        }
        var capped = progress > 1.0 ? 1.0 : progress;
        var sweep = (360.0 * capped).toNumber();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (sweep >= 360) {
            dc.drawCircle(cx, cy, radius);
        } else {
            // Clockwise from 12 o'clock.
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 90, (90 - sweep + 360) % 360);
        }
        dc.setPenWidth(1);
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
    //! A number to at most one decimal, with no trailing ".0".
    //!
    //! Separate from formatWeight because this half is pure arithmetic and the
    //! other half depends on the athlete's unit setting. Tested directly.
    public function formatNumber(value as Float) as String {
        // Work in tenths as integers: Math.floor/round return Double, and
        // comparing those against a Float trips the type checker.
        var tenths = Math.round(value * 10.0).toNumber();
        var whole = tenths / 10;
        var frac = tenths % 10;
        if (frac == 0) {
            return whole.toString();
        }
        return whole.toString() + "." + frac.toString();
    }

    //! A stored load, in the unit the athlete reads.
    //!
    //! Everything upstream of here is kilograms — FIT, history, the engine —
    //! and the conversion happens once, at the moment it becomes text.
    //!
    //! Reports exactly what is stored. Use it for a load that was **lifted**.
    public function formatWeight(weight as Float) as String {
        return formatNumber(Units.fromKg(weight));
    }

    //! A load the athlete has not lifted yet, on the step grid of their unit.
    //!
    //! A 55 kg template default is 121.3 lb, and a plan offering 121.3 reads as
    //! a measurement rather than a suggestion. Separate from formatWeight
    //! because the distinction is the whole point: a plan may be rounded to
    //! something sensible, a record may not be touched.
    public function formatPlannedWeight(weight as Float) as String {
        return formatNumber(Units.fromKg(Units.snap(weight)));
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
    //! Session volume. Tonnes once it stops fitting, because a strength session
    //! reaches five figures of kilograms quickly and "12450" is unreadable at
    //! arm's length.
    public function formatVolume(kg as Float) as String {
        var shown = Units.fromKg(kg);
        if (shown >= 1000.0) {
            var tenths = Math.round(shown / 100.0).toNumber();
            var big = (tenths / 10).toString() + "." + (tenths % 10).toString();
            // Tonnes in metric, because that is what a tonne is. In pounds
            // there is no such unit, so it stays pounds with a thousands mark —
            // "kilopounds" is not something anybody says in a gym.
            return Units.imperial()
                ? big + "k " + Units.label()
                : big + " t";
        }
        return formatNumber(shown) + " " + Units.label();
    }
}
