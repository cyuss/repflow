import Toybox.Lang;

//! Lifecycle of a single exercise inside a workout session.
//!
//! These values are persisted (see SessionRepository), so the numeric values
//! are part of the on-disk format and must never be reordered.
enum ExerciseState {
    //! No set has been performed yet and the exercise is not selected.
    EX_NOT_STARTED = 0,
    //! The exercise is the one currently selected by the athlete.
    EX_ACTIVE = 1,
    //! Started or deliberately deferred ("skip for now") — still resumable.
    EX_PENDING = 2,
    //! Every target set is done, or the athlete explicitly forced completion.
    EX_COMPLETED = 3,
    //! Deliberately abandoned for this session.
    EX_SKIPPED = 4
}

//! State of the overall workout session.
enum SessionState {
    SESSION_ACTIVE = 0,
    SESSION_FINISHED = 1
}

//! Helpers for rendering and reasoning about exercise state.
module ExerciseStateUtil {

    //! Single-character glyph used by the workout overview.
    //! Matches the legend documented in README.md.
    public function glyph(state as ExerciseState) as String {
        switch (state) {
            case EX_COMPLETED:
                return "✓"; // check mark
            case EX_ACTIVE:
                return "●"; // filled circle
            case EX_PENDING:
                return "!";
            case EX_SKIPPED:
                return "✕"; // cross
            default:
                return "○"; // hollow circle
        }
    }

    //! True when the athlete still has work left on this exercise.
    public function isUnfinished(state as ExerciseState) as Boolean {
        return state != EX_COMPLETED && state != EX_SKIPPED;
    }
}
