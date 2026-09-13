import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! First screen: pick a workout.
//!
//! One workout fills the screen at a time so it stays readable at arm's length.
//! UP/DOWN cycles, START begins, MENU edits.
//!
//! One page past the last workout is **New workout**, which is how an empty
//! session starts. It is a page rather than a menu entry because this screen is
//! a carousel, and a carousel that ends in "and one more thing you can do" is
//! how every Garmin activity picker already behaves.
class WorkoutListView extends WatchUi.View {

    private var _workouts as Array<Workout>;
    private var _index as Number;

    public function initialize() {
        View.initialize();
        _workouts = WorkoutRepository.all();
        _index = 0;
    }

    //! True when the cursor is on the "New workout" page rather than a workout.
    public function onNewPage() as Boolean {
        return _index >= _workouts.size();
    }

    public function selected() as Workout? {
        return onNewPage() ? null : _workouts[_index];
    }

    public function move(delta as Number) as Void {
        var n = _workouts.size() + 1;      // the carousel ends on New workout
        _index = (_index + delta + n) % n;
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var h = dc.getHeight();
        if (onNewPage()) {
            _drawNewPage(dc);
            Theme.drawPageDots(dc, _workouts.size() + 1, _index);
            return;
        }
        var workout = _workouts[_index];
        var gap = h / 30;

        var actionTop = Theme.drawActionBar(dc, "START", Theme.colorAccent());

        var y = h / 8;
        y = Theme.drawFitted(dc, y, WatchUi.loadResource(Rez.Strings.AppName) as String,
            Theme.fontsLabel(), Theme.colorAccent());
        y += gap;
        y = Theme.drawFitted(dc, y, WatchUi.loadResource(Rez.Strings.ChooseWorkout) as String,
            Theme.fontsLabel(), Theme.colorDim());

        // Centre the workout name in the space between the header and the
        // action bar, rather than pinning it to a fixed fraction of the screen.
        var nameFont = Theme.pickFont(dc, workout.name, Theme.fontsTitle(),
            Theme.usableWidth(dc, h / 2));
        var nameHeight = dc.getFontHeight(nameFont);
        var countText = workout.exercises.size().toString() + " exercises";
        var countHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var blockHeight = nameHeight + gap + countHeight;
        var blockTop = y + ((actionTop - y) - blockHeight) / 2;
        if (blockTop < y) {
            blockTop = y;
        }

        var afterName = Marquee.drawFitted(dc, blockTop, workout.name,
            Theme.fontsTitle(), Theme.colorText(), Theme.usableWidth(dc, blockTop));
        Theme.drawFitted(dc, afterName + gap, countText,
            [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>, Theme.colorDim());

        Theme.drawPageDots(dc, _workouts.size() + 1, _index);
        Marquee.endFrame();
    }

    //! The last page: start from nothing and build as you go.
    private function _drawNewPage(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var actionTop = Theme.drawActionBar(dc, "START", Theme.colorDone());

        var y = h / 8;
        y = Theme.drawFitted(dc, y, WatchUi.loadResource(Rez.Strings.AppName) as String,
            Theme.fontsLabel(), Theme.colorAccent());

        var label = WatchUi.loadResource(Rez.Strings.NewWorkout) as String;
        var labelFont = Theme.pickFont(dc, label, Theme.fontsTitle(),
            Theme.usableWidth(dc, h / 2));
        var labelHeight = dc.getFontHeight(labelFont);
        var signSize = (h * 22) / 100;
        var gap = h / 20;
        var block = signSize + gap + labelHeight;
        var top = y + ((actionTop - y) - block) / 2;
        if (top < y) {
            top = y;
        }

        Theme.drawAddMark(dc, dc.getWidth() / 2, top + signSize / 2, signSize,
            Theme.colorAccent());
        Theme.drawFitted(dc, top + signSize + gap, label,
            Theme.fontsTitle(), Theme.colorText());
    }
}

class WorkoutListDelegate extends WatchUi.BehaviorDelegate {

    private var _view as WorkoutListView;

    public function initialize(view as WorkoutListView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onNextPage() as Boolean {
        _view.move(1);
        return true;
    }

    public function onPreviousPage() as Boolean {
        _view.move(-1);
        return true;
    }

    //! MENU — edit this workout, or open RepFlow's settings.
    //!
    //! The settings live here as well as behind the watch's own app menu,
    //! because whether that menu offers a Settings entry is up to the firmware.
    //! This one always works.
    public function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({ :title => "RepFlow" });
        if (!_view.onNewPage()) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.EditWorkoutItem) as String,
                (_view.selected() as Workout).name, ITEM_EDIT, {}));
        }
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.NewWorkout) as String, null, ITEM_NEW, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.HevyImport) as String,
            HevyApi.hasKey()
                ? null
                : WatchUi.loadResource(Rez.Strings.HevyNoKey) as String,
            ITEM_HEVY, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.AppSettings) as String, null, ITEM_SETTINGS, {}));
        WatchUi.switchToView(menu, new WorkoutListMenuDelegate(_view), WatchUi.SLIDE_UP);
        return true;
    }

    public static const ITEM_EDIT = "edit";
    public static const ITEM_NEW = "new";
    public static const ITEM_SETTINGS = "settings";
    public static const ITEM_HEVY = "hevy";


    //! START — begin the highlighted workout, or open the editor when the
    //! cursor is on the New workout page.
    //!
    //! The session opens on the **list**, not on the first exercise.
    //!
    //! Starting on exercise one assumes the athlete is going to do exercise one,
    //! which is the assumption this whole app exists to refuse: the bench is
    //! taken, so you start with rows. Landing on the list costs one press when
    //! the order does happen to be the planned one, and saves a wrong start
    //! and a correction every other time.
    public function onSelect() as Boolean {
        if (_view.onNewPage()) {
            WorkoutEditor.createNew();
            return true;
        }
        var controller = AppController.instance();
        controller.startWorkout(_view.selected() as Workout);
        WatchUi.switchToView(new WorkoutOverviewView(), new WorkoutOverviewDelegate(),
            WatchUi.SLIDE_LEFT);
        return true;
    }
}

//! The workout picker's MENU.
class WorkoutListMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as WorkoutListView;

    public function initialize(view as WorkoutListView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        if (id.equals(WorkoutListDelegate.ITEM_SETTINGS)) {
            AppSettingsMenu.show();
            return;
        }
        if (id.equals(WorkoutListDelegate.ITEM_HEVY)) {
            HevySync.importRoutines();
            return;
        }
        if (id.equals(WorkoutListDelegate.ITEM_NEW)) {
            WorkoutEditor.createNew();
            return;
        }
        // Editing a built-in opens a copy the athlete owns, rather than
        // changing what ships with the app.
        var workout = _view.selected();
        if (workout == null) {
            WorkoutEditor.createNew();
            return;
        }
        if (WorkoutRepository.isCustom((workout as Workout).id)) {
            WorkoutEditor.edit(workout as Workout);
        } else {
            var copy = Workout.fromStorage((workout as Workout).toStorage());
            copy.id = WorkoutRepository.newCustomId(AppController.now());
            WorkoutEditor.edit(copy);
        }
    }

    public function onBack() as Void {
        var list = new WorkoutListView();
        WatchUi.switchToView(list, new WorkoutListDelegate(list), WatchUi.SLIDE_DOWN);
    }
}
