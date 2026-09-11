import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! End-of-workout screen, paged like the exercise screens.
//!
//!   Page 1 — the headline: duration and training volume
//!   Page 2 — the work:     exercises, sets, reps
//!   Page 3 — the body:     Garmin's calories and heart rate, where available
//!
//! Garmin metrics come straight from Activity.getActivityInfo() and are simply
//! omitted when the device or the activity does not provide them.
//! START saves the Garmin activity, MENU offers discard.
class WorkoutSummaryView extends WatchUi.View {

    public const PAGE_COUNT = 3;

    private var _summary as SessionSummary;
    private var _page as Number;

    public function initialize(summary as SessionSummary) {
        View.initialize();
        _summary = summary;
        _page = 0;
    }

    public function turnPage(delta as Number) as Void {
        _page = (_page + delta + PAGE_COUNT) % PAGE_COUNT;
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var h = dc.getHeight();
        var gap = h / 32;

        var actionTop = Theme.drawActionBar(
            dc, WatchUi.loadResource(Rez.Strings.SaveActivity) as String, Theme.COLOR_DONE);

        var y = h / 9;
        y = Theme.drawFitted(dc, y, WatchUi.loadResource(Rez.Strings.SummaryTitle) as String,
            Theme.fontsLabel(), Theme.COLOR_DONE);
        y += gap + gap;

        if (_page == 1) {
            _drawWorkPage(dc, y, gap);
        } else if (_page == 2) {
            _drawBodyPage(dc, y, gap);
        } else {
            _drawHeadlinePage(dc, y, gap, actionTop);
        }

        Theme.drawPageDots(dc, PAGE_COUNT, _page);
    }

    //! The two numbers worth seeing first, given room to breathe.
    private function _drawHeadlinePage(
        dc as Graphics.Dc,
        y as Number,
        gap as Number,
        actionTop as Number
    ) as Void {
        var duration = Theme.formatDuration(_summary.durationSec);
        var volume = Theme.formatVolume(_summary.totalVolume);

        var labelHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var maxWidth = Theme.usableWidth(dc, dc.getHeight() / 2);
        // Two stacked numbers plus their labels have to fit the space that is
        // left, so each gets an explicit share of it rather than the largest
        // font that happens to fit the width.
        var available = actionTop - y;
        var numberBudget = (available - labelHeight * 2 - gap * 3) / 2;

        var durationFont = Theme.pickFontFitting(dc, duration, Theme.fontsBig(),
            maxWidth, numberBudget);
        var volumeFont = Theme.pickFontFitting(dc, volume, Theme.fontsBig(),
            maxWidth, numberBudget);

        var blockHeight = dc.getFontHeight(durationFont) + labelHeight
            + gap * 3 + dc.getFontHeight(volumeFont) + labelHeight;
        var top = y + (available - blockHeight) / 2;
        if (top < y) {
            top = y;
        }

        top = _drawNumberWithLabel(dc, top, duration, durationFont,
            WatchUi.loadResource(Rez.Strings.Duration) as String, Theme.COLOR_TEXT);
        top += gap * 3;
        _drawNumberWithLabel(dc, top, volume, volumeFont,
            WatchUi.loadResource(Rez.Strings.Volume) as String, Theme.COLOR_ACCENT);
    }

    private function _drawNumberWithLabel(
        dc as Graphics.Dc,
        y as Number,
        value as String,
        font as Graphics.FontDefinition,
        label as String,
        color as Number
    ) as Number {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, y, font, value, Graphics.TEXT_JUSTIFY_CENTER);
        y += dc.getFontHeight(font);
        return Theme.drawFitted(dc, y, label,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.COLOR_DIM);
    }

    private function _drawWorkPage(dc as Graphics.Dc, y as Number, gap as Number) as Void {
        y = Theme.drawMetricRow(dc, y,
            WatchUi.loadResource(Rez.Strings.Exercises) as String,
            _summary.exercisesWorked.toString() + "/" + _summary.exerciseCount.toString(),
            Theme.COLOR_TEXT);
        y += gap + gap;

        y = Theme.drawMetricRow(dc, y,
            WatchUi.loadResource(Rez.Strings.SetsDone) as String,
            _summary.completedSets.toString(),
            Theme.COLOR_TEXT);
        y += gap + gap;

        Theme.drawMetricRow(dc, y,
            WatchUi.loadResource(Rez.Strings.TotalReps) as String,
            _summary.totalReps.toString(),
            Theme.COLOR_TEXT);
    }

    //! Garmin's own numbers. Rows show "--" rather than a fabricated zero when
    //! the device does not provide them.
    private function _drawBodyPage(dc as Graphics.Dc, y as Number, gap as Number) as Void {
        y = Theme.drawMetricRow(dc, y,
            WatchUi.loadResource(Rez.Strings.AvgHr) as String,
            LiveMetrics.format(LiveMetrics.averageHeartRate()),
            Theme.COLOR_HR);
        y += gap + gap;

        y = Theme.drawMetricRow(dc, y,
            WatchUi.loadResource(Rez.Strings.MaxHr) as String,
            LiveMetrics.format(LiveMetrics.maxHeartRate()),
            Theme.COLOR_HR);
        y += gap + gap;

        Theme.drawMetricRow(dc, y,
            WatchUi.loadResource(Rez.Strings.Calories) as String,
            LiveMetrics.format(LiveMetrics.calories()),
            Theme.COLOR_TEXT);
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

    //! START — save the Garmin activity and return to the workout picker.
    public function onSelect() as Boolean {
        AppController.instance().saveActivity();
        _toWorkoutList();
        return true;
    }

    public function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(Rez.Strings.SummaryTitle) as String
        });
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SaveActivity) as String, null, "save", {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.DiscardActivity) as String, null, "discard", {}));
        WatchUi.switchToView(menu, new SummaryActionsDelegate(_view), WatchUi.SLIDE_UP);
        return true;
    }

    //! BACK does not silently drop the recording — it offers the same choice.
    public function onBack() as Boolean {
        return onMenu();
    }

    private function _toWorkoutList() as Void {
        var list = new WorkoutListView();
        WatchUi.switchToView(list, new WorkoutListDelegate(list), WatchUi.SLIDE_RIGHT);
    }
}

class SummaryActionsDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as WorkoutSummaryView;

    public function initialize(view as WorkoutSummaryView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        if (id.equals("discard")) {
            AppController.instance().discardActivity();
        } else {
            AppController.instance().saveActivity();
        }
        var list = new WorkoutListView();
        WatchUi.switchToView(list, new WorkoutListDelegate(list), WatchUi.SLIDE_RIGHT);
    }

    public function onBack() as Void {
        WatchUi.switchToView(_view, new WorkoutSummaryDelegate(_view), WatchUi.SLIDE_DOWN);
    }
}
