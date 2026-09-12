import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! Edit the weight and the reps of the upcoming set, in one screen.
//!
//!        NEXT SET
//!     ┌──────────────┐
//!       57.5  ×  10
//!     └──────────────┘
//!        KG     REPS
//!
//! Built on `WatchUi.Picker`, the platform's own two-column editor: UP/DOWN
//! change the highlighted column, START moves to the next one and confirms on
//! the last, BACK steps back. That is the interaction every Garmin owner
//! already knows, and it beats anything bespoke for editing two values at once.
//!
//! Weights are carried through the picker as **tenths of a kilogram**, because
//! PickerFactory deals in Numbers and 2.5 kg steps are not integers.
class SetPicker extends WatchUi.Picker {

    public function initialize(exercise as Exercise, weight as Float, reps as Number) {
        var title = new WatchUi.Text({
            :text => (WatchUi.loadResource(Rez.Strings.NextSet) as String),
            :color => Theme.COLOR_ACCENT,
            :font => Graphics.FONT_XTINY,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_BOTTOM
        });

        var separator = new WatchUi.Text({
            :text => "x",
            :color => Theme.COLOR_DIM,
            :font => Graphics.FONT_SMALL,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_CENTER
        });

        var weightFactory = new WeightFactory();
        var repsFactory = new RepsFactory();

        var pattern = [weightFactory, separator, repsFactory] as Array<PickerFactory or WatchUi.Text>;
        var defaults = [
            weightFactory.getIndex(Tuning.toTenths(weight)),
            0,
            repsFactory.getIndex(reps)
        ] as Array<Number>;

        Picker.initialize({
            :title => title,
            :pattern => pattern,
            :defaults => defaults
        });
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        Picker.onUpdate(dc);
    }
}

//! Weight column, in tenths of a kilogram so 2.5 kg steps stay integral.
class WeightFactory extends WatchUi.PickerFactory {

    //! 0 to 300.0 kg in 2.5 kg steps.
    private const STEP_TENTHS = 25;
    private const MAX_TENTHS = 3000;

    public function initialize() {
        PickerFactory.initialize();
    }

    public function getSize() as Number {
        return MAX_TENTHS / STEP_TENTHS + 1;
    }

    public function getValue(index as Number) as Object? {
        return index * STEP_TENTHS;
    }

    public function getIndex(tenths as Number) as Number {
        var index = tenths / STEP_TENTHS;
        if (index < 0) {
            return 0;
        }
        if (index >= getSize()) {
            return getSize() - 1;
        }
        return index;
    }

    //! The selected row is drawn in the accent colour and the neighbours dimmed,
    //! so the column being edited is obvious at a glance.
    public function getDrawable(index as Number, selected as Boolean) as Drawable? {
        var tenths = index * STEP_TENTHS;
        return new WatchUi.Text({
            :text => Theme.formatWeight(tenths / 10.0),
            :color => selected ? Theme.COLOR_ACCENT : Theme.COLOR_DIM,
            :font => selected ? Graphics.FONT_NUMBER_MEDIUM : Graphics.FONT_MEDIUM,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_CENTER
        });
    }
}

//! Repetitions column.
class RepsFactory extends WatchUi.PickerFactory {

    private const MAX_REPS = 60;

    public function initialize() {
        PickerFactory.initialize();
    }

    public function getSize() as Number {
        return MAX_REPS + 1;
    }

    public function getValue(index as Number) as Object? {
        return index;
    }

    public function getIndex(reps as Number) as Number {
        if (reps < 0) {
            return 0;
        }
        if (reps > MAX_REPS) {
            return MAX_REPS;
        }
        return reps;
    }

    public function getDrawable(index as Number, selected as Boolean) as Drawable? {
        return new WatchUi.Text({
            :text => index.toString(),
            :color => selected ? Theme.COLOR_TEXT : Theme.COLOR_DIM,
            :font => selected ? Graphics.FONT_NUMBER_MEDIUM : Graphics.FONT_MEDIUM,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_CENTER
        });
    }
}

class SetPickerDelegate extends WatchUi.PickerDelegate {

    //! Where to go once the athlete is done: back to the exercise, or back to
    //! the rest screen they opened this from.
    private var _returnToRest as Boolean;

    public function initialize(returnToRest as Boolean) {
        PickerDelegate.initialize();
        _returnToRest = returnToRest;
    }

    public function onAccept(values as Array) as Boolean {
        var controller = AppController.instance();
        var tenths = values[0];
        var reps = values[2];
        if (tenths instanceof Number) {
            controller.setWeight(tenths / 10.0);
        }
        if (reps instanceof Number) {
            controller.setReps(reps);
        }
        controller.persistNow();
        _leave();
        return true;
    }

    public function onCancel() as Boolean {
        _leave();
        return true;
    }

    private function _leave() as Void {
        if (_returnToRest) {
            WatchUi.switchToView(new RestView(), new RestDelegate(), WatchUi.SLIDE_DOWN);
        } else {
            WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_DOWN);
        }
    }
}

//! Open the editor for the set the athlete is about to perform.
module SetEditor {
    public function open(exercise as Exercise, fromRest as Boolean) as Void {
        var controller = AppController.instance();
        var picker = new SetPicker(exercise, controller.pendingWeight(), controller.pendingReps());
        WatchUi.switchToView(picker, new SetPickerDelegate(fromRest), WatchUi.SLIDE_UP);
    }
}
