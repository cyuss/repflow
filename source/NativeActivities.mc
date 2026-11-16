import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Activity;
import Toybox.UserProfile;

//! What the watch itself knows about past training, and the calendar the
//! Analytics figures are cut by. Annotated for the glance, which counts the
//! week live, so it stays small and depends on nothing in the app.
//!
//! **What the watch gives is a summary, and only a summary.**
//! `UserProfile.getUserActivityHistory()` reports a sport, a start, a duration
//! and a distance — no sub-sport, no exercises, no sets, no loads, no heart
//! rate, no calories. So a native strength session is a date and a duration
//! here, and every screen says so rather than leaving a blank to be read as a
//! zero.
//!
//! **No sub-sport means no certainty that it was strength.** Every activity of
//! sport TRAINING is taken; a cardio class recorded under the same sport would
//! be counted too. There is nothing on the watch that tells them apart.
//!
//! **RepFlow's own sessions are in that history as well** — RepFlow records a
//! real TRAINING activity — so anything that starts within MATCH_SECONDS of a
//! logged RepFlow session is that session, and is not counted a second time.
(:glance :analytics)
module NativeActivities {

    //! How far apart two starts can be and still be the same session. The
    //! recording starts the moment the workout does; five minutes is slack for
    //! a clock correction, not for a second session.
    const MATCH_SECONDS = 300;

    //! An upper bound on the history walked, whatever the firmware returns.
    const MAX_SCAN = 400;

    const DAY = 86400;
    const WEEK = 604800;

    //! Training activities recorded since `since`, as [[start, seconds], ...].
    public function trainingSince(since as Number) as Array<Array<Number>> {
        var out = [] as Array<Array<Number>>;
        if (!(UserProfile has :getUserActivityHistory)) {
            return out;
        }
        var it = UserProfile.getUserActivityHistory();
        var scanned = 0;
        var activity = it.next();
        while (activity != null && scanned < MAX_SCAN) {
            scanned++;
            var start = activity.startTime;
            if (activity.type == Activity.SPORT_TRAINING && start != null) {
                var at = start.value();
                if (at >= since) {
                    var duration = activity.duration;
                    out.add([at, duration != null ? duration.value() : 0] as Array<Number>);
                }
            }
            activity = it.next();
        }
        return out;
    }

    //! True when `start` is the same session as one of `starts`.
    public function matches(start as Number, starts as Array<Number>) as Boolean {
        for (var i = 0; i < starts.size(); i++) {
            if ((start - starts[i]).abs() <= MATCH_SECONDS) {
                return true;
            }
        }
        return false;
    }

    // ------------------------------------------------------------------
    // The calendar. Local time; a week starts on Monday.
    // ------------------------------------------------------------------

    public function startOfDay(epoch as Number) as Number {
        var info = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_SHORT);
        return epoch - ((info.hour as Number) * 3600 + (info.min as Number) * 60
            + (info.sec as Number));
    }

    public function weekStart(epoch as Number) as Number {
        var info = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_SHORT);
        // day_of_week: 1 is Sunday. Days since Monday:
        var back = ((info.day_of_week as Number) + 5) % 7;
        return startOfDay(epoch) - back * DAY;
    }

    public function monthStart(epoch as Number) as Number {
        var info = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_SHORT);
        return startOfDay(epoch) - ((info.day as Number) - 1) * DAY;
    }

    //! Whole days from the day of `then` to the day of `now`: 0 today, 1
    //! yesterday. Rounded, so a daylight-saving hour does not shift a day.
    public function daysAgo(then as Number, now as Number) as Number {
        var diff = startOfDay(now) - startOfDay(then);
        return (diff + DAY / 2) / DAY;
    }
}
