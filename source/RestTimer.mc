import Toybox.Lang;

//! Pure state for the rest period between sets, in either of its two shapes.
//!
//!   **Timed** counts down from a duration and reaches zero once.
//!   **Open** counts up from nothing and ends when the athlete ends it.
//!
//! Open rest is not a countdown of zero length. It has no target, so it never
//! "reaches zero", never buzzes, and cannot be extended — there is nothing to
//! extend. Everything that asks this class a question has to be able to get the
//! answer "there is no target", which is why `remaining()` and `duration()` are
//! zero in open mode rather than some stand-in number.
//!
//! Deliberately free of Toybox.Timer so it can be unit-tested by calling
//! `tick()` directly. AppController owns the real 1 Hz Timer that drives it.
class RestTimer {

    private var _durationSec as Number;
    private var _remainingSec as Number;
    private var _elapsedSec as Number;
    private var _running as Boolean;
    private var _open as Boolean;

    public function initialize() {
        _durationSec = 0;
        _remainingSec = 0;
        _elapsedSec = 0;
        _running = false;
        _open = false;
    }

    public function start(durationSec as Number) as Void {
        _durationSec = durationSec > 0 ? durationSec : 0;
        _remainingSec = _durationSec;
        _elapsedSec = 0;
        _open = false;
        _running = _remainingSec > 0;
    }

    //! Rest with no target: the clock runs until the athlete stops it.
    public function startOpen() as Void {
        _durationSec = 0;
        _remainingSec = 0;
        _elapsedSec = 0;
        _open = true;
        _running = true;
    }

    //! Advance one second. Returns true on the tick that reaches zero, so the
    //! caller can fire the haptic exactly once.
    //!
    //! Open rest never returns true. There is no moment to announce, and a buzz
    //! is a claim that the rest is over — which in this mode only the athlete
    //! gets to make.
    public function tick() as Boolean {
        if (!_running) {
            return false;
        }
        if (_open) {
            _elapsedSec++;
            return false;
        }
        _remainingSec--;
        if (_remainingSec <= 0) {
            _remainingSec = 0;
            _running = false;
            return true;
        }
        return false;
    }

    //! Cut the rest short ("skip rest"), or end an open one.
    public function skip() as Void {
        _remainingSec = 0;
        _running = false;
    }

    //! Give back some rest — used when the athlete adds time.
    //!
    //! Does nothing to an open rest: there is no target to move, and silently
    //! converting one into a countdown would take away the mode the athlete
    //! chose.
    public function extend(seconds as Number) as Void {
        if (_open) {
            return;
        }
        _remainingSec += seconds;
        if (_remainingSec < 0) {
            _remainingSec = 0;
        }
        _running = _remainingSec > 0;
    }

    //! True when this rest has no target and is counting up.
    public function isOpen() as Boolean {
        return _open;
    }

    //! Seconds rested so far. Counts up in both modes.
    public function elapsed() as Number {
        return _open ? _elapsedSec : _durationSec - _remainingSec;
    }

    public function isRunning() as Boolean {
        return _running;
    }

    public function remaining() as Number {
        return _remainingSec;
    }

    public function duration() as Number {
        return _durationSec;
    }

    //! Elapsed rest, for a progress arc. 0.0 .. 1.0
    //!
    //! Meaningless for an open rest — there is no proportion of nothing — so it
    //! answers 0.0 and the rest screen draws no arc at all. See RestView.
    public function progress() as Float {
        if (_open) {
            return 0.0;
        }
        if (_durationSec <= 0) {
            return 1.0;
        }
        var done = _durationSec - _remainingSec;
        return done.toFloat() / _durationSec.toFloat();
    }

    //! "01:30" — what is left, or in open mode what has passed.
    public function format() as String {
        var total = _open ? _elapsedSec : _remainingSec;
        var m = total / 60;
        var s = total % 60;
        return m.format("%02d") + ":" + s.format("%02d");
    }
}
