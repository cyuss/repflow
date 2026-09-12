import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! End-of-workout recap, on the same data-field grid as the exercise screens.
//!
//!   Page 1 — the work        time, sets done / planned, reps, volume
//!   Page 2 — the body        Garmin's calories and heart rate
//!   Page 3 — the exercises   what was actually done, exercise by exercise
//!
//! It carries no buttons. Save and discard were answered in the stop menu
//! before this screen opened (see EndWorkoutFlow); a SAVE button here asked a
//! question that had already been asked, and spent the bottom of the screen
//! doing it. BACK leaves, UP/DOWN page.
//!
//! The rim ring is sets done against sets planned — the one number that says
//! whether the session was finished or cut short — and it is dimmed when the
//! recording was discarded, so the screen never looks like a saved activity.
//!
//! Garmin metrics come straight from Activity.getActivityInfo() and show "--"
//! rather than a fabricated zero when the device does not provide them.
class WorkoutSummaryView extends WatchUi.View {

    public const PAGE_COUNT = 3;

    private var _summary as SessionSummary;
    private var _workout as Workout;
    private var _saved as Boolean;
    private var _page as Number;

    public function initialize(summary as SessionSummary, workout as Workout, saved as Boolean) {
        View.initialize();
        _summary = summary;
        _workout = workout;
        _saved = saved;
        _page = 0;
    }

    public function turnPage(delta as Number) as Void {
        _page = (_page + delta + PAGE_COUNT) % PAGE_COUNT;
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var h = dc.getHeight();

        var planned = _summary.plannedSets;
        Theme.drawProgressRing(dc,
            planned > 0 ? _summary.completedSets.toFloat() / planned.toFloat() : 0.0,
            _saved ? Theme.COLOR_DONE : Theme.COLOR_SKIPPED);

        var y = Theme.drawFitted(dc, h / 16, _workout.name,
            [Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_TEXT);

        var status = _saved
            ? WatchUi.loadResource(Rez.Strings.SummaryTitle) as String
            : WatchUi.loadResource(Rez.Strings.SummaryDiscarded) as String;
        y = Theme.drawFitted(dc, y, status,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            _saved ? Theme.COLOR_DONE : Theme.COLOR_SKIPPED);

        y += h / 60;
        FieldGrid.drawRule(dc, y);

        var top = y + 1;
        var bottom = h - h / 13;

        if (_page == 1) {
            _drawBodyPage(dc, top, bottom);
        } else if (_page == 2) {
            _drawExercisesPage(dc, top, bottom);
        } else {
            _drawWorkPage(dc, top, bottom);
        }

        Theme.drawPageDots(dc, PAGE_COUNT, _page);
    }

    //! Duration leads full width — "1:02:34" needs it — with sets and reps
    //! sharing the wide middle, and volume closing full width.
    //!
    //! Sets are shown against the plan ("12/16"), not on their own: twelve sets
    //! means nothing without knowing whether sixteen were asked for.
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
            _summary.completedSets.toString() + "/" + _summary.plannedSets.toString(),
            WatchUi.loadResource(Rez.Strings.FieldSets) as String,
            _summary.completedSets >= _summary.plannedSets
                ? Theme.COLOR_DONE
                : Theme.COLOR_WARM,
            _summary.totalReps.toString(),
            WatchUi.loadResource(Rez.Strings.FieldReps) as String,
            Theme.COLOR_TEXT);

        FieldGrid.drawRule(dc, bottomTop);
        FieldGrid.drawSingle(dc, bottomTop, edge,
            Theme.formatVolume(_summary.totalVolume),
            WatchUi.loadResource(Rez.Strings.FieldVolume) as String,
            Theme.COLOR_ACCENT);
    }

    //! Garmin's own numbers, plus the average load moved per set — the one
    //! derived figure worth showing, because it says how heavy the session was
    //! rather than how long it took.
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
        var perSet = _summary.completedSets > 0
            ? Theme.formatVolume(_summary.totalVolume / _summary.completedSets.toFloat())
            : LiveMetrics.NO_VALUE;
        FieldGrid.drawSingle(dc, bottomTop, edge, perSet,
            WatchUi.loadResource(Rez.Strings.FieldPerSet) as String,
            Theme.COLOR_ACCENT);
    }

    //! What was actually done, exercise by exercise.
    //!
    //!   Lat Pulldown        4/4
    //!   Seated Row          2/4
    //!   Face Pull           0/4
    //!
    //! The count is coloured by the exercise's final state, so a glance
    //! separates finished from parked from skipped without a legend.
    //!
    //! Each row measures its own usable width: a round screen narrows towards
    //! the bottom, and a row that fits at the top of the list would run into
    //! the bezel at the end of it.
    private function _drawExercisesPage(dc as Graphics.Dc, top as Number, bottom as Number) as Void {
        var font = Graphics.FONT_XTINY;
        var lineHeight = dc.getFontHeight(font);
        var rowHeight = lineHeight + lineHeight / 4;
        var list = _workout.exercises;

        var available = bottom - top;
        var rows = available / rowHeight;
        if (rows < 1) {
            return;
        }
        // Leave the last row for "+N more" when the list cannot fit.
        var shown = list.size();
        var truncated = false;
        if (shown > rows) {
            shown = rows - 1;
            truncated = true;
        }

        // Centre on the rows actually drawn, not on the rows that would fit:
        // four exercises in a five-row space belong in the middle of it.
        var used = (shown + (truncated ? 1 : 0)) * rowHeight;
        var y = top + (available - used) / 2;
        if (y < top) {
            y = top;
        }

        // One margin for the whole block, measured at its narrowest row.
        //
        // Measuring each row against its own chord is geometrically right and
        // looks wrong: the circle narrows as the list descends, so every name
        // started a little further in than the one above it and the left edge
        // came out as a staircase. A list wants a straight margin.
        var width = Theme.bandWidth(dc, y, used) - dc.getWidth() / 14;
        var left = (dc.getWidth() - width - dc.getWidth() / 14) / 2;

        for (var i = 0; i < shown; i++) {
            var ex = list[i];
            var count = ex.completedSetCount().toString() + "/" + ex.targetSets.toString();
            _drawRow(dc, y, font, left, width, ex.name, count, Theme.stateColor(ex.state));
            y += rowHeight;
        }

        if (truncated) {
            var rest = list.size() - shown;
            dc.setColor(Theme.COLOR_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2, y, font, "+" + rest.toString(),
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    //! One list row: name on the left, count on the right.
    //!
    //! The block's right end stops short of the page dots. They live in a
    //! column down the right edge, and a right-aligned "0/4" ran into them.
    private function _drawRow(
        dc as Graphics.Dc,
        y as Number,
        font as Graphics.FontDefinition,
        left as Number,
        width as Number,
        name as String,
        count as String,
        countColor as Number
    ) as Void {
        var gap = width / 16;
        var countWidth = dc.getTextWidthInPixels(count, font);

        dc.setColor(countColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + width, y, font, count, Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(Theme.COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, y, font, _clip(dc, name, font, width - countWidth - gap),
            Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! Shorten `text` until it fits `maxWidth`, ending in a dot so the athlete
    //! can see that something was cut rather than misread a truncated name.
    private function _clip(
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
