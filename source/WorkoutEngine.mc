import Toybox.Lang;

//! The flexible workout state machine.
//!
//! Design rule: navigation is **always** by stable exercise id. There is no
//! "current index" and nothing in here increments a cursor. Any exercise may be
//! selected at any time, and selecting away from a partially-finished exercise
//! preserves every set already performed.
//!
//! This class is the single writer of `Exercise.state`. The legal transitions are:
//!
//!   NOT_STARTED --select--> ACTIVE
//!   ACTIVE      --select other, 0 sets done--> NOT_STARTED
//!   ACTIVE      --select other, >0 sets done--> PENDING
//!   ACTIVE      --target sets reached--> COMPLETED
//!   ACTIVE      --deferExercise--> PENDING        ("skip for now")
//!   PENDING     --select--> ACTIVE                (resume, sets intact)
//!   any         --skipExercise--> SKIPPED
//!   any         --forceCompleteExercise--> COMPLETED
//!   SKIPPED     --select--> ACTIVE                (change of mind)
//!
//! It holds no UI, no timers and no Garmin recording state, so it is fully
//! unit-testable (see tests/WorkoutEngineTest.mc).
class WorkoutEngine {

    private var _session as WorkoutSession;

    public function initialize(session as WorkoutSession) {
        _session = session;
    }

    public function getSession() as WorkoutSession {
        return _session;
    }

    public function getWorkout() as Workout {
        return _session.workout;
    }

    public function currentExercise() as Exercise? {
        return _session.currentExercise();
    }

    public function currentExerciseId() as String? {
        return _session.currentExerciseId;
    }

    // ------------------------------------------------------------------
    // Navigation
    // ------------------------------------------------------------------

    //! Select any exercise, from anywhere, at any time.
    //! Returns false only when the id is unknown.
    public function selectExercise(exerciseId as String) as Boolean {
        var target = _session.workout.findExercise(exerciseId);
        if (target == null) {
            return false;
        }
        _releaseCurrent(exerciseId);
        target.state = EX_ACTIVE;
        _session.currentExerciseId = target.id;
        return true;
    }

    //! "Skip for now": the machine is busy. The exercise stays resumable and
    //! keeps every completed set. It is never marked completed or skipped.
    public function deferExercise(exerciseId as String) as Boolean {
        var ex = _session.workout.findExercise(exerciseId);
        if (ex == null) {
            return false;
        }
        ex.state = EX_PENDING;
        var current = _session.currentExerciseId;
        if (current != null && current.equals(exerciseId)) {
            _session.currentExerciseId = null;
        }
        return true;
    }

    //! Abandon an exercise for this session (deliberate, not temporary).
    public function skipExercise(exerciseId as String) as Boolean {
        var ex = _session.workout.findExercise(exerciseId);
        if (ex == null) {
            return false;
        }
        ex.state = EX_SKIPPED;
        var current = _session.currentExerciseId;
        if (current != null && current.equals(exerciseId)) {
            _session.currentExerciseId = null;
        }
        return true;
    }

    //! Declare an exercise finished even though the target sets were not
    //! reached. This is the ONLY way to reach COMPLETED early.
    public function forceCompleteExercise(exerciseId as String) as Boolean {
        var ex = _session.workout.findExercise(exerciseId);
        if (ex == null) {
            return false;
        }
        ex.forcedComplete = true;
        ex.state = EX_COMPLETED;
        var current = _session.currentExerciseId;
        if (current != null && current.equals(exerciseId)) {
            _session.currentExerciseId = null;
        }
        return true;
    }

    //! Move the previously selected exercise out of ACTIVE without losing state.
    private function _releaseCurrent(nextId as String?) as Void {
        var current = _session.currentExercise();
        if (current == null) {
            return;
        }
        if (nextId != null && current.id.equals(nextId)) {
            return;
        }
        if (current.state != EX_ACTIVE) {
            return; // already PENDING / SKIPPED / COMPLETED — leave it alone
        }
        if (current.hasReachedTargetSets() || current.forcedComplete) {
            current.state = EX_COMPLETED;
        } else if (current.completedSetCount() > 0) {
            current.state = EX_PENDING;
        } else {
            current.state = EX_NOT_STARTED;
        }
    }

    // ------------------------------------------------------------------
    // Performing sets
    // ------------------------------------------------------------------

    //! Record a completed set for the selected exercise.
    //! Returns null when nothing is selected.
    public function completeCurrentSet(reps as Number, weight as Float, at as Number) as WorkoutSet? {
        var ex = _session.currentExercise();
        if (ex == null) {
            return null;
        }
        var set = ex.recordSet(reps, weight, at);
        if (ex.hasReachedTargetSets()) {
            ex.state = EX_COMPLETED;
            // Stay selected: the athlete may still want to add an extra set.
        }
        return set;
    }

    //! Undo the last completed set of the selected exercise.
    public function undoLastSet() as Boolean {
        var ex = _session.currentExercise();
        if (ex == null || ex.sets.size() == 0) {
            return false;
        }
        ex.sets.remove(ex.sets[ex.sets.size() - 1]);
        ex.forcedComplete = false;
        ex.state = EX_ACTIVE;
        return true;
    }

    // ------------------------------------------------------------------
    // Queries used by the UI
    // ------------------------------------------------------------------

    //! Exercises the athlete still has work left on (not completed, not skipped).
    public function unfinishedExercises() as Array<Exercise> {
        var out = [] as Array<Exercise>;
        var list = _session.workout.exercises;
        for (var i = 0; i < list.size(); i++) {
            if (ExerciseStateUtil.isUnfinished(list[i].state)) {
                out.add(list[i]);
            }
        }
        return out;
    }

    //! True when nothing is left to do — used to decide whether ending the
    //! workout needs an extra confirmation.
    public function isWorkoutComplete() as Boolean {
        return unfinishedExercises().size() == 0;
    }

    //! What to propose next on the rest screen.
    //!
    //! Preference order: keep going on the selected exercise, then resume a
    //! PENDING one, then start the first untouched one.
    public function suggestNextExercise() as Exercise? {
        var current = _session.currentExercise();
        if (current != null && ExerciseStateUtil.isUnfinished(current.state)) {
            return current;
        }
        var list = _session.workout.exercises;
        for (var i = 0; i < list.size(); i++) {
            if (list[i].state == EX_PENDING) {
                return list[i];
            }
        }
        for (var i = 0; i < list.size(); i++) {
            if (list[i].state == EX_NOT_STARTED) {
                return list[i];
            }
        }
        return null;
    }

    // ------------------------------------------------------------------
    // Session lifecycle
    // ------------------------------------------------------------------

    public function finishWorkout(at as Number) as SessionSummary {
        _releaseCurrent(null);
        _session.currentExerciseId = null;
        _session.finishedAt = at;
        _session.state = SESSION_FINISHED;
        return _session.summary(at);
    }

    public function summary(now as Number) as SessionSummary {
        return _session.summary(now);
    }
}
