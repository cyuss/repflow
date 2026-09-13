import Toybox.Lang;
import Toybox.Test;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Math;

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

    //! Feed the rep counter a sine-like oscillation.
    //!
    //! `reps` cycles of `samplesPerRep` samples each, swinging `amplitude`
    //! milli-g either side of gravity. It is the shape a wrist traces under a
    //! moving weight: one smooth rise and fall per repetition.
    public function feedOscillation(
        counter as RepCounter,
        reps as Number,
        samplesPerRep as Number,
        amplitude as Number
    ) as Void {
        for (var rep = 0; rep < reps; rep++) {
            for (var i = 0; i < samplesPerRep; i++) {
                var phase = (Math.PI * 2.0 * i.toFloat()) / samplesPerRep.toFloat();
                var swing = (amplitude.toFloat() * Math.sin(phase)).toNumber();
                counter.feed(
                    [0] as Array<Number>,
                    [1000 + swing] as Array<Number>,
                    [0] as Array<Number>);
            }
        }
    }

    //! An off-screen Dc the size of THIS device's screen, with its real font
    //! metrics — which is the only meaningful surface to test a layout against.
    //! Pairing one device's fonts with another device's screen size proves
    //! nothing about either.
    public function screenDc() as Graphics.Dc? {
        var settings = System.getDeviceSettings();
        var size = settings.screenHeight < settings.screenWidth
            ? settings.screenHeight
            : settings.screenWidth;
        return offscreenDc(size);
    }

    public function screenSize() as Number {
        var settings = System.getDeviceSettings();
        return settings.screenHeight < settings.screenWidth
            ? settings.screenHeight
            : settings.screenWidth;
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

    //! Assert the font chosen for `value` fits the cell it was given, and is at
    //! least `minHeight` tall — a cell that silently shrinks to a tiny font
    //! defeats the whole point of a data field.
    public function assertCellFits(
        dc as Graphics.Dc,
        value as String,
        cellWidth as Number,
        valueArea as Number,
        minHeight as Number
    ) as Void {
        var maxWidth = (cellWidth * 92) / 100;
        var font = Theme.pickFontFitting(dc, value, Theme.fontsCell(), maxWidth, valueArea);
        Test.assert(dc.getFontHeight(font) <= valueArea);
        Test.assert(dc.getTextWidthInPixels(value, font) <= maxWidth);
        Test.assert(dc.getFontHeight(font) >= minHeight);
    }

    //! Complete `count` sets of the currently selected exercise at its
    //! inherited weight/reps.
    public function completeSets(engine as WorkoutEngine, count as Number) as Void {
        for (var i = 0; i < count; i++) {
            var ex = engine.currentExercise() as Exercise;
            engine.completeCurrentSet(ex.plannedReps(), ex.plannedWeight(), null, T0 + i);
        }
    }
}
