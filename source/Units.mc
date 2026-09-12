import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Math;

//! Kilograms or pounds, decided once and applied everywhere.
//!
//! **Loads are stored in kilograms, always.** FIT records kilograms, history
//! compares kilograms, and the engine never sees a pound. Only the screen and
//! the editor convert — which means switching units mid-history changes nothing
//! about what was recorded, and a workout logged in London reads correctly in
//! Boston.
//!
//! The watch's own setting is the default, because an athlete who has already
//! told their Fenix they think in pounds should not have to tell RepFlow too.
module Units {

    const LB_PER_KG = 2.2046226;

    //! True when loads should be shown in pounds.
    public function imperial() as Boolean {
        var choice = Settings.units();
        if (choice == Tuning.UNITS_METRIC) {
            return false;
        }
        if (choice == Tuning.UNITS_STATUTE) {
            return true;
        }
        // `has` rather than try/catch: a device that does not report a weight
        // unit raises a Monkey C runtime error on the read, and those are not
        // Exceptions. See docs/API_LIMITATIONS.md.
        var settings = System.getDeviceSettings();
        if (!(settings has :weightUnits)) {
            return false;
        }
        return settings.weightUnits == System.UNIT_STATUTE;
    }

    //! A stored load, in whatever the athlete reads.
    public function fromKg(kg as Float) as Float {
        return imperial() ? kg * LB_PER_KG : kg;
    }

    //! A displayed load, back to what gets stored.
    public function toKg(value as Float) as Float {
        return imperial() ? value / LB_PER_KG : value;
    }

    //! "kg" or "lb", in the athlete's language.
    public function label() as String {
        return imperial()
            ? WatchUi.loadResource(Rez.Strings.Lb) as String
            : WatchUi.loadResource(Rez.Strings.Kg) as String;
    }

    //! One press of UP or DOWN, in the displayed unit.
    public function step() as Float {
        return Settings.weightStepTenths().toFloat() / 10.0;
    }

    //! Snap a load to the step grid of whatever unit is being read.
    //!
    //! A template default of 55 kg is 121.3 lb, and a plan that opens on 121.3
    //! looks like a measurement rather than a suggestion. Snapping makes it 121.
    //!
    //! Only ever applied to a **planned** load. A load that was actually lifted
    //! is reported exactly as it was recorded, in kilograms, whatever unit the
    //! screen happens to be in.
    public function snap(kg as Float) as Float {
        var s = step();
        if (s <= 0.0) {
            return kg;
        }
        var shown = fromKg(kg);
        var snapped = Math.round(shown / s) * s;
        if (snapped < 0.0) {
            snapped = 0.0;
        }
        return toKg(snapped.toFloat());
    }

    //! The same step expressed in kilograms, since that is what gets added to
    //! the stored load. Converting the step rather than the total keeps the
    //! displayed number landing on round values as the athlete holds the button.
    public function stepKg() as Float {
        return toKg(step());
    }
}
