import Toybox.Lang;
import Toybox.Application;
import Toybox.System;

//! The athlete's preferences, edited in Garmin Connect on the phone.
//!
//! Configuring an app on a 260 px screen is punishment, and Garmin already
//! gives every Connect IQ app a settings pane in its phone app for free. The
//! declarations live in `resources/properties.xml`; this module is the only
//! thing that reads them.
//!
//! Three rules, all of them about not breaking a workout:
//!
//!   * **Every value has a working default.** The app must behave correctly for
//!     someone who never opens the pane.
//!   * **Every read is validated.** A property comes back as whatever the phone
//!     last wrote, which may be null, the wrong type, or nonsense. Monkey C
//!     runtime errors cannot be caught, so a bad value is replaced, never used.
//!   * **Everything is cached.** These are read from drawing code at 1 Hz;
//!     `Properties.getValue` is not free, and the answers only change when
//!     `onSettingsChanged` fires.
module Settings {

    var _rest as Number? = null;
    var _step as Number? = null;
    var _units as Number? = null;
    var _haptics as Boolean? = null;
    var _repCounter as Boolean? = null;
    var _animations as Number? = null;
    var _theme as Number? = null;

    //! Re-read on the next call. Called from RepFlowApp.onSettingsChanged.
    public function invalidate() as Void {
        _rest = null;
        _step = null;
        _units = null;
        _haptics = null;
        _repCounter = null;
        _animations = null;
        _theme = null;
        Units.invalidate();
        Device.invalidate();
    }

    //! A property as a Number, clamped, with a default for every way it can be
    //! absent or wrong.
    public function readNumber(key as String, fallback as Number, low as Number, high as Number) as Number {
        var value = null;
        try {
            value = Application.Properties.getValue(key);
        } catch (e) {
            return fallback;
        }
        if (!(value instanceof Number)) {
            return fallback;
        }
        var n = value as Number;
        if (n < low) { return low; }
        if (n > high) { return high; }
        return n;
    }

    public function readBoolean(key as String, fallback as Boolean) as Boolean {
        var value = null;
        try {
            value = Application.Properties.getValue(key);
        } catch (e) {
            return fallback;
        }
        if (!(value instanceof Boolean)) {
            return fallback;
        }
        return value as Boolean;
    }

    //! Default rest between sets, in seconds. An exercise's own rest wins.
    public function restDefault() as Number {
        var v = _rest;
        if (v == null) {
            v = readNumber("restDefault", 90, 10, 900);
            _rest = v;
        }
        return v;
    }

    //! How much one press of UP or DOWN moves the load, in tenths of the
    //! displayed unit.
    public function weightStepTenths() as Number {
        var v = _step;
        if (v == null) {
            v = readNumber("weightStepTenths", 10, 1, 250);
            _step = v;
        }
        return v;
    }

    //! Tuning.UNITS_AUTO / UNITS_METRIC / UNITS_STATUTE.
    public function units() as Number {
        var v = _units;
        if (v == null) {
            v = readNumber("units", Tuning.UNITS_AUTO, Tuning.UNITS_AUTO, Tuning.UNITS_STATUTE);
            _units = v;
        }
        return v;
    }

    public function haptics() as Boolean {
        var v = _haptics;
        if (v == null) {
            v = readBoolean("haptics", true);
            _haptics = v;
        }
        return v;
    }

    //! Counting reps means running the accelerometer at 25 Hz, which costs
    //! battery, so it is off until the athlete asks for it.
    public function repCounter() as Boolean {
        var v = _repCounter;
        if (v == null) {
            v = readBoolean("repCounter", false);
            _repCounter = v;
        }
        return v;
    }

    //! Tuning.THEME_DARK / THEME_LIGHT.
    //!
    //! Dark is the default: a MIP screen in a dim gym reads best that way and
    //! an AMOLED spends almost nothing lighting it. Light exists because a
    //! watch in bright sun is a different problem entirely.
    public function theme() as Number {
        var v = _theme;
        if (v == null) {
            v = readNumber("theme", Tuning.THEME_DARK, Tuning.THEME_DARK, Tuning.THEME_LIGHT);
            _theme = v;
        }
        return v;
    }

    //! Change the theme from the watch, and make it stick.
    public function setTheme(value as Number) as Void {
        writeNumber("theme", value);
        _theme = value;
    }

    //! Write a property back, for the on-watch settings screen.
    //!
    //! The phone writes these too, so both routes share one source of truth and
    //! neither has its own copy to drift.
    public function writeNumber(key as String, value as Number) as Void {
        try {
            Application.Properties.setValue(key, value);
        } catch (e) {
            // A setting that will not persist is a setting that reverts on the
            // next launch; nothing else breaks.
        }
    }

    public function writeBoolean(key as String, value as Boolean) as Void {
        try {
            Application.Properties.setValue(key, value);
        } catch (e) {
            // as above
        }
    }

    //! Tuning.ANIM_AUTO / ANIM_OFF / ANIM_ON.
    public function animations() as Number {
        var v = _animations;
        if (v == null) {
            v = readNumber("animations", Tuning.ANIM_AUTO, Tuning.ANIM_AUTO, Tuning.ANIM_ON);
            _animations = v;
        }
        return v;
    }
}
