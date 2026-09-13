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

    public static const PAGE_COUNT = 7;

    private var _summary as SessionSummary;
    private var _workout as Workout;
    private var _zones as ZoneTracker;
    //! Whole kilograms per muscle group for the week this session fell in,
    //! read once at construction — the pages repaint on every tick.
    private var _weekly as Array<Number>;
    //! What was beaten this session: `[name, History.RECORD_*, reps, kg]` rows.
    private var _records as Array;
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
        records as Array,
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
        if (_saved && _records.size() > 0) {
            status = _records.size().toString() + " " +
                (WatchUi.loadResource(_records.size() == 1
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
            _drawEffortPage(dc, top, bottom);
        } else if (_page == 5) {
            _drawRecordsPage(dc, top, bottom);
        } else if (_page == 6) {
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
    //! What the session cost the athlete, rather than how much iron moved.
    //!
    //!            88
    //!        BODY BATT
    //!     -21    |    212
    //!    REC HR  |    KCAL
    //!     128    |    156
    //!     AVG    |    MAX
    //!
    //! **Body Battery takes the full-width band**, and that is a layout decision
    //! before it is an editorial one. On a round screen the three bands are not
    //! the same width: the single one spans the middle of the glass, the pair
    //! below it gets 91px a cell, and the bottom pair gets 64. "BODY BATT" needs
    //! 77px, so anywhere but the full-width band it either collides with its
    //! neighbour or has to be abbreviated into something that reads as the
    //! watch's own battery.
    //!
    //! It earns the position anyway: it is the one number that answers what the
    //! session took out of you, which is the question this page exists for.
    //!
    //! The heart rate pair is captioned **AVG** and **MAX**, not "AVG HR" and
    //! "MAX HR". At 50px in a 64px cell those two left seven pixels either side
    //! of the divider and read as touching on a real watch — reported, then
    //! measured. They sit together, in the heart rate colour, one page below a
    //! recovery figure also labelled HR; the two dropped words are carried by
    //! everything around them.
    private function _drawBodyPage(dc as Graphics.Dc, top as Number, bottom as Number) as Void {
        var edge = FieldGrid.edgeHeight(top, bottom);
        var middleTop = top + edge;
        var bottomTop = bottom - edge;

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

        FieldGrid.drawSingle(dc, top, edge, batteryText,
            WatchUi.loadResource(Rez.Strings.FieldBattery) as String,
            batteryColor);

        FieldGrid.drawRule(dc, middleTop);
        FieldGrid.drawPair(dc, middleTop, bottomTop - middleTop,
            recoveryText,
            WatchUi.loadResource(Rez.Strings.FieldRecovery) as String,
            _recovery == null ? Theme.colorFaint() : Theme.colorDone(),
            LiveMetrics.format(LiveMetrics.calories()),
            WatchUi.loadResource(Rez.Strings.FieldKcal) as String,
            Theme.colorWarm());

        FieldGrid.drawRule(dc, bottomTop);
        FieldGrid.drawPair(dc, bottomTop, edge,
            LiveMetrics.format(LiveMetrics.averageHeartRate()),
            WatchUi.loadResource(Rez.Strings.FieldAvgHr) as String,
            Theme.colorHr(),
            LiveMetrics.format(LiveMetrics.maxHeartRate()),
            WatchUi.loadResource(Rez.Strings.FieldMaxHr) as String,
            Theme.colorHr());
    }

    //! How hard the session felt, set by set.
    //!
    //!            8.2
    //!           AVG RPE
    //!        ▁▃▅▆▇▆▅█
    //!        first        last
    //!
    //! One bar per rated set, in the order they were performed, at the height
    //! of its rating and in its colour. A list of numbers would say what each
    //! set cost; the shape says whether the session held together — a ramp
    //! means you built into it, a wall of nines from the second set means you
    //! opened too heavy, and neither is visible any other way.
    //!
    //! Unrated sets are drawn as a mark on the baseline rather than skipped, so
    //! the chart keeps the session's real length and a gap reads as "not rated"
    //! instead of "did not happen".
    private function _drawEffortPage(dc as Graphics.Dc, top as Number, bottom as Number) as Void {
        var rated = [] as Array;      // Float? per performed set, in order
        var sum = 0.0;
        var count = 0;
        var list = _workout.exercises;
        for (var i = 0; i < list.size(); i++) {
            var sets = list[i].sets;
            for (var j = 0; j < sets.size(); j++) {
                var set = sets[j];
                if (!set.completed) {
                    continue;
                }
                rated.add(set.rpe);
                if (set.rpe != null) {
                    sum += set.rpe as Float;
                    count++;
                }
            }
        }

        var caption = WatchUi.loadResource(Rez.Strings.FieldRpe) as String;
        if (count == 0) {
            // Nothing was rated. Saying "--" is true; drawing an empty chart
            // would look like a rendering fault.
            FieldGrid.drawSingle(dc, top, bottom - top, LiveMetrics.NO_VALUE, caption,
                Theme.colorFaint());
            return;
        }

        var average = sum / count;
        var edge = FieldGrid.edgeHeight(top, bottom);
        FieldGrid.drawSingle(dc, top, edge, Rpe.format(_nearestRung(average)),
            WatchUi.loadResource(Rez.Strings.AvgRpe) as String, Rpe.color(_nearestRung(average)));
        FieldGrid.drawRule(dc, top + edge);
        _drawEffortChart(dc, top + edge, bottom, rated);
    }

    //! The rung nearest a computed average, so it can be drawn and coloured.
    //!
    //! An average of 8.2 is not a rating anybody gave; it is arithmetic over
    //! ratings. Snapping it to the ladder is what lets it share the scale's
    //! colours and its "8.5 not 8.50" formatting, and it never claims more
    //! precision than the eight rungs have.
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

    private function _drawEffortChart(
        dc as Graphics.Dc,
        top as Number,
        bottom as Number,
        rated as Array
    ) as Void {
        var count = rated.size();
        if (count <= 0) {
            return;
        }
        var height = bottom - top;
        var inset = height / 8;
        var chartTop = top + inset;
        var baseline = bottom - inset;
        var span = baseline - chartTop;
        if (span <= 4) {
            return;
        }

        // The page-dot gutter off both sides, as every chart on these pages
        // does, so the block stays centred.
        var gutter = dc.getWidth() / 14;
        var width = Theme.bandWidth(dc, chartTop, span) - gutter;
        var left = (dc.getWidth() - width) / 2;
        var pitch = width / count;
        var barWidth = (pitch * 62) / 100;
        if (barWidth < 2) {
            barWidth = 2;
        }

        // The bottom of the scale is RPE 6, not zero. A chart that started at
        // zero would spend three quarters of its height on effort nobody logs,
        // and every session would look identically hard.
        var rungs = Rpe.size();
        for (var i = 0; i < count; i++) {
            var x = left + i * pitch + (pitch - barWidth) / 2;
            var value = rated[i] as Float?;
            var rung = Rpe.indexOf(value);
            if (rung < 0) {
                // Unrated: a mark on the baseline, so the set still occupies
                // its place in the session.
                dc.setColor(Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
                Theme.fillBar(dc, x, baseline - 2, barWidth, 2);
                continue;
            }
            var barHeight = (span * (rung + 1)) / rungs;
            barHeight = (barHeight * Animator.value()).toNumber();
            if (barHeight < 2) {
                barHeight = 2;
            }
            dc.setColor(Rpe.colorAt(rung), Graphics.COLOR_TRANSPARENT);
            Theme.fillBar(dc, x, baseline - barHeight, barWidth, barHeight);
        }

        dc.setColor(Theme.colorFaint(), Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(left, baseline, width, 1);
    }

    //! What was beaten today, and by how much.
    //!
    //!        2 RECORDS
    //!     Bench Press
    //!     WEIGHT   82.5 kg
    //!     Lat Pulldown
    //!     EST 1RM  95 kg
    //!
    //! A count on the first page says "2 records" and leaves the athlete to work
    //! out which lift and by what, which is the whole of what they want to know.
    //! This names them.
    //!
    //! Records are rare, so the empty state is the common one and it says so
    //! plainly rather than showing an empty list.
    private function _drawRecordsPage(dc as Graphics.Dc, top as Number, bottom as Number) as Void {
        if (_records.size() == 0) {
            FieldGrid.drawSingle(dc, top, bottom - top,
                LiveMetrics.NO_VALUE,
                WatchUi.loadResource(Rez.Strings.RecordMany) as String,
                Theme.colorFaint());
            return;
        }

        var font = Graphics.FONT_XTINY;
        var lineHeight = dc.getFontHeight(font);
        var rowHeight = lineHeight * 2 + lineHeight / 3;
        var available = bottom - top;

        var shown = _records.size();
        var rows = available / rowHeight;
        if (rows < 1) {
            return;
        }
        var truncated = false;
        if (shown > rows) {
            shown = rows - 1;
            truncated = true;
        }
        if (shown < 1) {
            shown = 1;
            truncated = _records.size() > 1;
        }

        var used = (shown + (truncated ? 1 : 0)) * rowHeight;
        var y = top + (available - (used - lineHeight / 3)) / 2;
        if (y < top) {
            y = top;
        }

        var gutter = dc.getWidth() / 14;
        var width = Theme.bandWidth(dc, y, used) - gutter;
        var left = (dc.getWidth() - width) / 2;

        for (var i = 0; i < shown; i++) {
            var row = _records[i] as Array;
            Theme.drawClippedAt(dc, left, y, row[0] as String, font,
                Theme.colorText(), width);

            var kind = WatchUi.loadResource(_recordLabel(row[1] as Number)) as String;
            dc.setColor(Theme.colorWarm(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, y + lineHeight, font, kind, Graphics.TEXT_JUSTIFY_LEFT);

            var weight = row[3] as Float?;
            if (weight != null) {
                dc.setColor(Theme.colorAccent(), Graphics.COLOR_TRANSPARENT);
                dc.drawText(left + width, y + lineHeight, font,
                    Theme.formatWeight(weight as Float) + " " + Units.label(),
                    Graphics.TEXT_JUSTIFY_RIGHT);
            }
            y += rowHeight;
        }

        if (truncated) {
            dc.setColor(Theme.colorDim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2, y, font,
                "+" + (_records.size() - shown).toString(),
                Graphics.TEXT_JUSTIFY_CENTER);
        }
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
            dc.drawText(left, y, font, Theme.clipToWidth(dc, Muscle.name(group), font, labelWidth),
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
    //!
    //! The type size is chosen, not fixed: the largest font whose rows all fit
    //! wins, and the smallest is used only when the session is long enough that
    //! nothing else would show every exercise. Reading "Lat Pulldown 4/4" is the
    //! point of the page — shrinking it to leave white space around the list
    //! made a summary that had to be squinted at.
    private function _drawExercisesPage(dc as Graphics.Dc, top as Number, bottom as Number) as Void {
        var list = _workout.exercises;
        var available = bottom - top;

        var font = _listFont(dc, available, list.size());
        var lineHeight = dc.getFontHeight(font);
        var barHeight = lineHeight / 6;
        if (barHeight < 3) {
            barHeight = 3;
        }
        var barGap = lineHeight / 6;
        var rowHeight = _rowHeight(dc, font);

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
        var width = _listWidth(dc, y, used);
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

    //! Height of one row — name, gap, progress bar, gap to the next.
    private function _rowHeight(dc as Graphics.Dc, font as Graphics.FontDefinition) as Number {
        var lineHeight = dc.getFontHeight(font);
        var barHeight = lineHeight / 6;
        if (barHeight < 3) {
            barHeight = 3;
        }
        return lineHeight + lineHeight / 6 + barHeight + lineHeight / 3;
    }

    //! The largest font that still shows every exercise.
    //!
    //! Falls back to the smallest rather than to "as many as fit in a big
    //! font": a summary that hides two exercises to make the rest larger has
    //! answered the wrong question.
    private function _listFont(
        dc as Graphics.Dc,
        available as Number,
        count as Number
    ) as Graphics.FontDefinition {
        var ladder = [
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ] as Array<Graphics.FontDefinition>;
        for (var i = 0; i < ladder.size(); i++) {
            if (count * _rowHeight(dc, ladder[i]) <= available) {
                return ladder[i];
            }
        }
        return ladder[ladder.size() - 1];
    }

    //! How wide the block may be: the chord, stopped short of the page dots.
    //!
    //! The gutter used to be a flat fraction of the screen taken off both
    //! sides, which was wider than the dots need and left the list looking
    //! cramped inside a circle with room to spare. This asks the dots where
    //! they are instead. Symmetric, because the block is centred — whatever
    //! clearance the right edge needs, the left edge gets as well.
    private function _listWidth(dc as Graphics.Dc, y as Number, used as Number) as Number {
        var centre = dc.getWidth() / 2;
        var clearance = dc.getWidth() / 40;
        var half = Theme.pageDotsLeft(dc) - clearance - centre;
        var capped = half > 0 ? half * 2 : 0;
        var band = Theme.bandWidth(dc, y, used);
        return band < capped ? band : capped;
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
            Theme.clipToWidth(dc, exercise.name, font, width - countWidth - gap),
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
