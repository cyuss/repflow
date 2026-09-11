# Testing

## Running the tests

```sh
make test                      # default device
make test DEVICE=fenix847mm
scripts/test.sh fenix6pro testWeightAndRepInheritance   # a single test
```

Tests use Garmin's **Run No Evil** framework (`Toybox.Test`). They are compiled
into the binary only when `monkeyc -t` is passed, and they execute inside the
Connect IQ Simulator, which `scripts/test.sh` starts automatically.

`monkeydo` exits 0 even when tests fail, so `scripts/test.sh` parses the summary
output and exits non-zero on failure. Full output is kept in
`build/test-<device>.log`.

## What is tested

The workout engine is pure — no UI, no storage, no `ActivityRecording` — so it
is tested directly, without the simulator's UI ever being driven.

| # | Test | What it protects |
|---|---|---|
| 1 | `testLinearCompletion` | A → B → C completes normally |
| 2 | `testSkipForNowAndReturn` | A → defer B → C → return to B |
| 3 | `testAlternatingExercises` | A1 → B1 → A2 → B2 (supersets) |
| 4 | `testCannotCompleteEarlyWithoutForcing` | `COMPLETED` is unreachable early unless forced |
| 5 | `testPendingRemainsResumable` | `PENDING` resumes mid-exercise with values intact |
| 6,7 | `testWeightAndRepInheritance` | Next set inherits the values actually performed |
| | `testInheritanceSurvivesNavigation` | Inheritance survives leaving and returning |
| 8 | `testRestTimer` | Countdown, single zero-crossing, skip, extend, clamping |
| 9 | `testSessionSummary` | Duration, sets, reps, volume, exercises worked |
| | `testEmptySessionSummary` | An untouched session reports zeros, not garbage |
| 10 | `testSessionSerializationRoundTrip` | Persistence preserves state, inheritance and flags |

Plus the invariants that are easy to regress:

| Test | What it protects |
|---|---|
| `testUntouchedExerciseReturnsToNotStarted` | Looking at an exercise does not mark it started |
| `testSkippedExercise` | `SKIPPED` unblocks completion but stays reselectable |
| `testUnknownExerciseIdIsRejected` | Bad ids are rejected, not silently applied |
| `testCompleteSetWithNoSelection` | No-op instead of a crash |
| `testExtraSetsBeyondTarget` | Extra sets are allowed and counted |
| `testUndoLastSet` | Undo removes the set and reopens the exercise |
| `testSuggestNextExercise` | "Next" prefers current → pending → fresh → none |

## Writing tests

```monkeyc
(:test)
function testSomething(logger as Test.Logger) as Boolean {
    var engine = TestSupport.newEngine();
    engine.selectExercise("A");
    Test.assertEqual(TestSupport.stateOf(engine, "A"), EX_ACTIVE);
    return true;
}
```

`tests/TestSupport.mc` provides a fixed clock (`T0`), a three-exercise A/B/C
workout with two target sets each, and helpers (`newEngine`, `stateOf`,
`exerciseOf`, `completeSets`). Tests build workouts through `TestSupport` rather
than `WorkoutRepository`, so changing the shipped workout catalogue never breaks
the suite.

Return `true` to pass; a failed `Test.assert*` throws and fails the test.

## What is *not* unit tested, and why

- **Views and delegates** — Run No Evil cannot drive button presses or assert on
  rendered pixels. Screen behaviour is covered by `docs/SMOKE_TEST.md`, which is
  a mandatory release gate.
- **`GarminRecorder`** — `ActivityRecording.createSession` needs a live device or
  simulator activity. Verified in the simulator and on the watch; AC15 in the
  smoke test covers it.
- **`SessionRepository` against real `Storage`** — the *serialisation* is fully
  tested (test 10, a true round-trip through `toStorage`/`fromStorage`), which is
  where the bugs live. The `Storage` read/write itself is a thin, exception-
  wrapped Garmin call.

## Rules

- Tests describe intended product behaviour. If a test fails, the first
  assumption is that the code is wrong.
- Never weaken or delete a test to make a build green. If a test is genuinely
  wrong, fix it deliberately and say so in the commit message.
- A bug fix gets a test that fails before the fix.
- `make package` runs the full suite and refuses to build a release if anything
  fails.
