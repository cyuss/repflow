import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Application.Storage;

//! RepFlow in the glance loop:
//!
//!     (◆)  SESSIONS
//!          3            ▂ █ ▁ ▆ · · ·
//!     ▲ +1 vs last wk  ·  4.2 t
//!
//! Glances exist for watch apps from Connect IQ 4 — a Fenix 7 or later. A
//! Fenix 6 never asks for one, and RepFlow there is reached from the app list.
//!
//! **It runs in a few dozen kilobytes** (32 to 64 KB, by device) with only
//! what is annotated `:glance` loaded. So it reads one small Storage value
//! written by the app (AnalyticsData.writeGlanceCache) and counts the Garmin
//! side live from the watch's history: a native session shows up here without
//! RepFlow having been opened since. Nothing from Theme, Units or the session
//! log is reachable from here, by design.
(:glance :analytics)
class RepFlowGlanceView extends WatchUi.GlanceView {

    public function initialize() {
        GlanceView.initialize();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        GlanceDraw.draw(dc, 0, 0, dc.getWidth(), dc.getHeight());
    }
}

//! The figures and the drawing, shared by the real glance and by the
//! full-screen preview used while designing it (`just glance-preview`).
(:glance :analytics)
module GlanceDraw {

    //! The glance cannot reach Theme, so its colours are stated here: the
    //! same ink as the app, and the same two source colours as the charts —
    //! validated with the dataviz palette checker (see AnalyticsUi).
    const TEXT = 0xFFFFFF;
    const DIM = 0xAAAAAA;
    const FAINT = 0x3A3A3A;
    const ACCENT = 0x00AAFF;
    const REPFLOW = 0x2A8BE6;
    const GARMIN = 0xBF7A20;
    const UP = 0x55DD77;
    const DOWN = 0xFFAA00;

    // Fields of figures().
    const F_WEEK = 0;
    const F_PREVIOUS = 1;
    const F_KG = 2;
    const F_LAST_START = 3;
    const F_LAST_NAME = 4;
    const F_LAST_GARMIN = 5;
    const F_IMPERIAL = 6;
    const F_DAY_REPFLOW = 7;   //! seconds per weekday, Monday first
    const F_DAY_GARMIN = 8;

    //! How long worked-out figures are reused. The glance is repainted far
    //! more often than its figures change — a session count moves a few times
    //! a week — and each fresh answer means reading Storage and walking the
    //! watch's activity history.
    const FIGURES_TTL = 300;

    var _figures as Array? = null;
    var _figuresAt as Number = 0;

    //! `figures`, reused for a few minutes, and worked out again at once when
    //! the week has turned since (Monday midnight changes everything shown).
    public function cachedFigures(now as Number) as Array {
        var f = _figures;
        if (f != null && now >= _figuresAt && now - _figuresAt < FIGURES_TTL
                && NativeActivities.weekStart(now) == NativeActivities.weekStart(_figuresAt)) {
            return f;
        }
        f = figures(now);
        _figures = f;
        _figuresAt = now;
        return f;
    }

    //! Everything the glance shows, worked out live from the app's cache and
    //! the watch's own history.
    public function figures(now as Number) as Array {
        var cache = null;
        try {
            cache = Storage.getValue(AnalyticsKeys.GLANCE);
        } catch (e) {
        }
        var rf = [] as Array;
        var lastStart = 0;
        var lastName = "";
        var imperial = false;
        if (cache instanceof Dictionary) {
            var d = cache as Dictionary;
            var list = d["rf"] as Object?;
            if (list instanceof Array) {
                rf = list as Array;
            }
            var ls = d["ls"] as Object?;
            if (ls instanceof Number) {
                lastStart = ls as Number;
            }
            var ln = d["ln"] as Object?;
            if (ln instanceof String) {
                lastName = ln as String;
            }
            imperial = d["imp"] == true;
        }

        var day = NativeActivities.DAY;
        var week = NativeActivities.weekStart(now);
        var previous = week - NativeActivities.WEEK;
        var thisWeek = 0;
        var lastWeek = 0;
        var kg = 0;
        var dayRepFlow = [0, 0, 0, 0, 0, 0, 0] as Array<Number>;
        var dayGarmin = [0, 0, 0, 0, 0, 0, 0] as Array<Number>;
        var starts = [] as Array<Number>;
        for (var i = 0; i < rf.size(); i++) {
            var row = rf[i] as Object?;
            if (!(row instanceof Array) || (row as Array).size() < 2) {
                continue;
            }
            var a = row as Array;
            var start = a[0] as Object?;
            var volume = a[1] as Object?;
            if (!(start instanceof Number) || !(volume instanceof Number)) {
                continue;
            }
            // Caches written before durations were added have none: a
            // session still shows on its day, at a nominal half hour.
            var seconds = 1800;
            if (a.size() > 2) {
                var dur = a[2] as Object?;
                if (dur instanceof Number) {
                    seconds = dur as Number;
                }
            }
            var at = start as Number;
            starts.add(at);
            if (at >= week) {
                thisWeek++;
                kg += volume as Number;
                var index = (at - week) / day;
                if (index >= 0 && index < 7) {
                    dayRepFlow[index] += seconds;
                }
            } else if (at >= previous) {
                lastWeek++;
            }
        }
        if (lastStart > 0) {
            starts.add(lastStart);
        }

        // The Garmin side, live. RepFlow's own sessions are in the watch's
        // history too, and are not counted twice.
        var lastGarmin = 0;
        var natives = NativeActivities.trainingSince(previous);
        for (var i = 0; i < natives.size(); i++) {
            var start = natives[i][0];
            if (NativeActivities.matches(start, starts)) {
                continue;
            }
            if (start >= week) {
                thisWeek++;
                var index = (start - week) / day;
                if (index >= 0 && index < 7) {
                    dayGarmin[index] += natives[i][1];
                }
            } else {
                lastWeek++;
            }
            if (start > lastGarmin) {
                lastGarmin = start;
            }
        }
        var garminIsLast = lastGarmin > lastStart;
        return [thisWeek, lastWeek, kg,
            garminIsLast ? lastGarmin : lastStart,
            lastName, garminIsLast, imperial, dayRepFlow, dayGarmin] as Array;
    }

    //! The glance, in the rectangle given:
    //!
    //!     (◆)  REPFLOW · THIS WEEK            ▂ █ ▁ ▆ · · ·
    //!          3  sessions                    M T W T F S S
    //!             4.2 t
    //!     ▲ +1 vs last week   Push Day, yesterday
    //!
    //! A brand mark, the week's count as the hero in the watch's number font,
    //! the week day by day beside it, and one line of context: the trend
    //! against last week and the week's volume. Nothing is decoration: each part answers "how is my
    //! week going" from a different side.
    public function draw(dc as Graphics.Dc, x as Number, y as Number, w as Number, h as Number) as Void {
        var now = Time.now().value();
        var f = cachedFigures(now);
        var thisWeek = f[F_WEEK] as Number;
        var lastWeek = f[F_PREVIOUS] as Number;
        var kg = f[F_KG] as Number;
        var lastStart = f[F_LAST_START] as Number;

        // The glance row runs past the curve of the glass on the right; text
        // measured to its full width was cut by the bezel, not by `clip`.
        var width = (w * 86) / 100;
        var small = Graphics.FONT_XTINY;
        var smallLine = dc.getFontHeight(small);

        // Three bands: title, hero, context. The hero takes what is left.
        var heroH = h - smallLine * 2 - h / 20;
        if (heroH < smallLine) {
            heroH = smallLine;
        }
        var top = y + (h - smallLine * 2 - heroH) / 2;

        // The brand mark: a ring in the accent with a dumbbell inside, the
        // height of the title and hero together.
        var markR = (smallLine * 72) / 100;
        if (markR > width / 12) {
            markR = width / 12;
        }
        var markCx = x + markR + 1;
        var markCy = top + (smallLine + heroH) / 2;
        _drawMark(dc, markCx, markCy, markR);
        var textLeft = x + markR * 2 + markR / 2 + 2;

        // Title, set smaller than the system's smallest where the watch has
        // scalable fonts: it labels the count, it is not the thing read, and
        // at full size it crowded the week beside it.
        var titleFont = small as Graphics.FontType;
        if (Graphics has :getVectorFont) {
            var vf = Graphics.getVectorFont({
                :face => ["RobotoCondensedBold", "RobotoMedium", "RobotoRegular"],
                :size => (smallLine * 62) / 100
            });
            if (vf != null) {
                titleFont = vf;
            }
        }
        var title = WatchUi.loadResource(Rez.Strings.GlanceTitle) as String;
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textLeft, top + (smallLine - dc.getFontHeight(titleFont)) / 2, titleFont,
            clip(dc, title, titleFont, x + width - textLeft),
            Graphics.TEXT_JUSTIFY_LEFT);
        var heroTop = top + smallLine;

        // The week, day by day, beside the hero.
        // It starts after the title, so the two never touch, and runs the
        // height of title and hero together, its initials level with the
        // bottom of the count.
        var chartRight = x + width;
        var chartLeft = textLeft + dc.getTextWidthInPixels(title, titleFont) + width / 16;
        if (chartLeft < chartRight - (width * 44) / 100) {
            chartLeft = chartRight - (width * 44) / 100;
        }
        if (chartLeft > chartRight - (width * 32) / 100) {
            chartLeft = chartRight - (width * 32) / 100;
        }
        var chartW = chartRight - chartLeft;
        _drawWeek(dc, chartLeft, top + smallLine / 6, chartW, smallLine + heroH - smallLine / 6,
            f[F_DAY_REPFLOW] as Array<Number>, f[F_DAY_GARMIN] as Array<Number>,
            (now - NativeActivities.weekStart(now)) / NativeActivities.DAY);

        var textRight = chartLeft - width / 24;
        var textWidth = textRight - textLeft;

        // Hero: the week's count, in the number font.
        var fonts = [Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD,
            Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL] as Array<Graphics.FontDefinition>;
        var count = thisWeek.toString();
        var heroFont = Graphics.FONT_SMALL;
        for (var i = 0; i < fonts.size(); i++) {
            if (_ink(fonts[i]) <= heroH && dc.getTextWidthInPixels(count, fonts[i]) <= textWidth) {
                heroFont = fonts[i];
                break;
            }
        }
        var ink = _ink(heroFont);
        var digitsTop = heroTop + (heroH - ink) / 2;
        dc.setColor(TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textLeft, digitsTop, heroFont, count, Graphics.TEXT_JUSTIFY_LEFT);
        // The unit is the title, as on Garmin's own glances ("STEPS", then
        // the number); the week is said by the chart beside it and by the
        // trend under it. The volume goes to the line below.
        var loadShown = false;

        // Context: the trend, then the last session.
        var lineY = heroTop + heroH + h / 40;
        var cx = x;
        if (thisWeek == 0 && lastWeek == 0 && lastStart == 0) {
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, lineY, small, clip(dc, WatchUi.loadResource(Rez.Strings.GlanceNone) as String,
                small, width), Graphics.TEXT_JUSTIFY_LEFT);
            return;
        }
        var diff = thisWeek - lastWeek;
        var arrow = (smallLine * 45) / 100;
        var ay = lineY + smallLine / 2;
        if (diff != 0) {
            dc.setColor(diff > 0 ? UP : DOWN, Graphics.COLOR_TRANSPARENT);
            if (diff > 0) {
                dc.fillPolygon([[cx, ay + arrow / 2], [cx + arrow, ay + arrow / 2],
                    [cx + arrow / 2, ay - arrow / 2]] as Array<Graphics.Point2D>);
            } else {
                dc.fillPolygon([[cx, ay - arrow / 2], [cx + arrow, ay - arrow / 2],
                    [cx + arrow / 2, ay + arrow / 2]] as Array<Graphics.Point2D>);
            }
            cx += arrow + arrow / 2;
            var delta = (diff > 0 ? "+" : "") + diff.toString();
            dc.drawText(cx, lineY, small, delta, Graphics.TEXT_JUSTIFY_LEFT);
            cx += dc.getTextWidthInPixels(delta, small) + arrow / 2;
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            var vs = WatchUi.loadResource(Rez.Strings.GlanceVsPrev) as String;
            dc.drawText(cx, lineY, small, vs, Graphics.TEXT_JUSTIFY_LEFT);
            cx += dc.getTextWidthInPixels(vs, small);
        } else {
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            var same = WatchUi.loadResource(Rez.Strings.GlanceSamePrev) as String;
            dc.drawText(cx, lineY, small, same, Graphics.TEXT_JUSTIFY_LEFT);
            cx += dc.getTextWidthInPixels(same, small);
        }
        // The week's volume, when the hero line had no room for it.
        if (kg > 0 && !loadShown) {
            var tailLoad = "  ·  " + volume(kg, f[F_IMPERIAL] as Boolean);
            if (dc.getTextWidthInPixels(tailLoad, small) <= x + width - cx) {
                dc.setColor(TEXT, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, lineY, small, tailLoad, Graphics.TEXT_JUSTIFY_LEFT);
                cx += dc.getTextWidthInPixels(tailLoad, small);
            }
        }
        // The last session only when it fits whole: a name cut to "Garmi."
        // is noise, and the day chart above already says when it was.
        if (lastStart > 0) {
            var name = (f[F_LAST_GARMIN] as Boolean) || (f[F_LAST_NAME] as String).length() == 0
                ? WatchUi.loadResource(Rez.Strings.GlanceGarmin) as String
                : f[F_LAST_NAME] as String;
            var tail = "  ·  " + name + ", " + when(lastStart, now);
            if (dc.getTextWidthInPixels(tail, small) <= x + width - cx) {
                dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, lineY, small, tail, Graphics.TEXT_JUSTIFY_LEFT);
            }
        }
    }

    //! The week, Monday first: a column per day, each on its own faint track
    //! so the seven read as one shape, filled from the bottom with that day's
    //! training time, RepFlow and Garmin as one. Days to come keep an even
    //! fainter track.
    //! Under each column its initial, today's in white, the rest dim.
    //!
    //!     ▐ ▐ █ ▐ ▐ ▐ ▐
    //!     ▐ █ █ ▐ ▐ ▐ ▐
    //!     M T W T F S S
    function _drawWeek(
        dc as Graphics.Dc,
        left as Number,
        top as Number,
        width as Number,
        height as Number,
        repflow as Array<Number>,
        garmin as Array<Number>,
        today as Number
    ) as Void {
        // The initials, at a size of their own where the watch has scalable
        // fonts; without them the system's smallest is too big for the row,
        // and today is marked by a white track instead.
        var letters = null as Graphics.FontType?;
        if (Graphics has :getVectorFont) {
            letters = Graphics.getVectorFont({
                :face => ["RobotoCondensedBold", "RobotoMedium", "RobotoRegular"],
                :size => (height * 19) / 100
            });
        }
        var letterH = letters != null ? dc.getFontHeight(letters as Graphics.FontType) : 0;
        var plotTop = top;
        var plotBottom = top + height - (letterH > 0 ? (letterH * 95) / 100 : 0);
        var plot = plotBottom - plotTop;

        var gap = width / 14 < 3 ? 3 : width / 14;
        var bar = (width - gap * 6) / 7;
        if (bar < 3 || plot < bar) {
            return;
        }
        var radius = bar / 2;
        // Scaled to at least an hour, so one short session is not a full bar.
        var peak = 3600;
        for (var d = 0; d < 7; d++) {
            if (repflow[d] + garmin[d] > peak) {
                peak = repflow[d] + garmin[d];
            }
        }
        var initials = WatchUi.loadResource(Rez.Strings.GlanceDayLetters) as String;
        var rounded = dc has :fillRoundedRectangle;
        for (var d = 0; d < 7; d++) {
            var bx = left + d * (bar + gap);

            // The track.
            dc.setColor(d > today ? 0x1F1F1F : (letters == null && d == today ? 0x555555 : 0x333333),
                Graphics.COLOR_TRANSPARENT);
            _pill(dc, bx, plotTop, bar, plot, radius, rounded);

            // The day's training time, RepFlow and Garmin together.
            var total = repflow[d] + garmin[d];
            if (total > 0) {
                var fill = (plot * total) / peak;
                // Never thinner than round: a sliver reads as a smudge.
                if (fill < bar) {
                    fill = bar;
                }
                dc.setColor(REPFLOW, Graphics.COLOR_TRANSPARENT);
                _pill(dc, bx, plotBottom - fill, bar, fill, radius, rounded);
            }

            if (letters != null && d < initials.length()) {
                dc.setColor(d == today ? TEXT : (d > today ? 0x5A5A5A : DIM),
                    Graphics.COLOR_TRANSPARENT);
                dc.drawText(bx + bar / 2, plotBottom + letterH / 20, letters as Graphics.FontType,
                    initials.substring(d, d + 1) as String, Graphics.TEXT_JUSTIFY_CENTER);
            }
        }
    }

    //! A rounded column where the device can draw one, a plain one otherwise.
    function _pill(
        dc as Graphics.Dc,
        x as Number,
        y as Number,
        w as Number,
        h as Number,
        radius as Number,
        rounded as Boolean
    ) as Void {
        if (rounded && h >= w) {
            dc.fillRoundedRectangle(x, y, w, h, radius);
        } else {
            dc.fillRectangle(x, y, w, h);
        }
    }

    //! A ring in the accent around a dumbbell: plates, bar, plates.
    function _drawMark(dc as Graphics.Dc, cx as Number, cy as Number, r as Number) as Void {
        if (r < 6) {
            return;
        }
        dc.setColor(0x0A2A40, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(r / 8 < 2 ? 2 : r / 8);
        dc.drawCircle(cx, cy, r);
        dc.setPenWidth(1);
        var bar = r / 7 < 2 ? 2 : r / 7;
        var arm = (r * 62) / 100;
        dc.fillRectangle(cx - arm, cy - bar / 2, arm * 2, bar);
        var plateW = r / 5 < 2 ? 2 : r / 5;
        var big = (r * 90) / 100;
        var inner = (r * 60) / 100;
        dc.fillRectangle(cx - arm, cy - big / 2, plateW, big);
        dc.fillRectangle(cx + arm - plateW, cy - big / 2, plateW, big);
        dc.fillRectangle(cx - arm + plateW + 1, cy - inner / 2, plateW, inner);
        dc.fillRectangle(cx + arm - plateW * 2 - 1, cy - inner / 2, plateW, inner);
    }

    function _ink(font as Graphics.FontDefinition) as Number {
        if (Graphics has :getFontAscent) {
            var ascent = Graphics.getFontAscent(font);
            if (ascent > 0) {
                return ascent;
            }
        }
        return Graphics.getFontHeight(font);
    }

    //! "today", "yesterday", "3 days ago".
    public function when(then as Number, now as Number) as String {
        var days = NativeActivities.daysAgo(then, now);
        if (days <= 0) {
            return WatchUi.loadResource(Rez.Strings.GlanceToday) as String;
        }
        if (days == 1) {
            return WatchUi.loadResource(Rez.Strings.GlanceYesterday) as String;
        }
        return Lang.format(WatchUi.loadResource(Rez.Strings.GlanceDaysAgo) as String, [days]);
    }

    //! The same rounding as Theme.formatVolume, which the glance cannot reach.
    public function volume(kg as Number, imperial as Boolean) as String {
        var shown = imperial ? (kg * 2.20462).toNumber() : kg;
        if (shown >= 1000) {
            var tenths = (shown + 50) / 100;
            var big = (tenths / 10).toString() + "." + (tenths % 10).toString();
            return imperial ? big + "k lb" : big + " t";
        }
        return shown.toString() + (imperial ? " lb" : " kg");
    }

    //! Cut a line to the width, ending in a dot rather than at the bezel.
    public function clip(dc as Graphics.Dc, text as String, font as Graphics.FontType, width as Number) as String {
        if (width <= 0) {
            return "";
        }
        if (dc.getTextWidthInPixels(text, font) <= width) {
            return text;
        }
        var n = text.length();
        while (n > 1) {
            n--;
            var cut = text.substring(0, n);
            if (cut != null && dc.getTextWidthInPixels((cut as String) + ".", font) <= width) {
                return (cut as String) + ".";
            }
        }
        return "";
    }
}

//! The Storage keys the glance reads, where the glance can see them.
(:glance :analytics)
module AnalyticsKeys {
    const GLANCE = "agg";
}
