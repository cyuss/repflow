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
| Exercise | **log the active set** | **change data screen** | overview | exercise actions (edit set first) |
| Rest | skip rest | rest ± 15 s | overview | **edit next set** |
| Overview | select exercise | scroll | back to training | — |
| Set picker | next column / confirm | change value | previous column | — |
| Summary | save activity | page metrics | save/discard menu | save/discard menu |

The design rule: completing a set is always one press of START, and the
overview is always one press of BACK.

### The workflow

Modelled on Hevy's Apple Watch app, adapted to buttons and a round screen.

The main screen is the **set list** for the current exercise — not a single
"current set" panel. It answers the two questions an athlete has mid-exercise
(what did I just lift, how many sets are left) without pressing anything.

```
     Lat Pulldown
 ---------------------
  + 1        10 x 55        done      green
  + 2        10 x 55
 [ 3         10 x 57.5 ]    active    accent, outlined
    4        10 x 57.5      upcoming  dim
 ---------------------
        LOG SET
```

There is **no cursor**. The active set is always the next incomplete one, so
START logs it and the list advances by itself — the one-press promise survives.
Rows are windowed around the active set when an exercise has more than fit.

The rest of the loop follows Hevy too: logging a set starts the rest timer;
when the last set of an exercise is logged, leaving the rest screen moves
straight on to the next exercise rather than dropping you back on a finished
list.

### Data screens

UP/DOWN page through data screens, as in every native Garmin activity:

| Page | Shows |
|---|---|
| **SET** | The set list, and `LOG SET` |
| **BODY** | Heart rate, average HR, calories, elapsed timer |
| **WORKOUT** | Training volume, sets, reps, exercises done |

### Editing a set

**MENU** opens a two-column `WatchUi.Picker` — weight × reps — on both the set
page and the rest screen. On the rest screen it is a *direct* one-press open,
because deciding "next one at 57.5" is what a rest is for.

The Picker is the platform's own two-value editor: UP/DOWN change the
highlighted column, START advances and confirms on the last column, BACK steps
back. Every Garmin owner already knows it, which beats anything bespoke.

Weights travel through it as **tenths of a kilogram** — a `PickerFactory` deals
in Numbers, and 2.5 kg steps are not integers (`Tuning.toTenths`).

### The field grid, and the round screen

Screens are built from `source/FieldGrid.mc`: horizontal bands, each holding one
or two cells, every cell a big value with a small caption under it, separated by
hairlines. That is what Garmin's own activity screens do, and it is what makes a
watch readable mid-effort.

Two rules come straight from the display being a **circle**, and both are
enforced by tests:

**Only the middle band is ever split into columns.** The top and bottom of a
circle are narrow, so a half-width cell up there has almost no usable width.
`FieldGrid.bandWidth` returns the chord at the band's *narrowest* edge — not its
centre — so a cell can never spill past the bezel.

**Wide values need a full-width band.** `1:02:34`, `137.5`, `3.2 t` simply do not
fit half a cell on a round screen; short values (`55`, `10`, `132`) are what
belong side by side. Each page picks its bands accordingly — see the layout
diagrams at the top of `ExerciseView.mc`.

`FieldGrid.drawCell` sizes the value to the cell it was given, in both width and
height, using `Theme.fontsCell()` — a ladder that starts at the big number fonts
and continues down into the text fonts. That tail matters: in a four-field
layout on a 260x260 Fenix 6 Pro, a band is shorter than the smallest *number*
font, and a value overflowing its cell is worse than a smaller one.

The layout tests (`testSetPageFieldsAreLarge`, `testFourFieldLayoutCellsFit`,
`testBandWidthStaysInsideTheGlass`) measure against **the running device's own
screen size and font metrics**, so run them per target:

```sh
make test DEVICE=fenix6pro
make test DEVICE=fenix9pro51mm
```

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
