import Toybox.Lang;

//! Interaction constants shared by the controller and the views.
//!
//! These live in a module rather than on AppController because Monkey C does
//! not expose class-level `const` through the class name.
module Tuning {

    //! Weight adjustment step, in kg. 2.5 is one small plate per side.
    const WEIGHT_STEP = 2.5;

    //! Seconds added or removed by UP/DOWN on the rest screen.
    const REST_STEP = 15;
}
