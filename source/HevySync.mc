import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Application;

//! The two journeys between RepFlow and Hevy, and the screen that narrates them.
//!
//!   **Import**  routines in, once, before the gym.
//!   **Send**    the finished session out, straight after saving.
//!
//! Both are asynchronous and both can fail for a reason the athlete can fix —
//! usually "your phone is in the locker" — so neither is allowed to fail
//! silently and neither is allowed to lose anything.
//!
//! The module holds the in-flight state because a Connect IQ web callback takes
//! no context of its own worth the name, and a paged import has to remember
//! which page it is on and what it has collected so far.
module HevySync {

    //! Where the athlete's most recent load per Hevy movement is kept, so the
    //! first session on a new watch can still say what they lifted last time.
    const KEY_LAST = "hevyLast";

    const STATE_IDLE = 0;
    const STATE_IMPORTING = 1;
    const STATE_SENDING = 2;
    const STATE_DONE = 3;
    const STATE_FAILED = 4;

    var _state as Number = STATE_IDLE;
    var _message as String = "";
    //! How many routines the last import wrote, and how many the watch had no
    //! room for. Reported together, so "9 routines" never silently means
    //! "twelve, minus three you will not be told about".
    var _savedCount as Number = 0;
    var _refusedCount as Number = 0;
    var _page as Number = 1;
    var _collected as Array<Workout> = [] as Array<Workout>;
    var _sending as Dictionary? = null;
    var _view as HevyProgressView? = null;
    //! A module cannot hand `method(:onRoutines)` to a web request — there is no
    //! self to bind it to — so one object exists purely to own the callbacks.
    var _callbacks as HevyCallbacks = new HevyCallbacks();

    public function state() as Number {
        return _state;
    }

    public function message() as String {
        return _message;
    }

    // ------------------------------------------------------------------
    // Import
    // ------------------------------------------------------------------

    //! Pull every routine, page by page, and store them as RepFlow workouts.
    public function importRoutines() as Void {
        if (!HevyApi.hasKey()) {
            _fail(WatchUi.loadResource(Rez.Strings.HevyNoKey) as String);
            _show();
            return;
        }
        _state = STATE_IMPORTING;
        _message = WatchUi.loadResource(Rez.Strings.HevyImporting) as String;
        _page = 1;
        _collected = [] as Array<Workout>;
        _show();
        HevyApi.getRoutines(_page, _callbacks.method(:onRoutines));
    }

    public function onRoutines(code as Number, data as Dictionary or String or Null) as Void {
        if (!HevyApi.isSuccess(code)) {
            _fail(HevyApi.errorText(code));
            return;
        }
        if (!(data instanceof Dictionary)) {
            _fail(HevyApi.errorText(0));
            return;
        }

        var routines = (data as Dictionary)["routines"];
        var count = 0;
        if (routines instanceof Array) {
            var list = routines as Array;
            count = list.size();
            for (var i = 0; i < list.size(); i++) {
                var workout = HevyMap.routineToWorkout(list[i] as Object?);
                if (workout != null) {
                    _collected.add(workout as Workout);
                }
            }
        }

        // Stop on a short page, on an empty one, or at the safety cap. A
        // page_count that disagrees with reality must not spin forever.
        var more = count >= HevyApi.PAGE_SIZE && _page < HevyApi.MAX_PAGES;
        if (more) {
            _page++;
            _message = (WatchUi.loadResource(Rez.Strings.HevyImporting) as String) +
                " " + _collected.size().toString();
            WatchUi.requestUpdate();
            HevyApi.getRoutines(_page, _callbacks.method(:onRoutines));
            return;
        }

        _saveImported();
    }

    //! Write the fetched routines into local storage.
    //!
    //! A routine keeps Hevy's own id, so importing again after editing it in
    //! Hevy **updates** the workout on the watch rather than adding a second
    //! copy of it. That is the whole reason the id is not generated here.
    //!
    //! The watch holds a fixed number of custom workouts. More routines than
    //! that and the ones past the limit are not saved, which used to show up as
    //! a smaller number with no explanation — an import that says "9 routines"
    //! when you have twelve looks like it lost three of them at random. It now
    //! says the storage is full, because that is a thing the athlete can act on.
    function _saveImported() as Void {
        var saved = 0;
        var refused = 0;
        for (var i = 0; i < _collected.size(); i++) {
            if (WorkoutRepository.saveCustom(_collected[i])) {
                saved++;
            } else {
                refused++;
            }
        }
        _collected = [] as Array<Workout>;

        if (saved == 0) {
            _fail(refused > 0
                ? WatchUi.loadResource(Rez.Strings.HevyFull) as String
                : HevyApi.errorText(0));
            return;
        }

        _savedCount = saved;
        _refusedCount = refused;
        // History next, so "last time" works on the very first session.
        _message = WatchUi.loadResource(Rez.Strings.HevyLastTime) as String;
        WatchUi.requestUpdate();
        HevyApi.getRecentWorkouts(_callbacks.method(:onHistory));
    }

    public function onHistory(code as Number, data as Dictionary or String or Null) as Void {
        // History is a convenience. Failing to get it must not fail the import,
        // which is the part that actually matters.
        if (HevyApi.isSuccess(code) && data instanceof Dictionary) {
            var last = HevyMap.lastPerformed(data as Object?);
            if (last.size() > 0) {
                try {
                    Application.Storage.setValue(KEY_LAST,
                        last as Application.Storage.ValueType);
                } catch (e) {
                    // Nothing to do; the athlete simply gets no pre-fill.
                }
            }
        }
        _state = STATE_DONE;
        _message = _savedCount.toString() + " " +
            (WatchUi.loadResource(Rez.Strings.HevyRoutines) as String);
        if (_refusedCount > 0) {
            _message = _message + "\n" +
                (WatchUi.loadResource(Rez.Strings.HevyFull) as String);
        }
        WatchUi.requestUpdate();
    }

    //! What this movement was last done for, from Hevy, as [weightKg, reps].
    public function lastFromHevy(hevyId as String?) as Array? {
        if (hevyId == null) {
            return null;
        }
        var raw = null;
        try {
            raw = Application.Storage.getValue(KEY_LAST);
        } catch (e) {
            return null;
        }
        if (!(raw instanceof Dictionary)) {
            return null;
        }
        var row = (raw as Dictionary).get(hevyId as String);
        if (!(row instanceof Array) || (row as Array).size() < 2) {
            return null;
        }
        return row as Array;
    }

    // ------------------------------------------------------------------
    // Sending
    // ------------------------------------------------------------------

    //! Queue a finished session and try to send it.
    //!
    //! **Stored before the first attempt, cleared only on success.** Training
    //! with the phone in a locker is the normal case, not the edge case, and
    //! losing an hour of work to it would be unforgivable.
    public function sendSession(workout as Workout, startedAt as Number, finishedAt as Number) as Void {
        var isPrivate = Settings.readBoolean("privateWorkouts", true);
        var payload = HevyMap.sessionToPayload(workout, startedAt, finishedAt, isPrivate);
        if (payload == null) {
            return;         // nothing performed; nothing to log
        }
        HevyApi.savePending(payload as Dictionary);
        if (HevyApi.hasKey()) {
            _send(payload as Dictionary);
        }
    }

    //! Try the oldest queued workout again. Called on launch.
    public function sendOldestPending() as Void {
        var payload = HevyApi.oldestPending();
        if (payload == null || !HevyApi.hasKey()) {
            return;
        }
        _send(payload as Dictionary);
    }

    function _send(payload as Dictionary) as Void {
        _sending = payload;
        _state = STATE_SENDING;
        _message = WatchUi.loadResource(Rez.Strings.HevySending) as String;
        HevyApi.postWorkout(payload, _callbacks.method(:onSent));
    }

    public function onSent(code as Number, data as Dictionary or String or Null) as Void {
        var payload = _sending;
        _sending = null;

        if (HevyApi.isSuccess(code) && payload != null) {
            HevyApi.clearPending(payload as Dictionary);
            _state = STATE_DONE;
            _message = WatchUi.loadResource(Rez.Strings.HevySent) as String;
        } else {
            // It stays queued. Nothing is lost, and the next launch retries.
            _state = STATE_FAILED;
            _message = HevyApi.errorText(code);
        }
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------------
    // The screen
    // ------------------------------------------------------------------

    function _fail(text as String) as Void {
        _state = STATE_FAILED;
        _message = text;
        WatchUi.requestUpdate();
    }

    function _show() as Void {
        var view = new HevyProgressView();
        _view = view;
        WatchUi.switchToView(view, new HevyProgressDelegate(), WatchUi.SLIDE_UP);
    }
}

//! The web-request callbacks for the HevySync module. See the note on
//! `_callbacks`: a module has no self to bind a method to.
class HevyCallbacks {
    public function initialize() {
    }

    public function onRoutines(code as Number, data as Dictionary or String or Null) as Void {
        HevySync.onRoutines(code, data);
    }

    public function onHistory(code as Number, data as Dictionary or String or Null) as Void {
        HevySync.onHistory(code, data);
    }

    public function onSent(code as Number, data as Dictionary or String or Null) as Void {
        HevySync.onSent(code, data);
    }
}

//! One line of status, and nothing else.
//!
//! An import is over in a few seconds when the phone is there and never starts
//! when it is not, so a progress bar would be a lie either way. What the athlete
//! needs is the outcome and a way out.
class HevyProgressView extends WatchUi.View {

    public function initialize() {
        View.initialize();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var h = dc.getHeight();

        var y = Theme.drawFitted(dc, h / 5, "Hevy", Theme.fontsLabel(), Theme.colorAccent());

        var state = HevySync.state();
        var color = Theme.colorText();
        if (state == HevySync.STATE_FAILED) {
            color = Theme.colorHr();
        } else if (state == HevySync.STATE_DONE) {
            color = Theme.colorDone();
        }

        Theme.drawFitted(dc, y + h / 12, HevySync.message(), Theme.fontsBody(), color);

        // Unsent workouts are the one thing worth saying without being asked.
        var queued = HevyApi.pendingCount();
        if (queued > 0) {
            Theme.drawFitted(dc, h - h / 4,
                queued.toString() + " " +
                    (WatchUi.loadResource(Rez.Strings.HevyPending) as String),
                [Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
                Theme.colorDim());
        }
    }
}

class HevyProgressDelegate extends WatchUi.BehaviorDelegate {

    public function initialize() {
        BehaviorDelegate.initialize();
    }

    public function onSelect() as Boolean {
        return onBack();
    }

    //! Leaving never cancels anything that matters: an import in flight simply
    //! finishes into storage, and a queued workout stays queued.
    public function onBack() as Boolean {
        var list = new WorkoutListView();
        WatchUi.switchToView(list, new WorkoutListDelegate(list), WatchUi.SLIDE_DOWN);
        return true;
    }
}
