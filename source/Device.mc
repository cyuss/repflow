import Toybox.Lang;
import Toybox.System;

//! What this particular watch can afford.
//!
//! RepFlow runs on 33 products, from a 260x260 Fenix 6 Pro with 128 KB of app
//! memory to a 454x454 Fenix 9 Pro with several times that. Drawing the same
//! thing on both wastes the newer watch and strangles the older one.
//!
//! Two questions get asked, and they are different:
//!
//!   * **Can it afford motion?** Memory, because an animation holds frames and
//!     a timer while the rest of the app still has to fit. A workout must never
//!     stutter to make a transition look nice, so on the tight devices there is
//!     simply no motion at all.
//!   * **Can it afford detail?** Pixels, because a two-pixel hairline is a
//!     quarter of a stroke on a 454 px screen and a fifth of a letter on a 260.
//!
//! Everything here is read once and cached. `System.getSystemStats()` is not
//! free, and these answers cannot change while the app is running.
module Device {

    //! A watch that should stay still and keep its frames.
    const TIER_LEAN = 0;
    //! A watch with memory to spare for motion.
    const TIER_RICH = 1;

    //! 192 KB. Below this the app is competing with itself for memory and an
    //! animation is the first thing that should lose.
    const RICH_MEMORY = 196608;

    //! Screens at or above this get the heavier strokes and the extra detail.
    const HIGH_RES = 360;

    var _tier as Number? = null;
    var _size as Number? = null;
    var _fontScale as Float? = null;

    public function tier() as Number {
        var t = _tier;
        if (t != null) {
            return t;
        }
        var resolved = TIER_LEAN;
        var stats = System.getSystemStats();
        // `has` rather than try/catch: a missing symbol raises a Monkey C
        // runtime error, which is NOT an Exception and is NOT caught. Older
        // devices genuinely do not report every stat.
        if (stats has :totalMemory) {
            var total = stats.totalMemory;
            if (total != null && total >= RICH_MEMORY) {
                resolved = TIER_RICH;
            }
        }
        _tier = resolved;
        return resolved;
    }

    //! Shorter screen dimension, in pixels.
    public function screenSize() as Number {
        var s = _size;
        if (s != null) {
            return s;
        }
        var settings = System.getDeviceSettings();
        var resolved = settings.screenHeight < settings.screenWidth
            ? settings.screenHeight
            : settings.screenWidth;
        _size = resolved;
        return resolved;
    }

    public function isHighRes() as Boolean {
        return screenSize() >= HIGH_RES;
    }

    //! Whether this run may animate.
    //!
    //! The setting wins when the athlete has expressed a preference; otherwise
    //! it comes down to memory. Checked through `Settings`, which caches, so
    //! this is cheap enough to call from a view.
    public function animates() as Boolean {
        var choice = Settings.animations();
        if (choice == Tuning.ANIM_OFF) {
            return false;
        }
        if (choice == Tuning.ANIM_ON) {
            return true;
        }
        return tier() == TIER_RICH;
    }

    //! The athlete's text-size preference, as a multiplier around 1.0.
    //!
    //! Garmin lets the wearer scale system text. RepFlow picks its own fonts to
    //! fit measured space, so it cannot simply obey — but it can stop choosing
    //! the largest font that fits when the wearer has asked for larger text,
    //! which is what `Theme` uses this for.
    public function fontScale() as Float {
        var f = _fontScale;
        if (f != null) {
            return f;
        }
        var resolved = 1.0;
        var settings = System.getDeviceSettings();
        // The Fenix 6 Pro has no fontScale at all, and reading it there is a
        // "Symbol Not Found" runtime error — uncatchable, and fatal on the
        // first screen drawn. Found by the layout tests, not by the compiler.
        if (settings has :fontScale) {
            var scale = settings.fontScale;
            if (scale != null && scale > 0.1 && scale < 4.0) {
                resolved = scale;
            }
        }
        _fontScale = resolved;
        return resolved;
    }

    //! A stroke width that looks the same weight on every screen.
    public function stroke(fraction as Number) as Number {
        var w = (screenSize() * fraction) / 1000;
        return w < 1 ? 1 : w;
    }

    //! Forget the cached answers. Only the settings can actually change while
    //! the app runs; the rest is re-read for free.
    public function invalidate() as Void {
        _tier = null;
        _size = null;
        _fontScale = null;
    }
}
