# Manual smoke test

**This is the mandatory release gate.** No RepFlow build ships — to a watch or
to the Connect IQ Store — without a full pass, in the simulator and on a
physical watch.

Run it against a three-exercise workout. **Legs** works well (Back Squat,
Romanian Deadlift, Leg Press, …); the steps below call them A, B and C.

Record the result at the bottom of this file for each release.

---

## Steps

| # | Action | Expected |
|---|---|---|
| 1 | Launch RepFlow | Workout picker appears. UP/DOWN cycles the workouts on the watch |
| 2 | Press START on a workout | The overview opens. START again opens exercise A at `Set 1 / n`, weight and reps pre-filled from the template |
| 3 | Press BACK | The confirm screen: the set that was just performed, with its weight, reps and effort |
| 4 | Press START | Set recorded. Vibration. Rest screen counts down, shows A / Set 2 as next |
| 5 | Press BACK (rest over) | Back on A, now `Set 2 / n`, values inherited from set 1 |
| 6 | Press BACK, then UP twice, then START | Weight increased before logging; set 2 stored at the new weight |
| 7 | Press BACK (rest over), then START | Workout overview. A shows `2/n` and the active glyph |
| 8 | Select B | B opens at `Set 1 / n` |
| 9 | MENU → **Skip for now** | Returns to overview. **B shows `!` (pending), not `✓` and not `✕`** |
| 10 | Select C | C opens at `Set 1 / n` |
| 11 | Complete every set of C | After the last set, C reaches `✓` |
| 12 | Press START | Overview. A `●`/`!` partial, B `!` pending, C `✓` completed |
| 13 | Select B | **B resumes at `Set 1 / n` with its original values — nothing lost** |
| 14 | Complete every set of B | B reaches `✓` |
| 15 | Open the overview, select A | **A resumes at `Set 3 / n`, inheriting the weight from step 6** |
| 16 | Complete A's remaining sets | A reaches `✓` |
| 17 | Overview → **End workout** | Ends immediately (nothing unfinished). Summary appears |
| 18 | Press START on the summary | Activity saved; back at the workout picker |
| 19 | Review every step above | **No set, rep or weight value was lost at any point** |
| 20 | Sync and open Garmin Connect | A **strength training** activity appears with the right duration |

## Also verify

| Check | Expected |
|---|---|
| Buttons only | Disable touch (simulator: *Settings → Toggle Touch Screen*). Every step above still completes |
| Unfinished confirmation | Repeat to step 9, then End workout → **confirmation menu appears** listing the count of unfinished exercises; *Keep training* returns without changing anything |
| Interruption | Mid-workout, exit RepFlow and relaunch it → the session resumes on the same exercise with every set intact |
| Rest expiry | Let a rest timer run to 00:00 → vibrates **once**, timer turns green, does not go negative |
| Rest navigation | During rest press START → the exercise list opens, another exercise can be started immediately (this is the superset path). BACK out of that list returns to the rest, whether or not the countdown has finished |
| Summary numbers | Sets, reps and volume match what was actually performed |
| Discard | On the summary press BACK → *Discard* → no activity reaches Garmin Connect |

## Steps 9, 13 and 15 are the product

If step 8 marks B completed or skipped, if step 12 restarts B from scratch, or
if step 14 loses A's weight, **the release is blocked**. Those three steps are
the reason RepFlow exists.

---

## Results log

| Date | Version | Device | Simulator | Physical | Notes |
|---|---|---|---|---|---|
| | | | | | |
