import Toybox.Lang;

//! Aggregated numbers shown on the end-of-workout screen.
class SessionSummary {
    public var durationSec as Number;
    public var exerciseCount as Number;
    public var exercisesWorked as Number;
    public var completedSets as Number;
    public var totalReps as Number;
    public var totalVolume as Float;

    public function initialize() {
        durationSec = 0;
        exerciseCount = 0;
        exercisesWorked = 0;
        completedSets = 0;
        totalReps = 0;
        totalVolume = 0.0;
    }
}

//! One training session: a workout, when it ran, and which exercise is selected.
class WorkoutSession {

    public var workout as Workout;
    //! Epoch seconds.
    public var startedAt as Number;
    public var finishedAt as Number?;
    //! Stable id of the selected exercise, or null when none is selected.
    public var currentExerciseId as String?;
    public var state as SessionState;

    public function initialize(workout as Workout, startedAt as Number) {
        me.workout = workout;
        me.startedAt = startedAt;
        me.finishedAt = null;
        me.currentExerciseId = null;
        me.state = SESSION_ACTIVE;
    }

    public function currentExercise() as Exercise? {
        var id = currentExerciseId;
        if (id == null) {
            return null;
        }
        return workout.findExercise(id);
    }

    public function summary(now as Number) as SessionSummary {
        var s = new SessionSummary();
        var end = finishedAt != null ? finishedAt as Number : now;
        s.durationSec = end - startedAt;
        if (s.durationSec < 0) {
            s.durationSec = 0;
        }
        var list = workout.exercises;
        s.exerciseCount = list.size();
        for (var i = 0; i < list.size(); i++) {
            var ex = list[i];
            var done = ex.completedSetCount();
            if (done > 0) {
                s.exercisesWorked++;
            }
            s.completedSets += done;
            s.totalReps += ex.totalReps();
            s.totalVolume += ex.totalVolume();
        }
        return s;
    }

    public function toStorage() as Dictionary {
        return {
            "w" => workout.toStorage(),
            "s" => startedAt,
            "f" => finishedAt,
            "c" => currentExerciseId,
            "st" => state as Number
        };
    }

    public static function fromStorage(data as Dictionary) as WorkoutSession {
        var session = new WorkoutSession(
            Workout.fromStorage(data["w"] as Dictionary),
            data["s"] as Number
        );
        session.finishedAt = data["f"] as Number?;
        session.currentExerciseId = data["c"] as String?;
        session.state = data["st"] as SessionState;
        return session;
    }
}
