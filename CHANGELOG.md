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
- **Set-list workflow modelled on Hevy's Apple Watch app**: the main screen is
  the current exercise's list of sets — done, active, upcoming — rather than a
  single-set panel. No cursor: the active set is always the next incomplete one,
  so START logs it and the list advances by itself
- Finishing an exercise moves straight on to the next one after the rest
- **Two-column set editor** built on `WatchUi.Picker` (weight × reps), the
  platform's own two-value editor; one press from the rest screen
- **Multiple data screens during an exercise, paged with UP/DOWN like a native
  Garmin activity**: SET (the set list), BODY (live heart rate, timer,
  calories) and WORKOUT (volume, exercises, sets, reps)
- Progress ring around the rim — the one area of a round display a field grid
  cannot use — showing how far through the exercise, or the rest, you are
- Colour used to carry meaning: heart rate red, calories amber, completed work
  green, the editable load in the accent
- Live heart rate also shown on the rest screen, where recovery is worth watching
- Paged workout summary: headline, work done, and Garmin's own body metrics
- Button-first interaction: one press of START completes a set, one press of
  BACK opens the overview; touch is optional everywhere
- **Garmin-style data field grid** (`FieldGrid`): bands of big value plus small
  caption, separated by hairlines, as on a native activity screen
- Layout respects the display being round — only the middle band is split into
  columns, and wide values ("1:02:34", "3.2 t") take a full-width band, because
  a half cell near the top or bottom of a circle is far too narrow for them
- Measured layout engine (`Theme`): text is placed from a running cursor with
  explicit gaps and a round-screen-aware usable width, so lines cannot collide
  or crowd on any screen size
- Resolution-adaptive drawing in code rather than per-device XML layouts
- Per-device launcher icons rendered at each product's exact pixel size
  (`scripts/make-icons.sh`), so nothing is rescaled
- Height-aware font selection (`Theme.pickFontFitting`): fonts are chosen to fit
  the space actually available, not just the width, so nothing overflows on the
  shorter 260x260 Fenix 6 Pro screen
- Accent and heart-rate colours chosen from Garmin's 64-colour palette so they
  render exactly on 8-bit MIP displays as well as on AMOLED
- **Heart rate zone gauge**: a five-segment bar coloured from the athlete's own
  `UserProfile` thresholds — a compact row on the set and editor screens, and a
  full data field on the metric screen. Never guesses a maximum heart rate: with
  no reading, or no zones on the profile, nothing is filled
- **Exercise state icons carry meaning in their shape**, not their colour: tick
  for done, play for the exercise in hand, pause for one set aside, cross for
  skipped, empty ring for untouched. Amber is the colour of unfinished work, so
  active and pending read as one family
- Set editor shows a **+ above and a - below the focused value**, where the
  buttons physically are, and no line of button hints
- The load on the set screen is **two aligned cells, weight | reps** — the same
  shape as the editor, so the screen you read and the screen you edit match
- **Garmin-style stop menu**: keep training / save / discard, with the safe
  answer first, replacing a SAVE button on the recap that asked a question
  already answered
- **Four-page workout recap**: the work (time, sets done against planned, reps,
  volume), the body (calories, average and maximum heart rate, load per set),
  **time in heart rate zone as a bar chart** — the screen a Fenix shows after
  any activity — and the exercises one by one, each with its own progress bar
- `ZoneTracker` — seconds in each heart rate zone, counted off the same 1 Hz
  tick that drives the rest timer. Connect IQ reports the *current* heart rate
  and nothing about how long it has been where, so RepFlow counts it itself;
  seconds the watch could not place belong to no bar

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
- `SessionSnapshot` validates the persisted session field by field, against a
  schema version, **before** parsing it. Monkey C runtime errors such as
  "Unexpected Type" are not Exceptions and are not caught (verified by
  experiment), so misreading a snapshot written by an older build would abort
  the app rather than fail gracefully

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
