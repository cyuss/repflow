import Toybox.Lang;

//! A workout template plus the live per-exercise state for the current session.
//!
//! Exercises are addressed by stable String id — never by list position — so the
//! athlete can move through them in any order.
class Workout {

    public var id as String;
    public var name as String;
    public var exercises as Array<Exercise>;

    public function initialize(id as String, name as String, exercises as Array<Exercise>) {
        me.id = id;
        me.name = name;
        me.exercises = exercises;
    }

    public function findExercise(exerciseId as String) as Exercise? {
        for (var i = 0; i < exercises.size(); i++) {
            if (exercises[i].id.equals(exerciseId)) {
                return exercises[i];
            }
        }
        return null;
    }

    //! Display position of an exercise, or -1. Used only for rendering order.
    public function indexOf(exerciseId as String) as Number {
        for (var i = 0; i < exercises.size(); i++) {
            if (exercises[i].id.equals(exerciseId)) {
                return i;
            }
        }
        return -1;
    }

    public function toStorage() as Dictionary {
        var raw = [] as Array;
        for (var i = 0; i < exercises.size(); i++) {
            raw.add(exercises[i].toStorage());
        }
        return { "i" => id, "n" => name, "e" => raw };
    }

    public static function fromStorage(data as Dictionary) as Workout {
        var raw = data["e"] as Array;
        var list = [] as Array<Exercise>;
        for (var i = 0; i < raw.size(); i++) {
            list.add(Exercise.fromStorage(raw[i] as Dictionary));
        }
        return new Workout(data["i"] as String, data["n"] as String, list);
    }
}
