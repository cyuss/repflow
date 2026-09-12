import Toybox.Lang;

//! How fast the heart rate comes down between sets.
//!
//! The beats dropped in the first minute of rest is one of the few genuinely
//! informative numbers a strength session produces, and nothing else in this
//! category shows it. It costs nothing extra to collect: the same 1 Hz tick
//! that fills the zone chart feeds this.
//!
//! What it measures, precisely: the peak heart rate seen since this rest began,
//! minus the current one. The peak keeps rising for the first seconds of rest —
//! heart rate lags effort — so taking it from the moment the set ended would
//! under-report every time.
//!
//! `best()` is the largest drop reached **within** the first minute of any rest
//! this session, which is the figure that is comparable week to week. A drop
//! measured over three minutes of standing around says nothing about fitness.
//!
//! Pure: Toybox.Lang only, heart rate arrives as an argument. Fully tested.
class RecoveryTracker {

    //! The window a recovery figure means anything over.
    public static const WINDOW_SECONDS = 60;

    private var _resting as Boolean;
    private var _peak as Number?;
    private var _current as Number?;
    private var _elapsed as Number;
    private var _best as Number?;

    public function initialize() {
        _resting = false;
        _peak = null;
        _current = null;
        _elapsed = 0;
        _best = null;
    }

    //! A rest period began. Everything restarts; the session best does not.
    public function startRest() as Void {
        _resting = true;
        _peak = null;
        _current = null;
        _elapsed = 0;
    }

    public function endRest() as Void {
        _resting = false;
    }

    //! One second passed, with this heart rate — or none.
    public function sample(hr as Number?) as Void {
        if (!_resting) {
            return;
        }
        _elapsed++;
        if (hr == null || hr <= 0) {
            return;
        }
        _current = hr;
        var peak = _peak;
        if (peak == null || hr > peak) {
            _peak = hr;
            return;         // a new peak is not a drop
        }
        var drop = (peak as Number) - hr;
        if (_elapsed <= WINDOW_SECONDS) {
            var best = _best;
            if (best == null || drop > best) {
                _best = drop;
            }
        }
    }

    //! Beats below this rest's peak, right now. Null until there is one.
    public function drop() as Number? {
        var peak = _peak;
        var current = _current;
        if (!_resting || peak == null || current == null) {
            return null;
        }
        var d = (peak as Number) - (current as Number);
        return d > 0 ? d : 0;
    }

    //! The best one-minute recovery this session, or null.
    public function best() as Number? {
        return _best;
    }

    public function isResting() as Boolean {
        return _resting;
    }
}
