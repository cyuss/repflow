import Toybox.Lang;
import Toybox.Math;

//! Counting repetitions from the wrist, honestly.
//!
//! Garmin's own strength activity counts reps, and that counter is **not**
//! exposed to Connect IQ — so this is RepFlow's own, built from raw
//! accelerometer samples. It is worth being plain about what that means: this
//! is a rhythm detector, not a movement classifier. It is good at bench press,
//! squats, curls and rows, where the wrist traces one clear arc per rep. It is
//! poor at anything where the wrist barely moves, and it cannot tell a rep from
//! a rack adjustment.
//!
//! **Which is why nothing it counts is ever logged on its own.** The count is
//! shown live and pre-fills the editor when the set ends; the athlete confirms
//! or corrects it in the same press they were already making. A counter that is
//! right eight times in ten is worse than no counter if it writes silently,
//! because then every set has to be checked — and checking costs more than
//! counting did.
//!
//! The algorithm, in order:
//!
//!   1. Magnitude of the acceleration vector, in milli-g. Direction is thrown
//!      away deliberately: it makes the count independent of which wrist the
//!      watch is on and which way it is facing.
//!   2. A fast smoothing pass, to drop sensor noise.
//!   3. A slow baseline, which is gravity plus whatever posture the arm is in.
//!      Subtracting it leaves only the movement.
//!   4. A peak count with hysteresis: the signal has to rise past a threshold
//!      and come back below its negative to score one. A single threshold
//!      counts every wobble twice.
//!   5. A refractory period. No human performs a repetition in under half a
//!      second, so anything faster is the same rep bouncing.
//!
//! The threshold adapts to the recent range of movement, with a floor: a
//! stationary wrist must never accumulate reps, which is the failure that would
//! actually lose the athlete's trust.
//!
//! Pure — Toybox.Lang and Math only, samples arrive as arguments — so the whole
//! thing is tested against synthetic waveforms rather than by waving a watch.
class RepCounter {

    //! Samples per second requested from the sensor.
    public static const SAMPLE_RATE = 25;
    //! Half a second. Faster than this is one rep counted twice.
    public static const MIN_PERIOD_SAMPLES = 13;
    //! Below this much movement, in milli-g, nothing counts at all.
    public static const NOISE_FLOOR = 90;
    //! Fraction of the recent swing a peak must reach.
    public static const THRESHOLD_PERCENT = 35;

    private var _fast as Float;        //! smoothed magnitude
    private var _slow as Float;        //! baseline: gravity plus posture
    private var _range as Float;       //! recent peak-to-peak swing
    private var _primed as Boolean;    //! true once the signal has gone high
    private var _sinceRep as Number;
    private var _count as Number;
    private var _seen as Number;

    public function initialize() {
        // Assigned here as well as in reset(): the type checker does not follow
        // a constructor into a helper, and these members do not accept null.
        _fast = 0.0;
        _slow = 0.0;
        _range = 0.0;
        _primed = false;
        _sinceRep = MIN_PERIOD_SAMPLES;
        _count = 0;
        _seen = 0;
    }

    public function reset() as Void {
        _fast = 0.0;
        _slow = 0.0;
        _range = 0.0;
        _primed = false;
        _sinceRep = MIN_PERIOD_SAMPLES;
        _count = 0;
        _seen = 0;
    }

    public function count() as Number {
        return _count;
    }

    //! How many samples have been seen. Used to tell "no movement" from
    //! "no sensor" — a counter that was never fed must not read as zero reps.
    public function samplesSeen() as Number {
        return _seen;
    }

    //! Feed one batch of axes, in milli-g, as the sensor delivers them.
    //! Returns the number of repetitions newly counted.
    public function feed(
        xs as Array<Number>?,
        ys as Array<Number>?,
        zs as Array<Number>?
    ) as Number {
        if (xs == null || ys == null || zs == null) {
            return 0;
        }
        var n = xs.size();
        if (ys.size() < n) { n = ys.size(); }
        if (zs.size() < n) { n = zs.size(); }

        var before = _count;
        for (var i = 0; i < n; i++) {
            _step(xs[i], ys[i], zs[i]);
        }
        return _count - before;
    }

    function _step(x as Number, y as Number, z as Number) as Void {
        _seen++;
        var magnitude = Math.sqrt(
            (x.toFloat() * x.toFloat()) +
            (y.toFloat() * y.toFloat()) +
            (z.toFloat() * z.toFloat())
        ).toFloat();

        if (_seen == 1) {
            _fast = magnitude;
            _slow = magnitude;
            return;
        }

        // Fast pass removes sensor noise; the slow one is gravity and posture.
        _fast = _fast + (magnitude - _fast) * 0.35;
        _slow = _slow + (_fast - _slow) * 0.02;

        var signal = _fast - _slow;
        var swing = signal < 0.0 ? -signal : signal;
        // The range decays, so a set that gets slower does not keep being judged
        // against how explosive its first rep was.
        _range = _range * 0.98;
        if (swing > _range) {
            _range = swing;
        }

        var threshold = (_range * THRESHOLD_PERCENT) / 100.0;
        if (threshold < NOISE_FLOOR) {
            threshold = NOISE_FLOOR.toFloat();
        }

        if (_sinceRep < MIN_PERIOD_SAMPLES) {
            _sinceRep++;
        }

        if (!_primed) {
            if (signal > threshold) {
                _primed = true;
            }
            return;
        }
        // Primed: the arm went up. One rep when it comes back down past the
        // mirror of the threshold, and not before the refractory period.
        if (signal < -threshold) {
            _primed = false;
            if (_sinceRep >= MIN_PERIOD_SAMPLES) {
                _count++;
                _sinceRep = 0;
            }
        }
    }
}
