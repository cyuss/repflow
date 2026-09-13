import Toybox.Lang;
import Toybox.WatchUi;

//! RepFlow's settings, on the watch.
//!
//! The same preferences the Garmin Connect phone app edits, reachable without a
//! phone. Both routes write the same `Application.Properties`, so there is one
//! source of truth and neither can drift from the other.
//!
//! Reached two ways:
//!
//!   * `AppBase.getSettingsView()` — the hook the system uses when the watch
//!     offers a Settings entry for an app in its own list. Whether that entry
//!     appears is up to the device's firmware, not to the app, so it cannot be
//!     the only way in.
//!   * MENU on the workout picker, which always works.
//!
//! Everything is a list that cycles on select. No sub-screens except the two
//! numbers, which reuse the editor the set screen already taught the athlete.
module AppSettingsMenu {

    const ITEM_THEME = "theme";
    const ITEM_UNITS = "units";
    const ITEM_REST = "rest";
    const ITEM_REST_MODE = "restmode";
    const ITEM_STEP = "step";
    const ITEM_HAPTICS = "haptics";
    const ITEM_REPS = "reps";
    const ITEM_ANIM = "anim";

    //! Build the menu.
    //!
    //! This used to be rebuilt after every change, on the belief that a Menu2
    //! item's sublabel could not be altered in place. `MenuItem.setSubLabel`
    //! has existed since API 3.0, and rebuilding put the cursor back at the top
    //! of the list every time a setting was toggled — so changing two things in
    //! a row meant scrolling down twice. A wrong comment cost more than the
    //! code it described.
    public function build() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(Rez.Strings.AppSettings) as String
        });

        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SetTheme) as String,
            themeLabel(), ITEM_THEME, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SetUnits) as String,
            unitsLabel(), ITEM_UNITS, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.RestMode) as String,
            restModeLabel(), ITEM_REST_MODE, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.RestLabel) as String,
            Theme.formatDuration(Settings.restDefault()), ITEM_REST, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.WeightLabel) as String,
            stepLabel(), ITEM_STEP, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SetHaptics) as String,
            onOff(Settings.haptics()), ITEM_HAPTICS, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SetRepCounter) as String,
            onOff(Settings.repCounter()), ITEM_REPS, {}));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SetAnimations) as String,
            animLabel(), ITEM_ANIM, {}));
        return menu;
    }

    public function show() as Void {
        var menu = build();
        WatchUi.switchToView(menu, new AppSettingsDelegate(false, menu), WatchUi.SLIDE_UP);
    }

    public function onOff(value as Boolean) as String {
        return WatchUi.loadResource(value ? Rez.Strings.SettingOn : Rez.Strings.SettingOff) as String;
    }

    public function themeLabel() as String {
        return WatchUi.loadResource(Settings.theme() == Tuning.THEME_LIGHT
            ? Rez.Strings.SetThemeLight
            : Rez.Strings.SetThemeDark) as String;
    }

    public function unitsLabel() as String {
        var units = Settings.units();
        if (units == Tuning.UNITS_METRIC) {
            return WatchUi.loadResource(Rez.Strings.SetUnitsMetric) as String;
        }
        if (units == Tuning.UNITS_STATUTE) {
            return WatchUi.loadResource(Rez.Strings.SetUnitsStatute) as String;
        }
        // "Follow the watch", plus what the watch actually says, because the
        // athlete should not have to guess which one that resolves to.
        return (WatchUi.loadResource(Rez.Strings.SetUnitsAuto) as String) +
            " (" + Units.label() + ")";
    }

    //! The weight step, in whichever unit is in force.
    public function stepLabel() as String {
        return "+/- " + Theme.formatNumber(Units.step()) + " " + Units.label();
    }

    public function restModeLabel() as String {
        return WatchUi.loadResource(Settings.restMode() == Tuning.REST_OPEN
            ? Rez.Strings.RestOpen
            : Rez.Strings.RestTimed) as String;
    }

    public function animLabel() as String {
        var choice = Settings.animations();
        if (choice == Tuning.ANIM_OFF) {
            return WatchUi.loadResource(Rez.Strings.SetAnimOff) as String;
        }
        if (choice == Tuning.ANIM_ON) {
            return WatchUi.loadResource(Rez.Strings.SetAnimOn) as String;
        }
        return WatchUi.loadResource(Rez.Strings.SetAnimAuto) as String;
    }
}

//! `fromSystem` is true when the watch opened this itself, in which case
//! leaving must pop back to the system rather than into RepFlow's own screens.
class AppSettingsDelegate extends WatchUi.Menu2InputDelegate {

    private var _fromSystem as Boolean;
    //! The menu being driven, so a change can update a neighbouring row —
    //! switching units rewrites the weight-step row as well as its own.
    private var _menu as WatchUi.Menu2;
    //! Which row opened the number editor, so returning from it lands back on
    //! that row rather than at the top of the list.
    private var _editing as String?;

    public function initialize(fromSystem as Boolean, menu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        _fromSystem = fromSystem;
        _menu = menu;
        _editing = null;
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;

        if (id.equals(AppSettingsMenu.ITEM_THEME)) {
            Settings.setTheme(Settings.theme() == Tuning.THEME_LIGHT
                ? Tuning.THEME_DARK
                : Tuning.THEME_LIGHT);
            _update(item, AppSettingsMenu.themeLabel());
            return;
        }
        if (id.equals(AppSettingsMenu.ITEM_UNITS)) {
            var next = Settings.units() + 1;
            if (next > Tuning.UNITS_STATUTE) {
                next = Tuning.UNITS_AUTO;
            }
            Settings.writeNumber("units", next);
            Settings.invalidate();
            // The weight step is quoted in whichever unit is in force, so it
            // changes too — and a row that silently disagrees with the one
            // above it is worse than a rebuild.
            _updateById(AppSettingsMenu.ITEM_STEP, AppSettingsMenu.stepLabel());
            _update(item, AppSettingsMenu.unitsLabel());
            return;
        }
        if (id.equals(AppSettingsMenu.ITEM_HAPTICS)) {
            Settings.writeBoolean("haptics", !Settings.haptics());
            Settings.invalidate();
            _update(item, AppSettingsMenu.onOff(Settings.haptics()));
            return;
        }
        if (id.equals(AppSettingsMenu.ITEM_REPS)) {
            Settings.writeBoolean("repCounter", !Settings.repCounter());
            Settings.invalidate();
            _update(item, AppSettingsMenu.onOff(Settings.repCounter()));
            return;
        }
        if (id.equals(AppSettingsMenu.ITEM_ANIM)) {
            var next = Settings.animations() + 1;
            if (next > Tuning.ANIM_ON) {
                next = Tuning.ANIM_AUTO;
            }
            Settings.writeNumber("animations", next);
            Settings.invalidate();
            _update(item, AppSettingsMenu.animLabel());
            return;
        }
        if (id.equals(AppSettingsMenu.ITEM_REST_MODE)) {
            Settings.setRestMode(Settings.restMode() == Tuning.REST_OPEN
                ? Tuning.REST_TIMED
                : Tuning.REST_OPEN);
            _update(item, AppSettingsMenu.restModeLabel());
            return;
        }
        if (id.equals(AppSettingsMenu.ITEM_REST)) {
            _editing = AppSettingsMenu.ITEM_REST;
            _number(WatchUi.loadResource(Rez.Strings.RestLabel) as String, "s",
                Settings.restDefault(), 10, 900, 5, false, method(:onRest));
            return;
        }
        if (id.equals(AppSettingsMenu.ITEM_STEP)) {
            _editing = AppSettingsMenu.ITEM_STEP;
            _number(WatchUi.loadResource(Rez.Strings.WeightLabel) as String,
                Units.label().toUpper(), Settings.weightStepTenths(), 1, 250, 1, true,
                method(:onStep));
            return;
        }
    }

    public function onRest(value as Number) as Void {
        Settings.writeNumber("restDefault", value);
        Settings.invalidate();
        _rebuild();
    }

    public function onStep(value as Number) as Void {
        Settings.writeNumber("weightStepTenths", value);
        Settings.invalidate();
        _rebuild();
    }

    public function onCancel() as Void {
        _rebuild();
    }

    public function onBack() as Void {
        if (_fromSystem) {
            // The watch opened this; give it back.
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        var list = new WorkoutListView();
        WatchUi.switchToView(list, new WorkoutListDelegate(list), WatchUi.SLIDE_DOWN);
    }

    //! Change one row's sublabel where it stands.
    //!
    //! No view switch, so the cursor stays exactly where the athlete left it.
    //! Toggling three settings in a row used to mean scrolling back down twice.
    private function _update(item as WatchUi.MenuItem, sub as String) as Void {
        item.setSubLabel(sub);
        WatchUi.requestUpdate();
    }

    //! The same, for a row other than the one that was pressed.
    private function _updateById(id as String, sub as String) as Void {
        var index = _menu.findItemById(id);
        if (index < 0) {
            return;
        }
        var item = _menu.getItem(index);
        if (item != null) {
            (item as WatchUi.MenuItem).setSubLabel(sub);
        }
    }

    //! Rebuild the menu, landing on the row that was being edited.
    //!
    //! Only the number editors need this: they replace the whole view, so there
    //! is no menu left to update in place. Restoring the focus is what stops a
    //! trip into "Default rest" from dumping the athlete back at "Background".
    function _rebuild() as Void {
        var menu = AppSettingsMenu.build();
        var id = _editing;
        if (id != null && menu has :setFocus) {
            var index = menu.findItemById(id as String);
            if (index >= 0) {
                menu.setFocus(index);
            }
        }
        WatchUi.switchToView(menu, new AppSettingsDelegate(_fromSystem, menu),
            WatchUi.SLIDE_IMMEDIATE);
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
}
