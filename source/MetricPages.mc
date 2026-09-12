import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! The two data screens that mean the same thing whether you are working or
//! resting: what your body is doing, and what the session has accumulated.
//!
//! They live here rather than on the exercise screen because the rest screen
//! shows them too, under the same UP/DOWN paging. That is the point: the
//! athlete learns one paging model and it does not change when the timer
//! starts. A second, different set of rest screens would be a second thing to
//! learn for no gain.
//!
//! Garmin's four-field round layout throughout: a full-width band, a split
//! middle, a full-width band. Wide values ("1:02:34", "3.2 t") always take a
//! full band, because half a cell near the top or bottom of a circle is far too
//! narrow for them.
module MetricPages {

    //! Title and a rule, the header both pages share.
    public function header(dc as Graphics.Dc, title as String) as Number {
        var h = dc.getHeight();
        var y = Marquee.drawFitted(dc, h / 14, title, Theme.fontsTitle(), Theme.COLOR_TEXT,
            Theme.usableWidth(dc, h / 14));
        y += h / 44;
        FieldGrid.drawRule(dc, y);
        return y + 1;
    }

    //! Where a page's fields stop. Low, because the bottom of a round screen is
    //! narrow and the caption needs the width.
    public function bottom(dc as Graphics.Dc) as Number {
        var h = dc.getHeight();
        return h - h / 13;
    }

    //! The body: heart rate with its zone gauge, average and calories, elapsed.
    //!
    //! Heart rate leads because it is the number worth a glance mid-set, and
    //! the elapsed time sits full width at the bottom because "1:02:34" is far
    //! too wide for half a cell on a round screen.
    public function drawBody(dc as Graphics.Dc, title as String) as Void {
        var top = header(dc, title);
        var end = bottom(dc);
        var edge = FieldGrid.edgeHeight(top, end);
        var middleTop = top + edge;
        var bottomTop = end - edge;

        Theme.drawHeartRateField(dc, top, edge,
            WatchUi.loadResource(Rez.Strings.FieldHr) as String);

        FieldGrid.drawRule(dc, middleTop);
        FieldGrid.drawPair(dc, middleTop, bottomTop - middleTop,
            LiveMetrics.format(LiveMetrics.averageHeartRate()),
            WatchUi.loadResource(Rez.Strings.FieldAvgHr) as String,
            Theme.COLOR_HR,
            LiveMetrics.format(LiveMetrics.calories()),
            WatchUi.loadResource(Rez.Strings.FieldKcal) as String,
            Theme.COLOR_WARM);

        var timer = LiveMetrics.timerSeconds();
        FieldGrid.drawRule(dc, bottomTop);
        FieldGrid.drawSingle(dc, bottomTop, edge,
            timer != null ? Theme.formatDuration(timer) : LiveMetrics.NO_VALUE,
            WatchUi.loadResource(Rez.Strings.FieldTime) as String,
            Theme.COLOR_TEXT);
    }

    //! The session so far: volume, sets and reps, exercises finished.
    public function drawWorkout(dc as Graphics.Dc, engine as WorkoutEngine) as Void {
        var summary = engine.summary(AppController.now());
        var top = header(dc, engine.getWorkout().name);
        var end = bottom(dc);

        var done = 0;
        var list = engine.getWorkout().exercises;
        for (var i = 0; i < list.size(); i++) {
            if (list[i].state == EX_COMPLETED) {
                done++;
            }
        }

        var edge = FieldGrid.edgeHeight(top, end);
        var middleTop = top + edge;
        var bottomTop = end - edge;

        FieldGrid.drawSingle(dc, top, edge,
            Theme.formatVolume(summary.totalVolume),
            WatchUi.loadResource(Rez.Strings.FieldVolume) as String,
            Theme.COLOR_ACCENT);

        FieldGrid.drawRule(dc, middleTop);
        FieldGrid.drawPair(dc, middleTop, bottomTop - middleTop,
            summary.completedSets.toString(),
            WatchUi.loadResource(Rez.Strings.FieldSets) as String,
            Theme.COLOR_DONE,
            summary.totalReps.toString(),
            WatchUi.loadResource(Rez.Strings.FieldReps) as String,
            Theme.COLOR_TEXT);

        FieldGrid.drawRule(dc, bottomTop);
        FieldGrid.drawSingle(dc, bottomTop, edge,
            done.toString() + "/" + summary.exerciseCount.toString(),
            WatchUi.loadResource(Rez.Strings.FieldExercises) as String,
            Theme.COLOR_DONE);
    }
}
