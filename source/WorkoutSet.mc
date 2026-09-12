import Toybox.Lang;

//! One set of one exercise.
//!
//! `target*` values are what the athlete intends to do (pre-filled from the
//! previous set — see Exercise.plannedReps / plannedWeight).
//! `actual*` values are only populated once the set is completed.
class WorkoutSet {

    public var index as Number;
    public var targetReps as Number;
    //! Planned load, or null when the routine sets none.
    public var targetWeight as Float?;
    public var actualReps as Number?;
    public var actualWeight as Float?;
    public var completed as Boolean;
    //! Epoch seconds, or null while the set is not completed.
    public var completedAt as Number?;

    public function initialize(index as Number, targetReps as Number, targetWeight as Float?) {
        me.index = index;
        me.targetReps = targetReps;
        me.targetWeight = targetWeight;
        me.actualReps = null;
        me.actualWeight = null;
        me.completed = false;
        me.completedAt = null;
    }

    //! Mark this set done with the values the athlete actually performed.
    public function complete(reps as Number, weight as Float?, at as Number) as Void {
        actualReps = reps;
        actualWeight = weight;
        completed = true;
        completedAt = at;
    }

    //! Undo completion, keeping the performed values as the new targets so a
    //! mis-press does not destroy data.
    public function uncomplete() as Void {
        var reps = actualReps;
        var weight = actualWeight;
        if (reps != null) {
            targetReps = reps;
        }
        if (weight != null) {
            targetWeight = weight;
        }
        actualReps = null;
        actualWeight = null;
        completed = false;
        completedAt = null;
    }

    //! Volume contribution (kg x reps) of this set; 0 while incomplete.
    public function volume() as Float {
        var reps = actualReps;
        var weight = actualWeight;
        if (!completed || reps == null || weight == null) {
            return 0.0;
        }
        return weight * reps;
    }

    public function toStorage() as Array {
        return [index, targetReps, targetWeight, actualReps, actualWeight, completed, completedAt];
    }

    //! Storage can hand a whole number back as a Number even though it was
    //! written as a Float.
    private static function _toFloat(value as Object?) as Float? {
        if (value instanceof Float) {
            return value as Float;
        }
        if (value instanceof Number) {
            return (value as Number).toFloat();
        }
        return null;
    }

    public static function fromStorage(data as Array) as WorkoutSet {
        var weight = _toFloat(data[2] as Object?);
        var set = new WorkoutSet(data[0] as Number, data[1] as Number,
            weight != null ? weight : 0.0);
        set.actualReps = data[3] as Number?;
        set.actualWeight = _toFloat(data[4] as Object?);
        set.completed = data[5] as Boolean;
        set.completedAt = data[6] as Number?;
        return set;
    }
}
