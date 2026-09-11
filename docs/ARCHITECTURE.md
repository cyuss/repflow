# Architecture

## Layers

```
                +---------------------------------------+
   UI           |  WorkoutListView   ExerciseView       |
                |  RestView          WorkoutOverviewView|
                |  ValueEditorView   WorkoutSummaryView |
                |  ExerciseActionsMenu  EndWorkoutFlow  |
                +------------------+--------------------+
                                   |  (views render state, forward presses)
                +------------------v--------------------+
   Coordination |            AppController              |
                |  owns engine, rest timer, recorder,   |
                |  persistence and screen transitions   |
                +----+----------+-----------+-----------+
                     |          |           |
        +------------v--+  +----v------+  +-v-------------------+
   Domain| WorkoutEngine |  | RestTimer |  | GarminRecorder      |
        | Workout       |  | (pure)    |  | ActivityRecording   |
        | Exercise      |  +-----------+  | FitContributor      |
        | WorkoutSet    |                 +---------------------+
        | WorkoutSession|
        +-------+-------+                 +---------------------+
                |                         | SessionRepository   |
                +------------------------>| WorkoutRepository   |
                                          | Application.Storage |
                                          +---------------------+
```

Dependencies point **downward only**:

- The domain (`WorkoutEngine` and the model classes) imports `Toybox.Lang` and
  nothing else. No UI, no timers, no storage, no `ActivityRecording`. This is
  what makes it unit-testable.
- `RestTimer` is a pure countdown driven by an injected `tick()`. The real
  1 Hz `Toybox.Timer` lives in `AppController`.
- `GarminRecorder` is the only file that touches `ActivityRecording`.
- `SessionRepository` is the only file that touches `Application.Storage`.
- Views never call storage or recording directly.

## Files

| File | Responsibility |
|---|---|
| `RepFlowApp.mc` | `AppBase`; chooses the initial view, restores an interrupted session |
| `AppController.mc` | Wiring and screen transitions; the only stateful singleton |
| `ExerciseState.mc` | `ExerciseState` / `SessionState` enums + glyph helpers |
| `WorkoutSet.mc` | One set: target vs actual reps/weight, completion |
| `Exercise.mc` | An exercise and its sets; **value inheritance** rules |
| `Workout.mc` | Exercise collection, lookup by stable id |
| `WorkoutSession.mc` | One session; `SessionSummary` aggregation |
| `WorkoutEngine.mc` | The state machine. Sole writer of `Exercise.state` |
| `RestTimer.mc` | Pure countdown state |
| `WorkoutRepository.mc` | Built-in workout catalogue |
| `SessionRepository.mc` | Persistence: active session + history |
| `GarminRecorder.mc` | `ActivityRecording` + developer FIT fields |
| `Theme.mc` | Colours, fonts, formatting, adaptive text drawing |
| `*View.mc` | Screens (drawn in code, not XML layouts) |

## Why navigation is by id, never by index

The product promise is arbitrary ordering, so `WorkoutEngine` has **no cursor**
and nothing in it increments an index. Every navigation call takes a `String`
exercise id and looks the exercise up. This makes the following sequence
ordinary rather than a special case:

```
A set 1 → B set 1 → A set 2 → C set 1 → B set 2
```

`WorkoutEngine` is the single writer of `Exercise.state`, through named
transitions (`selectExercise`, `deferExercise`, `skipExercise`,
`forceCompleteExercise`, `completeCurrentSet`, `undoLastSet`). The legal
transitions are listed in the class comment. Keeping one writer is what stops
state from drifting as screens come and go.

### The one non-obvious rule

Navigating *away* from the active exercise does not lose it — `_releaseCurrent`
decides where it lands:

- target sets reached, or forced → `COMPLETED`
- at least one set performed → `PENDING` (resumable)
- nothing performed → back to `NOT_STARTED`

That last case matters: merely *looking* at an exercise must not mark it
started.

## Why screens are drawn in code

No XML layouts. The screens are simple (a title, one or two big numbers, an
action label) and `Theme.drawFitted` picks the largest font from a ladder that
fits the available width. One code path scales from the Fenix 6 Pro's 240×240
to the Fenix 8's 454×454 without a per-device layout file, which keeps both the
memory footprint and the device matrix small.

`WatchUi.Menu2` is used for the overview and the action menus so scrolling,
touch and button input behave exactly like the rest of the watch.

## Navigation model

RepFlow keeps a **flat view stack**: screens replace each other with
`WatchUi.switchToView` rather than stacking with `pushView`. Garmin's own
`Menu2Sample` does the same with `Menu2`, and it means BACK can be given a
meaningful destination on every screen instead of unwinding an unpredictable
stack.

One consequence worth knowing: `WatchUi.Confirmation` pops itself once its
delegate returns, which fights `switchToView`. `EndWorkoutFlow` therefore uses
a two-item `Menu2` as its confirmation instead.

## Persistence strategy

`SessionRepository.saveActive()` runs after every state-changing action — set
completed, exercise selected, deferred, forced complete, undone — and on
`onStop()`. The cost is one small `Storage.setValue` per interaction, which is
well inside the budget, and the benefit is that a crash or an accidental exit
costs at most nothing.

On launch, `RepFlowApp.getInitialView()` prefers a restored session over the
workout picker, landing straight back on the exercise that was active.

## Memory discipline

- No allocation in `onUpdate` beyond the strings being drawn.
- Session state is serialised with one-character keys.
- History stores aggregates only, capped at 20 entries.
- Views are constructed on transition, not held in fields.

## Extension points (deliberately not built yet)

- **Editable / synced workouts** — `WorkoutRepository` is already the single
  source of workouts, so adding a persisted user catalogue is a change to one
  module.
- **Last-session values and PRs** — `SessionRepository` history already stores
  per-session aggregates; per-exercise history slots in beside it.
- **Supersets / drop sets** — `Exercise` gains a group id; the engine's id-based
  navigation already supports the behaviour.

Nothing speculative was built for these. See the roadmap in `README.md`.
