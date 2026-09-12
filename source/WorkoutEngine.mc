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
//!   COMPLETED   --addSet--> ACTIVE or PENDING     (one more than planned)
//!   any         --substituteExercise--> SKIPPED   (moved on, sets kept)
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
    public function completeCurrentSet(reps as Number, weight as Float?, at as Number) as WorkoutSet? {
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

    // ------------------------------------------------------------------
    // Changing the workout while it is running
    //
    // The gym floor does not respect a plan: a machine is taken for the third
    // time, or an exercise turns out to feel wrong today. All three of these
    // are list operations rather than rewrites, because navigation is by stable
    // id and nothing anywhere holds a position.
    // ------------------------------------------------------------------

    //! Add an exercise that was not in the plan. Returns false on a duplicate id.
    public function addExercise(exercise as Exercise) as Boolean {
        if (_session.workout.findExercise(exercise.id) != null) {
            return false;
        }
        _session.workout.exercises.add(exercise);
        return true;
    }

    //! Replace `exerciseId` with `replacement`, in place.
    //!
    //! Sets already performed stay with the exercise they were performed on, so
    //! the old one is kept when it has any — swapping mid-exercise must not
    //! erase work. It is marked SKIPPED instead, which is the truth: the
    //! athlete moved on from it.
    public function substituteExercise(exerciseId as String, replacement as Exercise) as Boolean {
        var list = _session.workout.exercises;
        var index = _session.workout.indexOf(exerciseId);
        if (index < 0 || _session.workout.findExercise(replacement.id) != null) {
            return false;
        }
        var old = list[index];
        if (old.completedSetCount() > 0) {
            old.state = EX_SKIPPED;
            list.add(replacement);
        } else {
            // Nothing was performed, so it can simply take the old one's place
            // and its position in the plan.
            var rebuilt = [] as Array<Exercise>;
            for (var i = 0; i < list.size(); i++) {
                rebuilt.add(i == index ? replacement : list[i]);
            }
            _session.workout.exercises = rebuilt;
            if (_session.currentExerciseId != null &&
                (_session.currentExerciseId as String).equals(exerciseId)) {
                _session.currentExerciseId = replacement.id;
                replacement.state = EX_ACTIVE;
            }
        }
        return true;
    }

    //! One more set than the plan asked for, on an exercise that earned it.
    //!
    //! Raising the target is what actually happens here, because "sets done out
    //! of sets planned" is on three screens and an extra set that did not move
    //! the target would read as an off-by-one everywhere.
    public function addSet(exerciseId as String) as Boolean {
        var ex = _session.workout.findExercise(exerciseId);
        if (ex == null) {
            return false;
        }
        ex.targetSets += 1;
        ex.forcedComplete = false;
        if (ex.state == EX_COMPLETED) {
            // It has work left again, so it cannot stay COMPLETED. Which of the
            // two unfinished states it takes depends on whether the athlete is
            // standing at it right now.
            var currentId = _session.currentExerciseId;
            ex.state = (currentId != null && (currentId as String).equals(exerciseId))
                ? EX_ACTIVE
                : EX_PENDING;
        }
        return true;
    }

    //! Exercises the athlete still has work left on.
    //!
    //! This asks about *work*, not about the display state, because the two can
    //! legitimately disagree: reselecting an exercise whose sets are all done
    //! makes it ACTIVE again (so the athlete can review it or add a set), and
    //! that must not make the workout look unfinished.
    public function unfinishedExercises() as Array<Exercise> {
        var out = [] as Array<Exercise>;
        var list = _session.workout.exercises;
        for (var i = 0; i < list.size(); i++) {
            var ex = list[i];
            if (ex.state == EX_SKIPPED) {
                continue; // deliberately abandoned for this session
            }
            if (ex.hasReachedTargetSets() || ex.forcedComplete) {
                continue; // the work is done, whatever the exercise is showing
            }
            out.add(ex);
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
