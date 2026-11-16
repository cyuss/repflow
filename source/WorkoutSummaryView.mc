import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Math;

//! End-of-workout recap.
//!
//!   Page 1 — the work        time, sets done / planned, reps, volume
//!   Page 2 — the body        Body Battery, recovery, calories, heart rate
//!   Page 3 — time in zones   the bar chart a Fenix shows after any activity
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

    //! The ink height `_drawFigure` would use for these arguments.
    private function _figureInk(
        dc as Graphics.Dc,
        value as String,
        unit as String,
        maxWidth as Number,
        maxInk as Number
    ) as Number {
        var fonts = [
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_MILD,
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY
        ] as Array<Graphics.FontDefinition>;
        var unitWidth = unit.length() > 0
            ? dc.getTextWidthInPixels(" " + unit, Graphics.FONT_XTINY)
            : 0;
        return Theme.inkHeight(Theme.pickFontFitting(dc, value, fonts, maxWidth - unitWidth, maxInk));
    }

    //! An arc gauge: a track of `span` degrees opening at the bottom, filled
    //! clockwise from its left end by `fraction`.
    private function _drawGauge(
        dc as Graphics.Dc,
        cx as Number,
        cy as Number,
        radius as Number,
        pen as Number,
        span as Number,
        fraction as Float,
        color as Number
    ) as Void {
        var start = 270 - (360 - span) / 2;          // left end, degrees
        var finish = (start - span + 360) % 360;     // right end
        dc.setPenWidth(pen);
        dc.setColor(_track(), Graphics.COLOR_TRANSPARENT);
        if (span >= 360) {
            dc.drawCircle(cx, cy, radius);
        } else {
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, start, finish);
        }
        var f = fraction > 1.0 ? 1.0 : fraction;
        var sweep = (span * f * Animator.value()).toNumber();
        if (sweep > 0) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            if (sweep >= 360) {
                dc.drawCircle(cx, cy, radius);
            } else {
                dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, start, (start - sweep + 360) % 360);
            }
        }
        dc.setPenWidth(1);
    }

    // ==================================================================
    // Page 1 — the work
    // ==================================================================

    //!              PUSH DAY
    //!            🏆 3 RECORDS
    //!              1:05:20
    //!                TIME
    //!        ( 12 )  ( 122 )  ( 4.6 )
    //!         /17
    //!         SETS     REPS    VOLUME
    //!
    //! The session's name and how it ended, then the time as the hero, then
    //! three pods — small ring gauges, the shape the watch gives its own
    //! glanceable figures. The SETS pod is the only one with a real fraction
    //! to show, sets done against sets planned, so it is the only one whose
    //! ring fills partway; the other two close their ring in their colour.
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

        // The pods sit low, as large as they can be while their outer edges
        // stay inside the ring; the hero takes the space above them.
        var gap = h / 32;
        var r = (h * 12) / 100;
        var pcy = h / 2 + (h * 19) / 100;
        var reach = _maskRadius(dc) - h / 60;
        // Shrink until the outer pods clear the curve.
        while (r > 10) {
            var step0 = r * 2 + gap;
            var dy0 = pcy - h / 2;
            if (Math.sqrt((step0 * step0 + dy0 * dy0).toFloat()).toNumber() + r <= reach) {
                break;
            }
            r -= 1;
        }
        var podsTop = pcy - r;

        // The hero, centred between the status line and the pods.
        var capLine = dc.getFontHeight(Graphics.FONT_XTINY);
        var heroInk = podsTop - top - capLine - h / 14;
        if (heroInk > h / 5) {
            heroInk = h / 5;
        }
        var duration = Theme.formatDuration(_summary.durationSec);
        var heroWidth = _halfAt(dc, top) * 2;
        var ink = _figureInkLarge(dc, duration, heroWidth, heroInk);
        var heroTop = top + (podsTop - top - ink - capLine - h / 80) / 2;
        var below = _drawFigure(dc, cx, heroTop, duration, "",
            Theme.colorText(), heroWidth, heroInk, true);
        dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, below + h / 120, Graphics.FONT_XTINY,
            WatchUi.loadResource(Rez.Strings.FieldTime) as String, Graphics.TEXT_JUSTIFY_CENTER);

        var step = r * 2 + gap;
        var planned = _summary.plannedSets;
        var done = _summary.completedSets;
        var volume = _splitVolume(_summary.totalVolume);
        _drawPod(dc, cx - step, pcy, r, done.toString(), "/" + planned.toString(),
            WatchUi.loadResource(Rez.Strings.FieldSets) as String,
            planned > 0 ? done.toFloat() / planned.toFloat() : 0.0,
            done >= planned ? Theme.colorDone() : Theme.colorWarm());
        _drawPod(dc, cx, pcy, r, _summary.totalReps.toString(), "",
            WatchUi.loadResource(Rez.Strings.FieldReps) as String, 1.0, Theme.colorText());
        _drawPod(dc, cx + step, pcy, r, volume[0], volume[1],
            WatchUi.loadResource(Rez.Strings.FieldVolume) as String, 1.0, Theme.colorAccent());
    }

    private function _figureInkLarge(
        dc as Graphics.Dc,
        value as String,
        maxWidth as Number,
        maxInk as Number
    ) as Number {
        var fonts = [
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_MILD,
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL
        ] as Array<Graphics.FontDefinition>;
        return Theme.inkHeight(Theme.pickFontFitting(dc, value, fonts, maxWidth, maxInk));
    }

    //! One pod: a ring gauge with the figure and its caption inside it. A
    //! secondary part of the figure — the "/17" of "12/17", the "t" of
    //! "4.6 t" — sits small beside it, on its baseline.
    private function _drawPod(
        dc as Graphics.Dc,
        cx as Number,
        cy as Number,
        r as Number,
        value as String,
        sub as String,
        caption as String,
        fraction as Float,
        color as Number
    ) as Void {
        var pen = r / 8 < 3 ? 3 : r / 8;
        _drawGauge(dc, cx, cy, r, pen, 360, fraction, color);

        var hole = (r - pen) * 2;
        var capFont = Graphics.FONT_XTINY;
        var capLine = dc.getFontHeight(capFont);
        var maxInk = (hole * 34) / 100;
        var inner = (hole * 80) / 100;
        var ink = _figureInk(dc, value, sub, inner, maxInk);
        var block = ink + (capLine * 85) / 100;
        var y = cy - block / 2;
        _drawFigure(dc, cx, y, value, sub, color, inner, maxInk, false);
        dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
        var shown = Theme.clipToWidth(dc, caption, capFont, inner + pen);
        dc.drawText(cx, y + ink + capLine / 10, capFont, shown, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ==================================================================
    // Page 2 — the body
    // ==================================================================

    //!                BODY
    //!     REC HR    ╭─────╮    KCAL
    //!       -31    (  -21  )    512
    //!              ( BODY  )
    //!     ♥ AVG     ╰ BATT╯    ♥ MAX
    //!       118                 161
    //!
    //! What the session cost the athlete, rather than how much iron moved.
    //! Body Battery is the centre of the page, on the arc the watch draws it
    //! with everywhere else — filled to where the session left you, with what
    //! it cost in the middle. The four heart and energy figures sit in the
    //! four corners around it, where a round screen has room and nothing else
    //! to put there.
    private function _drawBodyPage(dc as Graphics.Dc, bottom as Number) as Void {
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var top = _drawPageTitle(dc,
            WatchUi.loadResource(Rez.Strings.SummaryBody) as String,
            Theme.colorAccent(), MARK_NONE);

        // Best beats dropped in a minute of rest, and what the session cost in
        // Body Battery. "--" when the watch could not measure them.
        var recoveryText = _metrics.recovery == null
            ? LiveMetrics.NO_VALUE
            : "-" + (_metrics.recovery as Number).toString();
        var batteryText = LiveMetrics.NO_VALUE;
        var batteryColor = Theme.colorFaint();
        var start = _metrics.batteryStart;
        var finish = LiveMetrics.bodyBattery();
        if (start != null && finish != null) {
            var spent = (start as Number) - (finish as Number);
            batteryText = spent > 0 ? "-" + spent.toString() : (finish as Number).toString();
            batteryColor = Theme.colorText();
        } else if (finish != null) {
            batteryText = (finish as Number).toString();
            batteryColor = Theme.colorText();
        }

        // Two columns: the gauge on the left, the four figures stacked on the
        // right, the pair centred on the glass a little below the title.
        var capFont = Graphics.FONT_XTINY;
        var capLine = dc.getFontHeight(capFont);
        var radius = (h * 12) / 100;
        var pen = h / 40 < 4 ? 4 : h / 40;
        var gx = cx - (h * 26) / 100;
        var gy = h / 2 + h / 40 - capLine / 2;
        _drawGauge(dc, gx, gy, radius, pen, 270,
            finish != null ? (finish as Number).toFloat() / 100.0 : 0.0, Theme.colorAccent());
        var hole = (radius - pen) * 2;
        var maxInk = (hole * 48) / 100;
        var ink = _figureInk(dc, batteryText, "", (hole * 78) / 100, maxInk);
        _drawFigure(dc, gx, gy - ink / 2, batteryText, "", batteryColor,
            (hole * 78) / 100, maxInk, false);
        dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(gx, gy + radius + h / 120 - capLine / 3, capFont,
            WatchUi.loadResource(Rez.Strings.FieldBattery) as String, Graphics.TEXT_JUSTIFY_CENTER);

        // The list: four rows, caption left, figure right, hairlines between.
        var rowHeight = (h * 12) / 100;
        var listTop = h / 2 + h / 40 - rowHeight * 2;
        var listLeft = gx + radius + pen + h / 25;
        var rows = [
            [WatchUi.loadResource(Rez.Strings.FieldRecovery) as String, recoveryText,
                _metrics.recovery == null ? Theme.colorFaint() : Theme.colorDone(), false],
            [WatchUi.loadResource(Rez.Strings.FieldKcal) as String,
                LiveMetrics.format(_metrics.calories), Theme.colorWarm(), false],
            [WatchUi.loadResource(Rez.Strings.FieldAvgHr) as String,
                LiveMetrics.format(_metrics.averageHeartRate), Theme.colorHr(), true],
            [WatchUi.loadResource(Rez.Strings.FieldMaxHr) as String,
                LiveMetrics.format(_metrics.maxHeartRate), Theme.colorHr(), true]
        ] as Array<Array>;
        var fonts = [
            Graphics.FONT_NUMBER_MILD,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY
        ] as Array<Graphics.FontDefinition>;
        // One right edge for the whole column, at its narrower end, so the
        // figures line up.
        var topHalf = _halfAt(dc, listTop);
        var bottomHalf = _halfAt(dc, listTop + rowHeight * rows.size());
        var right = cx + (topHalf < bottomHalf ? topHalf : bottomHalf) - h / 50;
        for (var i = 0; i < rows.size(); i++) {
            var row = rows[i];
            var rowTop = listTop + i * rowHeight;
            var mid = rowTop + rowHeight / 2;
            var x = listLeft;
            if (row[3] as Boolean) {
                var size = (capLine * 50) / 100;
                Theme.drawHeart(dc, x + size / 2, mid, size, Theme.colorHr());
                x += size + size / 2;
            }
            var caption = row[0] as String;
            dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, mid, capFont, caption,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            var room = right - (x + dc.getTextWidthInPixels(caption, capFont) + h / 16);
            var value = row[1] as String;
            var font = Theme.pickFontFitting(dc, value, fonts, room, (rowHeight * 50) / 100);
            var valueInk = Theme.inkHeight(font);
            dc.setColor(row[2] as Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(right, mid - valueInk / 2, font, value, Graphics.TEXT_JUSTIFY_RIGHT);
            if (i < rows.size() - 1) {
                _hairline(dc, listLeft, rowTop + rowHeight, right, rowTop + rowHeight);
            }
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
        var font = _rowFont(dc, bottom - top, ZoneTracker.ZONE_COUNT + 1, 1);
        var line = dc.getFontHeight(font);
        var rowHeight = (line * 128) / 100;
        var block = rowHeight * ZoneTracker.ZONE_COUNT - (rowHeight - line);
        var y = h / 2 - block / 2 + h / 40;
        if (y < top + h / 40) {
            y = top + h / 40;
        }
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
        var rowHeight = line + line / 2;
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
                _drawExerciseRow(dc, list[i], span[0], y + line / 4, span[1], font, radius, whole);
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
        var nameWidth = left + width - countWidth - radius - nameLeft;
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
                        left + width - valueWidth - width / 16 - nameLeft),
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

        var inner = left + pad;
        var innerWidth = width - pad * 2;
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
            Theme.colorText(), _halfAt(dc, top) * 2, h / 11, false) + h / 30;

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
        top += barHeight + h / 30;

        var font = _rowFont(dc, bottom - top, 5, 1);
        var line = dc.getFontHeight(font);
        var rowHeight = line + line / 3;
        var start = _listStart(dc, top, bottom, groups.size(), rowHeight, line / 3);
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
