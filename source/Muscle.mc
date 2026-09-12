import Toybox.Lang;
import Toybox.WatchUi;

//! Muscle groups, for grouping the catalogue and for weekly volume.
//!
//! The numeric values are persisted with every exercise, so they must never be
//! reordered. `MUSCLE_OTHER` is what an exercise saved before this existed
//! migrates to — see SessionSnapshot's v1 to v2 migration.
//!
//! Ten groups, not four. "Arms" would be convenient for a menu and useless for
//! the thing this exists to answer: whether the week's pushing and pulling are
//! anywhere near each other.
module Muscle {

    const OTHER = 0;
    const CHEST = 1;
    const BACK = 2;
    const SHOULDERS = 3;
    const BICEPS = 4;
    const TRICEPS = 5;
    const QUADS = 6;
    const HAMSTRINGS = 7;
    const GLUTES = 8;
    const CALVES = 9;
    const CORE = 10;

    const COUNT = 11;

    //! Every group the catalogue is browsed by, in the order it is shown:
    //! the big pushing and pulling groups first, because that is where most
    //! sessions start.
    public function browseOrder() as Array<Number> {
        return [CHEST, BACK, SHOULDERS, BICEPS, TRICEPS,
                QUADS, HAMSTRINGS, GLUTES, CALVES, CORE] as Array<Number>;
    }

    public function name(group as Number) as String {
        switch (group) {
            case CHEST:      return WatchUi.loadResource(Rez.Strings.MuscleChest) as String;
            case BACK:       return WatchUi.loadResource(Rez.Strings.MuscleBack) as String;
            case SHOULDERS:  return WatchUi.loadResource(Rez.Strings.MuscleShoulders) as String;
            case BICEPS:     return WatchUi.loadResource(Rez.Strings.MuscleBiceps) as String;
            case TRICEPS:    return WatchUi.loadResource(Rez.Strings.MuscleTriceps) as String;
            case QUADS:      return WatchUi.loadResource(Rez.Strings.MuscleQuads) as String;
            case HAMSTRINGS: return WatchUi.loadResource(Rez.Strings.MuscleHamstrings) as String;
            case GLUTES:     return WatchUi.loadResource(Rez.Strings.MuscleGlutes) as String;
            case CALVES:     return WatchUi.loadResource(Rez.Strings.MuscleCalves) as String;
            case CORE:       return WatchUi.loadResource(Rez.Strings.MuscleCore) as String;
            default:         return WatchUi.loadResource(Rez.Strings.MuscleOther) as String;
        }
    }

    //! A colour per group, so the weekly volume chart reads without a legend.
    //! Pulled from the palette the rest of the app already uses.
    public function color(group as Number) as Number {
        switch (group) {
            case CHEST:      return Theme.COLOR_HR;
            case BACK:       return Theme.COLOR_ACCENT;
            case SHOULDERS:  return Theme.COLOR_WARM;
            case BICEPS:     return 0x55AAAA;
            case TRICEPS:    return 0xAA55FF;
            case QUADS:      return Theme.COLOR_DONE;
            case HAMSTRINGS: return Theme.COLOR_DONE_DIM;
            case GLUTES:     return 0xFF55AA;
            case CALVES:     return 0xAAAA00;
            case CORE:       return Theme.COLOR_DIM;
            default:         return Theme.COLOR_SKIPPED;
        }
    }

    public function isValid(group as Number) as Boolean {
        return group >= 0 && group < COUNT;
    }
}
