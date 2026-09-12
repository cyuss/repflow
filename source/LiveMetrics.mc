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

    //! The athlete's own heart rate zone thresholds, read once.
    //!
    //! Six numbers: the floor of zone 1, then the ceiling of each of the five
    //! zones. They come from the watch's profile and cannot change while a
    //! workout runs, so reading them on every frame — which the gauge would
    //! otherwise do — is pure waste.
    var _zones as Array<Number>? = null;
    var _zonesRead as Boolean = false;

    public function zones() as Array<Number>? {
        if (_zonesRead) {
            return _zones;
        }
        _zonesRead = true;
        if (!(UserProfile has :getHeartRateZones)) {
            return null;
        }
        try {
            var z = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
            if (z != null && z.size() >= 6) {
                _zones = z;
            }
        } catch (e) {
            _zones = null;
        }
        return _zones;
    }

    //! Which heart rate zone the athlete is in: 1..5, or null.
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
        var z = zones();
        if (z == null) {
            return null;
        }
        for (var i = 1; i <= 5; i++) {
            if (hr <= z[i]) {
                return i;
            }
        }
        return 5;   // above the top threshold is still zone 5
    }

    //! How far through its own zone a reading sits, from 0.0 to 1.0.
    //!
    //! This is what turns five lit blocks into a gauge. "Zone 3" covers a wide
    //! span of effort — the bottom of it and the top of it are different
    //! workouts — and the number alone never says which end you are at.
    //!
    //! Null when there is no reading or no profile, never a guessed 0.5.
    public function zoneProgressFor(hr as Number?) as Float? {
        if (hr == null) {
            return null;
        }
        var z = zones();
        var zone = zoneFor(hr);
        if (z == null || zone == null) {
            return null;
        }
        return progressIn(hr as Number, z[(zone as Number) - 1], z[zone as Number]);
    }

    //! Where `hr` sits between two thresholds, 0.0 to 1.0.
    //!
    //! Split out from zoneProgressFor because this half is arithmetic and the
    //! other half reads a profile the tests cannot set. Degenerate bounds give
    //! a full bar rather than a division by zero: a zone with no width is one
    //! the athlete is at the top of.
    public function progressIn(hr as Number, floor as Number, ceiling as Number) as Float {
        if (ceiling <= floor) {
            return 1.0;
        }
        if (hr >= ceiling) {
            return 1.0;
        }
        if (hr <= floor) {
            return 0.0;
        }
        return (hr - floor).toFloat() / (ceiling - floor).toFloat();
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
