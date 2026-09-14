import Toybox.Lang;
import Toybox.Math;

//! Turning Hevy's JSON into RepFlow's model, and a finished session back into
//! Hevy's JSON.
//!
//! Pure — no network, no storage, no UI — so every shape Hevy can send is
//! testable without a key or a phone.
//!
//! **Nothing is assumed about the payload.** It arrives from a web service over
//! Bluetooth and is parsed by the system into Monkey C values; a missing field,
//! a string where a number was expected, or a null in a list all have to be
//! survivable, because a Monkey C runtime error is not catchable and would
//! abort the app mid-import.
module HevyMap {

    //! Hevy ids are prefixed so they can never collide with a catalogue id, and
    //! so it is obvious on sight where an exercise came from.
    const PREFIX = "h_";

    // ------------------------------------------------------------------
    // Hevy -> RepFlow
    // ------------------------------------------------------------------

    //! One routine as a RepFlow workout, or null if it is not usable.
    public function routineToWorkout(raw as Object?) as Workout? {
        if (!(raw instanceof Dictionary)) {
            return null;
        }
        var routine = raw as Dictionary;
        var id = _string(routine["id"] as Object?);
        var title = _string(routine["title"] as Object?);
        if (id == null || title == null) {
            return null;
        }

        var rawExercises = routine["exercises"];
        if (!(rawExercises instanceof Array)) {
            return null;
        }
        var list = rawExercises as Array;

        var exercises = [] as Array<Exercise>;
        var seen = {} as Dictionary;
        for (var i = 0; i < list.size(); i++) {
            var ex = _exercise(list[i] as Object?, seen);
            if (ex != null) {
                exercises.add(ex as Exercise);
            }
        }
        if (exercises.size() == 0) {
            return null;
        }
        return new Workout(PREFIX + (id as String), title as String, exercises);
    }

    function _exercise(raw as Object?, seen as Dictionary) as Exercise? {
        if (!(raw instanceof Dictionary)) {
            return null;
        }
        var data = raw as Dictionary;
        var title = _string(data["title"] as Object?);
        var templateId = _string(data["exercise_template_id"] as Object?);
        if (title == null) {
            return null;
        }

        var sets = data["sets"];
        var setCount = (sets instanceof Array) ? (sets as Array).size() : 0;
        if (setCount <= 0) {
            setCount = 1;       // a routine with no set rows still means "do it"
        }

        // Reps and load come from the first set. RepFlow carries one target per
        // exercise, not one per set; where a routine ramps, the opening value is
        // the one offered and the athlete changes it on the set itself.
        var reps = 10;
        var weight = null as Float?;
        if (sets instanceof Array && (sets as Array).size() > 0) {
            var first = (sets as Array)[0];
            if (first instanceof Dictionary) {
                var r = _number((first as Dictionary)["reps"] as Object?);
                if (r == null) {
                    // A rep range means the low end: better to be asked for one
                    // more than to be told to stop early.
                    var range = (first as Dictionary)["rep_range"];
                    if (range instanceof Dictionary) {
                        r = _number((range as Dictionary)["start"] as Object?);
                    }
                }
                if (r != null && (r as Number) > 0) {
                    reps = r as Number;
                }
                weight = _float((first as Dictionary)["weight_kg"] as Object?);
                // Hevy writes 0 where a routine sets no target load, and its
                // own app shows an empty field for those — 60 of the 102 set
                // rows in the athlete's four routines are zeros of that kind.
                //
                // Taken literally it means "open every set at nothing and dial
                // up from there", and worse, it overrides the load inherited
                // from the last time the movement was performed, which is the
                // pre-fill that makes importing worth anything. An absent
                // target is absent.
                if (weight != null && (weight as Float) <= 0.0) {
                    weight = null;
                }
            }
        }

        // rest_seconds is declared as a string in Hevy's own schema and comes
        // back as a number in practice, so both are accepted.
        var rest = _number(data["rest_seconds"] as Object?);
        var restSeconds = (rest == null || (rest as Number) < 0) ? 0 : rest as Number;

        // The same movement can appear twice in one routine. The id has to stay
        // unique inside the workout or "select any exercise at any time" cannot
        // tell them apart.
        var base = templateId == null ? _slug(title as String) : templateId as String;
        var id = PREFIX + base;
        var suffix = 1;
        while (seen.hasKey(id)) {
            suffix++;
            id = PREFIX + base + "#" + suffix.toString();
        }
        seen.put(id, true);

        var exercise = new Exercise(id, title as String, setCount, reps, weight, restSeconds);
        exercise.hevyId = templateId;
        exercise.muscle = muscleFor(title as String);
        return exercise;
    }

    //! Best guess at the muscle group: RepFlow's own catalogue first, then the
    //! words in the name.
    //!
    //! The catalogue is a list of movements someone can *build a workout from*,
    //! not a dictionary of every way a movement can be written, and Hevy writes
    //! them differently. The catalogue says "DB Shoulder Press" and "Dumbbell
    //! Curl"; Hevy says "Shoulder Press (Dumbbell)" and "Bicep Curl (Dumbbell)".
    //! Neither matched, so both landed in OTHER — and OTHER is not drawn, so the
    //! week's chart quietly lost the volume instead of misplacing it. An athlete
    //! who trained shoulders saw a page that did not mention shoulders.
    public function muscleFor(title as String) as Number {
        var lower = title.toLower();
        var groups = Muscle.browseOrder();
        for (var g = 0; g < groups.size(); g++) {
            var rows = ExerciseCatalogue.forMuscle(groups[g]);
            for (var i = 0; i < rows.size(); i++) {
                var name = ((rows[i] as Array)[ExerciseCatalogue.F_NAME] as String).toLower();
                if (lower.equals(name) || lower.find(name) != null || name.find(lower) != null) {
                    return groups[g];
                }
            }
        }
        return byKeyword(lower);
    }

    //! What the words say, when no catalogue entry matched.
    //!
    //! Written as an ordered run of tests rather than a table, because the
    //! order *is* the logic and it allocates nothing: "leg curl" has to be read
    //! before "curl" or every hamstring movement becomes a biceps one, and
    //! "lateral raise" before "row" or an upright row becomes a back exercise.
    //!
    //! Anything genuinely ambiguous is left in OTHER rather than guessed at. A
    //! missing bar is a gap; a wrong bar is a lie about what was trained.
    public function byKeyword(lower as String) as Number {
        // Legs, most specific first — "leg curl" must beat "curl".
        if (_has(lower, "leg curl") || _has(lower, "nordic") ||
            _has(lower, "good morning") || _has(lower, "romanian")) {
            return Muscle.HAMSTRINGS;
        }
        if (_has(lower, "calf") || _has(lower, "calves")) {
            return Muscle.CALVES;
        }
        if (_has(lower, "squat") || _has(lower, "lunge") ||
            _has(lower, "leg extension") || _has(lower, "leg press") ||
            _has(lower, "step-up") || _has(lower, "step up")) {
            return Muscle.QUADS;
        }
        if (_has(lower, "glute") || _has(lower, "hip thrust") ||
            _has(lower, "hip abduction")) {
            return Muscle.GLUTES;
        }

        // Arms — "pushdown" and "extension" before anything with "press".
        if (_has(lower, "tricep") || _has(lower, "pushdown") ||
            _has(lower, "skullcrusher") || _has(lower, "skull crusher")) {
            return Muscle.TRICEPS;
        }
        if (_has(lower, "curl")) {
            return Muscle.BICEPS;
        }

        // Shoulders before back, so an upright row stays a shoulder movement.
        if (_has(lower, "shoulder") || _has(lower, "delt") ||
            _has(lower, "lateral raise") || _has(lower, "front raise") ||
            _has(lower, "overhead press") || _has(lower, "upright row") ||
            _has(lower, "arnold")) {
            return Muscle.SHOULDERS;
        }
        if (_has(lower, "row") || _has(lower, "pulldown") || _has(lower, "pull-up") ||
            _has(lower, "pullup") || _has(lower, "chin-up") || _has(lower, "chinup") ||
            _has(lower, "deadlift") || _has(lower, "face pull") || _has(lower, "shrug")) {
            return Muscle.BACK;
        }
        if (_has(lower, "bench") || _has(lower, "chest") || _has(lower, "pec") ||
            _has(lower, "fly") || _has(lower, "push-up") || _has(lower, "pushup")) {
            return Muscle.CHEST;
        }
        if (_has(lower, "plank") || _has(lower, "crunch") || _has(lower, "sit-up") ||
            _has(lower, "russian twist") || _has(lower, "ab wheel") ||
            _has(lower, "leg raise")) {
            return Muscle.CORE;
        }
        return Muscle.OTHER;
    }

    function _has(haystack as String, needle as String) as Boolean {
        return haystack.find(needle) != null;
    }

    //! A stable id from a name, for the rare exercise with no template id.
    function _slug(title as String) as String {
        var out = "";
        var chars = title.toLower().toCharArray();
        for (var i = 0; i < chars.size() && out.length() < 20; i++) {
            var n = chars[i].toNumber();
            if ((n >= 97 && n <= 122) || (n >= 48 && n <= 57)) {
                out += chars[i].toString();
            }
        }
        return out.length() > 0 ? out : "x";
    }

    // ------------------------------------------------------------------
    // RepFlow -> Hevy
    // ------------------------------------------------------------------

    //! A finished session as the body of POST /v1/workouts.
    //!
    //! Only exercises with a Hevy movement id and at least one performed set are
    //! included: Hevy files a set against `exercise_template_id`, and there is
    //! nothing honest to send for an exercise that has none.
    //!
    //! A set with no load sends `weight_kg` as null, which is what Hevy's own
    //! schema asks for. Sending a zero would write a lie into the athlete's
    //! history.
    //!
    //! The effort rating is sent the same way, and is sanitised on the way out:
    //! Hevy's `rpe` is an enumeration, not a range, and one value off the ladder
    //! is answered with a 400 that loses the **whole** session, not the set. See
    //! Rpe.
    //! What Garmin measured, as a line of text for Hevy's description.
    //!
    //! Hevy carries no heart rate. Its API takes weight, reps, distance,
    //! duration, RPE and a custom metric per set, and on the workout a title, a
    //! description and the times — there is nothing physiological anywhere in
    //! it. The description is the only place these numbers can go, and putting
    //! them there beats dropping them.
    //!
    //! Null when the watch measured nothing, so a session with no strap paired
    //! gets no description rather than an empty one.
    public function describe(metrics as RecapMetrics?) as String? {
        if (metrics == null) {
            return null;
        }
        var parts = [] as Array<String>;
        var avg = (metrics as RecapMetrics).averageHeartRate;
        var peak = (metrics as RecapMetrics).maxHeartRate;
        var kcal = (metrics as RecapMetrics).calories;

        if (avg != null || peak != null) {
            var beats = avg == null
                ? (peak as Number).toString()
                : (peak == null
                    ? (avg as Number).toString()
                    : (avg as Number).toString() + " / " + (peak as Number).toString());
            parts.add("HR " + beats + " bpm");
        }
        if (kcal != null && (kcal as Number) > 0) {
            parts.add((kcal as Number).toString() + " kcal");
        }
        if (parts.size() == 0) {
            return null;
        }
        var out = parts[0];
        for (var i = 1; i < parts.size(); i++) {
            out += " - " + parts[i];
        }
        return out + " - RepFlow on Garmin";
    }

    public function sessionToPayload(
        workout as Workout,
        startedAt as Number,
        finishedAt as Number,
        isPrivate as Boolean,
        metrics as RecapMetrics?
    ) as Dictionary? {
        var exercises = [] as Array;
        var list = workout.exercises;

        for (var i = 0; i < list.size(); i++) {
            var ex = list[i];
            if (ex.hevyId == null) {
                continue;
            }
            var sets = [] as Array;
            for (var j = 0; j < ex.sets.size(); j++) {
                var set = ex.sets[j];
                if (!set.completed) {
                    continue;
                }
                sets.add({
                    "type" => "normal",
                    "weight_kg" => set.actualWeight,
                    "reps" => set.actualReps,
                    "rpe" => Rpe.sanitise(set.rpe)
                } as Object);
            }
            if (sets.size() == 0) {
                continue;
            }
            exercises.add({
                "exercise_template_id" => ex.hevyId as String,
                "superset_id" => null,
                "notes" => null,
                "sets" => sets
            } as Object);
        }

        if (exercises.size() == 0) {
            return null;       // nothing was performed; there is nothing to log
        }

        return {
            "workout" => {
                "title" => workout.name,
                "description" => describe(metrics),
                "start_time" => HevyApi.iso8601(startedAt),
                "end_time" => HevyApi.iso8601(finishedAt),
                "is_private" => isPrivate,
                "exercises" => exercises
            }
        } as Dictionary;
    }

    // ------------------------------------------------------------------
    // Hevy history -> "what did I lift last time"
    // ------------------------------------------------------------------

    //! The most recent load and reps for each movement, from a page of
    //! workouts, keyed by `exercise_template_id`.
    //!
    //! This is what makes the first session on a new watch useful: RepFlow's own
    //! history is empty then, and Hevy's is not.
    //!
    //! Newest first is what the API returns, so the first time a movement is
    //! seen is the most recent one and later ones are ignored.
    public function lastPerformed(raw as Object?) as Dictionary {
        var out = {} as Dictionary;
        if (!(raw instanceof Dictionary)) {
            return out;
        }
        var workouts = (raw as Dictionary)["workouts"];
        if (!(workouts instanceof Array)) {
            return out;
        }
        var list = workouts as Array;

        for (var w = 0; w < list.size(); w++) {
            if (!(list[w] instanceof Dictionary)) {
                continue;
            }
            var exercises = (list[w] as Dictionary)["exercises"];
            if (!(exercises instanceof Array)) {
                continue;
            }
            var exList = exercises as Array;
            for (var e = 0; e < exList.size(); e++) {
                if (!(exList[e] instanceof Dictionary)) {
                    continue;
                }
                var ex = exList[e] as Dictionary;
                var templateId = _string(ex["exercise_template_id"] as Object?);
                if (templateId == null || out.hasKey(templateId)) {
                    continue;
                }
                var sets = ex["sets"];
                if (!(sets instanceof Array)) {
                    continue;
                }
                var best = _heaviestSet(sets as Array);
                if (best != null) {
                    out.put(templateId as String, best as Array);
                }
            }
        }
        return out;
    }

    //! The heaviest completed set of an exercise, as [weightKg, reps].
    //!
    //! The heaviest rather than the last: the last set of a session is often a
    //! back-off set, and offering that as next week's opener walks the load
    //! down week after week.
    function _heaviestSet(sets as Array) as Array? {
        var bestWeight = null as Float?;
        var bestReps = 0;
        var any = false;

        for (var i = 0; i < sets.size(); i++) {
            if (!(sets[i] instanceof Dictionary)) {
                continue;
            }
            var set = sets[i] as Dictionary;
            var reps = _number(set["reps"] as Object?);
            if (reps == null || (reps as Number) <= 0) {
                continue;
            }
            var weight = _float(set["weight_kg"] as Object?);
            any = true;
            if (bestWeight == null) {
                bestWeight = weight;
                bestReps = reps as Number;
            } else if (weight != null && (weight as Float) > (bestWeight as Float)) {
                bestWeight = weight;
                bestReps = reps as Number;
            }
        }
        return any ? [bestWeight, bestReps] as Array : null;
    }

    // ------------------------------------------------------------------
    // Reading values that came off a wire
    // ------------------------------------------------------------------

    function _string(value as Object?) as String? {
        return (value instanceof String) ? value as String : null;
    }

    function _number(value as Object?) as Number? {
        if (value instanceof Number) {
            return value as Number;
        }
        if (value instanceof Float) {
            return (value as Float).toNumber();
        }
        if (value instanceof Double) {
            return (value as Double).toNumber();
        }
        if (value instanceof String) {
            var n = (value as String).toNumber();
            return n;
        }
        return null;
    }

    function _float(value as Object?) as Float? {
        if (value instanceof Float) {
            return value as Float;
        }
        if (value instanceof Number) {
            return (value as Number).toFloat();
        }
        if (value instanceof Double) {
            return (value as Double).toFloat();
        }
        return null;
    }
}
