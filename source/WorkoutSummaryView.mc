import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! End-of-workout recap, on the same data-field grid as the exercise screens.
//!
//!   Page 1 — the work        time, sets done / planned, reps, volume
//!   Page 2 — the body        Garmin's calories and heart rate
//!   Page 3 — time in zones   the bar chart a Fenix shows after any activity
//!   Page 4 — the exercises   what was actually done, exercise by exercise
//!   Page 5 — this week       volume per muscle group, across the last 7 days
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

    public static const PAGE_COUNT = 5;

    private var _summary as SessionSummary;
    private var _workout as Workout;
    private var _zones as ZoneTracker;
    //! Whole kilograms per muscle group for the week this session fell in,
    //! read once at construction — the pages repaint on every tick.
    private var _weekly as Array<Number>;
    private var _records as Number;
    //! Garmin's Body Battery when the session began, for the before-and-after.
    private var _batteryStart as Number?;
    //! Best one-minute heart rate recovery this session.
    private var _recovery as Number?;
    private var _saved as Boolean;
    private var _page as Number;

    public function initialize(
        summary as SessionSummary,
        workout as Workout,
        zones as ZoneTracker,
        weekly as Array<Number>,
        records as Number,
        batteryStart as Number?,
        recovery as Number?,
        saved as Boolean
    ) {
        View.initialize();
        _summary = summary;
        _workout = workout;
        _zones = zones;
        _weekly = weekly;
        _records = records;
        _batteryStart = batteryStart;
        _recovery = recovery;
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
        // Each page draws itself once, finished. Re-animating on every swipe
        // would put motion between the athlete and a number they are reading.
        Animator.stop();
        _page = (_page + delta + PAGE_COUNT) % PAGE_COUNT;
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var h = dc.getHeight();

        var planned = _summary.plannedSets;
        Theme.drawProgressRing(dc,
            (planned > 0 ? _summary.completedSets.toFloat() / planned.toFloat() : 0.0)
                * Animator.value(),
            _saved ? Theme.colorDone() : Theme.colorFaint());

        var y = Marquee.drawFitted(dc, h / 16, _workout.name,
            [Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.colorText(), Theme.usableWidth(dc, h / 16));

        // A record is the headline when there is one. "Workout done" is true
        // of every session; "2 records" is true of this one.
        var status = _saved
            ? WatchUi.loadResource(Rez.Strings.SummaryTitle) as String
            : WatchUi.loadResource(Rez.Strings.SummaryDiscarded) as String;
        var statusColor = _saved ? Theme.colorDone() : Theme.colorFaint();
        if (_saved && _records > 0) {
            status = _records.toString() + " " +
                (WatchUi.loadResource(_records == 1
                    ? Rez.Strings.RecordOne
                    : Rez.Strings.RecordMany) as String);
            statusColor = Theme.colorWarm();
        }
        y = Theme.drawFitted(dc, y, status,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, statusColor);

        y += h / 60;
        FieldGrid.drawRule(dc, y);

        var top = y + 1;
        var bottom = h - h / 13;

        if (_page == 1) {
            _drawBodyPage(dc, top, bottom);
        } else if (_page == 2) {
            _drawZonesPage(dc, top, bottom);
        } else if (_page == 3) {
            _drawExercisesPage(dc, top, bottom);
        } else if (_page == 4) {
            _drawWeekPage(dc, top, bottom);
        } else {
            _drawWorkPage(dc, top, bottom);
        }

        Theme.drawPageDots(dc, PAGE_COUNT, _page);
        Marquee.endFrame();
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
            Theme.colorText());

        FieldGrid.drawRule(dc, middleTop);
        FieldGrid.drawPair(dc, middleTop, bottomTop - middleTop,
            _summary.completedSets.toString() + "/" + _summary.plannedSets.toString(),
            WatchUi.loadResource(Rez.Strings.FieldSets) as String,
            _summary.completedSets >= _summary.plannedSets
                ? Theme.colorDone()
                : Theme.colorWarm(),
            _summary.totalReps.toString(),
            WatchUi.loadResource(Rez.Strings.FieldReps) as String,
            Theme.colorText());

        FieldGrid.drawRule(dc, bottomTop);
        FieldGrid.drawSingle(dc, bottomTop, edge,
            Theme.formatVolume(_summary.totalVolume),
            WatchUi.loadResource(Rez.Strings.FieldVolume) as String,
            Theme.colorAccent());
    }

    //! Garmin's own numbers, plus the two this app is in a position to add.
    //!
    //! Recovery and Body Battery both replace figures that were derivable from
    //! page one. They are here because they answer something a set count cannot:
    //! how hard the session actually was on the athlete, rather than how much
    //! iron moved.
    //!
    //! The bottom band splits, against the usual rule that only the middle does.
    //! It is allowed here because both values are two or three characters —
    //! "18" and "-21" — which is what the rule is really about.
    private function _drawBodyPage(dc as Graphics.Dc, top as Number, bottom as Number) as Void {
        var edge = FieldGrid.edgeHeight(top, bottom);
        var middleTop = top + edge;
        var bottomTop = bottom - edge;

        FieldGrid.drawSingle(dc, top, edge,
            LiveMetrics.format(LiveMetrics.calories()),
            WatchUi.loadResource(Rez.Strings.FieldKcal) as String,
            Theme.colorWarm());

        FieldGrid.drawRule(dc, middleTop);
        FieldGrid.drawPair(dc, middleTop, bottomTop - middleTop,
            LiveMetrics.format(LiveMetrics.averageHeartRate()),
            WatchUi.loadResource(Rez.Strings.FieldAvgHr) as String,
            Theme.colorHr(),
            LiveMetrics.format(LiveMetrics.maxHeartRate()),
            WatchUi.loadResource(Rez.Strings.FieldMaxHr) as String,
            Theme.colorHr());

        // Best beats dropped in a minute of rest, and what the session cost in
        // Body Battery. Both are "--" when the watch could not measure them,
        // never a zero that reads like a result.
        var recoveryText = _recovery == null
            ? LiveMetrics.NO_VALUE
            : "-" + (_recovery as Number).toString();

        var batteryText = LiveMetrics.NO_VALUE;
        var batteryColor = Theme.colorFaint();
        var start = _batteryStart;
        var finish = LiveMetrics.bodyBattery();
        if (start != null && finish != null) {
            var spent = (start as Number) - (finish as Number);
            batteryText = spent > 0 ? "-" + spent.toString() : (finish as Number).toString();
            batteryColor = Theme.colorDone();
        } else if (finish != null) {
            batteryText = (finish as Number).toString();
            batteryColor = Theme.colorDone();
        }

        FieldGrid.drawRule(dc, bottomTop);
        FieldGrid.drawPair(dc, bottomTop, edge,
            recoveryText,
            WatchUi.loadResource(Rez.Strings.FieldRecovery) as String,
            _recovery == null ? Theme.colorFaint() : Theme.colorDone(),
            batteryText,
            WatchUi.loadResource(Rez.Strings.FieldBattery) as String,
            batteryColor);
    }

    //! The week's volume, muscle group by muscle group.
    //!
    //!   Back      ####################   4.2 t
    //!   Chest     ##########             2.1 t
    //!   Biceps    ###                    0.6 t
    //!
    //! Only the groups that were actually trained appear. A list of ten rows
    //! with seven zeroes in it says nothing, and the question this answers is
    //! whether the week is balanced — six pushing exercises and one pulling is
    //! visible in three seconds here and invisible anywhere else in the app.
    //!
    //! The bar scale is the busiest group, not a target: RepFlow does not know
    //! what the athlete is training for and will not invent a prescription.
    private function _drawWeekPage(dc as Graphics.Dc, top as Number, bottom as Number) as Void {
        var order = Muscle.browseOrder();
        var peak = 0;
        var trained = 0;
        for (var i = 0; i < order.size(); i++) {
            var v = _weekly[order[i]];
            if (v > 0) {
                trained++;
                if (v > peak) {
                    peak = v;
                }
            }
        }
        if (peak <= 0) {
            FieldGrid.drawSingle(dc, top, bottom - top, LiveMetrics.NO_VALUE,
                WatchUi.loadResource(Rez.Strings.ThisWeek) as String, Theme.colorFaint());
            return;
        }

        var font = Graphics.FONT_XTINY;
        var lineHeight = dc.getFontHeight(font);
        var rowHeight = lineHeight + lineHeight / 5;
        var available = bottom - top;

        var rows = available / rowHeight;
        var shown = trained < rows ? trained : rows;
        var used = rowHeight * shown;
        var visible = used - lineHeight / 5;
        var y = top + (available - visible) / 2;
        if (y < top) {
            y = top;
        }

        var gutter = dc.getWidth() / 14;
        var width = Theme.bandWidth(dc, y, used) - gutter;
        var left = (dc.getWidth() - width) / 2;
        var labelWidth = (width * 34) / 100;
        var valueWidth = (width * 26) / 100;
        var gap = dc.getWidth() / 40;
        var barLeft = left + labelWidth + gap;
        var barWidth = width - labelWidth - valueWidth - gap * 2;
        var barHeight = (lineHeight * 45) / 100;
        if (barWidth < 4) {
            return;
        }

        var drawn = 0;
        for (var i = 0; i < order.size() && drawn < shown; i++) {
            var group = order[i];
            var volume = _weekly[group];
            if (volume <= 0) {
                continue;
            }
            var color = Muscle.color(group);

            dc.setColor(Theme.colorText(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, y, font, _clip(dc, Muscle.name(group), font, labelWidth),
                Graphics.TEXT_JUSTIFY_LEFT);

            var barTop = y + (lineHeight - barHeight) / 2;
            var filled = ((barWidth * volume) / peak) * Animator.value();
            if (filled < 3) {
                filled = 3;
            }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barLeft, barTop, filled, barHeight);

            dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left + width, y, font, Theme.formatVolume(volume.toFloat()),
                Graphics.TEXT_JUSTIFY_RIGHT);

            y += rowHeight;
            drawn++;
        }
    }

    //! Time in heart rate zone, as a bar chart — the screen a Fenix shows at
    //! the end of any activity, so this one does not feel like a different
    //! watch.
    //!
    //!   Z5  ###              0:24
    //!   Z4  #########        1:12
    //!   Z3  ##############   2:05
    //!
    //! Zone 5 on top, counting down, the way Garmin orders it. Bars are scaled
    //! against the busiest zone rather than the workout's length: a strength
    //! session spends most of its time resting, and scaling to the clock would
    //! leave every bar a stub.
    //!
    //! With nothing to show — no strap, no zones on the profile — the page says
    //! so instead of drawing five empty bars that look like a zero-effort
    //! session.
    private function _drawZonesPage(dc as Graphics.Dc, top as Number, bottom as Number) as Void {
        var caption = WatchUi.loadResource(Rez.Strings.FieldZones) as String;
        var peak = _zones.peakSeconds();
        if (peak <= 0) {
            FieldGrid.drawSingle(dc, top, bottom - top, LiveMetrics.NO_VALUE, caption,
                Theme.colorFaint());
            return;
        }

        var font = Graphics.FONT_XTINY;
        var lineHeight = dc.getFontHeight(font);
        var rowHeight = lineHeight + lineHeight / 5;
        var used = rowHeight * ZoneTracker.ZONE_COUNT;

        var available = bottom - top;
        var visible = used - lineHeight / 5;   // the last row's trailing gap
        var y = top + (available - visible) / 2;
        if (y < top) {
            y = top;
        }

        // One margin for the block, measured at its narrowest row, with the
        // page-dot gutter taken off both sides so the chart stays centred.
        var gutter = dc.getWidth() / 14;
        var width = Theme.bandWidth(dc, y, used) - gutter;
        var left = (dc.getWidth() - width) / 2;

        var labelWidth = dc.getTextWidthInPixels("Z5", font);
        var timeWidth = dc.getTextWidthInPixels("00:00", font);
        var gap = dc.getWidth() / 26;
        var barLeft = left + labelWidth + gap;
        var barWidth = width - labelWidth - timeWidth - gap * 2;
        var barHeight = (lineHeight * 50) / 100;

        if (barWidth < 4) {
            return;
        }

        for (var zone = ZoneTracker.ZONE_COUNT; zone >= 1; zone--) {
            var seconds = _zones.secondsIn(zone);
            var color = Theme.zoneColor(zone);

            dc.setColor(seconds > 0 ? Theme.colorText() : Theme.colorFaint(),
                Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, y, font, "Z" + zone.toString(), Graphics.TEXT_JUSTIFY_LEFT);

            var barTop = y + (lineHeight - barHeight) / 2;
            // The empty track keeps the five rows reading as one chart even
            // when only two of them have any time in them.
            dc.setColor(Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barLeft, barTop + barHeight - 2, barWidth, 2);

            if (seconds > 0) {
                var filled = ((barWidth * seconds) / peak) * Animator.value();
                if (filled < 3) {
                    filled = 3;
                }
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(barLeft, barTop, filled, barHeight);
            }

            dc.setColor(seconds > 0 ? color : Theme.colorFaint(),
                Graphics.COLOR_TRANSPARENT);
            dc.drawText(left + width, y, font, Theme.formatDuration(seconds),
                Graphics.TEXT_JUSTIFY_RIGHT);

            y += rowHeight;
        }
    }

    //! What was actually done, exercise by exercise.
    //!
    //!   Lat Pulldown                4/4
    //!   ==============================
    //!   Seated Row                  2/4
    //!   ===============---------------
    //!
    //! Each row carries its own progress bar: sets done against sets targeted,
    //! in the colour of the exercise's final state. The numbers alone made the
    //! page a table; the bars make the shape of the session readable at arm's
    //! length — which exercise was finished, which was cut short, which was
    //! never touched — without reading a single digit.
    //!
    //! It is the same bar idiom as the time-in-zone chart one page back, on
    //! purpose: two charts that behave the same way read as one screen.
    private function _drawExercisesPage(dc as Graphics.Dc, top as Number, bottom as Number) as Void {
        var font = Graphics.FONT_XTINY;
        var lineHeight = dc.getFontHeight(font);
        var barHeight = lineHeight / 6;
        if (barHeight < 3) {
            barHeight = 3;
        }
        var barGap = lineHeight / 6;
        var rowHeight = lineHeight + barGap + barHeight + lineHeight / 3;
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
        //
        // The last row's trailing gap is spacing *between* rows, not part of
        // what you see, so centring the raw block height left the list sitting
        // high by half of it.
        var used = (shown + (truncated ? 1 : 0)) * rowHeight;
        var visible = used - lineHeight / 3;
        var y = top + (available - visible) / 2;
        if (y < top) {
            y = top;
        }

        // One margin for the whole block, measured at its narrowest row.
        //
        // Measuring each row against its own chord is geometrically right and
        // looks wrong: the circle narrows as the list descends, so every name
        // started a little further in than the one above it and the left edge
        // came out as a staircase. A list wants a straight margin.
        //
        // The page-dot gutter comes off *both* sides. Taking it off the right
        // alone kept the rows clear of the dots and pushed the whole block off
        // centre by half a gutter, which is exactly as visible as a collision.
        var gutter = dc.getWidth() / 14;
        var width = Theme.bandWidth(dc, y, used) - gutter;
        var left = (dc.getWidth() - width) / 2;

        for (var i = 0; i < shown; i++) {
            var ex = list[i];
            _drawRow(dc, y, font, left, width, barGap, barHeight, ex);
            y += rowHeight;
        }

        if (truncated) {
            var rest = list.size() - shown;
            dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2, y, font, "+" + rest.toString(),
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    //! One list row: name on the left, count on the right, progress underneath.
    //!
    //! The block's right end stops short of the page dots. They live in a
    //! column down the right edge, and a right-aligned "0/4" ran into them.
    private function _drawRow(
        dc as Graphics.Dc,
        y as Number,
        font as Graphics.FontDefinition,
        left as Number,
        width as Number,
        barGap as Number,
        barHeight as Number,
        exercise as Exercise
    ) as Void {
        var done = exercise.completedSetCount();
        var target = exercise.targetSets;
        var count = done.toString() + "/" + target.toString();
        var color = Theme.stateColor(exercise.state);

        var gap = width / 16;
        var countWidth = dc.getTextWidthInPixels(count, font);

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + width, y, font, count, Graphics.TEXT_JUSTIFY_RIGHT);

        // A skipped exercise is a fact about the session, not a headline.
        dc.setColor(exercise.state == EX_SKIPPED ? Theme.colorDim() : Theme.colorText(),
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, y, font,
            _clip(dc, exercise.name, font, width - countWidth - gap),
            Graphics.TEXT_JUSTIFY_LEFT);

        var barTop = y + dc.getFontHeight(font) + barGap;
        dc.setColor(Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(left, barTop, width, barHeight);

        if (done > 0 && target > 0) {
            var full = done >= target ? width : (width * done) / target;
            var filled = full * Animator.value();
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(left, barTop, filled, barHeight);
        }
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
