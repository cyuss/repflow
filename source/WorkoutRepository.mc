import Toybox.Lang;

//! Built-in workout templates.
//!
//! V0.1 ships a fixed catalogue. A future version will let the athlete edit
//! workouts and persist them (see docs/ARCHITECTURE.md, roadmap V0.2+), which is
//! why callers always go through this repository rather than constructing
//! Workout objects directly.
module WorkoutRepository {

    //! Fresh, unstarted copies of every built-in workout.
    //! Each call allocates new objects so a previous session's state never leaks.
    public function all() as Array<Workout> {
        return [
            backAndTriceps(),
            chestAndBiceps(),
            legs()
        ] as Array<Workout>;
    }

    public function count() as Number {
        return 3;
    }

    //! Load a single template by id, or null.
    public function byId(workoutId as String) as Workout? {
        var list = all();
        for (var i = 0; i < list.size(); i++) {
            if (list[i].id.equals(workoutId)) {
                return list[i];
            }
        }
        return null;
    }

    public function backAndTriceps() as Workout {
        return new Workout("w_back_tri", "Back + Triceps", [
            new Exercise("e_lat_pulldown", "Lat Pulldown", 4, 10, 55.0, 90),
            new Exercise("e_seated_row", "Seated Row", 4, 10, 60.0, 90),
            new Exercise("e_face_pull", "Face Pull", 4, 12, 25.0, 60),
            new Exercise("e_triceps_pushdown", "Triceps Pushdown", 4, 10, 30.0, 60)
        ] as Array<Exercise>);
    }

    public function chestAndBiceps() as Workout {
        return new Workout("w_chest_bi", "Chest + Biceps", [
            new Exercise("e_bench_press", "Bench Press", 4, 8, 70.0, 120),
            new Exercise("e_incline_db", "Incline DB Press", 3, 10, 24.0, 90),
            new Exercise("e_cable_fly", "Cable Fly", 3, 12, 15.0, 60),
            new Exercise("e_barbell_curl", "Barbell Curl", 3, 10, 30.0, 60),
            new Exercise("e_hammer_curl", "Hammer Curl", 3, 12, 14.0, 60)
        ] as Array<Exercise>);
    }

    public function legs() as Workout {
        return new Workout("w_legs", "Legs", [
            new Exercise("e_back_squat", "Back Squat", 5, 5, 90.0, 180),
            new Exercise("e_rdl", "Romanian Deadlift", 4, 8, 80.0, 120),
            new Exercise("e_leg_press", "Leg Press", 4, 10, 140.0, 90),
            new Exercise("e_leg_curl", "Leg Curl", 3, 12, 40.0, 60),
            new Exercise("e_calf_raise", "Calf Raise", 4, 15, 60.0, 45)
        ] as Array<Exercise>);
    }
}
