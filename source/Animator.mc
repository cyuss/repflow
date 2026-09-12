import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;
import Toybox.System;

//! One short, eased entrance, on the watches that can afford it.
//!
//! **What this deliberately is not.** There is no motion during a set. A screen
//! that animates while the athlete is under a bar is a screen that stutters at
//! the moment it matters. So this runs at exactly two moments — arriving at an
//! exercise, and opening the recap — and is silent on everything below
//! `Device.TIER_RICH`.
//!
//! A view asks for `value()` and multiplies whatever it is drawing by it: a
//! ring sweeps out, bars grow from the left. On a lean device `value()` is
//! always 1.0, so the same drawing code produces the finished frame with no
//! branch of its own.
//!
//! Ease-out cubic, because a thing that arrives fast and settles reads as
//! responsive, while a linear one reads as slow.
module Animator {

    //! 20 fps. Connect IQ clamps a Timer to a 50 ms minimum and says so in the
    //! log, so asking for 33 was asking for 50 while looking like a mistake.
    const FRAME_MS = 50;

    //! A module cannot hand `method(:onFrame)` to a Timer — there is no self to
    //! bind it to — so one object exists purely to own that callback.
    var _frames as AnimatorFrames = new AnimatorFrames();
    var _timer as Timer.Timer? = null;
    var _startedAt as Number = 0;
    var _durationMs as Number = 0;
    var _running as Boolean = false;

    //! Begin an entrance. Harmless — and free — on a device that should not.
    public function start(durationMs as Number) as Void {
        if (!Device.animates() || durationMs <= 0) {
            _running = false;
            return;
        }
        var timer = _timer;
        if (timer == null) {
            timer = new Timer.Timer();
            _timer = timer;
        }
        _startedAt = System.getTimer();
        _durationMs = durationMs;
        _running = true;
        timer.start(_frames.method(:onFrame), FRAME_MS, true);
    }

    public function stop() as Void {
        _running = false;
        var timer = _timer;
        if (timer != null) {
            timer.stop();
        }
    }

    public function isRunning() as Boolean {
        return _running;
    }

    //! 0.0 to 1.0, eased. Always 1.0 when nothing is animating, so a view can
    //! multiply by it unconditionally.
    public function value() as Float {
        if (!_running) {
            return 1.0;
        }
        var elapsed = System.getTimer() - _startedAt;
        if (elapsed >= _durationMs) {
            return 1.0;
        }
        if (elapsed < 0) {
            return 1.0;     // the millisecond counter wrapped; show the result
        }
        var t = elapsed.toFloat() / _durationMs.toFloat();
        // Ease-out cubic: 1 - (1 - t)^3
        var inv = 1.0 - t;
        return 1.0 - inv * inv * inv;
    }

    public function onFrame() as Void {
        if (!_running) {
            stop();
            return;
        }
        if ((System.getTimer() - _startedAt) >= _durationMs) {
            stop();
        }
        WatchUi.requestUpdate();
    }

}

//! The Timer callback for the Animator module. See the note on `_frames`.
class AnimatorFrames {
    public function initialize() {
    }

    public function onFrame() as Void {
        Animator.onFrame();
    }
}
