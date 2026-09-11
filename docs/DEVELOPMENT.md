# Development

## Commands

Every command works through `make` or `just`.

| Task | make | just |
|---|---|---|
| Check the environment | `make doctor` | `just doctor` |
| Install SDK & tooling | `make bootstrap` | `just bootstrap` |
| Create signing key | `make key` | `just key` |
| List buildable devices | `make devices` | `just devices` |
| Build | `make build` | `just build` |
| Build every device | `make build-all` | `just build-all` |
| Run tests | `make test` | `just test` |
| Run in simulator | `make sim` | `just sim` |
| Sideload to a watch | `make sideload` | `just sideload` |
| Full release build | `make package` | `just package` |
| Clean | `make clean` | `just clean` |

### Choosing a device

```sh
make devices                          # ids that can be built right now
make build DEVICE=fenix847mm
make sim   DEVICE=fenix9pro47mm
just build fenix847mm
```

Device ids always come from the installed device definitions.
`scripts/devices.sh --all` lists everything installed locally and is the
authoritative source; `--missing` lists products declared in `manifest.xml`
whose definitions are not installed. (`--known` reads the SDK's bundled
reference-artwork folder, which lags reality — it has no Fenix 9 entries.)

### Type checking

`monkeyc`'s type checker runs at level **3 (strict)** by default, and the whole
tree — source and tests — is clean at that level. Keep it that way. You can
lower it temporarily while refactoring:

```sh
make build TYPECHECK=1     # 0=off 1=gradual 2=informative 3=strict
```

## Project layout

```
manifest.xml          application id, products, permissions
monkey.jungle         build configuration (source + tests on the source path)
source/               domain, engine, persistence, recording, views
tests/                Run No Evil unit tests, (:test) annotated
resources/            strings, launcher icon
resources-fre/        French strings
scripts/              bootstrap, doctor, build, test, sim, sideload, package
docs/                 this documentation
build/                output (git-ignored)
store-assets/         Connect IQ Store listing material
```

`monkey.jungle` puts both `source` and `tests` on the source path. Test code is
annotated `(:test)` and is only compiled into the binary when `monkeyc -t` is
used, so it costs nothing in a release build.

## Working on the domain

The workout engine has no dependency on UI, storage or recording, so the fast
loop is:

1. change `source/WorkoutEngine.mc` (or a model class);
2. add or adjust a test in `tests/WorkoutEngineTest.mc`;
3. `make test`.

Do not reach for the simulator to verify engine behaviour — that is what the
tests are for. See `docs/TESTING.md`.

## Working on the UI

```sh
make sim DEVICE=fenix6pro
```

The simulator keeps running between invocations; `make sim` rebuilds and pushes
a new binary to the already-open window.

Useful simulator menus:

- **Settings → Toggle Touch Screen** — verify that RepFlow is fully usable with
  buttons alone. Touch is an enhancement in RepFlow, never a requirement.
- **Simulation → Activity Monitor / Heart Rate** — feed the values that
  `WorkoutSummaryView` reads back from `Activity.getActivityInfo()`.
- **File → View Memory** — check the memory headroom, especially for
  `fenix6pro`, the tightest supported target.

### Buttons

| Screen | START | UP / DOWN | BACK | MENU (long press) |
|---|---|---|---|---|
| Workout list | start workout | change workout | exit | — |
| Exercise | **complete set** | **change data screen** | overview | exercise actions |
| Rest | skip rest | rest ± 15 s | overview | exercise actions |
| Overview | select exercise | scroll | back to training | — |
| Value editor | confirm | change value | confirm | — |
| Summary | save activity | page metrics | save/discard menu | save/discard menu |

The design rule: completing a set is always one press of START, and the
overview is always one press of BACK.

### Data screens

The exercise screen is **paged with UP/DOWN**, the way every native Garmin
activity behaves — that is the muscle memory RepFlow should not fight:

| Page | Shows |
|---|---|
| **SET** | Exercise, set X/Y, progress dots, load in kg, reps, `COMPLETE SET` |
| **BODY** | Live heart rate (hero), elapsed timer, average HR, calories |
| **WORKOUT** | Training volume (hero), exercises done, sets, reps |

Because UP/DOWN pages rather than adjusts, **weight and reps are edited from the
MENU** — "Edit weight" is deliberately the first item, so it sits under the
cursor the instant the menu opens. That is the right trade: the load changes
roughly once per exercise, while a set is completed several times per exercise
and still takes a single press. On touch devices, tapping the weight or the reps
on the SET page opens the same editor directly.

Live metrics come from `source/LiveMetrics.mc`, the only place RepFlow reads
`Activity.getActivityInfo()`. Every field is nullable and renders as `--` rather
than a fabricated zero when the device has nothing to give.

## VS Code

The Garmin Monkey C extension gives syntax highlighting, completion against the
SDK, and the debugger.

- **Monkey C: Verify Installation** — sanity-check the SDK wiring.
- **Run → Run Without Debugging** — pick a device and launch the simulator.
- **Monkey C: Export Project** — build the Store `.iq` bundle (though
  `make package` does this from the CLI with `monkeyc -e`).

`make bootstrap` installs the extension when the `code` command is available.

## Build warnings

**A clean build emits none.** Any warning is a defect — treat it as one.

### Launcher icons

Launcher icons are a different pixel size on almost every product (40x40 on
Fenix 6, 65x65 on Fenix 9 Pro, 56x56 on vivoactive 5, ...). Shipping one bitmap
makes the compiler rescale it, with a warning and a soft-looking icon.

Instead, the icon is rendered at each required size into `resources-icon-<N>/`,
and `monkey.jungle` points every device at the folder holding its exact size.
Regenerate them all with:

```sh
scripts/make-icons.sh
```

The vector master is `store-assets/icon.svg`; edit that, never the PNGs.

## Conventions

- Private fields and methods are prefixed with `_`.
- Types are annotated on public signatures; `monkeyc` checks them.
- Comments explain *why*, not *what*. The state-transition table in
  `WorkoutEngine.mc` is the one place worth reading before changing behaviour.
- No new abstraction without a second caller.
- Never invent a Garmin API. Verify against the installed SDK docs at
  `$SDK_HOME/doc/Toybox/`, and record any limitation found in
  `docs/API_LIMITATIONS.md`.
