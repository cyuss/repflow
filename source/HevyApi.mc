import Toybox.Lang;
import Toybox.Communications;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

//! The Hevy public REST API, and the queue that stops a workout being lost.
//!
//! Authentication is a per-account key sent in an `api-key` header. It requires
//! a Hevy Pro account; there is no OAuth and nothing to register.
//!
//! **Everything here is unforgiving about failure, because the thing at stake
//! is an hour of the athlete's training.** A workout is written to storage
//! before the first send is even attempted, and is removed only when Hevy has
//! confirmed it. Training with the phone in a locker — which is the normal gym
//! case, not the edge case — must cost nothing.
module HevyApi {

    const BASE = "https://api.hevyapp.com/v1";

    //! Hevy caps /v1/routines at ten per page. Verified in their OpenAPI spec:
    //! "Number of items on the requested page (Max 10)".
    const PAGE_SIZE = 10;
    //! Safety net, so a broken page_count cannot spin forever.
    const MAX_PAGES = 6;
    //! Recent workouts fetched for "what did I lift last time". Deliberately
    //! small: a big page is a slow Bluetooth transfer and can exceed the
    //! response size a watch can hold.
    const HISTORY_WORKOUTS = 5;
    //! Unsent workouts kept. More than this and something is badly wrong.
    const MAX_PENDING = 5;

    const KEY_STORAGE = "hevyApiKey";
    const KEY_PENDING = "hevyPending";

    // ------------------------------------------------------------------
    // The key
    // ------------------------------------------------------------------

    //! The key, from wherever it was set.
    //!
    //! Three places, in the order of who said it most recently and most
    //! deliberately: Storage is what the watch itself wrote, Properties is what
    //! the phone wrote, and the compiled-in key is what the build carried.
    //!
    //! The last of those exists because a property's default reaches the watch
    //! **only on a first install**. An update keeps whatever the property
    //! already held, so a watch that had RepFlow before the key existed kept the
    //! empty string and reported "No API key" while the key sat unread inside
    //! that very build. A constant has no such history — and being read last, it
    //! never overrides a key the athlete entered themselves.
    public function apiKey() as String {
        var stored = normalize(Application.Storage.getValue(KEY_STORAGE));
        if (stored != null) {
            return stored as String;
        }
        var fromPhone = null;
        try {
            fromPhone = Application.Properties.getValue(KEY_STORAGE);
        } catch (e) {
            fromPhone = null;
        }
        var phone = normalize(fromPhone);
        if (phone != null) {
            return phone as String;
        }
        var built = normalize(HevyKey.compiled());
        return built == null ? "" : built as String;
    }

    public function hasKey() as Boolean {
        return apiKey().length() > 0;
    }

    public function saveKey(key as String) as Void {
        try {
            Application.Storage.setValue(KEY_STORAGE, key);
        } catch (e) {
            // A key that will not persist is one the athlete retypes; nothing
            // else breaks.
        }
    }

    //! Turn whatever was typed or pasted into Hevy's canonical 8-4-4-4-12 form.
    //!
    //! Returns null when it is not 32 letters and digits. Hyphens and spaces are
    //! discarded on the way in and re-inserted on the way out, because a watch
    //! keyboard has no hyphen and a pasted key often carries stray whitespace —
    //! either of which would otherwise produce a silent 401.
    public function normalize(input as Object?) as String? {
        if (!(input instanceof String)) {
            return null;
        }
        var core = _alnum(input as String);
        if (core.length() != 32) {
            return null;
        }
        return core.substring(0, 8) + "-" + core.substring(8, 12) + "-" +
            core.substring(12, 16) + "-" + core.substring(16, 20) + "-" +
            core.substring(20, 32);
    }

    function _alnum(s as String) as String {
        var out = "";
        var chars = s.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var n = chars[i].toNumber();
            if ((n >= 48 && n <= 57) || (n >= 65 && n <= 90) || (n >= 97 && n <= 122)) {
                out += chars[i].toString();
            }
        }
        return out;
    }

    // ------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------

    //! What went wrong, in words the athlete can act on.
    //!
    //! The sign of the code is the first thing to read: **negative codes are
    //! Connect IQ transport errors** — the phone is away, Bluetooth is off, the
    //! request timed out — and **positive ones are HTTP statuses from Hevy**.
    //! Telling them apart is the difference between "move closer to your phone"
    //! and "your key is wrong".
    public function errorText(code as Number) as String {
        if (code == 401 || code == 403) {
            return WatchUi.loadResource(Rez.Strings.HevyErrKey) as String;
        }
        if (code == 429) {
            return WatchUi.loadResource(Rez.Strings.HevyErrRate) as String;
        }
        if (code >= 500) {
            return WatchUi.loadResource(Rez.Strings.HevyErrServer) as String;
        }
        if (code <= 0) {
            return WatchUi.loadResource(Rez.Strings.HevyErrPhone) as String;
        }
        return (WatchUi.loadResource(Rez.Strings.HevyErrGeneric) as String) + " " +
            code.toString();
    }

    public function isKeyError(code as Number) as Boolean {
        return code == 401 || code == 403;
    }

    public function isSuccess(code as Number) as Boolean {
        return code == 200 || code == 201;
    }

    // ------------------------------------------------------------------
    // Requests
    // ------------------------------------------------------------------

    //! What every response callback looks like. The option dictionaries are
    //! written out at each call site rather than shared, because the type
    //! checker only accepts the literal — a Dictionary passed by variable
    //! loses the shape it needs to match.
    typedef Responder as Method(responseCode as Number,
        data as Dictionary or String or Null) as Void;

    //! One page of routines, exercises and sets inline.
    public function getRoutines(page as Number, callback as Responder) as Void {
        Communications.makeWebRequest(BASE + "/routines",
            { "page" => page, "pageSize" => PAGE_SIZE } as Dictionary<Object, Object>,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => { "api-key" => apiKey(), "Accept" => "application/json" },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            callback);
    }

    //! The most recent workouts, for pre-filling what was lifted last time.
    public function getRecentWorkouts(callback as Responder) as Void {
        Communications.makeWebRequest(BASE + "/workouts",
            { "page" => 1, "pageSize" => HISTORY_WORKOUTS } as Dictionary<Object, Object>,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => { "api-key" => apiKey(), "Accept" => "application/json" },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            callback);
    }

    //! Log a finished workout. `payload` is the whole { "workout": {...} }.
    public function postWorkout(payload as Dictionary, callback as Responder) as Void {
        Communications.makeWebRequest(BASE + "/workouts",
            payload as Dictionary<Object, Object>,
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "api-key" => apiKey(),
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            callback);
    }

    // ------------------------------------------------------------------
    // Time
    // ------------------------------------------------------------------

    //! Epoch seconds as the ISO 8601 UTC string Hevy expects, e.g.
    //! "2024-08-14T12:00:00Z". Built by hand because Monkey C has no formatter
    //! that produces it.
    public function iso8601(epochSeconds as Number) as String {
        var info = Gregorian.utcInfo(new Time.Moment(epochSeconds), Time.FORMAT_SHORT);
        // Gregorian.Info types every field as nullable, and `month` can be a
        // String under other formats. FORMAT_SHORT gives numbers; each one is
        // pulled out and defaulted so a null cannot reach `.format`.
        return _pad(info.year, 4) + "-" + _pad(info.month, 2) + "-" +
            _pad(info.day, 2) + "T" + _pad(info.hour, 2) + ":" +
            _pad(info.min, 2) + ":" + _pad(info.sec, 2) + "Z";
    }

    function _pad(value as Object?, width as Number) as String {
        var n = 0;
        if (value instanceof Number) {
            n = value as Number;
        } else if (value instanceof Float) {
            n = (value as Float).toNumber();
        }
        var out = n.toString();
        while (out.length() < width) {
            out = "0" + out;
        }
        return out;
    }

    // ------------------------------------------------------------------
    // The pending queue
    // ------------------------------------------------------------------

    //! Every workout written but not yet confirmed by Hevy.
    //!
    //! A queue and not a single slot: finishing a second workout while the
    //! first is still unsent must not overwrite the first.
    public function pending() as Array {
        var raw = null;
        try {
            raw = Application.Storage.getValue(KEY_PENDING);
        } catch (e) {
            return [] as Array;
        }
        if (raw instanceof Array) {
            return raw as Array;
        }
        return [] as Array;
    }

    public function pendingCount() as Number {
        return pending().size();
    }

    //! Add a payload, or replace the one with the same start time.
    //!
    //! Matching on start time is what lets a summary screen be reopened, or a
    //! send retried, without the same session queueing twice.
    public function savePending(payload as Dictionary) as Void {
        var list = pending();
        var key = startTimeOf(payload);
        for (var i = 0; i < list.size(); i++) {
            if (startTimeOf(list[i] as Object?).equals(key)) {
                list[i] = payload as Object;
                _writePending(list);
                return;
            }
        }
        list.add(payload as Object);
        while (list.size() > MAX_PENDING) {
            list.remove(list[0] as Object);
        }
        _writePending(list);
    }

    //! Drop the entry Hevy has confirmed, found by its start time.
    public function clearPending(payload as Dictionary) as Void {
        var key = startTimeOf(payload);
        var list = pending();
        var kept = [] as Array;
        for (var i = 0; i < list.size(); i++) {
            if (!startTimeOf(list[i] as Object?).equals(key)) {
                kept.add(list[i] as Object);
            }
        }
        _writePending(kept);
    }

    //! The oldest unsent workout, or null.
    public function oldestPending() as Dictionary? {
        var list = pending();
        if (list.size() == 0) {
            return null;
        }
        var first = list[0];
        return (first instanceof Dictionary) ? first as Dictionary : null;
    }

    public function clearAllPending() as Void {
        _writePending([] as Array);
    }

    public function startTimeOf(payload as Object?) as String {
        if (!(payload instanceof Dictionary)) {
            return "";
        }
        var workout = (payload as Dictionary)["workout"];
        if (!(workout instanceof Dictionary)) {
            return "";
        }
        var start = (workout as Dictionary)["start_time"];
        return (start instanceof String) ? start as String : "";
    }

    //! The title of a queued workout, for telling the athlete what is waiting.
    public function titleOf(payload as Object?) as String {
        if (!(payload instanceof Dictionary)) {
            return "";
        }
        var workout = (payload as Dictionary)["workout"];
        if (!(workout instanceof Dictionary)) {
            return "";
        }
        var title = (workout as Dictionary)["title"];
        return (title instanceof String) ? title as String : "";
    }

    function _writePending(list as Array) as Void {
        try {
            Application.Storage.setValue(KEY_PENDING, list as Application.Storage.ValueType);
        } catch (e) {
            // Storage refused. The workout is still in memory for this run.
        }
    }
}
