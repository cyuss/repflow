import Toybox.Lang;
import Toybox.System;

//! What the screen is doing, so the app spends nothing on what nobody sees.
//!
//! On the AMOLED watches (Fenix 8 and 9, Epix, Venu…) the display is not
//! always lit. During a workout it drops to low power — the dimmed always-on
//! face — or switches off entirely, depending on the athlete's settings, and
//! it can stay that way for most of a session: the wrist is down, under a
//! bar, between sets.
//!
//! Every repaint is the processor waking, drawing the whole screen and pushing
//! it to the panel. At one a second for an hour that is 3,600 frames, and with
//! the display off every one of them is thrown away. So:
//!
//!   * **off**: no repaint at all, no scrolling, no animation. The tick still
//!     runs — the rest countdown has to reach zero and buzz, and the heart
//!     rate zones are still sampled — it just stops drawing.
//!   * **low power**: a repaint every few seconds rather than every second,
//!     and nothing that moves. The countdown's last seconds still go one by
//!     one, because that is when the wrist comes up to look.
//!   * **high power**: everything, as before.
//!
//! The watch says when this changes (`AppBase.onDisplayModeChanged`), and the
//! app repaints at once when the screen comes back: the first frame the athlete
//! sees is current, never the stale one from when it went dark.
//!
//! On a watch whose firmware cannot say — a memory-in-pixel Fenix 6 or 7,
//! whose screen is always on and costs next to nothing to redraw — everything
//! reads as high power, and nothing changes.
module Power {

    //! In low power, one repaint every this many ticks.
    const LOW_POWER_EVERY = 5;
    //! …except in the last seconds of a rest, which count one by one.
    const LOW_POWER_COUNTDOWN = 10;

    //! The display is off: nothing drawn now will be seen.
    public function screenOff() as Boolean {
        if (System has :getDisplayMode) {
            return System.getDisplayMode() == System.DISPLAY_MODE_OFF;
        }
        return false;
    }

    //! The display is dimmed or off: draw the essentials, and nothing that
    //! moves.
    public function dimmed() as Boolean {
        if (System has :getDisplayMode) {
            return System.getDisplayMode() != System.DISPLAY_MODE_HIGH_POWER;
        }
        return false;
    }

    //! Whether this tick should repaint a live screen.
    //!
    //! `tick` counts seconds; `restLeft` is the rest countdown's remaining
    //! seconds, or a negative number when no rest is running.
    public function repaintOnTick(tick as Number, restLeft as Number) as Boolean {
        if (!(System has :getDisplayMode)) {
            return true;
        }
        var mode = System.getDisplayMode();
        if (mode == System.DISPLAY_MODE_HIGH_POWER) {
            return true;
        }
        if (mode == System.DISPLAY_MODE_OFF) {
            return false;
        }
        return lowPowerRepaint(tick, restLeft);
    }

    //! The low-power rule on its own, so a test can walk it without a display.
    public function lowPowerRepaint(tick as Number, restLeft as Number) as Boolean {
        if (restLeft >= 0 && restLeft <= LOW_POWER_COUNTDOWN) {
            return true;
        }
        return tick % LOW_POWER_EVERY == 0;
    }
}
