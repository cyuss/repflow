# Changelog

All notable changes to RepFlow are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `backend/` — `repflow-garmin`, an optional command-line tool that fills in
  Garmin Connect's **native** exercise table for an activity RepFlow recorded.
  It downloads the activity's original FIT, reads the per-lap developer fields
  the watch already writes, resolves each exercise against Garmin's 1527-movement
  enum, and writes the set list into the existing activity — no second activity,
  and the heart rate, calories and timing the watch measured are untouched.
  Works retroactively on every RepFlow activity ever recorded. Outside Garmin's
  terms of service; `backend/README.md` says so plainly and says what it costs.
- A `rest` developer FIT field (id 14) on every lap: the seconds actually rested
  before that set. A RepFlow lap spans the rest *and* the set, so without it
  Garmin's Work Time / Rest Time split has nothing to read.
- `make test` now runs the backend's tests alongside the watch app's, and skips
  them cleanly on a machine where the backend is not set up.
- Both sync commands now **ask which session**: arrow keys through your recent
  strength activities, Enter to choose, `q` to cancel. They guess only with no
  terminal or `--yes`, and say which one they took.
- `make sync-garmin` / `just sync-garmin` — fill Garmin Connect's native
  exercise table for a recorded session. `sync-garmin-show` previews it.
- `make sync-hevy` / `just sync-hevy` — post the same session to Hevy, read from
  the same FIT file on Garmin's servers, so a session the watch could not send
  can be recovered weeks later without the watch. `sync-hevy-show` previews it.
  The API key is asked for and never stored.

- The watch buzzes when the rest ends by **either** route — the countdown
  reaching zero, or pressing START to go back to the bar — and once per rest,
  so watching the last second of a countdown no longer earns two buzzes half a
  second apart. Open rest gets a buzz it could not otherwise have: there is no
  zero to reach, so the press is the only moment there is.
- **An effort page** in the recap: one bar per rated set, in the order they
  were performed, at the height of its rating and in its colour, with the
  session average above. The shape says whether the session held together in a
  way a list of numbers does not.
- **A records page** in the recap, naming what was beaten and by how much. The
  first page said "2 records" and left the athlete to work out which lift.
- **A set clock** on the exercise screen, beside the exercise clock. They
  measure different spans — the exercise timer runs through every rest, so it
  answers a question about the last ten minutes rather than about the bar in
  your hands — and only one of them was visible.
- **Open rest** — rest that counts up and ends when you press, as an
  alternative to the countdown. Choose it in the settings, or switch mid-rest
  from the rest screen's menu. It never buzzes: a buzz claims the rest is over,
  and in this mode only the athlete gets to say that.
- **RPE** — an effort rating on each set, on the scale Hevy's API actually
  accepts (6, 7, 7.5, 8, 8.5, 9, 9.5, 10 — there is no 6.5, and a value off the
  ladder is answered with a 400 that loses the whole workout). It appears only
  while confirming a set, because a rating is something you give a set you have
  done. It costs no presses: START still logs from any field. Recorded per set,
  never inherited, carried to Hevy and into the FIT as a developer field.

### Fixed

- Discarding a workout no longer leaves the word "Discard" painted across the
  recap. Switching views from inside a `Menu2` selection callback leaves the
  menu's own layer on screen; the choice is now acted on a tick later, once the
  system has torn that layer down.
- `Theme.clear` drops any clip before clearing, so no view can inherit one from
  a scrolling line drawn earlier and repaint only part of itself.
- Ending a workout no longer stalls on the Save/Discard menu. Closing the FIT
  file is the slowest thing the app does and it was happening before the recap
  was drawn, inside the menu's own selection callback — so the menu sat there
  looking like the press had not registered.
- Exercise list rows take the largest font their height allows instead of the
  caption font. Width is no longer a reason to shrink one: a long name scrolls.

### Changed

- Importing Hevy routines says how many the watch had no room for, instead of
  reporting a smaller number with no explanation.
- Values are drawn in Garmin's own number font wherever they fit, which is now
  almost everywhere. They were falling back to a text font because the fit was
  measured against the font's line height, and a number font declares a descent
  its digits never use — `FONT_NUMBER_MILD` is 60px of line and 44px of ink, so
  a quarter of every value box was being reserved for nothing.
- Starting a workout opens the **exercise list**, not the first exercise.
  Starting on exercise one assumes you are going to do exercise one, which is
  the assumption this app exists to refuse.
- The workout overview moved from `Menu2` to `CustomMenu`, so long exercise
  names scroll on the focused row instead of being truncated by the system.
  Rows are left-aligned and taller — at a fifth of the screen the outermost
  rows sat where the glass has already curved past the icon column and their
  state rings came out as bare slivers.
- The rest screen's text is bounded by the countdown ring rather than by the
  glass.
- On the summary's body page, recovery and Body Battery moved to the middle
  band and Garmin's two heart rate figures to the bottom one: "BODY BATT" needs
  77px and the bottom band allows 56.
- On the summary's body page, Body Battery takes the full-width band — its
  caption is the longest in the app and that is the only band with no
  neighbour — and the heart rate pair is captioned AVG and MAX. At 50px in a
  64px cell "AVG HR" left seven pixels either side of the divider and read as
  touching. Field captions also drop a size when they do not fit, and the test
  now requires a quarter of the cell held clear rather than a bare fit.
- The exercise-screen heart rate row is a zone-coloured heart and the number,
  without the zone gauge and the "Z3" beside it.
- Exercise names written to the FIT may now be 40 characters rather than 24.
  Imported Hevy names were being truncated — "Triceps Extension (Cable)" became
  "Triceps Extension (Cable" — and a truncated name is a mis-identified exercise
  when it is read back.

## [1.0.0] - 2026-09-12

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
