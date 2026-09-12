import Toybox.Lang;
import Toybox.Math;

//! Interaction constants shared by the controller and the views.
//!
//! These live in a module rather than on AppController because Monkey C does
//! not expose class-level `const` through the class name.
module Tuning {

    //! Weight adjustment step, in kg. 2.5 is one small plate per side.
    const WEIGHT_STEP = 2.5;

    //! Seconds added or removed by UP/DOWN on the rest screen.
    const REST_STEP = 15;

    // ------------------------------------------------------------------
    // Exercise data screens, paged with UP/DOWN like a native Garmin activity.
    // ------------------------------------------------------------------

    //! The set: exercise, load, reps, and the COMPLETE SET action.
    const PAGE_SET = 0;
    //! Live Garmin metrics: heart rate, elapsed time, calories.
    const PAGE_BODY = 1;
    //! Session totals: volume, exercises, sets, reps.
    const PAGE_WORKOUT = 2;
    const PAGE_COUNT = 3;

    // ------------------------------------------------------------------
    // Set editor focus
    // ------------------------------------------------------------------

    const FOCUS_WEIGHT = 0;
    const FOCUS_REPS = 1;

    //! Where the set editor should go when it closes. RepFlow keeps a flat view
    //! stack, so a screen names its destination rather than relying on what
    //! happens to be underneath it.
    const RETURN_EXERCISE = 0;
    const RETURN_REST = 1;

    //! Weights travel through the editor as tenths of a kilogram, because a
    //! PickerFactory deals in Numbers and 2.5 kg steps are not integers.
    public function toTenths(kg as Float) as Number {
        return Math.round(kg * 10.0).toNumber();
    }
}
