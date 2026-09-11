# RepFlow

**Your workout. Your order.**

RepFlow is a flexible strength-training app for Garmin watches that lets you
change exercise order, temporarily skip occupied machines, resume them later,
and track sets, reps and weight without breaking your workout.

---

## Why RepFlow exists

Structured workouts assume you will do the exercises in the order they were
written. Real gyms disagree:

- the machine you need is taken;
- you want to superset two movements;
- you want to skip something and come back to it;
- you want to change the weight mid-workout.

Every other option makes you choose between following the plan and tracking
nothing. RepFlow's whole design follows from one rule:

> **Select any exercise at any time.**

There is no linear workout index. The engine navigates by stable exercise id,
and moving between exercises never loses a single set.

## Screenshots

| Workout picker | Exercise | Rest | Overview | Summary |
|---|---|---|---|---|
| _`store-assets/screenshots/01-workouts.png`_ | _`02-exercise.png`_ | _`03-rest.png`_ | _`04-overview.png`_ | _`05-summary.png`_ |

> Placeholders — capture from the simulator with **File → Save Screenshot**, or
> from the watch, before submitting to the Store.

## Features

- **Pick any exercise, any time** — from a one-press workout overview.
- **Skip for now** — an occupied machine becomes `PENDING`, not skipped and not
  completed. It stays in the list, and resumes exactly where you left it.
- **Alternate freely** — supersets and circuits work because two
  partially-completed exercises can be interleaved without data loss.
- **Smart value inheritance** — the next set is pre-filled with the weight and
  reps you *actually* performed, not the template's. Change set 2 to 57.5 kg and
  set 3 follows.
- **One press per set** — START completes the set. That is the whole hot path.
- **Rest timer** — counts down with a draining arc, shows what is next, vibrates
  once at zero. Skip it, extend it, or walk away and do something else.
- **Honest completion** — RepFlow will not call a workout done while exercises
  are unfinished without asking you first.
- **Real Garmin activity** — records a genuine strength training activity that
  syncs to Garmin Connect, with a lap per set.
- **Offline first** — no phone, no internet, no account. Ever.
- **Survives interruption** — state is persisted after every set; kill the app
  mid-workout and it resumes where you were.

## Supported devices

**Primary targets**

- **Fenix 9 Pro 47 mm** (`fenix9pro47mm`) — 454x454 AMOLED
- **Fenix 9 Pro 51 mm** (`fenix9pro51mm`) — 466x466 AMOLED
- Fenix 9 Pro 43 mm, Fenix 9 Pro Solar 47/51 mm, Fenix 9 43/47 mm
- Fenix 8 family (`fenix8pro47mm`, `fenix847mm`, `fenix843mm`, `fenix8solar47mm`, `fenix8solar51mm`)

**Secondary target**

- Fenix 6 Pro (`fenix6pro`) and the rest of the Fenix 6 family — 240x240, no
  touch, the tightest layout and memory budget RepFlow supports

Plus the Fenix 7 family, epix 2 family, Venu 3 / 3S and vivoactive 5 / 6 —
**34 devices in total**, all verified to compile.

Run `make devices` to see exactly what your machine can build right now, and
`scripts/device-matrix.sh` for per-device resolution, memory and input details.

## Architecture

```
Views  ──▶  AppController  ──▶  WorkoutEngine (pure domain)
                 │                    │
                 ├──▶ RestTimer (pure)│
                 ├──▶ GarminRecorder ─┴──▶ ActivityRecording / FIT
                 └──▶ SessionRepository ──▶ Application.Storage
```

Dependencies point downward only. The workout engine imports `Toybox.Lang` and
nothing else — no UI, no storage, no recording — which is what makes it fully
unit-testable. `GarminRecorder` is the only file that touches
`ActivityRecording`; `SessionRepository` is the only one that touches `Storage`.

Full detail: **`docs/ARCHITECTURE.md`**.

## Quick start

```sh
git clone <this repo> && cd RepFlow
make bootstrap        # JDK, Connect IQ SDK, SDK Manager, VS Code ext, signing key
make doctor           # verify the environment
make test             # run the workout engine test suite
make sim              # build and launch in the Connect IQ Simulator
```

### One manual step

Garmin ships **device definitions** only through the Connect IQ SDK Manager,
which requires signing in with a Garmin account and accepting the SDK licence.
Nothing can compile without them.

1. Open the Connect IQ SDK Manager (`make bootstrap` installs it).
2. Sign in, accept the licence.
3. **Devices** tab → download the devices you target
   (at minimum `fenix9pro47mm`, `fenix9pro51mm`, `fenix6pro`).
4. `make doctor`.

Everything else is automated. See **`docs/ENVIRONMENT.md`**.

## Build

```sh
make devices                       # list buildable device ids
make build                         # default device
make build DEVICE=fenix847mm       # a specific device
make build-all                     # every supported, installed device
RELEASE=1 scripts/build.sh fenix6pro
```

`just` recipes mirror every `make` target: `just build fenix847mm`.

## Simulator

```sh
make sim DEVICE=fenix6pro
```

Builds, launches the simulator if it is not running, and pushes the binary.

In VS Code: **Monkey C: Verify Installation**, then
**Run → Run Without Debugging** and pick a device.

## Tests

```sh
make test
make test DEVICE=fenix847mm
```

Garmin's Run No Evil framework, executed in the simulator. The suite covers
arbitrary navigation, skip/pending/resume, alternating exercises, value
inheritance, rest timer state, summary maths and persistence round-trips.

See **`docs/TESTING.md`**.

## Physical device testing

```sh
make sideload DEVICE=fenix6pro
```

Builds a signed release PRG and copies it to a USB-connected watch's
`GARMIN/APPS/`. It never deletes anything on the watch, and prints manual
instructions if the watch is in MTP mode.

Then work through **`docs/SMOKE_TEST.md`** — the mandatory release gate.
Full workflow: **`docs/DEVICE_TESTING.md`**.

## Release

```sh
make package
```

Runs doctor, the full test suite, a release build for every supported device,
then produces the Connect IQ Store `.iq` bundle with `monkeyc --package-app`.

Submission steps: **`docs/CONNECT_IQ_DEPLOYMENT.md`**.
Gate list: **`docs/RELEASE_CHECKLIST.md`**.

## Known Garmin limitations

Verified against the installed SDK, not assumed:

- **No native per-set FIT messages.** Connect IQ's `ActivityRecording.Session`
  cannot write Garmin's `set` messages. RepFlow records a genuine strength
  activity, marks a lap per set, and writes developer FIT fields for total sets,
  reps and volume — but Garmin Connect's built-in per-set breakdown stays empty.
- **No pause/resume on a recording session.** `stop()` + `start()` is the
  supported equivalent.
- **A recording cannot be reattached after an app restart.** RepFlow's own
  workout state is fully restored; the Garmin recording restarts, so an
  interrupted workout produces two activities.
- **Garmin Connect workouts cannot be read or reordered** from Connect IQ. This
  is precisely why RepFlow owns its own engine.

Detail and workarounds: **`docs/API_LIMITATIONS.md`**.

## Roadmap

| Version | Focus |
|---|---|
| **V0.1** | **Flexible workout engine, arbitrary navigation, skip/resume, rest timer, strength recording** ← current |
| V0.2 | Persistence improvements, history, last-session values, personal records |
| V0.3 | Supersets, circuits, warm-up sets, drop sets, RPE/RIR |
| V0.4 | Optional RepFlow API, workout synchronisation |
| V0.5 | Lightweight web/PWA workout editor |
| V0.6 | iOS/Android companion app, if justified |
| V1 | A mature Hevy-like strength experience for Garmin |

Possible later: Garmin Training API, Hevy import, cloud sync, progression
recommendations. None of it is built or stubbed today.

## Documentation

| Doc | Contents |
|---|---|
| `docs/PRODUCT.md` | The problem, the principle, the flows |
| `docs/ARCHITECTURE.md` | Layers, files, state machine, design decisions |
| `docs/ENVIRONMENT.md` | SDK, tooling, the one manual step |
| `docs/DEVELOPMENT.md` | Commands, button map, conventions |
| `docs/TESTING.md` | What is tested and why |
| `docs/SMOKE_TEST.md` | The mandatory manual release gate |
| `docs/DEVICE_TESTING.md` | Sideloading and on-watch verification |
| `docs/DEVICE_MATRIX.md` | Per-device capabilities and results |
| `docs/SIGNING.md` | The signing key and the app UUID |
| `docs/API_LIMITATIONS.md` | Verified Garmin API constraints |
| `docs/CONNECT_IQ_DEPLOYMENT.md` | Store export and submission |
| `docs/RELEASE_CHECKLIST.md` | Release gate list |
| `docs/IMPLEMENTATION_PLAN.md` | Phased build plan and status |

## Licence

Not yet chosen. Add one before publishing.
