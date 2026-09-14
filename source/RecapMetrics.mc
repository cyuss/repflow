import Toybox.Lang;

//! What Garmin measured, captured at the moment the workout ended.
//!
//! These have to be read **before** the recording is closed. `getActivityInfo`
//! answers null once there is no activity, so a recap that asks for calories
//! while drawing gets "--" every time — which is exactly what it did: the
//! numbers were on screen for as long as it took to stop the recording, and
//! gone by the time anybody looked.
//!
//! Each one is nullable and stays that way. A watch with no optical sensor, a
//! strap that never paired, a session too short to burn a calorie Garmin will
//! admit to — all of those are honestly "--", and none of them is a zero.
class RecapMetrics {

    public var calories as Number?;
    public var averageHeartRate as Number?;
    public var maxHeartRate as Number?;
    //! Body Battery when the session began, for the before-and-after.
    public var batteryStart as Number?;
    //! Best beats dropped in a minute of rest during the session.
    public var recovery as Number?;

    public function initialize(
        calories as Number?,
        averageHeartRate as Number?,
        maxHeartRate as Number?,
        batteryStart as Number?,
        recovery as Number?
    ) {
        me.calories = calories;
        me.averageHeartRate = averageHeartRate;
        me.maxHeartRate = maxHeartRate;
        me.batteryStart = batteryStart;
        me.recovery = recovery;
    }

    //! Read everything Garmin can still answer. Call while recording.
    public static function capture(
        batteryStart as Number?,
        recovery as Number?
    ) as RecapMetrics {
        return new RecapMetrics(
            LiveMetrics.calories(),
            LiveMetrics.averageHeartRate(),
            LiveMetrics.maxHeartRate(),
            batteryStart,
            recovery);
    }
}
