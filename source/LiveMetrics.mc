import Toybox.Lang;
import Toybox.Activity;
import Toybox.UserProfile;
import Toybox.SensorHistory;

//! Read-only access to the Garmin metrics that are genuinely available while an
//! activity is recording.
//!
//! Two kinds of "no value" have to be handled, and they are different:
//!
//!   * `Activity.getActivityInfo()` returns nothing outside an activity. The SDK
//!     types it as non-null, so it is widened to `Info?` below — the runtime
//!     really can hand back null, and reading a field off that would throw.
//!   * Individual fields are null when the device does not supply them: no
//!     optical HR, no strap paired, the sensor still acquiring.
//!
//! Every accessor returns null rather than a zero, so the UI can show "--"
//! instead of a confident lie. This is the only place RepFlow reads Garmin's
//! live activity data.
module LiveMetrics {

    const NO_VALUE = "--";

    //! The SDK types getActivityInfo() as non-null; it is not, outside an
    //! activity. Widening it here keeps the null guards honest and lets the
    //! type checker verify them.
    public function info() as Activity.Info? {
        return Activity.getActivityInfo() as Activity.Info?;
    }

    public function heartRate() as Number? {
        var i = info();
        return i == null ? null : i.currentHeartRate;
    }

    public function averageHeartRate() as Number? {
        var i = info();
        return i == null ? null : i.averageHeartRate;
    }

    public function maxHeartRate() as Number? {
        var i = info();
        return i == null ? null : i.maxHeartRate;
    }

    public function calories() as Number? {
        var i = info();
        return i == null ? null : i.calories;
    }

    //! Moving time of the Garmin activity, in seconds.
    public function timerSeconds() as Number? {
        var i = info();
        if (i == null) {
            return null;
        }
        var ms = i.timerTime;
        if (ms == null) {
            return null;
        }
        return ms / 1000;
    }

    //! Which heart rate zone the athlete is in: 1..5, or null.
    //!
    //! UserProfile.getHeartRateZones returns six thresholds — the floor of zone
    //! 1 followed by the ceiling of each zone — so the zone is the first
    //! ceiling the reading falls under.
    public function heartRateZone() as Number? {
        return zoneFor(heartRate());
    }

    //! The zone a given reading falls in. Separate from heartRateZone() so the
    //! 1 Hz tick can read the sensor once and feed both the zone chart and the
    //! recovery tracker from it.
    public function zoneFor(hr as Number?) as Number? {
        if (hr == null) {
            return null;
        }
        if (!(UserProfile has :getHeartRateZones)) {
            return null;
        }
        try {
            var zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
            if (zones == null || zones.size() < 6) {
                return null;
            }
            for (var i = 1; i <= 5; i++) {
                if (hr <= zones[i]) {
                    return i;
                }
            }
            return 5;   // above the top threshold is still zone 5
        } catch (e) {
            return null;
        }
    }

    //! The wearer's current Body Battery, 0-100, or null.
    //!
    //! Garmin's own number, read rather than computed — RepFlow has no business
    //! estimating it. Not every device tracks it and not every firmware exposes
    //! the history module, so both are checked with `has` rather than a
    //! try/catch: a missing symbol is a Monkey C runtime error, and those are
    //! not Exceptions.
    public function bodyBattery() as Number? {
        if (!(Toybox has :SensorHistory)) {
            return null;
        }
        if (!(SensorHistory has :getBodyBatteryHistory)) {
            return null;
        }
        try {
            var iterator = SensorHistory.getBodyBatteryHistory({
                :period => 1,
                :order => SensorHistory.ORDER_NEWEST_FIRST
            });
            var sample = iterator.next();
            if (sample == null) {
                return null;
            }
            var value = sample.data;
            if (!(value instanceof Number) && !(value instanceof Float)) {
                return null;
            }
            var n = (value instanceof Float) ? (value as Float).toNumber() : value as Number;
            return (n >= 0 && n <= 100) ? n : null;
        } catch (e) {
            return null;
        }
    }

    //! Render a nullable number, or "--" when the device has nothing to give.
    public function format(value as Number?) as String {
        if (value == null) {
            return NO_VALUE;
        }
        return value.toString();
    }
}
