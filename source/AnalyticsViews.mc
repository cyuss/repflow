import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.System;
import Toybox.Math;

//! Analytics, inside RepFlow: four overview pages, then the history.
//!
//!   THIS WEEK / THIS MONTH / 30 DAYS     sessions, against the period before,
//!                                        then time, volume, sets and reps
//!   SESSIONS PER WEEK                    eight weeks, RepFlow and Garmin stacked
//!   VOLUME PER WEEK                      eight weeks, RepFlow's alone
//!   LAST SESSION                         what it was and where it came from
//!   START                                the history, filterable
//!
//! Reached from the glance, or from MENU on the workout picker. BACK goes to
//! the workout picker, so the app is never a dead end.
//!
//! Garmin sessions are a date and a duration (see NativeActivities). Wherever
//! one is part of a figure, the page says that volume, sets and reps are
//! RepFlow's alone — a total that quietly left them out would read as a
//! complete one.
(:analytics)
class AnalyticsView extends WatchUi.View {

    public static const PAGES = 6;
    //! Weeks in the charts, the current one last.
    public static const WEEKS = 8;

    private var _entries as Array<Array>;
    private var _now as Number;
    private var _page as Number;
    //! [title, stats, previous stats, "vs" string] per period page.
    private var _periods as Array<Array>;
    //! Per chart week, oldest first: RepFlow sessions, Garmin sessions, kg.
    private var _weekRepFlow as Array<Number>;
    private var _weekGarmin as Array<Number>;
    private var _weekVolume as Array<Number>;
    private var _firstWeek as Number;

    public function initialize() {
        View.initialize();
        _now = AppController.now();
        _page = 0;
        // Demo data is the whole story in the simulator: the simulator's own
        // activity history would otherwise be merged into it.
        if (!DevLaunch.DEMO) {
            AnalyticsData.refreshNative(_now);
        }
        _entries = AnalyticsData.sessions(_now - AnalyticsData.KEEP_SECONDS);

        var day = AnalyticsData.DAY;
        var week = NativeActivities.weekStart(_now);
        var month = NativeActivities.monthStart(_now);
        var lastMonth = NativeActivities.monthStart(month - day);
        var end = _now + 1;
        _periods = [
            [Rez.Strings.ThisWeek,
                AnalyticsData.statsBetween(_entries, week, end),
                AnalyticsData.statsBetween(_entries, week - 7 * day, week),
                Rez.Strings.VsLastWeek],
            [Rez.Strings.ThisMonth,
                AnalyticsData.statsBetween(_entries, month, end),
                AnalyticsData.statsBetween(_entries, lastMonth, month),
                Rez.Strings.VsLastMonth],
            [Rez.Strings.Last30Days,
                AnalyticsData.statsBetween(_entries, _now - 30 * day, end),
                AnalyticsData.statsBetween(_entries, _now - 60 * day, _now - 30 * day),
                Rez.Strings.VsPrevious30]
        ] as Array<Array>;

        _weekRepFlow = [] as Array<Number>;
        _weekGarmin = [] as Array<Number>;
        _weekVolume = [] as Array<Number>;
        _firstWeek = week - (WEEKS - 1) * 7 * day;
        for (var k = 0; k < WEEKS; k++) {
            var from = _firstWeek + k * 7 * day;
            var s = AnalyticsData.statsBetween(_entries, from, from + 7 * day);
            _weekRepFlow.add(s.repflow);
            _weekGarmin.add(s.garmin);
            _weekVolume.add(s.volume);
        }
    }

    public function turnPage(delta as Number) as Void {
        _page = (_page + delta + PAGES) % PAGES;
        Marquee.stop();
        WatchUi.requestUpdate();
    }

    public function onHide() as Void {
        Marquee.stop();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        if (_entries.size() == 0) {
            _drawEmpty(dc);
        } else if (_page < 3) {
            _drawPeriod(dc, _periods[_page]);
        } else if (_page == 3) {
            _drawSessionsChart(dc);
        } else if (_page == 4) {
            _drawVolumeChart(dc);
        } else {
            _drawLast(dc);
        }
        Theme.drawPageDots(dc, PAGES, _page);
        Marquee.endFrame();
    }

    // ------------------------------------------------------------------

    private function _drawPeriod(dc as Graphics.Dc, period as Array) as Void {
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var stats = period[1] as PeriodStats;
        var previous = period[2] as PeriodStats;

        var y = AnalyticsUi.title(dc, WatchUi.loadResource(period[0] as ResourceId) as String,
            Theme.colorAccent());

        // The hero: how many sessions, and against the period before.
        var unit = WatchUi.loadResource(stats.count == 1
            ? Rez.Strings.UnitSession : Rez.Strings.UnitSessions) as String;
        y = AnalyticsUi.figure(dc, cx, y + h / 120, stats.count.toString(), unit,
            Theme.colorText(), h / 11);
        var small = Graphics.FONT_XTINY;
        var smallLine = dc.getFontHeight(small);

        // Where they came from, then how that compares with the period before.
        dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + h / 100, small,
            (WatchUi.loadResource(Rez.Strings.SourceRepFlow) as String) + " " + stats.repflow.toString()
            + "   " + (WatchUi.loadResource(Rez.Strings.SourceGarmin) as String) + " " + stats.garmin.toString(),
            Graphics.TEXT_JUSTIFY_CENTER);
        y += h / 100 + smallLine;
        var diff = stats.count - previous.count;
        var vs = WatchUi.loadResource(period[3] as ResourceId) as String;
        var trend = diff == 0 ? "= " + vs : (diff > 0 ? "+" : "") + diff.toString() + " " + vs;
        var trendColor = diff > 0 ? Theme.colorDone() : (diff < 0 ? Theme.colorWarm() : Theme.colorDim());
        dc.setColor(trendColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, small, trend, Graphics.TEXT_JUSTIFY_CENTER);
        y += smallLine + h / 80;

        var rows = [
            [WatchUi.loadResource(Rez.Strings.FieldTime) as String, AnalyticsUi.hours(stats.duration)],
            [WatchUi.loadResource(Rez.Strings.FieldVolume) as String,
                stats.repflow > 0 ? Theme.formatVolume(stats.volume.toFloat()) : LiveMetrics.NO_VALUE],
            [WatchUi.loadResource(Rez.Strings.SetsRepsRow) as String,
                stats.repflow > 0
                    ? stats.sets.toString() + " / " + stats.reps.toString()
                    : LiveMetrics.NO_VALUE]
        ] as Array<Array>;
        y = AnalyticsUi.rows(dc, y, rows);

        if (stats.garmin > 0) {
            AnalyticsUi.note(dc, y + h / 80, WatchUi.loadResource(Rez.Strings.GarminSummaryOnly) as String);
        } else {
            AnalyticsUi.note(dc, y + h / 80, WatchUi.loadResource(Rez.Strings.HistoryHint) as String);
        }
    }

    private function _drawLast(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var e = _entries[0];
        var garmin = (e[AnalyticsData.E_SOURCE] as Number) == AnalyticsData.SRC_GARMIN;

        var y = AnalyticsUi.title(dc, WatchUi.loadResource(Rez.Strings.LastSession) as String,
            Theme.colorAccent());
        var name = AnalyticsUi.entryName(e);
        y = Marquee.draw(dc, y + h / 60, name,
            [Graphics.FONT_SMALL] as Array<Graphics.FontDefinition>, Theme.colorText(),
            Theme.usableWidth(dc, y) - dc.getWidth() / 10);
        dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY,
            AnalyticsUi.date(e[AnalyticsData.E_START] as Number, true), Graphics.TEXT_JUSTIFY_CENTER);
        y += dc.getFontHeight(Graphics.FONT_XTINY) + h / 40;

        var rows = AnalyticsUi.sessionRows(e);
        y = AnalyticsUi.rows(dc, y, rows.slice(0, 4));
        // No START hint here: four rows already reach the curve, and the
        // period pages before this one have said it.
        if (garmin) {
            AnalyticsUi.note(dc, y + h / 80, WatchUi.loadResource(Rez.Strings.GarminSummaryOnly) as String);
        }
    }

    //! Sessions per week: how regular, at a glance. RepFlow at the base of each
    //! bar, Garmin on top, a two-pixel gap between them; a legend, because
    //! there are two series; the count labelled on this week and on the
    //! busiest week only.
    private function _drawSessionsChart(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var y = AnalyticsUi.title(dc, WatchUi.loadResource(Rez.Strings.ChartSessions) as String,
            Theme.colorAccent());
        y = AnalyticsUi.legend(dc, y + h / 80);
        var stacks = [] as Array<Array<Number>>;
        for (var k = 0; k < WEEKS; k++) {
            stacks.add([_weekRepFlow[k], _weekGarmin[k]] as Array<Number>);
        }
        AnalyticsUi.weekBars(dc, y + h / 18, h - h / 4, stacks,
            [AnalyticsUi.repflowColor(), AnalyticsUi.garminColor()] as Array<Number>,
            _firstWeek, false);
    }

    //! Volume per week, RepFlow's alone — Garmin gives no loads, and a bar
    //! that silently left a session out would read as a light week.
    private function _drawVolumeChart(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var y = AnalyticsUi.title(dc, WatchUi.loadResource(Rez.Strings.ChartVolume) as String,
            Theme.colorAccent());
        y = AnalyticsUi.note(dc, y + h / 80, WatchUi.loadResource(Rez.Strings.ChartRepFlowOnly) as String);
        var stacks = [] as Array<Array<Number>>;
        for (var k = 0; k < WEEKS; k++) {
            stacks.add([_weekVolume[k]] as Array<Number>);
        }
        AnalyticsUi.weekBars(dc, y + h / 18, h - h / 4, stacks,
            [AnalyticsUi.repflowColor()] as Array<Number>, _firstWeek, true);
    }

    private function _drawEmpty(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var y = AnalyticsUi.title(dc, WatchUi.loadResource(Rez.Strings.AnalyticsTitle) as String,
            Theme.colorAccent());
        y = h / 2 - dc.getFontHeight(Graphics.FONT_SMALL);
        dc.setColor(Theme.colorText(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, y, Graphics.FONT_SMALL,
            WatchUi.loadResource(Rez.Strings.NoSessions) as String, Graphics.TEXT_JUSTIFY_CENTER);
        AnalyticsUi.note(dc, y + dc.getFontHeight(Graphics.FONT_SMALL) + h / 40,
            WatchUi.loadResource(Rez.Strings.NoSessionsHint) as String);
    }
}

(:analytics)
class AnalyticsDelegate extends WatchUi.BehaviorDelegate {

    private var _view as AnalyticsView;

    public function initialize(view as AnalyticsView) {
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

    public function onSelect() as Boolean {
        AnalyticsNav.history(WatchUi.SLIDE_LEFT);
        return true;
    }

    public function onBack() as Boolean {
        var list = new WorkoutListView();
        WatchUi.switchToView(list, new WorkoutListDelegate(list), WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// ======================================================================
// History
// ======================================================================

//! Where the screens go, in one place, so each one rebuilds what it shows.
(:analytics)
module AnalyticsNav {

    //! The history's filters, for as long as the app is open.
    var period as Number = 1;      //! index into PERIOD_DAYS
    var source as Number = 0;      //! 0 all, 1 RepFlow, 2 Garmin

    const PERIOD_DAYS = [7, 30, 400] as Array<Number>;

    public function overview(transition as WatchUi.SlideType) as Void {
        var view = new AnalyticsView();
        WatchUi.switchToView(view, new AnalyticsDelegate(view), transition);
    }

    public function history(transition as WatchUi.SlideType) as Void {
        var now = AppController.now();
        var all = AnalyticsData.sessions(now - PERIOD_DAYS[period] * AnalyticsData.DAY);
        var shown = [] as Array<Array>;
        for (var i = 0; i < all.size(); i++) {
            var src = all[i][AnalyticsData.E_SOURCE] as Number;
            if (source == 0 || (source == 1 && src == AnalyticsData.SRC_REPFLOW)
                    || (source == 2 && src == AnalyticsData.SRC_GARMIN)) {
                shown.add(all[i]);
            }
        }
        var menu = new AnalyticsHistoryMenu(shown);
        WatchUi.switchToView(menu, new AnalyticsHistoryDelegate(shown), transition);
    }

    public function filters() as Void {
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(Rez.Strings.Filters) as String
        });
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.FilterPeriod) as String,
            periodLabel(), :period, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.FilterSource) as String,
            sourceLabel(), :source, {}));
        WatchUi.switchToView(menu, new AnalyticsFilterDelegate(), WatchUi.SLIDE_UP);
    }

    public function periodLabel() as String {
        var ids = [Rez.Strings.Period7, Rez.Strings.Period30, Rez.Strings.Period12m] as Array<ResourceId>;
        return WatchUi.loadResource(ids[period]) as String;
    }

    public function sourceLabel() as String {
        var ids = [Rez.Strings.SourceAll, Rez.Strings.SourceRepFlow, Rez.Strings.SourceGarmin] as Array<ResourceId>;
        return WatchUi.loadResource(ids[source]) as String;
    }
}

//! The sessions, newest first, in the same rows as the exercise list.
(:analytics)
class AnalyticsHistoryMenu extends WatchUi.CustomMenu {

    public function initialize(entries as Array<Array>) {
        var height = System.getDeviceSettings().screenHeight;
        CustomMenu.initialize(height / 4, Theme.colorBg(), {
            :focusItemHeight => height / 3,
            :title => new OverviewTitle(
                (WatchUi.loadResource(Rez.Strings.HistoryTitle) as String) + "  "
                + AnalyticsNav.periodLabel()),
            :theme => null
        });
        addItem(new AnalyticsFilterItem());
        if (entries.size() == 0) {
            addItem(new ActionMenuItem(WatchUi.loadResource(Rez.Strings.NoSessions) as String, "none"));
        }
        for (var i = 0; i < entries.size(); i++) {
            addItem(new AnalyticsSessionItem(entries[i], i));
        }
    }

    public function drawForeground(dc as Graphics.Dc) as Void {
        Marquee.endFrame();
    }

    public function onHide() as Void {
        Marquee.stop();
    }
}

//! The first row: what the list is showing, and the way to change it.
(:analytics)
class AnalyticsFilterItem extends WatchUi.CustomMenuItem {

    public function initialize() {
        CustomMenuItem.initialize("filter", {});
    }

    public function draw(dc as Graphics.Dc) as Void {
        var height = dc.getHeight();
        var focused = isFocused();
        var nameFont = RowLayout.nameFont(dc, height, Theme.captionFont());
        var nameHeight = dc.getFontHeight(nameFont);
        var sub = AnalyticsNav.periodLabel() + "  " + AnalyticsNav.sourceLabel();
        var block = nameHeight + height / 16 + dc.getFontHeight(Theme.captionFont());
        var top = (height - block) / 2;
        Theme.drawClippedAt(dc, RowLayout.textLeft(dc), top,
            WatchUi.loadResource(Rez.Strings.Filters) as String, nameFont,
            focused ? Theme.colorText() : Theme.colorDim(), RowLayout.textWidth(dc));
        Theme.drawClippedAt(dc, RowLayout.textLeft(dc), top + nameHeight + height / 16, sub,
            Theme.captionFont(), focused ? Theme.colorAccent() : Theme.colorFaint(),
            RowLayout.textWidth(dc));
        // A funnel would be a glyph a Fenix 6 font does not have; three bars
        // narrowing downwards say "filter" in the icon column.
        var cx = RowLayout.iconCentre(dc);
        var cy = top + nameHeight / 2;
        var w = RowLayout.gutter(dc) / 2;
        dc.setColor(focused ? Theme.colorAccent() : Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
        var bar = w / 6 < 2 ? 2 : w / 6;
        dc.fillRectangle(cx - w / 2, cy - bar * 2, w, bar);
        dc.fillRectangle(cx - w / 3, cy - bar / 2, (w * 2) / 3, bar);
        dc.fillRectangle(cx - w / 6, cy + bar, w / 3, bar);
    }
}

//! One session: source mark, name, and its date, time and volume.
(:analytics)
class AnalyticsSessionItem extends WatchUi.CustomMenuItem {

    private var _entry as Array;

    public function initialize(entry as Array, index as Number) {
        CustomMenuItem.initialize(index, {});
        _entry = entry;
    }

    public function draw(dc as Graphics.Dc) as Void {
        var height = dc.getHeight();
        var focused = isFocused();
        var subFont = Theme.captionFont();
        var nameFont = RowLayout.nameFont(dc, height, subFont);
        var nameHeight = dc.getFontHeight(nameFont);
        var gap = height / 16;
        var top = (height - nameHeight - gap - dc.getFontHeight(subFont)) / 2;
        if (top < 0) {
            top = 0;
        }
        var garmin = (_entry[AnalyticsData.E_SOURCE] as Number) == AnalyticsData.SRC_GARMIN;
        var name = AnalyticsUi.entryName(_entry);
        var textLeft = RowLayout.textLeft(dc);
        var textWidth = RowLayout.textWidth(dc);
        var nameColor = focused ? Theme.colorText() : Theme.colorDim();
        if (focused) {
            Marquee.focus("h" + (_entry[AnalyticsData.E_START] as Number).toString());
            Marquee.drawAt(dc, textLeft, top, name,
                [nameFont] as Array<Graphics.FontDefinition>, nameColor, textWidth);
        } else {
            Theme.drawClippedAt(dc, textLeft, top, name, nameFont, nameColor, textWidth);
        }

        var sub = AnalyticsUi.date(_entry[AnalyticsData.E_START] as Number, false) + "   "
            + AnalyticsUi.hours(_entry[AnalyticsData.E_DURATION] as Number);
        if (!garmin) {
            var r = _entry[AnalyticsData.E_RECORD] as Array;
            sub += "   " + Theme.formatVolume((r[SessionLog.R_VOLUME] as Number).toFloat());
        }
        Theme.drawClippedAt(dc, textLeft, top + nameHeight + gap, sub, subFont,
            focused ? Theme.colorAccent() : Theme.colorFaint(), textWidth);

        AnalyticsUi.sourceMark(dc, RowLayout.iconCentre(dc), top + nameHeight / 2,
            RowLayout.gutter(dc) / 5, garmin);
    }
}

(:analytics)
class AnalyticsHistoryDelegate extends WatchUi.Menu2InputDelegate {

    private var _entries as Array<Array>;

    public function initialize(entries as Array<Array>) {
        Menu2InputDelegate.initialize();
        _entries = entries;
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof String) {
            if ((id as String).equals("filter")) {
                AnalyticsNav.filters();
            }
            return;
        }
        if (id instanceof Number && (id as Number) < _entries.size()) {
            var view = new AnalyticsSessionView(_entries[id as Number]);
            WatchUi.switchToView(view, new AnalyticsSessionDelegate(view), WatchUi.SLIDE_LEFT);
        }
    }

    public function onBack() as Void {
        AnalyticsNav.overview(WatchUi.SLIDE_RIGHT);
    }
}

(:analytics)
class AnalyticsFilterDelegate extends WatchUi.Menu2InputDelegate {

    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    //! Each press moves the setting on one step; the sub-label shows where it is.
    public function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :period) {
            AnalyticsNav.period = (AnalyticsNav.period + 1) % AnalyticsNav.PERIOD_DAYS.size();
            item.setSubLabel(AnalyticsNav.periodLabel());
        } else {
            AnalyticsNav.source = (AnalyticsNav.source + 1) % 3;
            item.setSubLabel(AnalyticsNav.sourceLabel());
        }
        WatchUi.requestUpdate();
    }

    public function onBack() as Void {
        AnalyticsNav.history(WatchUi.SLIDE_DOWN);
    }
}

// ======================================================================
// One session
// ======================================================================

//! A session in full: its figures, then each exercise. UP and DOWN scroll.
(:analytics)
class AnalyticsSessionView extends WatchUi.View {

    private var _entry as Array;
    private var _offset as Number;
    private var _maxOffset as Number;

    public function initialize(entry as Array) {
        View.initialize();
        _entry = entry;
        _offset = 0;
        _maxOffset = 0;
    }

    public function scroll(direction as Number) as Void {
        var step = System.getDeviceSettings().screenHeight / 5;
        _offset += direction * step;
        if (_offset > _maxOffset) {
            _offset = _maxOffset;
        }
        if (_offset < 0) {
            _offset = 0;
        }
        WatchUi.requestUpdate();
    }

    public function onHide() as Void {
        Marquee.stop();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var garmin = (_entry[AnalyticsData.E_SOURCE] as Number) == AnalyticsData.SRC_GARMIN;

        // A fixed header; the rest scrolls beneath it.
        var y = AnalyticsUi.title(dc, AnalyticsUi.date(_entry[AnalyticsData.E_START] as Number, true),
            Theme.colorAccent());
        y = Marquee.draw(dc, y, AnalyticsUi.entryName(_entry),
            [Graphics.FONT_SMALL] as Array<Graphics.FontDefinition>, Theme.colorText(),
            Theme.usableWidth(dc, y) - dc.getWidth() / 10);
        y += h / 60;
        Theme.setColor(dc, Theme.colorFaint());
        var ruleHalf = Theme.usableWidth(dc, y) / 3;
        dc.drawLine(cx - ruleHalf, y, cx + ruleHalf, y);
        var top = y + 1;
        var bottom = h - h / 10;

        if (dc has :setClip) {
            dc.setClip(0, top, dc.getWidth(), bottom - top);
        }
        var start = top + h / 60 - _offset;
        var end = AnalyticsUi.rows(dc, start, AnalyticsUi.sessionRows(_entry));
        if (garmin) {
            end = AnalyticsUi.note(dc, end + h / 80,
                WatchUi.loadResource(Rez.Strings.GarminSummaryOnly) as String);
        } else {
            end = _drawExercises(dc, end + h / 40);
        }
        if (dc has :clearClip) {
            dc.clearClip();
        }
        var content = end + _offset - top;
        _maxOffset = content > bottom - top ? content - (bottom - top) + h / 20 : 0;
    }

    //! One block per exercise: name and heaviest load, then sets and reps.
    private function _drawExercises(dc as Graphics.Dc, y as Number) as Number {
        var r = _entry[AnalyticsData.E_RECORD] as Array;
        var detail = r[SessionLog.R_DETAIL] as Array;
        var h = dc.getHeight();
        if (detail.size() == 0) {
            return AnalyticsUi.note(dc, y, WatchUi.loadResource(Rez.Strings.NoDetail) as String);
        }
        var span = AnalyticsUi.span(dc);
        var left = span[0];
        var width = span[1];
        var font = Graphics.FONT_TINY;
        var small = Graphics.FONT_XTINY;
        var line = dc.getFontHeight(font);
        var smallLine = dc.getFontHeight(small);
        var setsLabel = WatchUi.loadResource(Rez.Strings.FieldSets) as String;
        var repsLabel = WatchUi.loadResource(Rez.Strings.FieldReps) as String;
        for (var i = 0; i < detail.size(); i++) {
            var row = detail[i];
            if (!(row instanceof Array) || (row as Array).size() != 4) {
                continue;
            }
            var d = row as Array;
            var top = d[SessionLog.D_TOP_TENTHS] as Number;
            var load = top > 0
                ? Theme.formatWeight(top.toFloat() / 10.0) + " " + Units.label()
                : "";
            var loadWidth = dc.getTextWidthInPixels(load, font);
            dc.setColor(Theme.colorAccent(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left + width, y, font, load, Graphics.TEXT_JUSTIFY_RIGHT);
            Theme.drawClippedAt(dc, left, y, d[SessionLog.D_NAME] as String, font,
                Theme.colorText(), width - loadWidth - width / 20);
            dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, y + line, small,
                (d[SessionLog.D_SETS] as Number).toString() + " " + setsLabel.toLower() + "   "
                + (d[SessionLog.D_REPS] as Number).toString() + " " + repsLabel.toLower(),
                Graphics.TEXT_JUSTIFY_LEFT);
            y += line + smallLine + h / 40;
        }
        return y;
    }
}

(:analytics)
class AnalyticsSessionDelegate extends WatchUi.BehaviorDelegate {

    private var _view as AnalyticsSessionView;

    public function initialize(view as AnalyticsSessionView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onNextPage() as Boolean {
        _view.scroll(1);
        return true;
    }

    public function onPreviousPage() as Boolean {
        _view.scroll(-1);
        return true;
    }

    public function onBack() as Boolean {
        AnalyticsNav.history(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// ======================================================================
// Shared drawing
// ======================================================================

(:analytics)
module AnalyticsUi {

    //! A small-caps title near the top of the glass. Returns the y below it.
    public function title(dc as Graphics.Dc, text as String, color as Number) as Number {
        var h = dc.getHeight();
        var y = h / 12;
        var font = Theme.captionFont();
        var label = text.toUpper();
        if (dc.getTextWidthInPixels(label, font) > Theme.usableWidth(dc, y)) {
            font = Graphics.FONT_XTINY;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, y, font, label, Graphics.TEXT_JUSTIFY_CENTER);
        return y + dc.getFontHeight(font);
    }

    //! A figure in the number font with its unit small beside it, centred on
    //! `cx`. Returns the y below the digits' ink.
    public function figure(
        dc as Graphics.Dc,
        cx as Number,
        y as Number,
        value as String,
        unit as String,
        color as Number,
        maxInk as Number
    ) as Number {
        var fonts = [
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_MILD,
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM
        ] as Array<Graphics.FontDefinition>;
        var unitFont = Graphics.FONT_TINY;
        var unitText = " " + unit;
        var unitWidth = dc.getTextWidthInPixels(unitText, unitFont);
        var font = Theme.pickFontFitting(dc, value, fonts,
            Theme.usableWidth(dc, y) - unitWidth, maxInk);
        var ink = Theme.inkHeight(font);
        var valueWidth = dc.getTextWidthInPixels(value, font);
        var left = cx - (valueWidth + unitWidth) / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, y, font, value, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + valueWidth, y + ink - Theme.inkHeight(unitFont), unitFont,
            unitText, Graphics.TEXT_JUSTIFY_LEFT);
        return y + ink;
    }

    //! `[left, width]` of a block of rows: one width, clear of the page dots,
    //! narrow enough to stay on the glass across the lower half.
    public function span(dc as Graphics.Dc) as Array<Number> {
        var cx = dc.getWidth() / 2;
        var half = (dc.getWidth() * 36) / 100;
        var dots = Theme.pageDotsLeft(dc) - dc.getWidth() / 30 - cx;
        if (dots < half) {
            half = dots;
        }
        return [cx - half, half * 2] as Array<Number>;
    }

    //! Label-and-value rows with a hairline between them. Returns the y below.
    public function rows(dc as Graphics.Dc, y as Number, rows as Array<Array>) as Number {
        var h = dc.getHeight();
        var span = span(dc);
        var left = span[0];
        var width = span[1];
        var labelFont = Graphics.FONT_XTINY;
        var valueFont = Graphics.FONT_TINY;
        var rowHeight = dc.getFontHeight(valueFont) + h / 70;
        for (var i = 0; i < rows.size(); i++) {
            var row = rows[i] as Array;
            var mid = y + rowHeight / 2;
            var value = row[1] as String;
            var valueWidth = dc.getTextWidthInPixels(value, valueFont);
            dc.setColor(Theme.colorText(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left + width, mid, valueFont, value,
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, mid, labelFont,
                Theme.clipToWidth(dc, (row[0] as String).toUpper(), labelFont,
                    width - valueWidth - width / 20),
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            if (i < rows.size() - 1) {
                Theme.setColor(dc, Theme.colorFaint());
                dc.drawLine(left, y + rowHeight, left + width, y + rowHeight);
            }
            y += rowHeight;
        }
        return y;
    }

    //! A short dim line, centred. Returns the y below it.
    //!
    //! Measured on the circle itself at the line's lower edge, less a margin:
    //! the generic usable width keeps an eighth back for headings, and down
    //! here, where the glass is narrowest, that eighth was the end of the
    //! sentence.
    public function note(dc as Graphics.Dc, y as Number, text as String) as Number {
        var font = Graphics.FONT_XTINY;
        var line = dc.getFontHeight(font);
        var r = dc.getWidth() / 2;
        var dy = (y + (line * 3) / 4 - dc.getHeight() / 2).abs();
        var square = r * r - dy * dy;
        var width = square > 0 ? (Math.sqrt(square.toFloat()) * 2).toNumber() - dc.getWidth() / 9 : 0;
        dc.setColor(Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, y, font, Theme.clipToWidth(dc, text, font, width),
            Graphics.TEXT_JUSTIFY_CENTER);
        return y + line;
    }

    //! The rows describing one session. Garmin's has no figures to give but
    //! its time.
    public function sessionRows(e as Array) as Array<Array> {
        var garmin = (e[AnalyticsData.E_SOURCE] as Number) == AnalyticsData.SRC_GARMIN;
        var rows = [
            [WatchUi.loadResource(Rez.Strings.FilterSource) as String,
                WatchUi.loadResource(garmin ? Rez.Strings.SourceGarmin : Rez.Strings.SourceRepFlow) as String],
            [WatchUi.loadResource(Rez.Strings.FieldTime) as String,
                AnalyticsUi.hours(e[AnalyticsData.E_DURATION] as Number)]
        ] as Array<Array>;
        if (garmin) {
            return rows;
        }
        var r = e[AnalyticsData.E_RECORD] as Array;
        rows.add([WatchUi.loadResource(Rez.Strings.FieldVolume) as String,
            Theme.formatVolume((r[SessionLog.R_VOLUME] as Number).toFloat())]);
        rows.add([WatchUi.loadResource(Rez.Strings.SetsRepsRow) as String,
            (r[SessionLog.R_SETS] as Number).toString() + " / " + (r[SessionLog.R_REPS] as Number).toString()]);
        rows.add([WatchUi.loadResource(Rez.Strings.FieldExercises) as String,
            (r[SessionLog.R_EXERCISES] as Number).toString()]);
        return rows;
    }

    public function entryName(e as Array) as String {
        if ((e[AnalyticsData.E_SOURCE] as Number) == AnalyticsData.SRC_GARMIN) {
            return WatchUi.loadResource(Rez.Strings.GarminSession) as String;
        }
        var name = (e[AnalyticsData.E_RECORD] as Array)[SessionLog.R_NAME] as String;
        return name.length() > 0 ? name : WatchUi.loadResource(Rez.Strings.AppName) as String;
    }

    //! "Mon 14 Nov" or "Mon 14 Nov 18:05", in the watch's language.
    public function date(epoch as Number, withTime as Boolean) as String {
        var info = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_MEDIUM);
        var text = (info.day_of_week as String) + " " + (info.day as Number).toString()
            + " " + (info.month as String);
        if (withTime) {
            text += " " + (info.hour as Number).format("%d") + ":" + (info.min as Number).format("%02d");
        }
        return text;
    }

    //! "52 min" or "3 h 05": a total, not a stopwatch.
    public function hours(seconds as Number) as String {
        var minutes = (seconds + 30) / 60;
        if (minutes < 60) {
            return minutes.toString() + " min";
        }
        return (minutes / 60).toString() + " h " + (minutes % 60).format("%02d");
    }

    // ------------------------------------------------------------------
    // Charts
    // ------------------------------------------------------------------

    //! The two sources' colours: one per entity, the same on every chart, the
    //! glance and the history's marks. Checked with the dataviz palette
    //! validator — lightness band, chroma, colour-blind separation (protan
    //! ΔE 26.8 dark, 24.1 light) and contrast — for each theme.
    public function repflowColor() as Number {
        return Theme.light() ? 0x1F6FC0 : 0x2A8BE6;
    }

    public function garminColor() as Number {
        return Theme.light() ? 0xA0600F : 0xBF7A20;
    }

    //! "■ RepFlow   ■ Garmin", centred. Returns the y below it.
    public function legend(dc as Graphics.Dc, y as Number) as Number {
        var font = Graphics.FONT_XTINY;
        var line = dc.getFontHeight(font);
        var size = (line * 45) / 100;
        var gap = size / 2;
        var space = size * 2;
        var a = WatchUi.loadResource(Rez.Strings.SourceRepFlow) as String;
        var b = WatchUi.loadResource(Rez.Strings.SourceGarmin) as String;
        var total = size + gap + dc.getTextWidthInPixels(a, font) + space
            + size + gap + dc.getTextWidthInPixels(b, font);
        var x = dc.getWidth() / 2 - total / 2;
        var cy = y + line / 2;
        var names = [a, b] as Array<String>;
        var colors = [repflowColor(), garminColor()] as Array<Number>;
        for (var i = 0; i < 2; i++) {
            dc.setColor(colors[i], Graphics.COLOR_TRANSPARENT);
            Theme.fillBar(dc, x, cy - size / 2, size, size);
            x += size + gap;
            // Text wears text ink; the swatch beside it carries the identity.
            dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, names[i], Graphics.TEXT_JUSTIFY_LEFT);
            x += dc.getTextWidthInPixels(names[i], font) + space;
        }
        return y + line;
    }

    //! Eight weeks of bars between `top` and `bottom`, oldest on the left.
    //!
    //! Each bar is a stack of `stacks[k]`, bottom series first, with a two-
    //! pixel gap between segments and between bars; the top segment has
    //! rounded ends, the base sits square on the baseline. One axis, scaled to
    //! the tallest week. Only two values are written: this week's, over its
    //! bar, and the busiest week's when that is another one. Under the axis,
    //! the first week's date on the left and "this week" on the right.
    public function weekBars(
        dc as Graphics.Dc,
        top as Number,
        bottom as Number,
        stacks as Array<Array<Number>>,
        colors as Array<Number>,
        firstWeek as Number,
        volume as Boolean
    ) as Void {
        var span = span(dc);
        var left = span[0];
        var width = span[1];
        var n = stacks.size();
        var small = Graphics.FONT_XTINY;
        var line = dc.getFontHeight(small);
        var plotTop = top + line;               // room for a value label
        var gap = width / 30 < 4 ? 4 : width / 30;
        var barWidth = (width - gap * (n - 1)) / n;

        var totals = [] as Array<Number>;
        var peak = 0;
        var peakIndex = 0;
        for (var k = 0; k < n; k++) {
            var t = 0;
            for (var s = 0; s < stacks[k].size(); s++) {
                t += stacks[k][s];
            }
            totals.add(t);
            if (t > peak) {
                peak = t;
                peakIndex = k;
            }
        }

        // Baseline, recessive.
        Theme.setColor(dc, Theme.colorFaint());
        dc.drawLine(left, bottom, left + width, bottom);

        var plot = bottom - plotTop;
        for (var k = 0; k < n; k++) {
            var x = left + k * (barWidth + gap);
            if (totals[k] <= 0 || peak <= 0) {
                // An empty week is a tick on the baseline, not a missing bar.
                Theme.setColor(dc, Theme.colorFaint());
                dc.fillRectangle(x + barWidth / 3, bottom - 2, barWidth / 3, 2);
                continue;
            }
            var y = bottom;
            var last = -1;
            for (var s = 0; s < stacks[k].size(); s++) {
                if (stacks[k][s] > 0) {
                    last = s;
                }
            }
            for (var s = 0; s <= last; s++) {
                var value = stacks[k][s];
                if (value <= 0) {
                    continue;
                }
                var segment = (plot * value) / peak;
                if (segment < 3) {
                    segment = 3;
                }
                if (s > 0 && y < bottom) {
                    y -= 2;                     // the surface gap between fills
                }
                dc.setColor(colors[s], Graphics.COLOR_TRANSPARENT);
                if (s == last && dc has :fillRoundedRectangle && segment > 8) {
                    // Rounded data-end, square base.
                    var r = barWidth / 4 < 4 ? barWidth / 4 : 4;
                    dc.fillRoundedRectangle(x, y - segment, barWidth, segment, r);
                    dc.fillRectangle(x, y - segment / 2, barWidth, segment / 2);
                } else {
                    dc.fillRectangle(x, y - segment, barWidth, segment);
                }
                y -= segment;
            }
            if (k == n - 1 || (k == peakIndex && peakIndex != n - 1)) {
                var label = volume ? Theme.formatVolume(totals[k].toFloat()) : totals[k].toString();
                dc.setColor(k == n - 1 ? Theme.colorText() : Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
                var anchor = x + barWidth / 2;
                var lw = dc.getTextWidthInPixels(label, small);
                // Keep the label inside the plot's width at either end.
                if (anchor - lw / 2 < left) {
                    anchor = left + lw / 2;
                }
                if (anchor + lw / 2 > left + width) {
                    anchor = left + width - lw / 2;
                }
                dc.drawText(anchor, y - line - 2, small, label, Graphics.TEXT_JUSTIFY_CENTER);
            }
        }

        // The span, named at its two ends.
        var info = Gregorian.info(new Time.Moment(firstWeek), Time.FORMAT_MEDIUM);
        var start = (info.day as Number).toString() + " " + (info.month as String);
        dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, bottom + 4, small, start, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(left + width, bottom + 4, small,
            WatchUi.loadResource(Rez.Strings.ChartThisWeek) as String, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    //! RepFlow's mark is a filled dot in its colour; Garmin's a ring in its
    //! own, because what it stands for is a session we only know the outline of.
    public function sourceMark(dc as Graphics.Dc, cx as Number, cy as Number, r as Number, garmin as Boolean) as Void {
        var radius = r < 3 ? 3 : r;
        if (garmin) {
            dc.setColor(garminColor(), Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(radius / 3 < 2 ? 2 : radius / 3);
            dc.drawCircle(cx, cy, radius);
            dc.setPenWidth(1);
        } else {
            dc.setColor(repflowColor(), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, cy, radius);
        }
    }
}
