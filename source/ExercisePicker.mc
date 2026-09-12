import Toybox.Lang;
import Toybox.WatchUi;

//! Choosing a movement from the catalogue: muscle group, then exercise.
//!
//! Two screens rather than one list of eighty, because scrolling eighty items
//! on a watch is not a thing anyone will do twice. Both are `Menu2`, so
//! scrolling, touch and buttons all behave the way the rest of the watch does.
//!
//! The picker is opened from three places and has to do something different in
//! each, so the caller states its intent up front and the picker calls back into
//! one place when a row is chosen. The intent is module state rather than a
//! closure because Monkey C has no closures worth the name, and a menu delegate
//! that has to be constructed before the menu makes passing context awkward.
module ExercisePicker {

    //! Add to the workout open in the editor.
    const FOR_EDITOR = 0;
    //! Add to the workout that is running right now.
    const FOR_SESSION = 1;
    //! Replace an exercise in the workout that is running right now.
    const FOR_SUBSTITUTE = 2;

    var _intent as Number = FOR_SESSION;
    //! The exercise being replaced, for FOR_SUBSTITUTE.
    var _targetId as String? = null;

    public function open(intent as Number, targetId as String?) as Void {
        _intent = intent;
        _targetId = targetId;
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(Rez.Strings.PickMuscle) as String
        });
        var groups = Muscle.browseOrder();
        for (var i = 0; i < groups.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(
                Muscle.name(groups[i]), null, groups[i].toString(), {}));
        }
        WatchUi.switchToView(menu, new MuscleMenuDelegate(), WatchUi.SLIDE_UP);
    }

    public function showGroup(group as Number) as Void {
        var menu = new WatchUi.Menu2({ :title => Muscle.name(group) });
        var rows = ExerciseCatalogue.forMuscle(group);
        for (var i = 0; i < rows.size(); i++) {
            var row = rows[i] as Array;
            var weight = (row[ExerciseCatalogue.F_WEIGHT] as Number).toFloat();
            // Bodyweight movements have no load to show, and "0 kg" reads as a
            // mistake rather than as "yourself".
            var sub = weight > 0.0
                ? (row[ExerciseCatalogue.F_REPS] as Number).toString() + " x " +
                    Theme.formatPlannedWeight(weight) + " " + Units.label()
                : (row[ExerciseCatalogue.F_REPS] as Number).toString() + " " +
                    (WatchUi.loadResource(Rez.Strings.FieldReps) as String).toLower();
            menu.addItem(new WatchUi.MenuItem(
                row[ExerciseCatalogue.F_NAME] as String, sub,
                group.toString() + ":" + i.toString(), {}));
        }
        WatchUi.switchToView(menu, new CatalogueMenuDelegate(), WatchUi.SLIDE_LEFT);
    }

    //! A row was chosen. Everything the three callers do differently happens here.
    public function choose(group as Number, index as Number) as Void {
        var rows = ExerciseCatalogue.forMuscle(group);
        if (index < 0 || index >= rows.size()) {
            cancel();
            return;
        }
        var row = rows[index] as Array;

        if (_intent == FOR_EDITOR) {
            WorkoutEditor.addFromCatalogue(row, group);
            return;
        }

        var controller = AppController.instance();
        var engine = controller.engine();
        if (engine == null) {
            cancel();
            return;
        }

        // A movement can legitimately appear twice in one workout, so the id
        // gets a suffix until it is unique. See ExerciseCatalogue.toExercise.
        var suffix = 0;
        var exercise = ExerciseCatalogue.toExercise(row, group, 3, suffix);
        while (engine.getWorkout().findExercise(exercise.id) != null && suffix < 9) {
            suffix++;
            exercise = ExerciseCatalogue.toExercise(row, group, 3, suffix);
        }

        if (_intent == FOR_SUBSTITUTE && _targetId != null) {
            controller.substituteExercise(_targetId as String, exercise);
        } else {
            controller.addExercise(exercise);
        }
        controller.selectExercise(exercise.id);
        WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_LEFT);
    }

    //! Back out to wherever the picker was opened from.
    public function cancel() as Void {
        if (_intent == FOR_EDITOR) {
            WorkoutEditor.reopen();
            return;
        }
        var engine = AppController.instance().engine();
        if (engine != null && engine.currentExercise() != null) {
            WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_DOWN);
            return;
        }
        WatchUi.switchToView(new WorkoutOverviewView(), new WorkoutOverviewDelegate(),
            WatchUi.SLIDE_DOWN);
    }
}

class MuscleMenuDelegate extends WatchUi.Menu2InputDelegate {

    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        ExercisePicker.showGroup((item.getId() as String).toNumber() as Number);
    }

    public function onBack() as Void {
        ExercisePicker.cancel();
    }
}

class CatalogueMenuDelegate extends WatchUi.Menu2InputDelegate {

    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        var split = id.find(":");
        if (split == null) {
            return;
        }
        var group = (id.substring(0, split) as String).toNumber() as Number;
        var index = (id.substring(split + 1, id.length()) as String).toNumber() as Number;
        ExercisePicker.choose(group, index);
    }

    //! BACK returns to the muscle list rather than out of the picker: one wrong
    //! group should cost one press, not the whole journey.
    public function onBack() as Void {
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(Rez.Strings.PickMuscle) as String
        });
        var groups = Muscle.browseOrder();
        for (var i = 0; i < groups.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(
                Muscle.name(groups[i]), null, groups[i].toString(), {}));
        }
        WatchUi.switchToView(menu, new MuscleMenuDelegate(), WatchUi.SLIDE_RIGHT);
    }
}
