# Implementation plan

Phased build plan with live status. Each phase: state the objective, implement,
compile, run the relevant tests, fix failures, update docs, update CHANGELOG,
commit when stable.

| Phase | Objective | Status |
|---|---|---|
| 0 | Environment | ✅ verified — SDK 9.2.0, 62 device definitions |
| 1 | Build proof | ✅ verified — builds and runs in the simulator |
| 2 | Domain model | ✅ implemented |
| 3 | Workout engine | ✅ implemented, 18 tests green |
| 4 | Watch UI | ✅ implemented |
| 5 | Rest timer | ✅ implemented |
| 6 | Garmin activity recording | ✅ implemented |
| 7 | Persistence | ✅ implemented |
| 8 | Tests & device matrix | ✅ 33/33 products build; matrix generated |
| 9 | Physical device build | ✅ tooling ready — **on-watch run pending** |
| 10 | Connect IQ release pipeline | ✅ `.iq` bundle produced — **submission pending** |

**Verified on 2026-09-11, Connect IQ SDK 9.2.0:**

- `make build-all` — 33/33 declared products compile at **strict** type
  checking (`-l 3`), with no errors and no warnings beyond the expected
  per-device launcher-icon scaling notice
- `make test` — 18/18 unit tests pass on `fenix6pro` and `fenix9pro47mm`
- `make sim` — the app builds, pushes and runs in the Connect IQ Simulator
- `make package` — produces a genuine Connect IQ `.iq` Store bundle
  (7-zip container, 58 device variants)

**Outstanding, and genuinely human-only:**

- The manual smoke test (`docs/SMOKE_TEST.md`) in the simulator and on a
  physical Fenix — it needs eyes and button presses
- Store screenshots and icon (`store-assets/`)
- Submission to the Connect IQ developer portal (Garmin account)

---

## Phase 0 — Environment

**Objective:** a machine that can compile a Connect IQ project.

Done: detected macOS 26.5.2 / arm64 / zsh / Temurin JDK 26; installed Connect IQ
SDK **9.2.0** from Garmin's public SDK feed; installed the SDK Manager cask;
generated an RSA 4096 developer key outside the repo; wrote `doctor.sh` /
`doctor.ps1` and the three bootstrap scripts; recorded everything in
`docs/ENVIRONMENT.md`.

Device definitions required signing in to the Connect IQ SDK Manager with a
Garmin account — the one step that cannot be automated (see
`docs/ENVIRONMENT.md`). Once done, 62 device definitions were available.

## Phase 1 — Build proof

**Objective:** a minimal RepFlow that compiles and launches in the simulator.

Done. Device definitions were installed through the SDK Manager, after which
`make build` and `make sim` both succeed. RepFlow pushes to and runs in the
simulator on `fenix9pro47mm` and `fenix6pro`.

A correction worth recording: the SDK's bundled `resources/device-reference/`
folder contains no Fenix 9 entries, which initially looked like "the Fenix 9 Pro
does not exist". The downloaded device definitions tell the truth —
`fenix9pro47mm`, `fenix9pro51mm` and five more Fenix 9 variants are real and
compile. Always discover ids with `scripts/devices.sh --all`.

## Phase 2 — Domain model

**Objective:** a model that can express arbitrary ordering.

`WorkoutSet`, `Exercise`, `Workout`, `WorkoutSession`, `ExerciseState`.
Exercises carry stable String ids; `Workout.findExercise` looks up by id.
Serialisation lives on the model classes so persistence has no separate schema.

## Phase 3 — Workout engine

**Objective:** navigation by id, with explicit, testable state transitions.

`WorkoutEngine` — no cursor, single writer of `Exercise.state`, transitions
documented in the class comment. The subtle rule is `_releaseCurrent`: leaving
an exercise lands it on `COMPLETED` / `PENDING` / `NOT_STARTED` depending on work
done, so merely looking at an exercise never marks it started.

## Phase 4 — Watch UI

**Objective:** glanceable, button-first screens; one press per set.

Workout picker, exercise screen, overview (`Menu2`), action menu, value editor,
summary. Drawn in code with a font ladder rather than XML layouts. Flat
navigation via `switchToView`. START completes a set; BACK opens the overview.

## Phase 5 — Rest timer

**Objective:** a countdown that does not trap the athlete.

`RestTimer` is pure and tick-driven so it is unit-testable; `AppController` owns
the 1 Hz `Toybox.Timer`. Skip, extend, and — crucially — BACK during rest goes
to the overview so another exercise can be started. Vibrates exactly once at
zero.

## Phase 6 — Garmin activity recording

**Objective:** a real strength activity in Garmin Connect, no faked APIs.

`GarminRecorder` with `SPORT_TRAINING` / `SUB_SPORT_STRENGTH_TRAINING`, a lap per
set, and developer FIT fields for sets/reps/volume. Every genuine API limitation
found is written up in `docs/API_LIMITATIONS.md` rather than worked around
dishonestly.

## Phase 7 — Persistence

**Objective:** never lose a workout.

`SessionRepository` saves the active session after every state change and on
`onStop`; `RepFlowApp.getInitialView` restores it ahead of the picker. Compact
keys, capped history, every call exception-wrapped.

## Phase 8 — Tests & device matrix

**Objective:** the product promise, executable.

`tests/WorkoutEngineTest.mc` covers all ten required scenarios plus engine
invariants, and passes at strict type checking. `scripts/device-matrix.sh`
generates the capability table in `docs/DEVICE_MATRIX.md` by reading Garmin's own
`compiler.json` / `simulator.json` — resolution, watch-app memory limit, physical
keys, touch support and API level, none of it hand-written.

## Phase 9 — Physical device build

**Objective:** a signed PRG on a real watch.

`scripts/sideload.sh` builds a release PRG and copies it to
`GARMIN/APPS/RepFlow.prg`, never deleting anything, with manual instructions for
MTP-mode watches. Workflow in `docs/DEVICE_TESTING.md`, verification in
`docs/SMOKE_TEST.md`.

## Phase 10 — Connect IQ release pipeline

**Objective:** an `.iq` bundle and a documented submission path.

`scripts/package.sh` runs doctor, tests and a release build for every device,
then produces the bundle with `monkeyc -e` (the supported CLI equivalent of
VS Code's *Monkey C: Export Project*). It never claims to have produced an `.iq`
that does not exist. Submission steps in `docs/CONNECT_IQ_DEPLOYMENT.md`,
gates in `docs/RELEASE_CHECKLIST.md`.
