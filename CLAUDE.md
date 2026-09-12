# CLAUDE.md — working on RepFlow

Orientation for future Claude Code sessions.

## Start every session with

```sh
pwd
cat CLAUDE.md          # this file
git status
head -40 CHANGELOG.md
make doctor
make test
git log --oneline -15
```

Then continue from the current milestone (below).

## Product in one line

**RepFlow — your workout, your order.** A Garmin Connect IQ **watch app** for
flexible strength training: select any exercise at any time, defer an occupied
machine and resume it later, without losing workout state.

Read `docs/PRODUCT.md` before changing behaviour.

## The rule everything follows

> **Select any exercise at any time.**

`WorkoutEngine` navigates by **stable String exercise id**. There is no cursor
and nothing increments an index. This sequence must always be ordinary:

```
A set 1 → B set 1 → A set 2 → C set 1 → B set 2
```

If a change would make that harder, the change is wrong.

## Architecture

```
Views ──▶ AppController ──▶ WorkoutEngine (pure: imports only Toybox.Lang)
               ├──▶ RestTimer (pure, tick-driven)
               ├──▶ GarminRecorder ──▶ ActivityRecording   (ONLY file that does)
               └──▶ SessionRepository ──▶ Application.Storage (ONLY file that does)
```

- `WorkoutEngine` is the **single writer** of `Exercise.state`. Its class
  comment lists every legal transition — read it before touching state.
- Views render and forward presses. They never call storage or recording.
- Screens are drawn in code (`Theme.drawFitted` picks a font that fits), not
  from XML layouts, so one path covers 240×240 through 466×466.
- Navigation is **flat**: `WatchUi.switchToView` everywhere, not `pushView`.
  `WatchUi.Confirmation` pops itself and fights this — that is why
  `EndWorkoutFlow` uses a `Menu2` instead.

Full detail: `docs/ARCHITECTURE.md`.

## Key files

| File | Why it matters |
|---|---|
| `source/WorkoutEngine.mc` | The state machine. Start here |
| `source/Exercise.mc` | Value inheritance (`plannedReps` / `plannedWeight`) |
| `source/AppController.mc` | Wiring, transitions, persistence triggers, haptics |
| `source/GarminRecorder.mc` | All `ActivityRecording` |
| `source/SessionRepository.mc` | All `Application.Storage` |
| `source/SetListRenderer.mc` | The Hevy-style set list — the main screen |
| `source/FieldGrid.mc` | Round-screen data field layout |
| `tests/WorkoutEngineTest.mc` | The product promise, executable |
| `manifest.xml` | App UUID and supported products — handle with care |

## Garmin constraints — no-fake-API rule

**Never invent a class, method, constant or device id.** When unsure:

1. Read the installed SDK docs: `$SDK_HOME/doc/Toybox/*.html`
2. Grep the symbol table: `$SDK_HOME/bin/api.debug.xml`
3. Check Garmin's official docs online
4. Build a tiny proof-of-concept if still unsure

Then record what you found in `docs/API_LIMITATIONS.md`.

Verified limitations you must not paper over:

- Connect IQ **cannot write native per-set FIT `set` messages**. RepFlow marks
  one lap per set and writes developer fields. Do not claim otherwise.
- `ActivityRecording.Session` has **no pause/resume** — `stop()`/`start()`.
- A recording **cannot be reattached** after an app restart.
- Garmin Connect workouts **cannot be read or reordered** from Connect IQ.
- Device definitions require a **signed-in Garmin account** in the SDK Manager.
  There is no way to automate this.
- **`try/catch` does not catch Monkey C runtime errors** ("Symbol Not Found",
  "Unexpected Type") — they abort the app. Verified by experiment; see
  `docs/API_LIMITATIONS.md` §9. Never rely on a catch to make a parser safe.
  Validate persisted or external data first: see `source/SessionSnapshot.mc`,
  and bump `SCHEMA_VERSION` whenever the stored layout changes.
- **Do not trust a `monkeydo` crash report without clearing the simulator log
  first** — it replays stale crashes from a log shared with the test binary.
  See the trap section in `docs/TESTING.md`.

Device ids come from the **installed device definitions**: `make devices` or
`scripts/devices.sh --all`. Do **not** trust `scripts/devices.sh --known` — it
reads the SDK's bundled reference-artwork folder, which lags reality (it lists no
Fenix 9 at all, even though `fenix9pro47mm` and `fenix9pro51mm` build fine).

## Commands

| Task | Command |
|---|---|
| Environment check | `make doctor` |
| Build | `make build [DEVICE=id]` |
| Build everything | `make build-all` |
| Tests | `make test` |
| Simulator | `make sim [DEVICE=id]` |
| List device ids | `make devices` |
| Sideload to watch | `make sideload DEVICE=id` |
| Release bundle | `make package` |
| Clean | `make clean` |

`just` mirrors all of them.

## Test requirements

- Tests are **mandatory** and encode intended behaviour.
- **Never weaken or delete a test to make a build green.** If a test is genuinely
  wrong, fix it deliberately and say so in the commit message.
- Domain changes get a test *before* the simulator gets opened.
- A bug fix gets a test that fails before the fix.
- `docs/SMOKE_TEST.md` is the mandatory manual gate. Steps 8, 12 and 14
  (skip → pending → resume with state intact) are the product; if they fail, the
  release is blocked.

## Current milestone

**V0.1 MVP — code complete and verified against SDK 9.2.0.**

- 33/33 declared products build at strict type checking (`-l 3`)
- 18/18 unit tests pass on `fenix6pro` and `fenix9pro47mm`
- the app runs in the Connect IQ Simulator
- `make package` produces a real `.iq` Store bundle

What is left needs a human: the manual smoke test (`docs/SMOKE_TEST.md`) in the
simulator and on a physical Fenix, store screenshots and icon, and the Connect
IQ portal submission.

Check `CHANGELOG.md` `## [Unreleased]` and `docs/IMPLEMENTATION_PLAN.md` for the
live status, and `docs/FEATURE_BACKLOG.md` for what is worth building next and
which asks the platform refuses outright.

## Do not

- Regenerate the application UUID in `manifest.xml` (`289C529B…`) — it breaks
  every existing install once published. See `docs/SIGNING.md`.
- Regenerate or commit the developer signing key.
- Commit build artifacts (`build/`) or anything matching `*.der`, `*.pem`, `*.key`.
- Build speculative architecture for roadmap items (V0.2+). Keep the MVP small.
- Add a Garmin permission beyond `Fit` / `FitContributor` without a concrete need.
