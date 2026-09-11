import Toybox.Lang;

//! Pure countdown state for the rest period between sets.
//!
//! Deliberately free of Toybox.Timer so it can be unit-tested by calling
//! `tick()` directly. AppController owns the real 1 Hz Timer that drives it.
class RestTimer {

    private var _durationSec as Number;
    private var _remainingSec as Number;
    private var _running as Boolean;

    public function initialize() {
        _durationSec = 0;
        _remainingSec = 0;
        _running = false;
    }

    public function start(durationSec as Number) as Void {
        _durationSec = durationSec > 0 ? durationSec : 0;
        _remainingSec = _durationSec;
        _running = _remainingSec > 0;
    }

    //! Advance one second. Returns true on the tick that reaches zero, so the
    //! caller can fire the haptic exactly once.
    public function tick() as Boolean {
        if (!_running) {
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

    //! Cut the rest short ("skip rest").
    public function skip() as Void {
        _remainingSec = 0;
        _running = false;
    }

    //! Give back some rest — used when the athlete adds time.
    public function extend(seconds as Number) as Void {
        _remainingSec += seconds;
        if (_remainingSec < 0) {
            _remainingSec = 0;
        }
        _running = _remainingSec > 0;
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
    public function progress() as Float {
        if (_durationSec <= 0) {
            return 1.0;
        }
        var done = _durationSec - _remainingSec;
        return done.toFloat() / _durationSec.toFloat();
    }

    //! "01:30"
    public function format() as String {
        var m = _remainingSec / 60;
        var s = _remainingSec % 60;
        return m.format("%02d") + ":" + s.format("%02d");
    }
}
