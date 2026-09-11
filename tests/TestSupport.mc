import Toybox.Lang;
import Toybox.Test;
import Toybox.Graphics;

//! Shared helpers for the RepFlow unit tests.
//!
//! These build workouts directly rather than going through WorkoutRepository so
//! the tests stay independent of the shipped workout catalogue.
(:test)
module TestSupport {

    //! Fixed clock so completedAt values are deterministic.
    const T0 = 1700000000;

    //! Three exercises, A/B/C, 2 target sets each — the shape used by the
    //! arbitrary-navigation scenarios in docs/SMOKE_TEST.md.
    public function abcWorkout() as Workout {
        return new Workout("w_test", "Test", [
            new Exercise("A", "Exercise A", 2, 10, 50.0, 90),
            new Exercise("B", "Exercise B", 2, 12, 40.0, 60),
            new Exercise("C", "Exercise C", 2, 8, 60.0, 120)
        ] as Array<Exercise>);
    }

    public function newEngine() as WorkoutEngine {
        return new WorkoutEngine(new WorkoutSession(abcWorkout(), T0));
    }

    public function stateOf(engine as WorkoutEngine, id as String) as ExerciseState {
        var ex = engine.getWorkout().findExercise(id);
        return (ex as Exercise).state;
    }

    public function exerciseOf(engine as WorkoutEngine, id as String) as Exercise {
        return engine.getWorkout().findExercise(id) as Exercise;
    }

    //! An off-screen Dc with the running device's real font metrics, for the
    //! layout tests.
    //!
    //! Graphics.createBufferedBitmap is API 4.0; a Fenix 6 Pro is API 3.4 and
    //! only has the BufferedBitmap constructor. Returns null where neither is
    //! available, so the caller can skip rather than fail.
    public function offscreenDc(size as Number) as Graphics.Dc? {
        if (Graphics has :createBufferedBitmap) {
            var ref = Graphics.createBufferedBitmap({ :width => size, :height => size });
            var buffered = ref.get();
            if (buffered == null) {
                return null;
            }
            return (buffered as Graphics.BufferedBitmap).getDc();
        }
        if (Graphics has :BufferedBitmap) {
            var bitmap = new Graphics.BufferedBitmap({ :width => size, :height => size });
            return bitmap.getDc();
        }
        return null;
    }

    //! Complete `count` sets of the currently selected exercise at its
    //! inherited weight/reps.
    public function completeSets(engine as WorkoutEngine, count as Number) as Void {
        for (var i = 0; i < count; i++) {
            var ex = engine.currentExercise() as Exercise;
            engine.completeCurrentSet(ex.plannedReps(), ex.plannedWeight(), T0 + i);
        }
    }
}
