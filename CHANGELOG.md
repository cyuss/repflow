# Changelog

All notable changes to RepFlow are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial RepFlow project
- Flexible workout engine
- Arbitrary exercise navigation
- Pending / skip / resume support
- Strength activity recording
- Rest timer
- Workout summary

#### Environment & tooling

- Connect IQ SDK 9.2.0 installed and verified; SDK resolution is dynamic, never
  hard-coded (`scripts/lib.sh`)
- `scripts/doctor.sh` and `scripts/doctor.ps1` environment diagnostics
- Bootstrap scripts for macOS, Linux and Windows
- RSA 4096 developer signing key generation, stored outside source control
- `make` and `just` command sets: doctor, build, test, sim, sideload, package,
  clean, release-check
- Device discovery from the installed SDK (`scripts/devices.sh`,
  `scripts/device-matrix.sh`) — no invented product ids

#### Domain

- `Workout`, `Exercise`, `WorkoutSet`, `WorkoutSession` model
- `ExerciseState` (`NOT_STARTED` / `ACTIVE` / `PENDING` / `COMPLETED` / `SKIPPED`)
- `WorkoutEngine` — id-based navigation with explicit state transitions and no
  linear cursor
- Weight and repetition inheritance from the last performed set
- `RestTimer` — pure, tick-driven countdown
- Three built-in workouts: Back + Triceps, Chest + Biceps, Legs

#### Watch UI

- Workout picker, exercise screen, rest screen, workout overview, value editor,
  exercise actions menu and workout summary
- Button-first interaction: one press of START completes a set, one press of
  BACK opens the overview; touch is optional everywhere
- Resolution-adaptive drawing in code rather than per-device XML layouts

#### Garmin integration

- `GarminRecorder` — strength-training `ActivityRecording` session
  (`SPORT_TRAINING` / `SUB_SPORT_STRENGTH_TRAINING`)
- One FIT lap per completed set
- Developer FIT fields for total sets, reps and training volume
- Garmin calories and average heart rate surfaced on the summary when available

#### Persistence

- `SessionRepository` — active session saved after every state change, restored
  on launch
- Compact serialisation with short keys; history capped at 20 summary entries

#### Tests

- Run No Evil suite covering linear completion, skip/pending/resume, alternating
  exercises, forced completion, value inheritance, rest timer state, summary
  calculations and persistence round-trips

#### Documentation

- `README.md`, `CLAUDE.md`, and `docs/` covering product, architecture,
  environment, development, testing, smoke test, device testing, device matrix,
  signing, verified API limitations, Store deployment and the release checklist
- `store-assets/` templates for the Connect IQ Store listing

### Notes

- Verified against Connect IQ SDK 9.2.0: all 33 declared products compile, the
  unit suite (18 tests) passes on both `fenix6pro` and `fenix9pro47mm`, the app
  launches in the Connect IQ Simulator, and `make package` produces a genuine
  Connect IQ Store `.iq` bundle covering 58 device variants.
- The SDK's bundled `resources/device-reference/` folder lags the real device
  list and contains no Fenix 9 entries, but the downloaded Fenix 9 Pro device
  definitions build correctly. Always discover ids with
  `scripts/devices.sh --all`. See `docs/ENVIRONMENT.md`.
