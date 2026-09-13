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

    //! Two palettes, one meaning each.
    //!
    //! RepFlow was black-on-white from the start, because a MIP screen in a dim
    //! gym reads best that way and an AMOLED spends almost nothing lighting it.
    //! But a watch worn in bright sun is a different problem — a white ground
    //! is far more legible outdoors — so the athlete chooses, and everything
    //! here answers that choice.
    //!
    //! **Every colour is from Garmin's 64-colour palette** — each channel one of
    //! 00, 55, AA or FF — so it renders exactly on an 8-bit MIP display like the
    //! Fenix 6 Pro instead of being snapped to an approximate neighbour. That is
    //! why the light accents are not simply the dark ones darkened by eye.
    //!
    //! They are functions rather than constants because the answer changes with
    //! a setting. `Settings.theme()` caches, so this costs a comparison.

    // Dark: the default. White on black.
    const DARK_BG = Graphics.COLOR_BLACK;
    const DARK_TEXT = Graphics.COLOR_WHITE;
    const DARK_DIM = Graphics.COLOR_LT_GRAY;
    const DARK_FAINT = Graphics.COLOR_DK_GRAY;
    const DARK_ACCENT = 0x00AAFF;
    const DARK_DONE = Graphics.COLOR_GREEN;
    const DARK_PENDING = Graphics.COLOR_ORANGE;
    const DARK_HR = 0xFF5555;
    const DARK_WARM = 0xFFAA00;
    const DARK_DONE_DIM = 0x00AA55;

    // Light: black on white. The accents are darker, not paler — a colour that
    // reads on black is usually invisible on white.
    const LIGHT_BG = Graphics.COLOR_WHITE;
    const LIGHT_TEXT = Graphics.COLOR_BLACK;
    const LIGHT_DIM = 0x555555;
    const LIGHT_FAINT = 0xAAAAAA;
    const LIGHT_ACCENT = 0x0055AA;
    const LIGHT_DONE = 0x00AA00;
    const LIGHT_PENDING = 0xAA5500;
    const LIGHT_HR = 0xAA0000;
    const LIGHT_WARM = 0xAA5500;
    const LIGHT_DONE_DIM = 0x005500;

    public function light() as Boolean {
        return Settings.theme() == Tuning.THEME_LIGHT;
    }

    public function colorBg() as Number {
        return light() ? LIGHT_BG : DARK_BG;
    }

    public function colorText() as Number {
        return light() ? LIGHT_TEXT : DARK_TEXT;
    }

    //! Captions and secondary text.
    public function colorDim() as Number {
        return light() ? LIGHT_DIM : DARK_DIM;
    }

    //! Rules, empty tracks, things not reached. Quiet, never invisible.
    public function colorFaint() as Number {
        return light() ? LIGHT_FAINT : DARK_FAINT;
    }

    public function colorAccent() as Number {
        return light() ? LIGHT_ACCENT : DARK_ACCENT;
    }

    public function colorDone() as Number {
        return light() ? LIGHT_DONE : DARK_DONE;
    }

    public function colorPending() as Number {
        return light() ? LIGHT_PENDING : DARK_PENDING;
    }

    public function colorHr() as Number {
        return light() ? LIGHT_HR : DARK_HR;
    }

    //! Energy / calories.
    public function colorWarm() as Number {
        return light() ? LIGHT_WARM : DARK_WARM;
    }

    //! Completed work.
    public function colorDoneDim() as Number {
        return light() ? LIGHT_DONE_DIM : DARK_DONE_DIM;
    }

    //! Colour used for an exercise state in lists and headers.
    public function stateColor(state as ExerciseState) as Number {
        switch (state) {
            case EX_COMPLETED:
                return colorDone();
            case EX_ACTIVE:
                return colorWarm();
            case EX_PENDING:
                return colorPending();
            case EX_SKIPPED:
                return colorFaint();
            default:
                return colorDim();
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

    //! The caption font, dropped one size when the label will not fit.
    //!
    //! A caption is centred under its value and nothing measured it, so two
    //! captions in a pair grew towards each other until they touched. That was
    //! invisible here and obvious on a watch with large fonts turned on, where
    //! `captionFont` is a size up and "AVG HR" beside "MAX HR" ran together.
    //!
    //! Shrinking rather than clipping: a caption is a word, and half a word is
    //! worse than a small one. There is nothing below XTINY, so a label that
    //! still does not fit is a label that is too long — which is what
    //! testFieldCaptionsFitTheirCells is for.
    public function captionFontFor(
        dc as Graphics.Dc,
        text as String,
        maxWidth as Number
    ) as Graphics.FontDefinition {
        var font = captionFont();
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) {
            return font;
        }
        return Graphics.FONT_XTINY;
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
        dc.setColor(colorText(), colorBg());
        dc.clear();
    }

    //! Widest usable width at a given vertical position.
    //!
    //! On a round screen the usable width narrows towards the top and bottom,
    //! so a line that fits at the centre will clip against the bezel near the
    //! edges. This returns the chord of the display at that height, inset by a
    //! margin.
    public function usableWidth(dc as Graphics.Dc, y as Number) as Number {
        return usableWidthWithin(dc, y, 0);
    }

    //! The same, but bounded by a circle drawn `inset` pixels in from the glass.
    //!
    //! A screen with a full-width ring on it has two edges, not one, and the
    //! inner one is what the text has to respect. The rest screen's countdown
    //! ring is the case this exists for: a scrolling exercise name measured
    //! against the glass ran straight over the ring, which reads as a bug
    //! rather than as a layer.
    //!
    //! `inset` is the distance from the glass to the **inside** of whatever is
    //! drawn there — for a ring, its margin plus half its pen width, plus
    //! however much air the design wants between the two.
    public function usableWidthWithin(
        dc as Graphics.Dc,
        y as Number,
        inset as Number
    ) as Number {
        var w = dc.getWidth() - inset * 2;
        var h = dc.getHeight() - inset * 2;
        var cy = dc.getHeight() / 2;
        if (w <= 0 || h <= 0) {
            return 0;
        }
        var dy = (y - cy).abs().toFloat() / (h / 2).toFloat();
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
    //! How tall a font's ink actually is, as opposed to the line it sits on.
    //!
    //! Garmin's number fonts declare a descent they never use: FONT_NUMBER_MILD
    //! is 60px of line height and 44px of ascent, and digits have nothing below
    //! the baseline, so the last 16px are empty. Measuring a value box against
    //! the line height therefore throws away a quarter of the room and picks a
    //! smaller font than fits — which is why RepFlow's weights were drawn in a
    //! **text** font while the watch's own screens use the number one.
    //!
    //! Only ever call this for values. A label with a "g" or a "y" in it needs
    //! its descent, and a caption measured this way would sit on the rule below.
    public function inkHeight(font as Graphics.FontDefinition) as Number {
        if (Graphics has :getFontAscent) {
            var ascent = Graphics.getFontAscent(font);
            if (ascent > 0) {
                return ascent;
            }
        }
        return Graphics.getFontHeight(font);
    }

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
            // Ink, not line height: this function is only ever asked about
            // values, and a value has no descenders. See inkHeight.
            if (maxHeight > 0 && inkHeight(font) > maxHeight) {
                continue;
            }
            return font;
        }
        return fonts[fonts.size() - 1];
    }

    //! Shorten `text` until it fits `maxWidth`, ending in a dot.
    //!
    //! The dot is the point: a name cut silently is a name that can be misread
    //! — "Incline Bench Pr" looks like a movement someone might have invented —
    //! whereas one that ends in a dot says plainly that there is more of it.
    public function clipToWidth(
        dc as Graphics.Dc,
        text as String,
        font as Graphics.FontDefinition,
        maxWidth as Number
    ) as String {
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) {
            return text;
        }
        var cut = text.length();
        while (cut > 1) {
            cut--;
            var candidate = text.substring(0, cut);
            if (candidate == null) {
                return text;
            }
            var shortened = candidate + ".";
            if (dc.getTextWidthInPixels(shortened, font) <= maxWidth) {
                return shortened;
            }
        }
        return ".";
    }

    //! Centred text at a fixed size, clipped rather than shrunk.
    //!
    //! For a row in a list, where every line has to sit on the same baseline
    //! grid at the same size — `drawFitted` would give each row its own font
    //! and the list would read as a ransom note.
    //!
    //! `cx` is passed rather than taken from the Dc because a menu item's
    //! drawing context is not the screen, and its centre may not be the
    //! screen's centre.
    public function drawClipped(
        dc as Graphics.Dc,
        cx as Number,
        top as Number,
        text as String,
        font as Graphics.FontDefinition,
        color as Number,
        maxWidth as Number
    ) as Number {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, top, font, clipToWidth(dc, text, font, maxWidth),
            Graphics.TEXT_JUSTIFY_CENTER);
        return top + dc.getFontHeight(font);
    }

    //! The same, anchored to a left edge.
    //!
    //! A list is scanned down its left edge: centred rows make every name start
    //! somewhere different, so finding the one you want means reading them all.
    public function drawClippedAt(
        dc as Graphics.Dc,
        left as Number,
        top as Number,
        text as String,
        font as Graphics.FontDefinition,
        color as Number,
        maxWidth as Number
    ) as Number {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, top, font, clipToWidth(dc, text, font, maxWidth),
            Graphics.TEXT_JUSTIFY_LEFT);
        return top + dc.getFontHeight(font);
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

    //! The same, kept inside a circle `inset` pixels in from the glass.
    //!
    //! Two differences from `drawFitted`, both deliberate:
    //!
    //!   * the boundary is the inset circle, not the glass;
    //!   * the line is measured at its **baseline** rather than its top. Below
    //!     the centre the chord narrows as it descends, so the top of a line is
    //!     the widest part of it — measuring there is what lets the bottom of
    //!     the text cross an edge the top cleared.
    //!
    //! `drawFitted` keeps measuring at the top. It is on every screen in the
    //! app and changing how it picks fonts is a separate decision from fixing
    //! the one screen that has a ring on it.
    public function drawFittedWithin(
        dc as Graphics.Dc,
        y as Number,
        text as String,
        fonts as Array<Graphics.FontDefinition>,
        color as Number,
        inset as Number
    ) as Number {
        var tallest = fonts.size() > 0 ? fonts[0] : Graphics.FONT_XTINY;
        var measureAt = y + (dc.getFontHeight(tallest) * 3) / 4;
        var font = pickFont(dc, text, fonts, usableWidthWithin(dc, measureAt, inset));
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

        dc.setColor(colorDim(), Graphics.COLOR_TRANSPARENT);
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
        dc.setColor(colorBg(), Graphics.COLOR_TRANSPARENT);
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
            return colorFaint();
        }
        // Zone 1 is its own colour rather than one of the semantic ones: a
        // warm-up is not "information" and not "done", it is the bottom of the
        // scale. Teal on black, a darker teal on white — a pale one would
        // vanish against it.
        switch (zone) {
            case 1: return light() ? 0x005555 : 0x55AAAA;
            case 2: return colorAccent();
            case 3: return colorDone();
            case 4: return colorWarm();
            case 5: return colorHr();
            default: return colorFaint();
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
        zone as Number?,
        progress as Float?
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
            if (zone == null || i > (zone as Number) - 1) {
                // Not reached: a thin baseline, so the scale keeps its length.
                dc.setColor(colorFaint(), Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, top + height - rest, segWidth, rest);
                continue;
            }

            if (i < (zone as Number) - 1) {
                dc.setColor(zoneColor(i + 1), Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, top, segWidth, height);
                continue;
            }

            // The zone the athlete is actually in, filled as far through it as
            // they are. "Zone 3" spans a wide range of effort and the bottom of
            // it is a different workout from the top; a block that is either on
            // or off cannot say which end you are at.
            var full = progress == null ? 1.0 : progress as Float;
            if (full > 1.0) { full = 1.0; }
            if (full < 0.0) { full = 0.0; }
            var filled = (segWidth.toFloat() * full).toNumber();
            if (filled < 2) {
                filled = 2;      // always visibly in this zone, even at its floor
            }

            dc.setColor(colorFaint(), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, top + height - rest, segWidth, rest);
            dc.setColor(zoneColor(i + 1), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, top, filled, height);
        }
    }

    //! Heart rate as a compact one-line row: a heart, the number, the zone bar.
    //!
    //!   (heart) 132  #####
    //!
    //! The live heart rate as one compact row: a heart, and the number.
    //!
    //!         (heart)  132
    //!
    //! The heart carries the zone in its colour and nothing else does. This
    //! used to also draw a five-segment zone gauge and a "Z3" label, which was
    //! three encodings of one fact sitting above a screen whose job is the set
    //! in front of you. A colour is read without being looked at; a gauge has
    //! to be measured, and mid-set nobody measures anything.
    //!
    //! The full gauge still exists on the metrics page — see
    //! `drawHeartRateField`, where heart rate *is* the subject and there is
    //! room to say more about it.
    //!
    //! Returns the y just below the row.
    public function drawHeartRateGauge(dc as Graphics.Dc, top as Number) as Number {
        var hr = LiveMetrics.heartRate();
        var zone = LiveMetrics.zoneFor(hr);
        var font = Graphics.FONT_XTINY;
        var fontHeight = dc.getFontHeight(font);
        var text = LiveMetrics.format(hr);

        // No reading: grey. A reading but no zone profile: the plain heart
        // colour. Neither case is allowed to imply an effort level.
        var tint = hr == null ? colorFaint() : (zone == null ? colorHr() : zoneColor(zone));

        // Larger than it was, because it is now the only thing carrying the
        // zone. A glyph that has to be found is not a glance.
        var heartSize = (fontHeight * 82) / 100;
        var gap = (heartSize * 55) / 100;
        var textWidth = dc.getTextWidthInPixels(text, font);

        var left = (dc.getWidth() - (heartSize + gap + textWidth)) / 2;

        drawHeart(dc, left + heartSize / 2, top + fontHeight / 2, heartSize, tint);

        dc.setColor(hr != null ? colorText() : colorFaint(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + heartSize + gap, top, font, text, Graphics.TEXT_JUSTIFY_LEFT);

        return top + fontHeight;
    }

    public function drawHeartRateField(
        dc as Graphics.Dc,
        top as Number,
        height as Number,
        caption as String
    ) as Void {
        var hr = LiveMetrics.heartRate();
        var zone = LiveMetrics.zoneFor(hr);
        var progress = LiveMetrics.zoneProgressFor(hr);
        var text = LiveMetrics.format(hr);
        var color = hr == null
            ? colorFaint()
            : (zone == null ? colorHr() : zoneColor(zone));

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
            barWidth, barHeight, zone, progress);

        var label = zone != null ? caption + "   Z" + zone.toString() : caption;
        dc.setColor(colorDim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, top + height - captionHeight, captionFont, label,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! A small minus or plus, drawn from rectangles rather than typed, so it
    //! cannot fall foul of a device's font set.
    //! The "add" mark: a thin ring with a slim cross inside it.
    //!
    //!            ___
    //!          /     \
    //!         |   +   |
    //!          \ ___ /
    //!
    //! The new-workout page used to draw a bare plus at a quarter of its own
    //! size in stroke weight. At that thickness it stops reading as a symbol
    //! and starts reading as two bars, and nothing about it says "press this".
    //!
    //! A ring does. It is the affordance Garmin uses for an action target
    //! across its own menus, it echoes the progress ring and the state icons
    //! this app already draws, and the hairline weight is what separates a
    //! considered mark from a clip-art one. The cross is drawn with rounded
    //! ends for the same reason — square ends at this size look chipped.
    public function drawAddMark(
        dc as Graphics.Dc,
        cx as Number,
        cy as Number,
        size as Number,
        color as Number
    ) as Void {
        var radius = size / 2;
        if (radius < 6) {
            return;
        }
        var pen = size / 16;
        if (pen < 2) {
            pen = 2;
        }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen);
        // Inside the radius, so a thick pen cannot spill past the size asked for.
        dc.drawCircle(cx, cy, radius - pen / 2);
        dc.setPenWidth(1);

        // A third of the diameter. Any longer and the cross crowds the ring;
        // any shorter and it floats in the middle of it.
        var arm = (size * 17) / 100;
        var bar = pen;
        _roundBar(dc, cx - arm, cy - bar / 2, arm * 2, bar);
        _roundBar(dc, cx - bar / 2, cy - arm, bar, arm * 2);
    }

    //! A filled rectangle with rounded ends, falling back to a plain one on a
    //! device without rounded rectangles.
    //!
    //! At the sizes this app draws bars — eight pixels across — the rounding is
    //! the whole difference between a designed mark and a row of teeth.
    public function fillBar(
        dc as Graphics.Dc,
        x as Number,
        y as Number,
        width as Number,
        height as Number
    ) as Void {
        _roundBar(dc, x, y, width, height);
    }

    function _roundBar(
        dc as Graphics.Dc,
        x as Number,
        y as Number,
        width as Number,
        height as Number
    ) as Void {
        var shorter = width < height ? width : height;
        if (shorter >= 4 && dc has :fillRoundedRectangle) {
            dc.fillRoundedRectangle(x, y, width, height, shorter / 2);
            return;
        }
        dc.fillRectangle(x, y, width, height);
    }

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
        dc.setColor(colorDim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, capFont, caption, Graphics.TEXT_JUSTIFY_CENTER);
        return y + dc.getFontHeight(capFont);
    }

    //! Height drawMiniField needs.
    //! Will this many mini fields fit side by side in `width`?
    //!
    //! A mini field is centred on its column and nothing clips it, so a value
    //! or a caption wider than its share simply grows into its neighbour. That
    //! is invisible to the compiler and to every test that does not measure,
    //! which is why the caller asks before it draws rather than after someone
    //! reports it.
    //!
    //! 90% of a column, so two neighbours cannot meet in the middle.
    public function miniFieldsFit(
        dc as Graphics.Dc,
        width as Number,
        count as Number,
        values as Array<String>,
        captions as Array<String>
    ) as Boolean {
        if (count < 1) {
            return false;
        }
        var room = ((width / count) * 90) / 100;
        for (var i = 0; i < count; i++) {
            if (i < values.size() &&
                dc.getTextWidthInPixels(values[i], Graphics.FONT_TINY) > room) {
                return false;
            }
            if (i < captions.size() &&
                dc.getTextWidthInPixels(captions[i], captionFont()) > room) {
                return false;
            }
        }
        return true;
    }

    public function miniFieldHeight(dc as Graphics.Dc) as Number {
        return dc.getFontHeight(Graphics.FONT_TINY) + dc.getFontHeight(captionFont());
    }

    //! Time of day, small and dim, in the strip below the action bar.
    //!
    //! Native Garmin activity screens keep the clock there, and on a round
    //! display that strip is otherwise dead space — too narrow for content, too
    //! tall to ignore.
    public function drawClock(dc as Graphics.Dc, top as Number) as Void {
        drawClockWith(dc, top, null, colorDim());
    }

    //! The time of day, optionally with one more elapsed reading beside it.
    //!
    //! The bottom line of the exercise screen is one short row of small text
    //! with most of its width unused, which makes it the only place left to put
    //! a third clock without shrinking the two readouts above it.
    //!
    //! `leading` goes on the left and the time of day on the right, in
    //! different colours, and neither is captioned — there is no room, and none
    //! is needed. The pair is context, not data: the captioned readouts above
    //! are what the athlete reads, and these two are what they glance at.
    //!
    //! **Two things about the geometry, both learned the hard way.** The pair is
    //! centred with a gap rather than pushed to the edges of the chord: this
    //! row sits low, where the glass curves away fastest, and text pinned to
    //! the chord's ends had its bottom half cut off by the bezel. And the room
    //! is measured at the line's **bottom**, not its middle — below centre the
    //! chord closes as it descends, so the middle of a line always overstates
    //! what its descenders will have.
    //!
    //! When the pair will not fit, the time of day wins. It is the one that was
    //! already there.
    public function drawClockWith(
        dc as Graphics.Dc,
        top as Number,
        leading as String?,
        leadingColor as Number
    ) as Void {
        var now = System.getClockTime();
        var text = now.hour.format("%02d") + ":" + now.min.format("%02d");
        var font = Graphics.FONT_XTINY;

        if (leading != null) {
            var room = usableWidth(dc, top + dc.getFontHeight(font));
            var leadWidth = dc.getTextWidthInPixels(leading as String, font);
            var clockWidth = dc.getTextWidthInPixels(text, font);
            // Enough space between them that they never read as one value.
            var gap = dc.getWidth() / 10;
            var total = leadWidth + gap + clockWidth;
            if (total <= room) {
                var left = (dc.getWidth() - total) / 2;
                setColor(dc, leadingColor);
                dc.drawText(left, top, font, leading as String,
                    Graphics.TEXT_JUSTIFY_LEFT);
                setColor(dc, colorFaint());
                dc.drawText(left + total, top, font, text,
                    Graphics.TEXT_JUSTIFY_RIGHT);
                return;
            }
        }

        setColor(dc, colorDim());
        dc.drawText(dc.getWidth() / 2, top, font, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function setColor(dc as Graphics.Dc, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
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
        dc.setColor(colorFaint(), Graphics.COLOR_TRANSPARENT);
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
    //! Radius of a page dot on this screen.
    public function pageDotRadius(dc as Graphics.Dc) as Number {
        var spacing = pageDotSpacing(dc);
        var radius = spacing / 4;
        return radius < 2 ? 2 : radius;
    }

    public function pageDotSpacing(dc as Graphics.Dc) as Number {
        var spacing = (dc.getHeight() / 24).toNumber();
        return spacing < 10 ? 10 : spacing;
    }

    //! The leftmost pixel the page dots occupy.
    //!
    //! Content that must not collide with them needs this, and deriving it from
    //! the same numbers that draw them is the only way it stays true. The
    //! active dot is a pixel wider than the rest, so it sets the edge.
    public function pageDotsLeft(dc as Graphics.Dc) as Number {
        var radius = pageDotRadius(dc);
        return dc.getWidth() - (dc.getWidth() / 22) - radius - (radius + 1);
    }

    public function drawPageDots(dc as Graphics.Dc, count as Number, active as Number) as Void {
        if (count <= 1) {
            return;
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var spacing = pageDotSpacing(dc);
        var radius = pageDotRadius(dc);
        var x = w - (w / 22) - radius;
        var startY = h / 2 - ((count - 1) * spacing) / 2;
        for (var i = 0; i < count; i++) {
            dc.setColor(i == active ? colorAccent() : colorFaint(), Graphics.COLOR_TRANSPARENT);
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
                dc.setColor(colorDone(), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(startX + i * spacing, y + radius, radius);
            } else {
                dc.setColor(colorFaint(), Graphics.COLOR_TRANSPARENT);
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
    //! Null means the routine sets no target load, and that is worth saying
    //! rather than hiding behind a zero: "--" is a question, "0" is an answer.
    public function formatPlannedWeight(weight as Float?) as String {
        if (weight == null) {
            return LiveMetrics.NO_VALUE;
        }
        return formatNumber(Units.fromKg(weight as Float));
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
