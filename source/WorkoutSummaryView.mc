import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Math;

//! End-of-workout recap.
//!
//!   Page 1 — the session     time, sets done / planned, reps, volume
//!   Page 2 — effort          Training Effect, calories, Body Battery
//!   Page 3 — time in zones   the bar chart a Fenix shows after any activity,
//!                            with average, peak and recovery heart rate
//!   Page 4 — the exercises   what was actually done, exercise by exercise
//!   Page 5 — effort          average RPE per muscle group, this session
//!   Page 6 — records         what was beaten, one card each
//!   Page 7 — this week       volume per muscle group, across the last 7 days
//!
//! **One visual language for all seven**, the one the watch's own activity
//! recap speaks: a small-caps title in the page's colour at the top of the
//! glass, at most one hero figure in the number font, then tiles or rows
//! separated by hairlines, values set right, bars as rounded pills.
//!
//! **Everything follows the glass.** A row is as wide as the circle is at the
//! row's own height, measured inside the rim ring, so a list narrows as it
//! runs into the bottom of the screen the way the bezel does, instead of
//! ending on a straight edge with its corners cut off by the curve.
//!
//! It carries no buttons. Save and discard were answered in the stop menu
//! before this screen opened (see EndWorkoutFlow). BACK leaves, UP/DOWN page.
//!
//! The rim ring is sets done against sets planned — the one number that says
//! whether the session was finished or cut short — and it is dimmed when the
//! recording was discarded, so the screen never looks like a saved activity.
//!
//! Garmin metrics show "--" rather than a fabricated zero when the device does
//! not provide them.
class WorkoutSummaryView extends WatchUi.View {

    public static const PAGE_COUNT = 7;

    //! How a list that does not fit moves: slower than scrolling text, with a
    //! long rest at the top, because a list is read from its first row.
    private const LIST_MS_PER_PIXEL = 42;
    private const LIST_PAUSE_MS = 2400;

    //! Marks that can lead a title.
    private const MARK_NONE = 0;
    private const MARK_TROPHY = 1;
    private const MARK_CHECK = 2;

    private var _summary as SessionSummary;
    private var _workout as Workout;
    private var _zones as ZoneTracker;
    //! Whole kilograms per muscle group for the week this session fell in,
    //! read once at construction — the pages repaint on every tick.
    private var _weekly as Array<Number>;
    //! What was beaten this session: `[name, History.RECORD_*, reps, kg]` rows.
    private var _records as Array;
    //! What Garmin measured, read before the recording was closed.
    private var _metrics as RecapMetrics;
    private var _saved as Boolean;
    private var _page as Number;

    public function initialize(
        summary as SessionSummary,
        workout as Workout,
        zones as ZoneTracker,
        weekly as Array<Number>,
        records as Array,
        metrics as RecapMetrics,
        saved as Boolean
    ) {
        View.initialize();
        _summary = summary;
        _workout = workout;
        _zones = zones;
        _weekly = weekly;
        _records = records;
        _metrics = metrics;
        _saved = saved;
        _page = 0;
    }

    //! The recap earns an entrance: it is the one screen nobody is mid-set on.
    public function onShow() as Void {
        Animator.start(420);
    }

    public function onHide() as Void {
        Animator.stop();
        Marquee.stop();
    }

    public function turnPage(delta as Number) as Void {
        // Each page draws itself once, finished: no motion between the athlete
        // and a number they are reading. Whatever was scrolling starts again
        // from the beginning of its own text.
        Animator.stop();
        Marquee.stop();
        _page = (_page + delta + PAGE_COUNT) % PAGE_COUNT;
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var h = dc.getHeight();

        var bottom = h - h / 13;
        if (_page == 1) {
            _drawBodyPage(dc, bottom);
        } else if (_page == 2) {
            _drawZonesPage(dc, bottom);
        } else if (_page == 3) {
            _drawExercisesPage(dc, bottom);
        } else if (_page == 4) {
            _drawMuscleEffortPage(dc, bottom);
        } else if (_page == 5) {
            _drawRecordsPage(dc, bottom);
        } else if (_page == 6) {
            _drawWeekPage(dc, bottom);
        } else {
            _drawWorkPage(dc, bottom);
        }

        // Whatever ran down into the curve of the glass is hidden along the
        // curve, not along a straight line: a mask in the background colour
        // from just inside the rim ring outwards. The ring and the page dots
        // are drawn over it.
        if (dc has :clearClip) {
            dc.clearClip();
        }
        _drawMask(dc);
        var planned = _summary.plannedSets;
        Theme.drawProgressRing(dc,
            (planned > 0 ? _summary.completedSets.toFloat() / planned.toFloat() : 0.0)
                * Animator.value(),
            _saved ? Theme.colorDone() : Theme.colorFaint());
        Theme.drawPageDots(dc, PAGE_COUNT, _page);
        Marquee.endFrame();
    }

    // ==================================================================
    // Geometry
    // ==================================================================

    //! Radius of the circle everything is laid inside: the inside of the rim
    //! ring, less a little air.
    private function _innerRadius(dc as Graphics.Dc) as Number {
        var w = dc.getWidth();
        var h = dc.getHeight();
        return (w < h ? w : h) / 2 - Theme.progressRingInset(dc) - h / 60;
    }

    //! Half the width available at `y`: the chord of the inner circle there,
    //! stopped short of the page dots — on both sides, so content stays
    //! centred.
    private function _halfAt(dc as Graphics.Dc, y as Number) as Number {
        var cx = dc.getWidth() / 2;
        var r = _innerRadius(dc);
        var dy = y - dc.getHeight() / 2;
        var square = r * r - dy * dy;
        var half = square > 0 ? Math.sqrt(square.toFloat()).toNumber() : 0;
        var dots = Theme.pageDotsLeft(dc) - dc.getWidth() / 40 - cx;
        return half < dots ? half : dots;
    }

    //! `[left, width]` of something spanning `yTop`..`yBottom`: the chord at
    //! whichever edge is further from the centre, since that is the narrower.
    private function _span(dc as Graphics.Dc, yTop as Number, yBottom as Number) as Array<Number> {
        var cy = dc.getHeight() / 2;
        var far = (yTop - cy).abs() > (yBottom - cy).abs() ? yTop : yBottom;
        var half = _halfAt(dc, far);
        return [dc.getWidth() / 2 - half, half * 2] as Array<Number>;
    }

    //! Radius of the mask: just inside the rim ring. Content may run up to
    //! it; past it, it is hidden along the curve.
    private function _maskRadius(dc as Graphics.Dc) as Number {
        var w = dc.getWidth();
        var h = dc.getHeight();
        return (w < h ? w : h) / 2 - (Theme.progressRingInset(dc) - h / 36) - 1;
    }

    private function _drawMask(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var r = _maskRadius(dc);
        // The far corner of the framebuffer, from the centre.
        var reach = ((w > h ? w : h) * 72) / 100;
        var pen = reach - r;
        dc.setColor(Theme.colorBg(), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen);
        dc.drawCircle(w / 2, h / 2, r + pen / 2);
        dc.setPenWidth(1);
    }

    //! `[left, width]` of every row of a list: one width for the whole list,
    //! clear of the page dots and centred.
    private function _listSpan(dc as Graphics.Dc) as Array<Number> {
        var cx = dc.getWidth() / 2;
        var half = (_maskRadius(dc) * 80) / 100;
        var dots = Theme.pageDotsLeft(dc) - dc.getWidth() / 40 - cx;
        if (dots < half) {
            half = dots;
        }
        return [cx - half, half * 2] as Array<Number>;
    }

    //! The lowest y at which a whole row of the list's width is still on the
    //! glass. A list that fits stays above it; one that scrolls rests there.
    private function _comfortBottom(dc as Graphics.Dc, bottom as Number) as Number {
        var half = _listSpan(dc)[1] / 2;
        // A margin inside the mask, so a row that fits never grazes the ring.
        var r = _maskRadius(dc) - dc.getHeight() / 30;
        var dy = Math.sqrt((r * r - half * half).toFloat()).toNumber();
        var limit = dc.getHeight() / 2 + dy;
        return limit < bottom ? limit : bottom;
    }

    //! The lowest y a scrolling list draws to: the bottom of the mask.
    private function _maskBottom(dc as Graphics.Dc) as Number {
        return dc.getHeight() / 2 + _maskRadius(dc);
    }

    // ==================================================================
    // Shared pieces
    // ==================================================================

    //! A small-caps line at `y`, centred, in `color`, with an optional mark
    //! before it. Returns the y just below it.
    private function _drawTitleAt(
        dc as Graphics.Dc,
        y as Number,
        title as String,
        color as Number,
        mark as Number
    ) as Number {
        var cx = dc.getWidth() / 2;
        var text = title.toUpper();
        var room = _halfAt(dc, y) * 2;

        var font = Theme.captionFont();
        var lineHeight = dc.getFontHeight(font);
        var size = mark != MARK_NONE ? (lineHeight * 3) / 4 : 0;
        var gap = mark != MARK_NONE ? size / 2 : 0;
        if (dc.getTextWidthInPixels(text, font) + size + gap > room) {
            font = Graphics.FONT_XTINY;
            lineHeight = dc.getFontHeight(font);
            size = mark != MARK_NONE ? (lineHeight * 3) / 4 : 0;
            gap = mark != MARK_NONE ? size / 2 : 0;
        }
        var textWidth = dc.getTextWidthInPixels(text, font);
        var left = cx - (size + gap + textWidth) / 2;

        if (mark == MARK_TROPHY) {
            _drawTrophy(dc, left, y + (lineHeight - size) / 2, size, color);
        } else if (mark == MARK_CHECK) {
            _drawCheckDisc(dc, left + size / 2, y + lineHeight / 2, size / 2, color);
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + size + gap, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
        return y + lineHeight;
    }

    //! The page title, at the top of the glass.
    private function _drawPageTitle(
        dc as Graphics.Dc,
        title as String,
        color as Number,
        mark as Number
    ) as Number {
        return _drawTitleAt(dc, _titleTop(dc), title, color, mark);
    }

    private function _titleTop(dc as Graphics.Dc) as Number {
        return Theme.progressRingInset(dc) + dc.getHeight() / 18;
    }

    //! A figure in the number font, centred on `cx`, with its unit small and
    //! sitting on the figure's baseline. Height is the ink, not the line box:
    //! a number font's line carries a descent its digits never use.
    //! Returns the y just below the ink.
    private function _drawFigure(
        dc as Graphics.Dc,
        cx as Number,
        y as Number,
        value as String,
        unit as String,
        color as Number,
        maxWidth as Number,
        maxInk as Number,
        large as Boolean
    ) as Number {
        var fonts = (large
            ? [
                Graphics.FONT_NUMBER_HOT,
                Graphics.FONT_NUMBER_MEDIUM,
                Graphics.FONT_NUMBER_MILD,
                Graphics.FONT_LARGE,
                Graphics.FONT_MEDIUM,
                Graphics.FONT_SMALL
            ]
            : [
                Graphics.FONT_NUMBER_MEDIUM,
                Graphics.FONT_NUMBER_MILD,
                Graphics.FONT_LARGE,
                Graphics.FONT_MEDIUM,
                Graphics.FONT_SMALL,
                Graphics.FONT_TINY
            ]) as Array<Graphics.FontDefinition>;
        var unitFont = large ? Graphics.FONT_TINY : Graphics.FONT_XTINY;
        // A ratio's "/16" belongs to its figure; a unit stands a space apart.
        var unitText = unit;
        if (unit.length() > 0 && unit.find("/") != 0) {
            unitText = " " + unit;
        }
        var unitWidth = dc.getTextWidthInPixels(unitText, unitFont);
        var font = Theme.pickFontFitting(dc, value, fonts, maxWidth - unitWidth, maxInk);
        var ink = Theme.inkHeight(font);
        var valueWidth = dc.getTextWidthInPixels(value, font);
        var left = cx - (valueWidth + unitWidth) / 2;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, y, font, value, Graphics.TEXT_JUSTIFY_LEFT);
        if (unitText.length() > 0) {
            dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left + valueWidth, y + ink - Theme.inkHeight(unitFont), unitFont,
                unitText, Graphics.TEXT_JUSTIFY_LEFT);
        }
        return y + ink;
    }

    //! A caption under a figure, centred, dim, with an optional heart before
    //! it. Returns the y just below it.
    private function _drawCaption(
        dc as Graphics.Dc,
        cx as Number,
        y as Number,
        text as String,
        maxWidth as Number,
        heart as Boolean
    ) as Number {
        var font = Theme.captionFontFor(dc, text, maxWidth);
        var line = dc.getFontHeight(font);
        var textWidth = dc.getTextWidthInPixels(text, font);
        var size = heart ? (line * 55) / 100 : 0;
        var gap = heart ? size / 2 : 0;
        var left = cx - (size + gap + textWidth) / 2;
        if (heart) {
            Theme.drawHeart(dc, left + size / 2, y + line / 2, size, Theme.colorHr());
        }
        dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + size + gap, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
        return y + line;
    }

    private function _hairline(dc as Graphics.Dc, x1 as Number, y1 as Number, x2 as Number, y2 as Number) as Void {
        dc.setColor(Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x1, y1, x2, y2);
    }

    //! "Nothing here": a dash where the content would have been.
    private function _drawEmpty(dc as Graphics.Dc, top as Number, bottom as Number) as Void {
        var font = Graphics.FONT_NUMBER_MILD;
        var y = top + (bottom - top - Theme.inkHeight(font)) / 2;
        dc.setColor(Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, y, font, LiveMetrics.NO_VALUE, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! The largest row font that leaves room for `rows` rows of `lines` lines.
    private function _rowFont(
        dc as Graphics.Dc,
        available as Number,
        rows as Number,
        lines as Number
    ) as Graphics.FontDefinition {
        var ladder = [
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ] as Array<Graphics.FontDefinition>;
        for (var i = 0; i < ladder.size(); i++) {
            var line = dc.getFontHeight(ladder[i]);
            if (rows * (line * lines + line / 2) <= available) {
                return ladder[i];
            }
        }
        return ladder[ladder.size() - 1];
    }

    //! Where the first row of a list goes, and whether it is clipped:
    //! `[y, clipped]`. A list that fits is centred between `top` and `comfort`,
    //! wholly on the glass. One that does not crawls, resting with its last
    //! row at `comfort`; rows below that slide under the curve of the mask.
    private function _listStart(
        dc as Graphics.Dc,
        top as Number,
        comfort as Number,
        rows as Number,
        rowHeight as Number,
        trailing as Number
    ) as Array<Number> {
        var available = comfort - top;
        var visible = rows * rowHeight - trailing;
        if (visible <= available) {
            return [top + (available - visible) / 2, 0] as Array<Number>;
        }
        var offset = Marquee.travelPaced(visible - available,
            LIST_MS_PER_PIXEL, LIST_PAUSE_MS);
        Marquee.claimFrame();
        var clipped = dc has :setClip;
        if (clipped) {
            dc.setClip(0, top, dc.getWidth(), _maskBottom(dc) - top);
        }
        return [top - offset, clipped ? 1 : 0] as Array<Number>;
    }

    // ==================================================================
    // Surfaces
    // ==================================================================

    private function _amoled() as Boolean {
        var settings = System.getDeviceSettings();
        return (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
    }

    //! The colour of an empty gauge track: a deep grey on an AMOLED, the
    //! palette's faint grey on a MIP screen.
    private function _track() as Number {
        return _amoled() ? (Theme.light() ? 0xE6E6E6 : 0x262626) : Theme.colorFaint();
    }

    //! A rounded panel. Filled in a raised grey on an AMOLED, as the watch's
    //! own screens do; outlined on a MIP screen, whose palette has no grey
    //! dark enough to sit behind white text.
    private function _panel(
        dc as Graphics.Dc,
        x as Number,
        y as Number,
        width as Number,
        height as Number,
        radius as Number
    ) as Void {
        var rounded = dc has :fillRoundedRectangle;
        if (_amoled()) {
            dc.setColor(Theme.light() ? 0xE6E6E6 : 0x1E1E1E, Graphics.COLOR_TRANSPARENT);
            if (rounded) {
                dc.fillRoundedRectangle(x, y, width, height, radius);
            } else {
                dc.fillRectangle(x, y, width, height);
            }
            return;
        }
        dc.setColor(Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
        if (rounded) {
            dc.drawRoundedRectangle(x, y, width, height, radius);
        } else {
            dc.drawRectangle(x, y, width, height);
        }
    }

    //! A pill: a rectangle with fully rounded ends, in the current colour.
    private function _pill(
        dc as Graphics.Dc,
        x as Number,
        y as Number,
        width as Number,
        height as Number
    ) as Void {
        if (width <= 0) {
            return;
        }
        if (dc has :fillRoundedRectangle) {
            var radius = (width < height ? width : height) / 2;
            dc.fillRoundedRectangle(x, y, width, height, radius);
        } else {
            dc.fillRectangle(x, y, width, height);
        }
    }

    //! A track the full width, filled from the left by `fraction`.
    private function _drawBar(
        dc as Graphics.Dc,
        x as Number,
        y as Number,
        width as Number,
        height as Number,
        fraction as Float,
        color as Number
    ) as Void {
        dc.setColor(_track(), Graphics.COLOR_TRANSPARENT);
        _pill(dc, x, y, width, height);
        var f = fraction < 0.0 ? 0.0 : (fraction > 1.0 ? 1.0 : fraction);
        var fill = (width * f * Animator.value()).toNumber();
        if (fill > 0) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            _pill(dc, x, y, fill < height ? height : fill, height);
        }
    }

    //! One segment per planned set, the done ones lit — the way the watch
    //! counts the steps of a structured workout. A long session would make
    //! slivers of them, so past that it is one continuous bar.
    private function _drawSetBar(
        dc as Graphics.Dc,
        x as Number,
        y as Number,
        width as Number,
        height as Number,
        done as Number,
        planned as Number,
        color as Number
    ) as Void {
        var gap = height / 3 < 2 ? 2 : height / 3;
        if (planned <= 0 || (width - gap * (planned - 1)) / planned < height) {
            _drawBar(dc, x, y, width, height,
                planned > 0 ? done.toFloat() / planned.toFloat() : 0.0, color);
            return;
        }
        var lit = (done * Animator.value()).toNumber();
        for (var i = 0; i < planned; i++) {
            // Spread the remainder over the segments, so the bar ends exactly
            // at its right edge.
            var from = x + (i * (width + gap)) / planned;
            var to = x + ((i + 1) * (width + gap)) / planned - gap;
            dc.setColor(i < lit ? color : _track(), Graphics.COLOR_TRANSPARENT);
            _pill(dc, from, y, to - from, height);
        }
    }

    //! A line of a list: caption on the left, figure on the right, on one
    //! centre line. `sub`, when there is one, sits small and dim after the
    //! figure on its baseline — the "/17" of "12/17".
    private function _drawLabelled(
        dc as Graphics.Dc,
        left as Number,
        right as Number,
        mid as Number,
        caption as String,
        value as String,
        sub as String,
        color as Number,
        maxInk as Number
    ) as Number {
        var capFont = Theme.captionFont();
        dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, mid, capFont, caption,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var subFont = Graphics.FONT_TINY;
        var subWidth = sub.length() > 0 ? dc.getTextWidthInPixels(sub, subFont) : 0;
        var room = right - left - dc.getTextWidthInPixels(caption, capFont)
            - dc.getHeight() / 20 - subWidth;
        var fonts = [
            Graphics.FONT_NUMBER_MILD,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY
        ] as Array<Graphics.FontDefinition>;
        var font = Theme.pickFontFitting(dc, value, fonts, room, maxInk);
        var ink = Theme.inkHeight(font);
        // The ascent carries a little air above the digits; lift the figure
        // by it so it centres on the caption by eye, not by box.
        var top = mid - ink / 2 - ink / 12;
        if (subWidth > 0) {
            dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(right, top + ink - Theme.inkHeight(subFont), subFont, sub,
                Graphics.TEXT_JUSTIFY_RIGHT);
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(right - subWidth, top, font, value, Graphics.TEXT_JUSTIFY_RIGHT);
        return right - subWidth - dc.getTextWidthInPixels(value, font);
    }

    //! A column: caption on top, figure below, both centred on `cx`.
    //! `figure` is `[value, unit]`. Returns the y below the figure.
    private function _drawCell(
        dc as Graphics.Dc,
        cx as Number,
        y as Number,
        width as Number,
        caption as String,
        figure as Array<String>,
        color as Number,
        maxInk as Number,
        heart as Boolean
    ) as Number {
        var below = _drawCaption(dc, cx, y, caption, width, heart);
        return _drawFigure(dc, cx, below + dc.getHeight() / 90, figure[0], figure[1],
            color, width, maxInk, false);
    }

    //! The half-width of a band whose lowest edge is at `y`: the chord there,
    //! less a margin, so the band reads as set inside the glass.
    private function _bandHalf(dc as Graphics.Dc, y as Number) as Number {
        return (_halfAt(dc, y) * 86) / 100;
    }

    // ==================================================================
    // Page 1 — the session
    // ==================================================================

    //!               PUSH DAY
    //!           ✓ WORKOUT DONE
    //!               1:05:20
    //!                 TIME
    //!     SETS                     12/17
    //!     ▬ ▬ ▬ ▬ ▬ ▬ ▬ ▬ ▬ ▬ ▬ ▬ ▭ ▭ ▭ ▭
    //!            REPS   │   VOLUME
    //!             122   │   4.6 t
    //!
    //! No rings. A figure inside a ring only has the ring's hole to live in,
    //! and the numbers were squeezed into it. Here every figure has a whole
    //! column or a whole line. Sets done against sets planned is the only
    //! real fraction on the page, so it is the only bar: a segment per planned
    //! set, green when the session was finished, amber when it was cut short.
    //! A record, when there is one, is the headline: "Workout done" is true
    //! of every session, "2 records" of this one.
    private function _drawWorkPage(dc as Graphics.Dc, bottom as Number) as Void {
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;

        var y = _titleTop(dc);
        y = Marquee.draw(dc, y, _workout.name.toUpper(),
            [Theme.captionFont()] as Array<Graphics.FontDefinition>,
            Theme.colorDim(), _halfAt(dc, y) * 2);

        var status = _saved
            ? WatchUi.loadResource(Rez.Strings.SummaryTitle) as String
            : WatchUi.loadResource(Rez.Strings.SummaryDiscarded) as String;
        var statusColor = _saved ? Theme.colorDone() : Theme.colorFaint();
        var mark = _saved ? MARK_CHECK : MARK_NONE;
        if (_saved && _records.size() > 0) {
            status = _records.size().toString() + " " +
                (WatchUi.loadResource(_records.size() == 1
                    ? Rez.Strings.RecordOne
                    : Rez.Strings.RecordMany) as String);
            statusColor = Theme.colorWarm();
            mark = MARK_TROPHY;
        }
        var top = _drawTitleAt(dc, y + h / 120, status, statusColor, mark);

        // The hero: how long it took.
        var heroTop = top + h / 50;
        var below = _drawFigure(dc, cx, heroTop, Theme.formatDuration(_summary.durationSec), "",
            Theme.colorText(), (_halfAt(dc, heroTop) * 2 * 80) / 100, (h * 15) / 100, true);
        below = _drawCaption(dc, cx, below + h / 90,
            WatchUi.loadResource(Rez.Strings.FieldTime) as String, _halfAt(dc, below) * 2, false);

        // Sets: the count on a line, the bar under it.
        var planned = _summary.plannedSets;
        var done = _summary.completedSets;
        var setsColor = done >= planned ? Theme.colorDone() : Theme.colorWarm();
        var lineTop = below + h / 50;
        var lineHeight = (h * 8) / 100;
        var barHeight = h / 40;
        var barTop = lineTop + lineHeight + h / 45;
        var half = _bandHalf(dc, barTop + barHeight);
        _drawLabelled(dc, cx - half, cx + half, lineTop + lineHeight / 2,
            WatchUi.loadResource(Rez.Strings.FieldSets) as String,
            done.toString(), "/" + planned.toString(), setsColor, (lineHeight * 80) / 100);
        _drawSetBar(dc, cx - half, barTop, half * 2, barHeight, done, planned, setsColor);

        // Reps and volume: a column each, a rule between. The columns keep
        // the width of the band above; only their figures run lower.
        var cellTop = barTop + barHeight + h / 30;
        var q = half / 2;
        var volume = _splitVolume(_summary.totalVolume);
        var end = _drawSmallCell(dc, cx - q, cellTop,
            WatchUi.loadResource(Rez.Strings.FieldReps) as String,
            _summary.totalReps.toString(), "");
        _drawSmallCell(dc, cx + q, cellTop,
            WatchUi.loadResource(Rez.Strings.FieldVolume) as String,
            volume[0], volume[1]);
        _hairline(dc, cx, cellTop + h / 90, cx, end);
    }

    //! A column set small, under the sets bar: caption on top, figure below,
    //! its unit smaller after it, all centred on `cx`. The same scalable
    //! Roboto as the heart-rate row, so the two pages read as one family.
    //! Returns the y below the figure.
    private function _drawSmallCell(
        dc as Graphics.Dc,
        cx as Number,
        y as Number,
        caption as String,
        value as String,
        unit as String
    ) as Number {
        var h = dc.getHeight();
        var capFont = _sizedFont(["RobotoCondensedRegular", "RobotoRegular"] as Array<String>,
            (h * 55) / 1000, Graphics.FONT_XTINY);
        var valueFont = _sizedFont(["RobotoCondensedBold", "RobotoMedium", "RobotoRegular"] as Array<String>,
            (h * 100) / 1000, Graphics.FONT_MEDIUM);
        var unitFont = _sizedFont(["RobotoCondensedRegular", "RobotoRegular"] as Array<String>,
            (h * 60) / 1000, Graphics.FONT_XTINY);
        dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, capFont, caption, Graphics.TEXT_JUSTIFY_CENTER);

        var valueTop = y + dc.getFontHeight(capFont) + h / 120;
        var valueLine = dc.getFontHeight(valueFont);
        var gap = unit.length() > 0 ? h / 90 : 0;
        var valueWidth = dc.getTextWidthInPixels(value, valueFont);
        var unitWidth = unit.length() > 0 ? dc.getTextWidthInPixels(unit, unitFont) : 0;
        var left = cx - (valueWidth + gap + unitWidth) / 2;
        dc.setColor(Theme.colorText(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, valueTop, valueFont, value, Graphics.TEXT_JUSTIFY_LEFT);
        if (unitWidth > 0) {
            // On the figure's baseline.
            var baseline = valueTop + Graphics.getFontAscent(valueFont);
            dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left + valueWidth + gap, baseline - Graphics.getFontAscent(unitFont),
                unitFont, unit, Graphics.TEXT_JUSTIFY_LEFT);
        }
        return valueTop + (valueLine * 85) / 100;
    }

    // ==================================================================
    // Page 2 — the body
    // ==================================================================

    //!               EFFORT
    //!            ╭─────────╮
    //!          ╱             ╲
    //!         │      3.4      │
    //!          ╲  Improving  ╱
    //!
    //!        KCAL    │   BODY BATT
    //!         486    │    81 ▸ 63
    //!
    //! What the session did to the athlete, led by the figure the watch's own
    //! summary leads with: aerobic Training Effect, on Garmin's 0-5 scale.
    //! The gauge is large on purpose — the number sits alone in the middle of
    //! a ring three times its width, and the ring is the scale itself, five
    //! segments in the colours Garmin gives the levels, lit up to the score,
    //! with a marker at the exact value. Garmin's word for the level sits in
    //! the gauge's opening.
    //!
    //! Under it the two things the session spent: energy, and Body Battery
    //! from where the session started to where it left you. The heart-rate
    //! figures are on the zones page, with the zones they belong to.
    private function _drawBodyPage(dc as Graphics.Dc, bottom as Number) as Void {
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var top = _drawPageTitle(dc,
            WatchUi.loadResource(Rez.Strings.SummaryEffort) as String,
            Theme.colorAccent(), MARK_NONE);

        // The gauge.
        var radius = (h * 23) / 100;
        var pen = h / 34 < 5 ? 5 : h / 34;
        var gy = top + h / 30 + pen / 2 + radius;
        _drawEffectGauge(dc, cx, gy, radius, pen);

        // Energy and Body Battery, a column each.
        var cellTop = gy + (radius * 62) / 100 + h / 22;
        // The columns stand well apart, so neither figure crowds the rule
        // between them or the curve beside it.
        var q = (_bandHalf(dc, h / 2) * 50) / 100;
        var width = q * 2 - h / 12;
        var cellInk = (h * 9) / 100;
        var end = _drawCell(dc, cx - q, cellTop, width,
            WatchUi.loadResource(Rez.Strings.FieldKcal) as String,
            [LiveMetrics.format(_metrics.calories), ""] as Array<String>,
            _metrics.calories == null ? Theme.colorFaint() : Theme.colorText(),
            cellInk, false);
        _drawBatteryCell(dc, cx + q, cellTop, width, cellInk);
        var barWidth = (width * 55) / 100;
        var barHeight = h / 60;
        _drawBatteryBar(dc, cx + q - barWidth / 2, end + h / 25, barWidth, barHeight);
        _hairline(dc, cx, cellTop + h / 90, cx, end + h / 25 + barHeight);
    }

    //! Training Effect as a gauge: a 240-degree arc open at the bottom, cut
    //! into the five levels of Garmin's scale. Levels up to the score are lit
    //! in their colour, the rest are track; a marker sits at the exact value.
    private function _drawEffectGauge(
        dc as Graphics.Dc,
        cx as Number,
        cy as Number,
        radius as Number,
        pen as Number
    ) as Void {
        var h = dc.getHeight();
        var te = _metrics.trainingEffect;
        var score = te == null ? 0.0 : (te as Float) * Animator.value();
        var span = 240;
        var start = 210;                      // the left end, in degrees
        var step = span / 5;
        var gap = 3;
        dc.setPenWidth(pen);
        for (var k = 0; k < 5; k++) {
            var from = start - k * step - (k == 0 ? 0 : gap / 2 + 1);
            var to = start - (k + 1) * step + (k == 4 ? 0 : gap / 2 + 1);
            var lit = te != null && score > k.toFloat();
            dc.setColor(lit ? Theme.zoneColor(k + 1) : _track(), Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE,
                (from + 360) % 360, (to + 360) % 360);
        }
        dc.setPenWidth(1);

        var level = te == null ? 0 : (te as Float).toNumber();
        var color = te == null ? Theme.colorFaint() : Theme.zoneColor(level < 1 ? 1 : (level > 5 ? 5 : level));
        if (te != null) {
            // The marker: a disc in the background colour with the score's
            // colour inside, so it reads on a lit segment and on the track.
            var f = score / 5.0;
            var angle = Math.toRadians(start - span * f);
            var mx = cx + (radius * Math.cos(angle)).toNumber();
            var my = cy - (radius * Math.sin(angle)).toNumber();
            dc.setColor(Theme.colorBg(), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(mx, my, pen);
            dc.setColor(Theme.colorText(), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(mx, my, (pen * 62) / 100);
        }

        // The score, alone in the middle.
        var hole = (radius - pen) * 2;
        var value = te == null ? LiveMetrics.NO_VALUE : (te as Float).format("%.1f");
        var maxInk = (hole * 30) / 100;
        var fonts = [
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_MILD,
            Graphics.FONT_LARGE
        ] as Array<Graphics.FontDefinition>;
        var font = Theme.pickFontFitting(dc, value, fonts, (hole * 60) / 100, maxInk);
        var ink = Theme.inkHeight(font);
        var capFont = Theme.captionFont();
        var capLine = dc.getFontHeight(capFont);
        var valueTop = cy - ink / 2;
        dc.setColor(te == null ? Theme.colorFaint() : Theme.colorText(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, valueTop, font, value, Graphics.TEXT_JUSTIFY_CENTER);

        // Above it what it is; below it, in the opening, Garmin's word.
        var caption = WatchUi.loadResource(Rez.Strings.FieldEffect) as String;
        var room = (hole * 80) / 100;
        if (dc.getTextWidthInPixels(caption, Graphics.FONT_XTINY) <= room) {
            dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, valueTop - capLine - h / 120, Graphics.FONT_XTINY, caption,
                Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (te != null) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            var word = WatchUi.loadResource(_effectLabel(level)) as String;
            dc.drawText(cx, valueTop + ink + h / 40, capFont,
                Theme.clipToWidth(dc, word, capFont, (radius * 2 * 80) / 100),
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    //! Garmin's word for a Training Effect: 0 no benefit … 5 overreaching.
    private function _effectLabel(level as Number) as ResourceId {
        switch (level) {
            case 0: return Rez.Strings.Te0;
            case 1: return Rez.Strings.Te1;
            case 2: return Rez.Strings.Te2;
            case 3: return Rez.Strings.Te3;
            case 4: return Rez.Strings.Te4;
            default: return Rez.Strings.Te5;
        }
    }

    //! The Body Battery cell: where the session left you, as large as the
    //! calories beside it, and what it moved by, small, after it — "63 -18".
    //! The bar under it shows the same thing: blue up to the level, amber
    //! over what the session spent. Whichever end the watch could give,
    //! alone, when it had only one; "--" when it had neither.
    private function _drawBatteryCell(
        dc as Graphics.Dc,
        cx as Number,
        y as Number,
        width as Number,
        maxInk as Number
    ) as Void {
        var start = _metrics.batteryStart;
        var finish = _metrics.batteryEnd;
        var only = finish != null ? finish : start;
        var change = "";
        if (start != null && finish != null && start != finish) {
            var delta = (finish as Number) - (start as Number);
            change = (delta > 0 ? "+" : "") + delta.toString();
        }
        _drawCell(dc, cx, y, width,
            WatchUi.loadResource(Rez.Strings.FieldBattery) as String,
            [LiveMetrics.format(only), change] as Array<String>,
            only == null ? Theme.colorFaint() : Theme.colorText(), maxInk, false);
    }

    //! The Body Battery bar: blue up to where the session left it, amber over
    //! the part the session spent.
    private function _drawBatteryBar(
        dc as Graphics.Dc,
        x as Number,
        y as Number,
        width as Number,
        height as Number
    ) as Void {
        var start = _metrics.batteryStart;
        var finish = _metrics.batteryEnd;
        var level = finish != null ? finish : start;
        if (level == null) {
            _drawBar(dc, x, y, width, height, 0.0, Theme.colorFaint());
            return;
        }
        var t = Animator.value();
        dc.setColor(_track(), Graphics.COLOR_TRANSPARENT);
        _pill(dc, x, y, width, height);
        if (start != null && finish != null && (start as Number) > (finish as Number)) {
            dc.setColor(Theme.colorWarm(), Graphics.COLOR_TRANSPARENT);
            _pill(dc, x, y, ((width * (start as Number)) * t).toNumber() / 100, height);
        }
        var fill = ((width * (level as Number)) * t).toNumber() / 100;
        if (fill > 0) {
            dc.setColor(Theme.colorAccent(), Graphics.COLOR_TRANSPARENT);
            _pill(dc, x, y, fill < height ? height : fill, height);
        }
    }

    // ==================================================================
    // Page 3 — time in zones
    // ==================================================================

    //!          TIME IN ZONES
    //!     5  ▬▬▬▬               0:24   6%
    //!     4  ▬▬▬▬▬▬▬▬           1:12  17%
    //!     3  ▬▬▬▬▬▬▬▬▬▬▬▬▬▬     2:05  29%
    //!     2  ▬▬▬▬▬▬▬▬▬          1:30  21%
    //!     1  ▬▬                 0:12   3%
    //!
    //! The page a Fenix shows after any activity: zone 5 on top, a thick bar
    //! per zone in its colour on a dark track, the time and its share of the
    //! whole on the right. Bars are scaled against the busiest zone, not the
    //! clock — a strength session spends most of its time resting, and
    //! scaling to the clock would leave every bar a stub. Shares are of the
    //! time that was placed in a zone, so the five add up to the whole.
    private function _drawZonesPage(dc as Graphics.Dc, bottom as Number) as Void {
        var h = dc.getHeight();
        var top = _drawPageTitle(dc,
            WatchUi.loadResource(Rez.Strings.FieldZones) as String,
            Theme.colorAccent(), MARK_NONE);
        var peak = _zones.peakSeconds();
        bottom = _comfortBottom(dc, bottom);
        if (peak <= 0) {
            _drawEmpty(dc, top, bottom);
            return;
        }
        // Five rows centred on the middle of the glass, where it is widest,
        // in a block narrow enough that its corners clear the curve.
        // Under the bars, the heart rate itself: average, peak, recovery.
        var hrInk = (h * 6) / 100;
        var hrRow = h / 22 + (h * 125) / 1000;
        var font = _rowFont(dc, bottom - top - hrRow, ZoneTracker.ZONE_COUNT + 1, 1);
        var line = dc.getFontHeight(font);
        var rowHeight = (line * 118) / 100;
        var block = rowHeight * ZoneTracker.ZONE_COUNT - (rowHeight - line);
        // The bars start right under the title, so the heart-rate row below
        // them sits where the glass is still wide.
        var y = top + h / 50;
        _drawHeartRow(dc, y + block + h / 22, hrInk);
        var cx = dc.getWidth() / 2;
        // As long as the glass allows at the block's narrower edge, measured
        // just inside the ring rather than with the list's margin.
        var cy0 = h / 2;
        var far = (y - cy0).abs() > (y + block - cy0).abs() ? y : y + block;
        var rr = _maskRadius(dc) - h / 40;
        var dyz = far - cy0;
        var half = Math.sqrt((rr * rr - dyz * dyz).toFloat()).toNumber();
        var dotsHalf = Theme.pageDotsLeft(dc) - dc.getWidth() / 40 - dc.getWidth() / 2;
        if (dotsHalf < half) {
            half = dotsHalf;
        }
        var left = cx - half;
        var width = half * 2;

        var chipFont = Graphics.FONT_XTINY;
        var chip = (line * 90) / 100;
        var timeWidth = dc.getTextWidthInPixels("00:00", font);
        var gap = width / 30;
        var barLeft = left + chip + gap;
        var barWidth = width - chip - timeWidth - gap * 2;
        var barHeight = (line * 50) / 100;
        if (barWidth < 8) {
            return;
        }
        var track = _track();

        for (var zone = ZoneTracker.ZONE_COUNT; zone >= 1; zone--) {
            var seconds = _zones.secondsIn(zone);
            var color = Theme.zoneColor(zone);
            var lit = seconds > 0;
            var mid = y + line / 2;

            // The zone's badge: its number on its colour, or an outline when
            // no time was spent there.
            var rounded = dc has :fillRoundedRectangle;
            if (lit) {
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                if (rounded) {
                    dc.fillRoundedRectangle(left, mid - chip / 2, chip, chip, chip / 3);
                } else {
                    dc.fillRectangle(left, mid - chip / 2, chip, chip);
                }
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
                if (rounded) {
                    dc.drawRoundedRectangle(left, mid - chip / 2, chip, chip, chip / 3);
                } else {
                    dc.drawRectangle(left, mid - chip / 2, chip, chip);
                }
            }
            dc.drawText(left + chip / 2, mid, chipFont, zone.toString(),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            dc.setColor(track, Graphics.COLOR_TRANSPARENT);
            Theme.fillBar(dc, barLeft, mid - barHeight / 2, barWidth, barHeight);
            if (lit) {
                var filled = (((barWidth * seconds) / peak) * Animator.value()).toNumber();
                if (filled < barHeight) {
                    filled = barHeight;
                }
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                Theme.fillBar(dc, barLeft, mid - barHeight / 2, filled, barHeight);
            }

            dc.setColor(lit ? Theme.colorText() : Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left + width, mid, font, Theme.formatDuration(seconds),
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            y += rowHeight;
        }
    }

    //! Average, peak and recovery heart rate, a column each, under the zones.
    //! Set small, as a footnote to the zones above it: smaller than the
    //! system's smallest font, which on a Fenix 9 is still a large one, so
    //! drawn in the watch's own Roboto at a chosen size where the device has
    //! scalable fonts, and in the smallest system font where it does not.
    private function _drawHeartRow(dc as Graphics.Dc, y as Number, maxInk as Number) as Void {
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var capFont = _sizedFont(["RobotoCondensedRegular", "RobotoRegular"] as Array<String>,
            (h * 50) / 1000, Graphics.FONT_XTINY);
        var valueFont = _sizedFont(["RobotoCondensedBold", "RobotoMedium", "RobotoRegular"] as Array<String>,
            (h * 80) / 1000, Graphics.FONT_SMALL);
        var capLine = dc.getFontHeight(capFont);
        var valueLine = dc.getFontHeight(valueFont);
        var step = (_halfAt(dc, y + capLine) * 58) / 100;
        var recovery = _metrics.recovery;
        var cells = [
            [WatchUi.loadResource(Rez.Strings.FieldAvgHr) as String,
                LiveMetrics.format(_metrics.averageHeartRate)],
            [WatchUi.loadResource(Rez.Strings.FieldMaxHr) as String,
                LiveMetrics.format(_metrics.maxHeartRate)],
            [WatchUi.loadResource(Rez.Strings.FieldRecoveryShort) as String,
                recovery == null ? LiveMetrics.NO_VALUE : "-" + (recovery as Number).toString()]
        ] as Array<Array<String>>;
        var valueTop = y + capLine;
        for (var i = 0; i < cells.size(); i++) {
            var x = cx + (i - 1) * step;
            var value = cells[i][1];
            dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, capFont, cells[i][0], Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(value.equals(LiveMetrics.NO_VALUE) ? Theme.colorFaint() : Theme.colorText(),
                Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, valueTop, valueFont, value, Graphics.TEXT_JUSTIFY_CENTER);
        }
        var end = valueTop + (valueLine * 85) / 100;
        _hairline(dc, cx - step / 2, y + h / 90, cx - step / 2, end);
        _hairline(dc, cx + step / 2, y + h / 90, cx + step / 2, end);
    }

    //! The first of `faces` the device has, at `size` pixels; `fallback`
    //! when the device has no scalable fonts (Connect IQ before 4.2) or none
    //! of those faces.
    private function _sizedFont(
        faces as Array<String>,
        size as Number,
        fallback as Graphics.FontDefinition
    ) as Graphics.FontType {
        if (Graphics has :getVectorFont) {
            var font = Graphics.getVectorFont({:face => faces, :size => size});
            if (font != null) {
                return font;
            }
        }
        return fallback;
    }

    // ==================================================================
    // Page 4 — the exercises
    // ==================================================================

    //!            EXERCISES
    //!            3/5 done
    //!     (✓) Bench Press        4/4
    //!     (◔) Lateral Raise      2/4
    //!     (–) Overhead Ext.      0/3
    //!
    //! The badge carries the state: a filled tick for a finished exercise, a
    //! ring filled as far as the sets went for one cut short, an empty ring
    //! with a dash for one skipped. The badges are the shape of the session,
    //! readable without a single digit; the count on the right is the detail.
    private function _drawExercisesPage(dc as Graphics.Dc, bottom as Number) as Void {
        var h = dc.getHeight();
        var list = _workout.exercises;
        var top = _drawPageTitle(dc,
            WatchUi.loadResource(Rez.Strings.FieldExercises) as String,
            Theme.colorAccent(), MARK_NONE);
        bottom = _comfortBottom(dc, bottom);
        if (list.size() == 0) {
            _drawEmpty(dc, top, bottom);
            return;
        }

        var finished = 0;
        for (var i = 0; i < list.size(); i++) {
            if (list[i].state == EX_COMPLETED) {
                finished++;
            }
        }
        top = _drawFigure(dc, dc.getWidth() / 2, top + h / 60, finished.toString(),
            "/" + list.size().toString() + "  " +
                (WatchUi.loadResource(Rez.Strings.SummaryDone) as String),
            finished == list.size() ? Theme.colorDone() : Theme.colorText(),
            _halfAt(dc, top) * 2, h / 11, false) + h / 30;

        var font = _rowFont(dc, bottom - top, 5, 1);
        var line = dc.getFontHeight(font);
        var rowHeight = (line * 175) / 100;
        var start = _listStart(dc, top, bottom, list.size(), rowHeight, 0);
        var y = start[0];
        var clipped = start[1] == 1;
        var radius = (line * 30) / 100;
        var span = _listSpan(dc);
        var floor = clipped ? _maskBottom(dc) : bottom;

        for (var i = 0; i < list.size(); i++) {
            if (y + rowHeight > top && y < floor) {
                if (clipped) {
                    dc.setClip(0, top, dc.getWidth(), floor - top);
                }
                var whole = y >= top && y + rowHeight <= bottom;
                _drawExerciseRow(dc, list[i], span[0], y + (rowHeight - line) / 2, span[1], font, radius, whole);
                if (i < list.size() - 1) {
                    var rule = y + rowHeight - 1;
                    _hairline(dc, span[0] + radius * 3, rule, span[0] + span[1], rule);
                }
            }
            y += rowHeight;
        }
        if (clipped) {
            dc.clearClip();
        }
    }

    private function _drawExerciseRow(
        dc as Graphics.Dc,
        exercise as Exercise,
        left as Number,
        y as Number,
        width as Number,
        font as Graphics.FontDefinition,
        radius as Number,
        mayScroll as Boolean
    ) as Void {
        var line = dc.getFontHeight(font);
        var done = exercise.completedSetCount();
        var target = exercise.targetSets;
        _drawBadge(dc, left + radius, y + line / 2, radius, exercise.state, done, target);

        var count = done.toString() + "/" + target.toString();
        var countWidth = dc.getTextWidthInPixels(count, font);
        dc.setColor(exercise.state == EX_SKIPPED ? Theme.colorFaint() : Theme.colorDim(),
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + width, y, font, count, Graphics.TEXT_JUSTIFY_RIGHT);

        var nameLeft = left + radius * 3;
        var nameWidth = left + width - countWidth - radius * 4 - nameLeft;
        if (nameWidth <= 0) {
            return;
        }
        var nameColor = exercise.state == EX_SKIPPED ? Theme.colorDim() : Theme.colorText();
        if (mayScroll) {
            Marquee.drawAt(dc, nameLeft, y, exercise.shortName(),
                [font] as Array<Graphics.FontDefinition>, nameColor, nameWidth);
        } else {
            dc.setColor(nameColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(nameLeft, y, font,
                Theme.clipToWidth(dc, exercise.shortName(), font, nameWidth),
                Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    //! The state of one exercise, as a mark the size of a capital letter.
    private function _drawBadge(
        dc as Graphics.Dc,
        cx as Number,
        cy as Number,
        r as Number,
        state as ExerciseState,
        done as Number,
        target as Number
    ) as Void {
        if (state == EX_COMPLETED || (target > 0 && done >= target)) {
            _drawCheckDisc(dc, cx, cy, r, Theme.colorDone());
            return;
        }
        var pen = r / 4 < 2 ? 2 : r / 4;
        dc.setPenWidth(pen);
        dc.setColor(Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r - pen / 2);
        if (done > 0 && target > 0) {
            var sweep = (360 * done) / target;
            dc.setColor(Theme.stateColor(state), Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r - pen / 2, Graphics.ARC_CLOCKWISE, 90, (90 - sweep + 360) % 360);
        } else if (state == EX_SKIPPED) {
            dc.drawLine(cx - r / 2, cy, cx + r / 2, cy);
        }
        dc.setPenWidth(1);
    }

    //! A filled disc with a tick cut out of it.
    private function _drawCheckDisc(
        dc as Graphics.Dc,
        cx as Number,
        cy as Number,
        r as Number,
        color as Number
    ) as Void {
        var pen = r / 4 < 2 ? 2 : r / 4;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);
        dc.setColor(Theme.colorBg(), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen);
        dc.drawLine(cx - (r * 45) / 100, cy, cx - r / 8, cy + (r * 35) / 100);
        dc.drawLine(cx - r / 8, cy + (r * 35) / 100, cx + (r * 50) / 100, cy - (r * 35) / 100);
        dc.setPenWidth(1);
    }

    // ==================================================================
    // Page 5 — effort, by muscle
    // ==================================================================

    //!          RPE BY MUSCLE
    //!     ● Chest                8.5
    //!     ▰▰▰▰▰▱▱▱
    //!
    //! Not "was it hard" but "which part of me did it land on". The gauge is
    //! one segment per rung of the ladder the athlete actually uses, 6 to 10 —
    //! the segmented gauge the watch uses for its own effort scores — so a 6
    //! reads as the bottom of the scale, never as 60%. This session only: the
    //! title says so. The dot is the group's colour, as on the week page.
    private function _drawMuscleEffortPage(dc as Graphics.Dc, bottom as Number) as Void {
        var h = dc.getHeight();
        var top = _drawPageTitle(dc,
            WatchUi.loadResource(Rez.Strings.RpeByMuscle) as String,
            Theme.colorAccent(), MARK_NONE) + h / 40;
        bottom = _comfortBottom(dc, bottom);
        var averages = MuscleEffort.averages(_workout);
        var rated = MuscleEffort.ratedGroups(averages);
        if (rated == 0) {
            _drawEmpty(dc, top, bottom);
            return;
        }

        var font = _rowFont(dc, bottom - top, 3, 2);
        var line = dc.getFontHeight(font);
        var segHeight = line / 5 < 4 ? 4 : line / 5;
        var rowHeight = line + line / 6 + segHeight + line / 2;
        var start = _listStart(dc, top, bottom, rated, rowHeight, line / 2);
        var y = start[0];
        var clipped = start[1] == 1;

        var order = Muscle.browseOrder();
        // OTHER is not a group you pick from a menu, but effort really did land
        // there, and dropping it would quietly omit sets that were rated.
        order.add(Muscle.OTHER);
        var dot = line / 7 < 3 ? 3 : line / 7;
        var rungs = Rpe.size();
        var span = _listSpan(dc);
        var left = span[0];
        var width = span[1];
        var floor = clipped ? _maskBottom(dc) : bottom;

        for (var i = 0; i < order.size(); i++) {
            var group = order[i];
            var average = averages[group];
            if (average == null) {
                continue;
            }
            if (y + rowHeight > top && y < floor) {
                var rung = _nearestRung(average as Float);
                var reached = Rpe.indexOf(rung);
                var color = Rpe.color(rung);
                var value = Rpe.format(rung);
                var valueWidth = dc.getTextWidthInPixels(value, font);

                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                dc.drawText(left + width, y, font, value, Graphics.TEXT_JUSTIFY_RIGHT);

                dc.setColor(Muscle.color(group), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(left + dot, y + line / 2, dot);
                var nameLeft = left + dot * 4;
                dc.setColor(Theme.colorText(), Graphics.COLOR_TRANSPARENT);
                dc.drawText(nameLeft, y, font,
                    Theme.clipToWidth(dc, Muscle.name(group), font,
                        left + width - valueWidth - width / 10 - nameLeft),
                    Graphics.TEXT_JUSTIFY_LEFT);

                var segGap = width / 60 < 2 ? 2 : width / 60;
                var segWidth = (width - segGap * (rungs - 1)) / rungs;
                var segTop = y + line + line / 6;
                var lit = ((reached + 1) * Animator.value()).toNumber();
                for (var s = 0; s < rungs; s++) {
                    dc.setColor(s < lit ? color : Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
                    Theme.fillBar(dc, left + s * (segWidth + segGap), segTop, segWidth, segHeight);
                }
            }
            y += rowHeight;
        }
        if (clipped) {
            dc.clearClip();
        }
    }

    //! The rung nearest a computed average, so it can be drawn and coloured.
    //! An average of 8.2 is arithmetic, not a rating anybody gave; snapping it
    //! never claims more precision than the ladder has.
    private function _nearestRung(value as Float) as Float {
        var best = Rpe.SCALE[0];
        var gap = (value - best).abs();
        for (var i = 1; i < Rpe.SCALE.size(); i++) {
            var candidate = Rpe.SCALE[i];
            var distance = (value - candidate).abs();
            if (distance < gap) {
                best = candidate;
                gap = distance;
            }
        }
        return best;
    }

    // ==================================================================
    // Page 6 — records
    // ==================================================================

    //!           🏆 3 RECORDS
    //!     ╭──────────────────────────╮
    //!     │ Bench Press              │
    //!     │ WEIGHT           82.5 kg │
    //!     ╰──────────────────────────╯
    //!
    //! One card per record, so its three facts — which lift, what kind of
    //! record, the figure — cannot be read against the neighbouring one. The
    //! name has the card's full width on its own line; the kind and the figure
    //! share the line below, the figure in gold.
    private function _drawRecordsPage(dc as Graphics.Dc, bottom as Number) as Void {
        var h = dc.getHeight();
        var count = _records.size();
        var title = count == 0
            ? (WatchUi.loadResource(Rez.Strings.RecordMany) as String)
            : count.toString() + " " + (WatchUi.loadResource(count == 1
                ? Rez.Strings.RecordOne
                : Rez.Strings.RecordMany) as String);
        var top = _drawPageTitle(dc, title,
            count == 0 ? Theme.colorFaint() : Theme.colorWarm(), MARK_TROPHY) + h / 40;
        bottom = _comfortBottom(dc, bottom);
        if (count == 0) {
            _drawEmpty(dc, top, bottom);
            return;
        }

        var nameFont = _rowFont(dc, bottom - top, 4, 2);
        var nameLine = dc.getFontHeight(nameFont);
        var smallFont = nameFont == Graphics.FONT_SMALL ? Graphics.FONT_TINY : Graphics.FONT_XTINY;
        var pad = nameLine / 4;
        var cardHeight = pad + nameLine + dc.getFontHeight(smallFont) + pad;
        var spacing = nameLine / 4;
        var start = _listStart(dc, top, bottom, count, cardHeight + spacing, spacing);
        var y = start[0];
        var clipped = start[1] == 1;

        var span = _listSpan(dc);
        var floor = clipped ? _maskBottom(dc) : bottom;
        for (var i = 0; i < count; i++) {
            if (y + cardHeight > top && y < floor) {
                _drawRecordCard(dc, _records[i] as Array, span[0], y, span[1], pad,
                    nameFont, smallFont, y >= top && y + cardHeight <= bottom);
                if (clipped) {
                    dc.setClip(0, top, dc.getWidth(), floor - top);
                }
            }
            y += cardHeight + spacing;
        }
        if (clipped) {
            dc.clearClip();
        }
    }

    private function _drawRecordCard(
        dc as Graphics.Dc,
        row as Array,
        left as Number,
        y as Number,
        width as Number,
        pad as Number,
        nameFont as Graphics.FontDefinition,
        smallFont as Graphics.FontDefinition,
        mayScroll as Boolean
    ) as Void {
        // Nine parameters at most: CIQ 3 devices such as the Fenix 6 refuse a
        // tenth at compile time. The height follows from the fonts anyway.
        var height = pad * 2 + dc.getFontHeight(nameFont) + dc.getFontHeight(smallFont);
        _panel(dc, left, y, width, height, height / 4);

        // Wider at the sides than at the top: a figure set right needs air
        // between it and the card's rounded edge.
        var side = (pad * 7) / 4;
        var inner = left + side;
        var innerWidth = width - side * 2;
        var kind = row[1] as Number;
        var reps = row[2] as Number;
        var weight = row[3] as Float?;

        if (mayScroll) {
            Marquee.drawAt(dc, inner, y + pad, row[0] as String,
                [nameFont] as Array<Graphics.FontDefinition>, Theme.colorText(), innerWidth);
        } else {
            Theme.drawClippedAt(dc, inner, y + pad, row[0] as String, nameFont,
                Theme.colorText(), innerWidth);
        }

        // The figure is what was actually beaten: the load for a heaviest-set
        // record, the estimate for an estimated one-rep max, the set itself
        // for a volume record.
        var figure = "";
        if (weight != null) {
            var kg = weight as Float;
            if (kind == History.RECORD_1RM) {
                figure = Theme.formatWeight(History.estimated1RM(reps, kg)) + " " + Units.label();
            } else if (kind == History.RECORD_VOLUME) {
                figure = reps.toString() + " x " + Theme.formatWeight(kg) + " " + Units.label();
            } else {
                figure = Theme.formatWeight(kg) + " " + Units.label();
            }
        }
        var lineY = y + pad + dc.getFontHeight(nameFont);
        var figureWidth = dc.getTextWidthInPixels(figure, smallFont);
        dc.setColor(Theme.colorWarm(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(inner + innerWidth, lineY, smallFont, figure, Graphics.TEXT_JUSTIFY_RIGHT);

        var label = WatchUi.loadResource(_recordLabel(kind)) as String;
        dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(inner, lineY, smallFont,
            Theme.clipToWidth(dc, label, smallFont, innerWidth - figureWidth - pad),
            Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! A cup on a stem — drawn, not a glyph, so it is the same mark on every
    //! device whatever its fonts carry.
    private function _drawTrophy(
        dc as Graphics.Dc,
        x as Number,
        y as Number,
        size as Number,
        color as Number
    ) as Void {
        var cx = x + size / 2;
        var cupWidth = (size * 70) / 100;
        var cupHeight = (size * 55) / 100;
        var cupLeft = cx - cupWidth / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [cupLeft, y],
            [cupLeft + cupWidth, y],
            [cx + cupWidth / 4, y + cupHeight],
            [cx - cupWidth / 4, y + cupHeight]
        ] as Array<Graphics.Point2D>);
        var pen = size / 10 < 1 ? 1 : size / 10;
        dc.setPenWidth(pen);
        var handle = size / 6;
        dc.drawCircle(cupLeft, y + handle, handle);
        dc.drawCircle(cupLeft + cupWidth, y + handle, handle);
        dc.setPenWidth(1);
        dc.fillRectangle(cx - pen / 2 - 1, y + cupHeight, pen + 2, size / 5);
        dc.fillRectangle(cx - size / 4, y + size - size / 6, size / 2, size / 6);
    }

    private function _recordLabel(kind as Number) as ResourceId {
        if (kind == History.RECORD_WEIGHT) {
            return Rez.Strings.RecordWeight;
        }
        if (kind == History.RECORD_1RM) {
            return Rez.Strings.Record1RM;
        }
        return Rez.Strings.RecordVolume;
    }

    // ==================================================================
    // Page 7 — the week
    // ==================================================================

    //!          THIS WEEK
    //!            29.2 t
    //!     ▬▬▬▬▬▬▬▬ ▬▬▬▬▬ ▬▬▬ ▬ ▬     the split, at a glance
    //!     ● Quads               9.8 t
    //!     ● Chest               8.4 t
    //!
    //! The week's total is the hero; the bar under it is how that total
    //! divides, in each group's colour — whether pushing and pulling are
    //! anywhere near each other shows there before a row is read. Only groups
    //! actually trained get a row, busiest first. The title names the span:
    //! a row labelled Back under a leg session would otherwise read as the
    //! app deciding you trained your back.
    private function _drawWeekPage(dc as Graphics.Dc, bottom as Number) as Void {
        var h = dc.getHeight();
        var top = _drawPageTitle(dc,
            WatchUi.loadResource(Rez.Strings.ThisWeek) as String,
            Theme.colorAccent(), MARK_NONE);
        bottom = _comfortBottom(dc, bottom);

        var order = Muscle.browseOrder();
        var groups = [] as Array<Number>;
        var total = 0;
        for (var i = 0; i < order.size(); i++) {
            var v = _weekly[order[i]];
            if (v <= 0) {
                continue;
            }
            total += v;
            // Insertion: ten groups at most, and ties keep the browse order.
            groups.add(order[i]);
            for (var j = groups.size() - 1; j > 0 && _weekly[groups[j]] > _weekly[groups[j - 1]]; j--) {
                var swap = groups[j];
                groups[j] = groups[j - 1];
                groups[j - 1] = swap;
            }
        }
        if (total <= 0) {
            _drawEmpty(dc, top, bottom);
            return;
        }

        var hero = _splitVolume(total.toFloat());
        top = _drawFigure(dc, dc.getWidth() / 2, top + h / 60, hero[0], hero[1],
            Theme.colorText(), _halfAt(dc, top) * 2, h / 11, false) + h / 22;

        // The split: one rounded bar cut into the groups' colours.
        var barHeight = h / 45 < 4 ? 4 : h / 45;
        var barSpan = _listSpan(dc);
        var barLeft = barSpan[0];
        var barWidth = barSpan[1];
        var drawn = (barWidth * Animator.value()).toNumber();
        var segGap = barHeight / 2 < 2 ? 2 : barHeight / 2;
        var x = barLeft;
        for (var i = 0; i < groups.size(); i++) {
            var share = (barWidth * _weekly[groups[i]]) / total;
            if (i == groups.size() - 1) {
                share = barLeft + barWidth - x;
            }
            var piece = share - (i < groups.size() - 1 ? segGap : 0);
            if (x + piece > barLeft + drawn) {
                piece = barLeft + drawn - x;
            }
            if (piece > 0) {
                dc.setColor(Muscle.color(groups[i]), Graphics.COLOR_TRANSPARENT);
                Theme.fillBar(dc, x, top, piece < barHeight ? barHeight : piece, barHeight);
            }
            x += share;
        }
        top += barHeight + h / 22;

        var font = _rowFont(dc, bottom - top, 5, 1);
        var line = dc.getFontHeight(font);
        var rowHeight = (line * 150) / 100;
        var start = _listStart(dc, top, bottom, groups.size(), rowHeight, line / 2);
        var y = start[0];
        var clipped = start[1] == 1;
        var dot = line / 7 < 3 ? 3 : line / 7;
        var span = _listSpan(dc);
        var left = span[0];
        var width = span[1];
        var floor = clipped ? _maskBottom(dc) : bottom;

        for (var i = 0; i < groups.size(); i++) {
            if (y + rowHeight > top && y < floor) {
                var group = groups[i];
                var value = Theme.formatVolume(_weekly[group].toFloat());
                var valueWidth = dc.getTextWidthInPixels(value, font);
                dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
                dc.drawText(left + width, y, font, value, Graphics.TEXT_JUSTIFY_RIGHT);

                dc.setColor(Muscle.color(group), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(left + dot, y + line / 2, dot);
                var nameLeft = left + dot * 4;
                dc.setColor(Theme.colorText(), Graphics.COLOR_TRANSPARENT);
                dc.drawText(nameLeft, y, font,
                    Theme.clipToWidth(dc, Muscle.name(group), font,
                        left + width - valueWidth - width / 16 - nameLeft),
                    Graphics.TEXT_JUSTIFY_LEFT);
            }
            y += rowHeight;
        }
        if (clipped) {
            dc.clearClip();
        }
    }

    //! A volume as `[figure, unit]`, so the figure can take the number font
    //! and the unit sit small beside it. Same rounding as Theme.formatVolume.
    private function _splitVolume(kg as Float) as Array<String> {
        var shown = Units.fromKg(kg);
        if (shown >= 1000.0) {
            var tenths = Math.round(shown / 100.0).toNumber();
            var big = (tenths / 10).toString() + "." + (tenths % 10).toString();
            return (Units.imperial()
                ? [big, "k " + Units.label()]
                : [big, "t"]) as Array<String>;
        }
        return [Theme.formatNumber(shown), Units.label()] as Array<String>;
    }
}

class WorkoutSummaryDelegate extends WatchUi.BehaviorDelegate {

    private var _view as WorkoutSummaryView;

    public function initialize(view as WorkoutSummaryView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onNextPage() as Boolean {
        _view.turnPage(1);
        return true;
    }

    public function onPreviousPage() as Boolean {
        _view.turnPage(-1);
        return true;
    }

    //! Nothing is left to decide here — both buttons mean "I have read it".
    public function onSelect() as Boolean {
        return _leave();
    }

    public function onBack() as Boolean {
        return _leave();
    }

    private function _leave() as Boolean {
        var list = new WorkoutListView();
        WatchUi.switchToView(list, new WorkoutListDelegate(list), WatchUi.SLIDE_RIGHT);
        return true;
    }
}
