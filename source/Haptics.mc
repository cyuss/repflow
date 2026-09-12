import Toybox.Lang;
import Toybox.Attention;
import Toybox.System;

//! What the watch says when you are not looking at it.
//!
//! Three events matter during a workout and they must not feel the same:
//!
//!   set logged    one short tap          "got it, carry on"
//!   rest over     two firm pulses        "back under the bar"
//!   record        three rising pulses    "look at this one"
//!
//! A single buzz for all three teaches the athlete to look at the screen every
//! time, which is exactly what a wrist device is supposed to avoid.
//!
//! `Attention.vibrate` takes up to eight VibeProfiles and runs them in sequence;
//! a zero-strength profile is how you write a gap. Devices without a vibration
//! motor throw, and Forerunners flatten every pattern to one strength — both are
//! handled by doing nothing rather than by pretending.
module Haptics {

    public function setLogged() as Void {
        _play([new Attention.VibeProfile(45, 90)] as Array<Attention.VibeProfile>);
    }

    public function restOver() as Void {
        _play([
            new Attention.VibeProfile(75, 220),
            new Attention.VibeProfile(0, 120),
            new Attention.VibeProfile(75, 220)
        ] as Array<Attention.VibeProfile>);
    }

    //! Ten seconds of rest left: quiet enough to ignore if you are mid-chalk.
    public function restWarning() as Void {
        _play([
            new Attention.VibeProfile(35, 70),
            new Attention.VibeProfile(0, 80),
            new Attention.VibeProfile(35, 70)
        ] as Array<Attention.VibeProfile>);
    }

    //! A record. Rising, and the only pattern with three beats.
    public function record() as Void {
        _play([
            new Attention.VibeProfile(35, 90),
            new Attention.VibeProfile(0, 70),
            new Attention.VibeProfile(65, 90),
            new Attention.VibeProfile(0, 70),
            new Attention.VibeProfile(100, 180)
        ] as Array<Attention.VibeProfile>);
    }

    //! Something was refused — the end of a list, a value at its limit.
    public function refused() as Void {
        _play([new Attention.VibeProfile(25, 40)] as Array<Attention.VibeProfile>);
    }

    function _play(profiles as Array<Attention.VibeProfile>) as Void {
        if (!Settings.haptics()) {
            return;
        }
        // The watch's own "vibration off" always wins over ours.
        try {
            var settings = System.getDeviceSettings();
            if (settings has :vibrateOn && !settings.vibrateOn) {
                return;
            }
        } catch (e) {
            return;
        }
        try {
            if (Attention has :vibrate) {
                Attention.vibrate(profiles);
            }
        } catch (e) {
            // No motor, or the device refuses patterns. Silence is correct.
        }
    }
}
