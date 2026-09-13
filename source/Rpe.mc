import Toybox.Lang;

//! Rate of Perceived Exertion: how hard the set felt, on the athlete's own
//! scale, recorded once it has been done.
//!
//! **The scale is not ours to choose.** Hevy's API accepts `rpe` as a strict
//! enumeration and rejects the whole workout for a value outside it:
//!
//!     6, 7, 7.5, 8, 8.5, 9, 9.5, 10
//!
//! Note what is missing — there is no 6.5. A tidy "6 to 10 in halves" would
//! look right on the watch and cost the athlete their entire session on upload.
//! So the ladder below is transcribed from the published schema, and a test
//! asserts it still matches.
//!
//! Null is a real value here and the default one: a set nobody rated is
//! unrated, not an RPE of 8. Every consumer treats null as absent rather than
//! as a middling effort.
module Rpe {

    //! Exactly the values Hevy accepts, ascending.
    //! Source: PostWorkoutsRequestSet.rpe in the Hevy Public API schema.
    const SCALE = [6.0, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0] as Array<Float>;

    //! Where an unrated set starts when the athlete first presses UP.
    //!
    //! 8, not the bottom of the scale: someone reaching for RPE at all has just
    //! done a working set, and starting at 6 means four presses to say so.
    const OPENING = 8.0;

    //! The position of `value` in the scale, or -1 when it is not on it.
    public function indexOf(value as Float?) as Number {
        if (value == null) {
            return -1;
        }
        for (var i = 0; i < SCALE.size(); i++) {
            // Compared with a tolerance: these come back from storage and from
            // JSON, where 7.5 is not always bit-identical to 7.5.
            if ((SCALE[i] - (value as Float)).abs() < 0.01) {
                return i;
            }
        }
        return -1;
    }

    public function size() as Number {
        return SCALE.size();
    }

    //! Step up or down the ladder.
    //!
    //! From unrated, either direction lands on OPENING — the athlete has said
    //! "I want to rate this", not "I want the hardest one". Stepping below the
    //! bottom clears the rating rather than sticking at 6: changing your mind
    //! about rating a set has to be possible, and there is no other way out.
    public function step(value as Float?, direction as Number) as Float? {
        if (direction == 0) {
            return value;
        }
        var at = indexOf(value);
        if (at < 0) {
            return OPENING;
        }
        var next = direction > 0 ? at + 1 : at - 1;
        if (next < 0) {
            return null;
        }
        if (next >= SCALE.size()) {
            return SCALE[SCALE.size() - 1];
        }
        return SCALE[next];
    }

    //! "8" or "8.5" — never "8.0", which reads as a measurement rather than a
    //! judgement. `--` when the set was not rated.
    public function format(value as Float?) as String {
        if (value == null) {
            return LiveMetrics.NO_VALUE;
        }
        var whole = (value as Float).toNumber();
        var half = ((value as Float) - whole).abs() >= 0.25;
        return half ? whole.toString() + ".5" : whole.toString();
    }

    //! The colour of a rung, climbing with the effort it describes.
    //!
    //! Up to and including 8 is ordinary work and takes the accent colour.
    //! 8.5 and 9 are hard, and take the warm colour the app already uses for
    //! unfinished business. 9.5 and 10 are close to failure and take the colour
    //! it uses for a peak heart rate zone.
    //!
    //! This is the same language the zone chart speaks, on purpose: one app,
    //! one meaning for "this was hard".
    public function colorAt(index as Number) as Number {
        var value = (index >= 0 && index < SCALE.size()) ? SCALE[index] : 0.0;
        if (value >= 9.5) {
            return Theme.zoneColor(5);
        }
        if (value >= 8.5) {
            return Theme.colorWarm();
        }
        return Theme.colorAccent();
    }

    //! The colour of a whole rating — what the number itself is drawn in.
    //! Faint when the set was not rated, which is not an effort level.
    public function color(value as Float?) as Number {
        var at = indexOf(value);
        return at < 0 ? Theme.colorFaint() : colorAt(at);
    }

    //! Only values on the scale survive. Anything else — a corrupted record, a
    //! number from an older build, a Hevy set rated in an app that allows more
    //! — is dropped rather than sent on to be rejected.
    public function sanitise(value as Float?) as Float? {
        return indexOf(value) < 0 ? null : value;
    }
}
