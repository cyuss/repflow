import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Activity;

//! End-of-workout screen.
//!
//! Shows RepFlow's own numbers (sets, reps, volume) next to the Garmin metrics
//! that are genuinely available from Activity.getActivityInfo() — calories and
//! average heart rate are read straight from the live activity, and are simply
//! omitted when the device or the current activity does not provide them.
//!
//! START saves the Garmin activity, MENU offers discard.
class WorkoutSummaryView extends WatchUi.View {

    private var _summary as SessionSummary;
    private var _page as Number;

    public function initialize(summary as SessionSummary) {
        View.initialize();
        _summary = summary;
        _page = 0;
    }

    public function turnPage(delta as Number) as Void {
        var rows = _rows();
        var perPage = 3;
        var pages = (rows.size() + perPage - 1) / perPage;
        if (pages < 1) {
            pages = 1;
        }
        _page = (_page + delta + pages) % pages;
        WatchUi.requestUpdate();
    }

    //! [label, value] pairs, Garmin metrics appended only when available.
    private function _rows() as Array<Array<String> > {
        var rows = [
            [WatchUi.loadResource(Rez.Strings.Duration) as String, Theme.formatDuration(_summary.durationSec)],
            [WatchUi.loadResource(Rez.Strings.Exercises) as String, _summary.exercisesWorked.toString() + "/" + _summary.exerciseCount.toString()],
            [WatchUi.loadResource(Rez.Strings.SetsDone) as String, _summary.completedSets.toString()],
            [WatchUi.loadResource(Rez.Strings.TotalReps) as String, _summary.totalReps.toString()],
            [WatchUi.loadResource(Rez.Strings.Volume) as String, Theme.formatWeight(_summary.totalVolume) + (WatchUi.loadResource(Rez.Strings.Kg) as String)]
        ] as Array<Array<String> >;

        var info = Activity.getActivityInfo();
        if (info != null) {
            var calories = info.calories;
            if (calories != null) {
                rows.add([WatchUi.loadResource(Rez.Strings.Calories) as String, calories.toString()] as Array<String>);
            }
            var avgHr = info.averageHeartRate;
            if (avgHr != null) {
                rows.add([WatchUi.loadResource(Rez.Strings.AvgHr) as String, avgHr.toString()] as Array<String>);
            }
        }
        return rows;
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var w = dc.getWidth();
        var h = dc.getHeight();
        var maxW = (w * 0.84).toNumber();

        Theme.drawFitted(
            dc, (h * 0.09).toNumber(), WatchUi.loadResource(Rez.Strings.SummaryTitle) as String,
            [Graphics.FONT_SMALL, Graphics.FONT_TINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_DONE, maxW
        );

        var rows = _rows();
        var perPage = 3;
        var start = _page * perPage;
        var y = (h * 0.26).toNumber();
        var step = (h * 0.17).toNumber();

        for (var i = start; i < start + perPage && i < rows.size(); i++) {
            Theme.drawFitted(
                dc, y, rows[i][0],
                [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
                Theme.COLOR_DIM, maxW
            );
            Theme.drawFitted(
                dc, y + (h * 0.055).toNumber(), rows[i][1],
                [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY] as Array<Graphics.FontDefinition>,
                Theme.COLOR_TEXT, maxW
            );
            y += step;
        }

        Theme.drawFitted(
            dc, (h * 0.88).toNumber(), WatchUi.loadResource(Rez.Strings.SaveActivity) as String + " = START",
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_ACCENT, maxW
        );
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
        var menu = new WatchUi.Menu2({ :title => WatchUi.loadResource(Rez.Strings.SummaryTitle) as String });
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
