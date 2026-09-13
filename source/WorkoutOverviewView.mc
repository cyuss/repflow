import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.System;

//! The heart of "select any exercise at any time".
//!
//!     PECS + BICEPS
//!     (>) Bench Press (Barbell)
//!         2/4    20 kg
//!     ( ) Incline Bench Press (DB)
//!         0/4    18 kg
//!
//! Built on `WatchUi.CustomMenu` rather than `Menu2`, so scrolling, touch and
//! button input still behave the way the rest of the watch does while the rows
//! themselves are drawn here.
//!
//! **Why it moved off Menu2.** Menu2 takes a label as a String and decides for
//! itself what to do when the label is too long: it wraps, then it truncates.
//! Imported names are long — "Incline Bench Press (Dumbbell)" — and a list of
//! rows reading "Incline Bench Pr." is a list you cannot choose from, which is
//! the one thing this screen exists for. There is no API to scroll a Menu2
//! label. `CustomMenuItem.draw` is the supported way to take that decision
//! back, and it is available on every product RepFlow ships to.
//!
//! The focused row scrolls; the others are clipped with a trailing dot. Only
//! one row can be read at a time anyway, and a list where every row is moving
//! is unreadable.
class WorkoutOverviewView extends WatchUi.CustomMenu {

    public static const ITEM_END_WORKOUT = "__end__";
    public static const ITEM_ADD_EXERCISE = "__add__";

    public function initialize() {
        var settings = System.getDeviceSettings();
        var height = settings.screenHeight;
        var engine = AppController.instance().engine();
        var title = "Workout";
        if (engine != null) {
            title = engine.getWorkout().name;
        }

        // Four rows, not six.
        //
        // Row height is what decides how far from the centre the outermost row
        // sits, and on a round screen that decides whether its icon survives.
        // At a fifth of the screen the top and bottom rows sat where the glass
        // has already curved past the icon column, and their state rings came
        // out as bare vertical slivers — reported from a real watch and
        // reproduced in the simulator.
        //
        // Taller rows keep every row near the middle where the screen is at
        // its widest. They are also easier to hit and closer to what Garmin's
        // own menus do, so nothing is being traded away for the fix.
        CustomMenu.initialize(height / 4, Theme.colorBg(), {
            :focusItemHeight => height / 3,
            :title => new OverviewTitle(title),
            // Explicitly themeless: a menu theme would override the background
            // colour, and RepFlow's light mode is a background colour.
            :theme => null
        });
        _populate(engine);
    }

    private function _populate(engine as WorkoutEngine?) as Void {
        if (engine == null) {
            return;
        }
        var list = engine.getWorkout().exercises;
        for (var i = 0; i < list.size(); i++) {
            addItem(new ExerciseMenuItem(list[i]));
        }
        // An unplanned exercise is half of all sessions, so it lives here
        // rather than behind the per-exercise menu.
        addItem(new ActionMenuItem(
            WatchUi.loadResource(Rez.Strings.AddExercise) as String,
            ITEM_ADD_EXERCISE));
        // End the workout from the bottom of the list — no nested menu needed.
        addItem(new ActionMenuItem(
            WatchUi.loadResource(Rez.Strings.ActionEndWorkout) as String,
            ITEM_END_WORKOUT));
    }

    //! Drawn after every item, so it is the one place that knows a whole frame
    //! has been rendered. Without it the scroll timer would never stop.
    public function drawForeground(dc as Graphics.Dc) as Void {
        Marquee.endFrame();
    }

    public function onHide() as Void {
        Marquee.stop();
    }
}

//! The workout's name, across the top of the list.
//!
//! Scrolls when it has to, for the same reason the rows do: "Dos + Triceps"
//! fits and "Upper Body Push (Heavy)" does not, and shrinking the title until
//! it fits is how a heading becomes a smudge.
class OverviewTitle extends WatchUi.Drawable {

    private var _text as String;

    public function initialize(text as String) {
        Drawable.initialize({});
        _text = text;
    }

    public function draw(dc as Graphics.Dc) as Void {
        var height = dc.getHeight();
        var font = Theme.captionFont();
        var top = (height - dc.getFontHeight(font)) / 2;
        if (top < 0) {
            top = 0;
        }
        Marquee.draw(dc, top, _text.toUpper(),
            [font] as Array<Graphics.FontDefinition>, Theme.colorAccent(),
            RowLayout.textWidth(dc));
    }
}

//! Where the text goes in a list row, on any screen size.
//!
//! Shared by the rows and the title so they line up, and kept out of both so
//! the numbers are stated once.
module RowLayout {

    //! Where a row's text starts. Every row starts here, whatever it says.
    public function textLeft(dc as Graphics.Dc) as Number {
        return gutter(dc);
    }

    //! Width available to text.
    //!
    //! The gutter is taken off **both** sides even though only the left one
    //! holds an icon: the right one is what keeps the longest name clear of the
    //! curve of the glass.
    public function textWidth(dc as Graphics.Dc) as Number {
        var width = dc.getWidth();
        var usable = width - gutter(dc) * 2;
        return usable < 1 ? 1 : usable;
    }

    //! The icon column, mirrored as a margin on the right.
    public function gutter(dc as Graphics.Dc) as Number {
        return dc.getWidth() / 5;
    }

    //! Where the state icon's centre goes.
    //!
    //! Far enough in that the curve of the glass does not clip it on the
    //! outermost row the menu shows — see the row height chosen in
    //! WorkoutOverviewView — and far enough out that it stays a column you can
    //! run your eye down rather than a mark stuck to the text.
    public function iconCentre(dc as Graphics.Dc) as Number {
        return (gutter(dc) * 3) / 5;
    }
}

//! One exercise: state icon, name, and what is done of it.
class ExerciseMenuItem extends WatchUi.CustomMenuItem {

    private var _exercise as Exercise;

    public function initialize(exercise as Exercise) {
        CustomMenuItem.initialize(exercise.id, {});
        _exercise = exercise;
    }

    public function draw(dc as Graphics.Dc) as Void {
        var height = dc.getHeight();
        var focused = isFocused();

        var nameFont = Theme.captionFont();
        var subFont = Theme.captionFont();
        var nameHeight = dc.getFontHeight(nameFont);
        var subHeight = dc.getFontHeight(subFont);
        var gap = height / 16;

        var block = nameHeight + gap + subHeight;
        var top = (height - block) / 2;
        if (top < 0) {
            top = 0;
        }
        // The icon belongs to the exercise, and the exercise is the name. Level
        // with the name's own line, not with the middle of the two-line block —
        // centred on the block it read as though it belonged to the gap.
        var iconCy = top + nameHeight / 2;

        // Wide spacing, and a space before the unit: "2/4    20 kg" reads as
        // two facts, "2/420kg" as one run-on. ASCII only — the Fenix 6 Pro has
        // no glyph for a middot and draws a "?" box instead.
        var sub = _exercise.completedSetCount().toString() + "/" +
            _exercise.targetSets.toString() + "    " +
            Theme.formatPlannedWeight(_exercise.plannedWeight()) + " " + Units.label();

        var textWidth = RowLayout.textWidth(dc);
        var nameColor = focused ? Theme.colorText() : Theme.colorDim();
        if (_exercise.state == EX_SKIPPED) {
            // A skipped exercise is a fact about the session, not a headline.
            nameColor = Theme.colorFaint();
        }

        // Left-aligned, so the eye runs down one edge to find a name instead
        // of reading every row to work out where each one starts.
        var textLeft = RowLayout.textLeft(dc);
        if (focused) {
            Marquee.drawAt(dc, textLeft, top, _exercise.name,
                [nameFont] as Array<Graphics.FontDefinition>, nameColor, textWidth);
        } else {
            Theme.drawClippedAt(dc, textLeft, top, _exercise.name, nameFont,
                nameColor, textWidth);
        }

        Theme.drawClippedAt(dc, textLeft, top + nameHeight + gap, sub, subFont,
            focused ? Theme.colorAccent() : Theme.colorFaint(), textWidth);

        // The icon sits in the left gutter, centred on the row as a whole.
        // StateIcon draws its dot at 44% across its own box rather than in the
        // middle of it, so the box is placed to put that dot where it belongs
        // instead of assuming the two coincide.
        var iconSize = (RowLayout.gutter(dc) * 4) / 5;
        var icon = new StateIcon(_exercise.state, iconSize);
        icon.setLocation(RowLayout.iconCentre(dc) - (iconSize * 44) / 100,
            iconCy - iconSize / 2);
        icon.draw(dc);
    }
}

//! A plain action row: "Add exercise", "End workout".
class ActionMenuItem extends WatchUi.CustomMenuItem {

    private var _label as String;

    public function initialize(label as String, id as String) {
        CustomMenuItem.initialize(id, {});
        _label = label;
    }

    public function draw(dc as Graphics.Dc) as Void {
        var font = Theme.captionFont();
        var top = (dc.getHeight() - dc.getFontHeight(font)) / 2;
        if (top < 0) {
            top = 0;
        }
        Theme.drawClippedAt(dc, RowLayout.textLeft(dc), top, _label, font,
            isFocused() ? Theme.colorText() : Theme.colorDim(),
            RowLayout.textWidth(dc));
    }
}

class WorkoutOverviewDelegate extends WatchUi.Menu2InputDelegate {

    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        if (id.equals(WorkoutOverviewView.ITEM_END_WORKOUT)) {
            EndWorkoutFlow.request();
            return;
        }
        if (id.equals(WorkoutOverviewView.ITEM_ADD_EXERCISE)) {
            ExercisePicker.open(ExercisePicker.FOR_SESSION, null);
            return;
        }
        // Any exercise, any time — including completed and skipped ones.
        if (AppController.instance().selectExercise(id)) {
            WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_LEFT);
        }
    }

    //! BACK returns to training rather than dropping out of the workout: the
    //! selected exercise, else the next sensible one, else the end-of-workout
    //! flow. The overview is never a dead end.
    public function onBack() as Void {
        var controller = AppController.instance();
        var engine = controller.engine();
        if (engine == null) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return;
        }
        if (engine.currentExercise() != null) {
            WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_LEFT);
            return;
        }
        var next = engine.suggestNextExercise();
        if (next != null && controller.selectExercise(next.id)) {
            WatchUi.switchToView(new ExerciseView(), new ExerciseDelegate(), WatchUi.SLIDE_LEFT);
            return;
        }
        EndWorkoutFlow.request();
    }
}
