import Toybox.Lang;

//! How hard each muscle group was worked, from the ratings the athlete gave.
//!
//! Volume answers "how much"; this answers "how hard", and they are not the
//! same question. Two hundred kilos of curls at RPE 7 and eighty kilos of them
//! at RPE 9.5 are different weeks, and only the second one explains why the
//! elbows hurt.
//!
//! **An unrated set is not an RPE of anything.** It is left out of the average
//! rather than counted as a middling effort — the same rule the rest of the app
//! follows for a null rating. A group in which nothing was rated has no
//! average, which is null, which the screen draws as a dash.
//!
//! Every set of an exercise counts once, and lands on the group the exercise
//! carries. Exercises that never got a group stay in `Muscle.OTHER` and are
//! reported there rather than being spread across the ones that did — a number
//! attributed to the wrong muscle is worse than one attributed to none.
//!
//! Pure: it takes a workout and returns arrays. Nothing here reads storage,
//! the clock or the screen.
module MuscleEffort {

    //! Mean rating per group, indexed by `Muscle.*`, null where nothing in that
    //! group was rated.
    public function averages(workout as Workout) as Array<Float?> {
        var sums = new [Muscle.COUNT] as Array<Float>;
        var counts = ratedSets(workout);
        for (var i = 0; i < Muscle.COUNT; i++) {
            sums[i] = 0.0;
        }

        var list = workout.exercises;
        for (var i = 0; i < list.size(); i++) {
            var exercise = list[i];
            var group = exercise.muscle;
            if (group < 0 || group >= Muscle.COUNT) {
                group = Muscle.OTHER;
            }
            var sets = exercise.sets;
            for (var j = 0; j < sets.size(); j++) {
                var set = sets[j];
                if (!set.completed || set.rpe == null) {
                    continue;
                }
                sums[group] += set.rpe as Float;
            }
        }

        var out = new [Muscle.COUNT] as Array<Float?>;
        for (var i = 0; i < Muscle.COUNT; i++) {
            out[i] = counts[i] > 0 ? sums[i] / counts[i] : null;
        }
        return out;
    }

    //! How many rated sets each group has. The averages are only as meaningful
    //! as this is large, and a caller that wants to say so needs the number.
    public function ratedSets(workout as Workout) as Array<Number> {
        var counts = new [Muscle.COUNT] as Array<Number>;
        for (var i = 0; i < Muscle.COUNT; i++) {
            counts[i] = 0;
        }
        var list = workout.exercises;
        for (var i = 0; i < list.size(); i++) {
            var exercise = list[i];
            var group = exercise.muscle;
            if (group < 0 || group >= Muscle.COUNT) {
                group = Muscle.OTHER;
            }
            var sets = exercise.sets;
            for (var j = 0; j < sets.size(); j++) {
                var set = sets[j];
                if (set.completed && set.rpe != null) {
                    counts[group]++;
                }
            }
        }
        return counts;
    }

    //! How many groups have an average at all. Zero means the athlete rated
    //! nothing, which is a page that should say so rather than draw an empty
    //! chart.
    public function ratedGroups(averages as Array<Float?>) as Number {
        var n = 0;
        for (var i = 0; i < averages.size(); i++) {
            if (averages[i] != null) {
                n++;
            }
        }
        return n;
    }

    //! Where a rating sits on the ladder, as 0.0 to 1.0.
    //!
    //! Measured across the scale the athlete actually uses — 6 to 10 — rather
    //! than from zero. An RPE of 6 drawn at 60% of the bar would say the set
    //! was most of the way to failure, which is the opposite of what 6 means.
    //! The bottom of the scale is the bottom of the bar, and the drawing keeps
    //! a visible stub so "the easiest thing I did" never reads as "nothing".
    public function position(value as Float?) as Float {
        if (value == null) {
            return 0.0;
        }
        var low = Rpe.SCALE[0];
        var high = Rpe.SCALE[Rpe.SCALE.size() - 1];
        var span = high - low;
        if (span <= 0.0) {
            return 0.0;
        }
        var t = ((value as Float) - low) / span;
        if (t < 0.0) {
            return 0.0;
        }
        return t > 1.0 ? 1.0 : t;
    }
}
