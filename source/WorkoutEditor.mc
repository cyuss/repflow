import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Math;

//! Building and changing a workout, on the watch.
//!
//! Needing a phone to change a plan is what makes watch apps get deleted, so
//! everything here works with the four buttons and no keyboard.
//!
//! **Naming without typing.** A custom workout is named after what is in it —
//! "Chest + Biceps", "Legs" — recomputed every time it is saved. Garmin's text
//! entry is not available on every target and is miserable on the ones where it
//! is, and a name that describes the contents is more useful than one the
//! athlete had to invent anyway.
//!
//! The workout being edited is module state. It is a draft: nothing reaches
//! storage until the athlete leaves the editor, so backing out of a half-built
//! session leaves the stored list exactly as it was.
module WorkoutEditor {

    const ITEM_ADD = "__add__";
    const ITEM_SAVE = "__save__";
    const ITEM_DELETE = "__delete__";

    const ACT_SETS = "sets";
    const ACT_REPS = "reps";
    const ACT_WEIGHT = "weight";
    const ACT_REST = "rest";
    const ACT_UP = "up";
    const ACT_DOWN = "down";
    const ACT_REMOVE = "remove";

    var _draft as Workout? = null;
    //! Id of the exercise whose own menu is open, for the callbacks.
    var _editing as String? = null;

    // ------------------------------------------------------------------
    // Opening
    // ------------------------------------------------------------------

    //! Start a brand new, empty workout (1.1).
    public function createNew() as Void {
        var id = WorkoutRepository.newCustomId(AppController.now());
        _draft = new Workout(id, WatchUi.loadResource(Rez.Strings.NewWorkout) as String,
            [] as Array<Exercise>);
        // Straight to the catalogue: an empty workout with nothing in it is not
        // a screen worth showing.
        ExercisePicker.open(ExercisePicker.FOR_EDITOR, null);
    }

    //! Edit an existing custom workout.
    public function edit(workout as Workout) as Void {
        _draft = workout;
        reopen();
    }

    public function draft() as Workout? {
        return _draft;
    }

    //! Show the editor for whatever draft is open.
    public function reopen() as Void {
        var workout = _draft;
        if (workout == null) {
            _toList();
            return;
        }
        var menu = new WatchUi.Menu2({ :title => suggestName(workout) });
        var list = workout.exercises;
        for (var i = 0; i < list.size(); i++) {
            var ex = list[i];
            menu.addItem(new WatchUi.MenuItem(
                ex.name,
                ex.targetSets.toString() + " x " + ex.targetReps.toString() + "   " +
                    Theme.formatPlannedWeight(ex.plannedWeight()) + " " + Units.label(),
                ex.id, {}));
        }
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.AddExercise) as String, null, ITEM_ADD, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SaveWorkout) as String, null, ITEM_SAVE, {}));
        if (WorkoutRepository.isCustom(workout.id)) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.DeleteWorkout) as String, null, ITEM_DELETE, {}));
        }
        WatchUi.switchToView(menu, new WorkoutEditorDelegate(), WatchUi.SLIDE_UP);
    }

    // ------------------------------------------------------------------
    // Editing
    // ------------------------------------------------------------------

    //! A row was chosen in the catalogue while the editor was open.
    public function addFromCatalogue(row as Array, group as Number) as Void {
        var workout = _draft;
        if (workout == null) {
            _toList();
            return;
        }
        var suffix = 0;
        var exercise = ExerciseCatalogue.toExercise(row, group, 3, suffix);
        while (workout.findExercise(exercise.id) != null && suffix < 9) {
            suffix++;
            exercise = ExerciseCatalogue.toExercise(row, group, 3, suffix);
        }
        workout.exercises.add(exercise);
        reopen();
    }

    //! The per-exercise menu: targets, position, removal.
    public function showExercise(exerciseId as String) as Void {
        var workout = _draft;
        if (workout == null) {
            _toList();
            return;
        }
        var ex = workout.findExercise(exerciseId);
        if (ex == null) {
            reopen();
            return;
        }
        _editing = exerciseId;

        var menu = new WatchUi.Menu2({ :title => ex.name });
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.FieldSets) as String,
            ex.targetSets.toString(), ACT_SETS, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.FieldReps) as String,
            ex.targetReps.toString(), ACT_REPS, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.WeightLabel) as String,
            Theme.formatPlannedWeight(ex.defaultWeight) + " " + Units.label(), ACT_WEIGHT, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.RestLabel) as String,
            Theme.formatDuration(ex.restDuration), ACT_REST, {}));

        var index = workout.indexOf(exerciseId);
        if (index > 0) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.MoveUp) as String, null, ACT_UP, {}));
        }
        if (index >= 0 && index < workout.exercises.size() - 1) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.MoveDown) as String, null, ACT_DOWN, {}));
        }
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.RemoveExercise) as String, null, ACT_REMOVE, {}));
        WatchUi.switchToView(menu, new ExerciseEditorDelegate(), WatchUi.SLIDE_LEFT);
    }

    public function editing() as Exercise? {
        var workout = _draft;
        var id = _editing;
        if (workout == null || id == null) {
            return null;
        }
        return workout.findExercise(id as String);
    }

    //! Move an exercise one place up or down the plan.
    public function move(exerciseId as String, delta as Number) as Boolean {
        var workout = _draft;
        if (workout == null) {
            return false;
        }
        var list = workout.exercises;
        var from = workout.indexOf(exerciseId);
        var to = from + delta;
        if (from < 0 || to < 0 || to >= list.size()) {
            return false;
        }
        var moved = list[from];
        list[from] = list[to];
        list[to] = moved;
        return true;
    }

    public function remove(exerciseId as String) as Void {
        var workout = _draft;
        if (workout == null) {
            return;
        }
        var rebuilt = [] as Array<Exercise>;
        var list = workout.exercises;
        for (var i = 0; i < list.size(); i++) {
            if (!list[i].id.equals(exerciseId)) {
                rebuilt.add(list[i]);
            }
        }
        workout.exercises = rebuilt;
    }

    // ------------------------------------------------------------------
    // Leaving
    // ------------------------------------------------------------------

    //! Write the draft and go back to the workout list.
    public function save() as Void {
        var workout = _draft;
        if (workout != null && workout.exercises.size() > 0) {
            workout.name = suggestName(workout);
            WorkoutRepository.saveCustom(workout);
        }
        _draft = null;
        _editing = null;
        _toList();
    }

    //! Leave without writing. A half-built workout is not worth keeping, and
    //! an edit the athlete backed out of is one they changed their mind about.
    public function discard() as Void {
        _draft = null;
        _editing = null;
        _toList();
    }

    public function deleteDraft() as Void {
        var workout = _draft;
        if (workout != null) {
            WorkoutRepository.removeCustom(workout.id);
        }
        _draft = null;
        _editing = null;
        _toList();
    }

    // ------------------------------------------------------------------
    // Naming
    // ------------------------------------------------------------------

    //! A name from the contents: the one or two muscle groups with the most
    //! sets in them, which is how lifters name sessions anyway.
    public function suggestName(workout as Workout) as String {
        var list = workout.exercises;
        if (list.size() == 0) {
            return WatchUi.loadResource(Rez.Strings.NewWorkout) as String;
        }
        var tally = new [Muscle.COUNT] as Array<Number>;
        for (var i = 0; i < Muscle.COUNT; i++) {
            tally[i] = 0;
        }
        for (var i = 0; i < list.size(); i++) {
            var m = list[i].muscle;
            if (Muscle.isValid(m)) {
                tally[m] += list[i].targetSets;
            }
        }

        var first = _largest(tally, -1);
        if (first < 0) {
            return WatchUi.loadResource(Rez.Strings.NewWorkout) as String;
        }
        var second = _largest(tally, first);
        // A second group earns a mention at a third of the leader's sets.
        // Seven chest sets and three of curls is "Chest + Biceps"; seven chest
        // sets and one plank is a chest session that happens to end in a plank.
        if (second < 0 || tally[second] * 3 < tally[first]) {
            return Muscle.name(first);
        }
        return Muscle.name(first) + " + " + Muscle.name(second);
    }

    function _largest(tally as Array<Number>, exclude as Number) as Number {
        var best = -1;
        var bestValue = 0;
        for (var i = 1; i < Muscle.COUNT; i++) {
            if (i == exclude) {
                continue;
            }
            if (tally[i] > bestValue) {
                bestValue = tally[i];
                best = i;
            }
        }
        return best;
    }

    function _toList() as Void {
        var list = new WorkoutListView();
        WatchUi.switchToView(list, new WorkoutListDelegate(list), WatchUi.SLIDE_DOWN);
    }
}

class WorkoutEditorDelegate extends WatchUi.Menu2InputDelegate {

    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        if (id.equals(WorkoutEditor.ITEM_ADD)) {
            ExercisePicker.open(ExercisePicker.FOR_EDITOR, null);
            return;
        }
        if (id.equals(WorkoutEditor.ITEM_SAVE)) {
            WorkoutEditor.save();
            return;
        }
        if (id.equals(WorkoutEditor.ITEM_DELETE)) {
            WorkoutEditor.deleteDraft();
            return;
        }
        WorkoutEditor.showExercise(id);
    }

    //! BACK saves rather than discards. Everything in this menu is an explicit
    //! edit the athlete already made; throwing them away because they left by
    //! the wrong door would be the surprise, not the safety.
    public function onBack() as Void {
        WorkoutEditor.save();
    }
}

class ExerciseEditorDelegate extends WatchUi.Menu2InputDelegate {

    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var ex = WorkoutEditor.editing();
        if (ex == null) {
            WorkoutEditor.reopen();
            return;
        }
        var id = item.getId() as String;

        if (id.equals(WorkoutEditor.ACT_SETS)) {
            _number(WatchUi.loadResource(Rez.Strings.FieldSets) as String, "",
                ex.targetSets, 1, 20, 1, false, method(:onSets));
            return;
        }
        if (id.equals(WorkoutEditor.ACT_REPS)) {
            _number(WatchUi.loadResource(Rez.Strings.FieldReps) as String, "",
                ex.targetReps, 1, 100, 1, false, method(:onReps));
            return;
        }
        if (id.equals(WorkoutEditor.ACT_WEIGHT)) {
            // Edited in the athlete's own unit, stored in kilograms.
            var shown = Math.round(Units.fromKg(ex.defaultWeight) * 10.0).toNumber();
            var step = Settings.weightStepTenths();
            _number(WatchUi.loadResource(Rez.Strings.WeightLabel) as String,
                Units.label().toUpper(), shown, 0, 10000, step, true, method(:onWeight));
            return;
        }
        if (id.equals(WorkoutEditor.ACT_REST)) {
            _number(WatchUi.loadResource(Rez.Strings.RestLabel) as String, "s",
                ex.restDuration, 0, 900, 5, false, method(:onRest));
            return;
        }
        if (id.equals(WorkoutEditor.ACT_UP)) {
            WorkoutEditor.move(ex.id, -1);
            WorkoutEditor.reopen();
            return;
        }
        if (id.equals(WorkoutEditor.ACT_DOWN)) {
            WorkoutEditor.move(ex.id, 1);
            WorkoutEditor.reopen();
            return;
        }
        if (id.equals(WorkoutEditor.ACT_REMOVE)) {
            WorkoutEditor.remove(ex.id);
            WorkoutEditor.reopen();
            return;
        }
    }

    public function onBack() as Void {
        WorkoutEditor.reopen();
    }

    function _number(
        title as String,
        unit as String,
        value as Number,
        min as Number,
        max as Number,
        step as Number,
        tenths as Boolean,
        done as Method(value as Number) as Void
    ) as Void {
        var view = new NumberEditorView(title, unit, value, min, max, step, tenths,
            done, method(:onCancel));
        WatchUi.switchToView(view, new NumberEditorDelegate(view), WatchUi.SLIDE_UP);
    }

    public function onSets(value as Number) as Void {
        var ex = WorkoutEditor.editing();
        if (ex != null) {
            ex.targetSets = value;
        }
        _back();
    }

    public function onReps(value as Number) as Void {
        var ex = WorkoutEditor.editing();
        if (ex != null) {
            ex.targetReps = value;
        }
        _back();
    }

    public function onWeight(value as Number) as Void {
        var ex = WorkoutEditor.editing();
        if (ex != null) {
            ex.defaultWeight = Units.toKg(value.toFloat() / 10.0);
        }
        _back();
    }

    public function onRest(value as Number) as Void {
        var ex = WorkoutEditor.editing();
        if (ex != null) {
            ex.restDuration = value;
        }
        _back();
    }

    public function onCancel() as Void {
        _back();
    }

    function _back() as Void {
        var ex = WorkoutEditor.editing();
        if (ex == null) {
            WorkoutEditor.reopen();
            return;
        }
        WorkoutEditor.showExercise(ex.id);
    }
}
