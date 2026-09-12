import Toybox.Lang;
import Toybox.Math;

//! Interaction constants shared by the controller and the views.
//!
//! These live in a module rather than on AppController because Monkey C does
//! not expose class-level `const` through the class name.
module Tuning {

    //! Seconds added or removed by UP/DOWN on the rest screen.
    const REST_STEP = 15;

    //! How much faster the load moves when the athlete is clearly holding the
    //! button down rather than tapping it. Going 60 to 100 kg one kilo at a
    //! time is forty presses; this turns it into eight.
    const COARSE_MULTIPLIER = 5;
    //! Two adjustments closer together than this are a hold, not two taps.
    const COARSE_WINDOW_MS = 350;

    // ------------------------------------------------------------------
    // Settings vocabulary. The numeric values are written by the phone app and
    // stored, so they must never be reordered.
    // ------------------------------------------------------------------

    const UNITS_AUTO = 0;
    const UNITS_METRIC = 1;
    const UNITS_STATUTE = 2;

    const THEME_DARK = 0;
    const THEME_LIGHT = 1;

    const ANIM_AUTO = 0;
    const ANIM_OFF = 1;
    const ANIM_ON = 2;

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

    //! The rest screen uses the same three pages, in the same order, reached
    //! with the same buttons. Page 0 is the countdown instead of the set; the
    //! other two are identical. One paging model, whether you are working or
    //! waiting — see MetricPages.
    const REST_PAGE_COUNT = 3;

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

    //! What the set editor is for.
    //!
    //! EDIT_NEXT dials in the set you are about to do. CONFIRM_LOG is shown the
    //! moment a set is finished, so the numbers recorded are the ones actually
    //! performed rather than the ones planned — the athlete gets the last word
    //! before the rest timer takes the screen.
    const EDITOR_EDIT_NEXT = 0;
    const EDITOR_CONFIRM_LOG = 1;

    //! Weights travel through the editor as tenths of a kilogram, because a
    //! PickerFactory deals in Numbers and 2.5 kg steps are not integers.
    public function toTenths(kg as Float) as Number {
        return Math.round(kg * 10.0).toNumber();
    }
}
