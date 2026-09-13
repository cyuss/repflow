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

    //! Best guess at the muscle group, by matching the name against RepFlow's
    //! own catalogue. Only the weekly volume chart depends on it, so a miss
    //! costs a bar and never a set.
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
        return Muscle.OTHER;
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
    public function sessionToPayload(
        workout as Workout,
        startedAt as Number,
        finishedAt as Number,
        isPrivate as Boolean
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
                "description" => null,
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
