import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! End-of-workout screen, on the same data-field grid as the exercise screens.
//!
//!   Page 1 — the work   duration, volume, sets, reps
//!   Page 2 — the body   Garmin's heart rate and calories, where available
//!
//! Garmin metrics come straight from Activity.getActivityInfo() and show "--"
//! rather than a fabricated zero when the device does not provide them.
//! START saves the Garmin activity, MENU offers discard.
class WorkoutSummaryView extends WatchUi.View {

    public const PAGE_COUNT = 2;

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

        var actionTop = Theme.drawActionBar(
            dc, WatchUi.loadResource(Rez.Strings.SaveActivity) as String, Theme.COLOR_DONE);

        var y = h / 14;
        y = Theme.drawFitted(dc, y, WatchUi.loadResource(Rez.Strings.SummaryTitle) as String,
            Theme.fontsTitle(), Theme.COLOR_DONE);
        y += h / 40;
        FieldGrid.drawRule(dc, y);

        var top = y + 1;
        var bottom = actionTop - h / 60;

        if (_page == 1) {
            _drawBodyPage(dc, top, bottom);
        } else {
            _drawWorkPage(dc, top, bottom);
        }

        Theme.drawPageDots(dc, PAGE_COUNT, _page);
    }

    //! Duration leads full width — "1:02:34" needs it — with sets and reps
    //! sharing the wide middle, and volume closing full width.
    private function _drawWorkPage(dc as Graphics.Dc, top as Number, bottom as Number) as Void {
        var edge = FieldGrid.edgeHeight(top, bottom);
        var middleTop = top + edge;
        var bottomTop = bottom - edge;

        FieldGrid.drawSingle(dc, top, edge,
            Theme.formatDuration(_summary.durationSec),
            WatchUi.loadResource(Rez.Strings.FieldTime) as String,
            Theme.COLOR_TEXT);

        FieldGrid.drawRule(dc, middleTop);
        FieldGrid.drawPair(dc, middleTop, bottomTop - middleTop,
            _summary.completedSets.toString(),
            WatchUi.loadResource(Rez.Strings.FieldSets) as String,
            Theme.COLOR_DONE,
            _summary.totalReps.toString(),
            WatchUi.loadResource(Rez.Strings.FieldReps) as String,
            Theme.COLOR_TEXT);

        FieldGrid.drawRule(dc, bottomTop);
        FieldGrid.drawSingle(dc, bottomTop, edge,
            Theme.formatVolume(_summary.totalVolume),
            WatchUi.loadResource(Rez.Strings.FieldVolume) as String,
            Theme.COLOR_ACCENT);
    }

    //! Garmin's own numbers, plus how much of the workout was actually worked.
    private function _drawBodyPage(dc as Graphics.Dc, top as Number, bottom as Number) as Void {
        var edge = FieldGrid.edgeHeight(top, bottom);
        var middleTop = top + edge;
        var bottomTop = bottom - edge;

        FieldGrid.drawSingle(dc, top, edge,
            LiveMetrics.format(LiveMetrics.calories()),
            WatchUi.loadResource(Rez.Strings.FieldKcal) as String,
            Theme.COLOR_WARM);

        FieldGrid.drawRule(dc, middleTop);
        FieldGrid.drawPair(dc, middleTop, bottomTop - middleTop,
            LiveMetrics.format(LiveMetrics.averageHeartRate()),
            WatchUi.loadResource(Rez.Strings.FieldAvgHr) as String,
            Theme.COLOR_HR,
            LiveMetrics.format(LiveMetrics.maxHeartRate()),
            WatchUi.loadResource(Rez.Strings.FieldMaxHr) as String,
            Theme.COLOR_HR);

        FieldGrid.drawRule(dc, bottomTop);
        FieldGrid.drawSingle(dc, bottomTop, edge,
            _summary.exercisesWorked.toString() + "/" + _summary.exerciseCount.toString(),
            WatchUi.loadResource(Rez.Strings.FieldExercises) as String,
            Theme.COLOR_DONE);
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
