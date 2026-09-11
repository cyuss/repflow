import Toybox.Lang;
import Toybox.Activity;

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

    //! Render a nullable number, or "--" when the device has nothing to give.
    public function format(value as Number?) as String {
        if (value == null) {
            return NO_VALUE;
        }
        return value.toString();
    }
}
