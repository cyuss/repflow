import Toybox.Lang;

//! Seconds spent in each heart rate zone, accumulated one sample per second.
//!
//! Garmin's own end-of-activity screens show time in zone as a bar chart, and
//! Connect IQ gives no way to read that figure back — `Activity.Info` reports
//! the *current* heart rate and nothing about how long it has been where. So
//! RepFlow counts it itself, off the same 1 Hz tick that drives the rest timer.
//!
//! What that is, precisely: one sample per tick, each worth one second, binned
//! by `LiveMetrics.heartRateZone()`. Seconds with no reading — sensor still
//! acquiring, strap dropped, no zones on the profile — are counted as sampled
//! but attributed to no zone, so `total()` never inflates a bar with time the
//! watch could not see.
//!
//! It is deliberately pure: it imports Toybox.Lang and nothing else, takes the
//! zone as an argument rather than reading the sensor, and is therefore fully
//! testable. Its only caller is AppController.onTick.
//!
//! It is **not persisted**. A workout interrupted by an app restart loses its
//! zone history, which is consistent with the recording itself: a Garmin
//! activity cannot be reattached after a restart either (see
//! docs/API_LIMITATIONS.md). Persisting it would change the stored session
//! layout for data that is already gone by then.
class ZoneTracker {

    public static const ZONE_COUNT = 5;

    //! Index 0 holds zone 1.
    private var _seconds as Array<Number>;
    private var _sampled as Number;

    public function initialize() {
        _seconds = [0, 0, 0, 0, 0] as Array<Number>;
        _sampled = 0;
    }

    //! One second passed with the athlete in `zone` (1..5), or nowhere known.
    public function sample(zone as Number?) as Void {
        _sampled++;
        if (zone == null || zone < 1 || zone > ZONE_COUNT) {
            return;
        }
        _seconds[zone - 1] += 1;
    }

    //! Seconds spent in `zone` (1..5); zero for anything outside that range.
    public function secondsIn(zone as Number) as Number {
        if (zone < 1 || zone > ZONE_COUNT) {
            return 0;
        }
        return _seconds[zone - 1];
    }

    //! Seconds actually attributed to a zone. Not the workout's duration.
    public function total() as Number {
        var sum = 0;
        for (var i = 0; i < ZONE_COUNT; i++) {
            sum += _seconds[i];
        }
        return sum;
    }

    //! Seconds observed, whether or not a zone could be determined.
    public function sampled() as Number {
        return _sampled;
    }

    //! The longest-held zone, or null when no second could be attributed.
    public function peakZone() as Number? {
        var best = 0;
        var bestZone = null as Number?;
        for (var i = 0; i < ZONE_COUNT; i++) {
            if (_seconds[i] > best) {
                best = _seconds[i];
                bestZone = i + 1;
            }
        }
        return bestZone;
    }

    //! Seconds in the busiest zone — the scale every bar is drawn against.
    public function peakSeconds() as Number {
        var best = 0;
        for (var i = 0; i < ZONE_COUNT; i++) {
            if (_seconds[i] > best) {
                best = _seconds[i];
            }
        }
        return best;
    }
}
