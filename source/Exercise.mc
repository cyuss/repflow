import Toybox.Lang;

//! A single exercise and every set performed for it during this session.
//!
//! `state` is written **only** by WorkoutEngine, through the explicit
//! transitions documented there. Nothing else mutates it.
class Exercise {

    public var id as String;
    public var name as String;
    public var targetSets as Number;
    public var targetReps as Number;
    public var defaultWeight as Float;
    //! Rest between sets, in seconds.
    public var restDuration as Number;
    public var sets as Array<WorkoutSet>;
    public var state as ExerciseState;
    //! True when the athlete explicitly declared the exercise finished before
    //! all target sets were performed.
    public var forcedComplete as Boolean;

    public function initialize(
        id as String,
        name as String,
        targetSets as Number,
        targetReps as Number,
        defaultWeight as Float,
        restDuration as Number
    ) {
        me.id = id;
        me.name = name;
        me.targetSets = targetSets;
        me.targetReps = targetReps;
        me.defaultWeight = defaultWeight;
        me.restDuration = restDuration;
        me.sets = [] as Array<WorkoutSet>;
        me.state = EX_NOT_STARTED;
        me.forcedComplete = false;
    }

    public function completedSetCount() as Number {
        var n = 0;
        for (var i = 0; i < sets.size(); i++) {
            if (sets[i].completed) {
                n++;
            }
        }
        return n;
    }

    //! True once the target number of sets has been performed.
    //! This is the *only* natural route to EX_COMPLETED.
    public function hasReachedTargetSets() as Boolean {
        return completedSetCount() >= targetSets;
    }

    //! 1-based number of the set the athlete is about to perform.
    public function currentSetNumber() as Number {
        var done = completedSetCount();
        return done < targetSets ? done + 1 : targetSets;
    }

    //! The last set the athlete completed, or null.
    public function lastCompletedSet() as WorkoutSet? {
        for (var i = sets.size() - 1; i >= 0; i--) {
            if (sets[i].completed) {
                return sets[i];
            }
        }
        return null;
    }

    //! Reps the next set should be pre-filled with: inherit from the last set
    //! actually performed, otherwise fall back to the exercise target.
    public function plannedReps() as Number {
        var last = lastCompletedSet();
        if (last != null) {
            var reps = last.actualReps;
            if (reps != null) {
                return reps;
            }
        }
        return targetReps;
    }

    //! Weight the next set should be pre-filled with — same inheritance rule.
    public function plannedWeight() as Float {
        var last = lastCompletedSet();
        if (last != null) {
            var weight = last.actualWeight;
            if (weight != null) {
                return weight;
            }
        }
        return defaultWeight;
    }

    //! Record a performed set. Returns the set that was created.
    public function recordSet(reps as Number, weight as Float, at as Number) as WorkoutSet {
        var set = new WorkoutSet(sets.size(), reps, weight);
        set.complete(reps, weight, at);
        sets.add(set);
        return set;
    }

    public function totalReps() as Number {
        var n = 0;
        for (var i = 0; i < sets.size(); i++) {
            var reps = sets[i].actualReps;
            if (sets[i].completed && reps != null) {
                n += reps;
            }
        }
        return n;
    }

    public function totalVolume() as Float {
        var v = 0.0;
        for (var i = 0; i < sets.size(); i++) {
            v += sets[i].volume();
        }
        return v;
    }

    public function toStorage() as Dictionary {
        var rawSets = [] as Array;
        for (var i = 0; i < sets.size(); i++) {
            rawSets.add(sets[i].toStorage());
        }
        return {
            "i" => id,
            "n" => name,
            "ts" => targetSets,
            "tr" => targetReps,
            "w" => defaultWeight,
            "r" => restDuration,
            "st" => state as Number,
            "fc" => forcedComplete,
            "s" => rawSets
        };
    }

    //! Storage can hand a whole number back as a Number even though it was
    //! written as a Float.
    private static function _toFloat(value as Object?) as Float {
        if (value instanceof Float) {
            return value as Float;
        }
        if (value instanceof Number) {
            return (value as Number).toFloat();
        }
        return 0.0;
    }

    public static function fromStorage(data as Dictionary) as Exercise {
        var ex = new Exercise(
            data["i"] as String,
            data["n"] as String,
            data["ts"] as Number,
            data["tr"] as Number,
            _toFloat(data["w"] as Object?),
            data["r"] as Number
        );
        ex.state = data["st"] as ExerciseState;
        ex.forcedComplete = data["fc"] as Boolean;
        var rawSets = data["s"] as Array;
        for (var i = 0; i < rawSets.size(); i++) {
            ex.sets.add(WorkoutSet.fromStorage(rawSets[i] as Array));
        }
        return ex;
    }
}
