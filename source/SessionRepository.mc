import Toybox.Lang;
import Toybox.Application.Storage;

//! Persistence for RepFlow's own data, kept deliberately separate from Garmin's
//! FIT recording (see GarminRecorder and docs/API_LIMITATIONS.md).
//!
//! Two things are stored:
//!   * KEY_ACTIVE  — the in-progress session, rewritten after every set so the
//!                   workout survives an app restart or a crash mid-workout.
//!   * KEY_HISTORY — a compact ring buffer of finished sessions.
//!
//! Everything here is best-effort: a storage failure must never interrupt a
//! workout, so writes are wrapped and failures are swallowed after being logged.
module SessionRepository {

    const KEY_ACTIVE = "active";
    const KEY_HISTORY = "history";

    //! Connect IQ limits the size of a single stored value and total app
    //! storage. Keep history short and summary-only.
    const MAX_HISTORY = 20;

    // ------------------------------------------------------------------
    // Active session
    // ------------------------------------------------------------------

    public function saveActive(session as WorkoutSession) as Boolean {
        try {
            Storage.setValue(KEY_ACTIVE, session.toStorage() as Storage.ValueType);
            return true;
        } catch (e) {
            return false;
        }
    }

    //! Restore an interrupted session, or null when there is nothing to resume.
    public function loadActive() as WorkoutSession? {
        try {
            var raw = Storage.getValue(KEY_ACTIVE);
            if (raw == null || !(raw instanceof Dictionary)) {
                return null;
            }
            var session = WorkoutSession.fromStorage(raw as Dictionary);
            if (session.state == SESSION_FINISHED) {
                return null;
            }
            return session;
        } catch (e) {
            // Corrupt or written by an older schema — drop it rather than crash.
            clearActive();
            return null;
        }
    }

    public function clearActive() as Void {
        try {
            Storage.deleteValue(KEY_ACTIVE);
        } catch (e) {
            // nothing useful to do
        }
    }

    // ------------------------------------------------------------------
    // History
    // ------------------------------------------------------------------

    //! Append a finished session's summary. Only aggregates are kept so history
    //! stays small regardless of how many sets were performed.
    public function appendHistory(session as WorkoutSession, summary as SessionSummary) as Boolean {
        try {
            var entry = {
                "w" => session.workout.name,
                "s" => session.startedAt,
                "d" => summary.durationSec,
                "e" => summary.exercisesWorked,
                "c" => summary.completedSets,
                "r" => summary.totalReps,
                "v" => summary.totalVolume
            };
            var history = loadHistory();
            history.add(entry as Object);
            while (history.size() > MAX_HISTORY) {
                history.remove(history[0] as Object);
            }
            Storage.setValue(KEY_HISTORY, history as Storage.ValueType);
            return true;
        } catch (e) {
            return false;
        }
    }

    public function loadHistory() as Array {
        try {
            var raw = Storage.getValue(KEY_HISTORY);
            if (raw == null || !(raw instanceof Array)) {
                return [] as Array;
            }
            return raw as Array;
        } catch (e) {
            return [] as Array;
        }
    }

    public function clearHistory() as Void {
        try {
            Storage.deleteValue(KEY_HISTORY);
        } catch (e) {
            // nothing useful to do
        }
    }
}
