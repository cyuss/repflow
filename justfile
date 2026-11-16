# RepFlow — your workout, your order.
#
# Override the build target:
#   just DEVICE=fenix847mm build      (or: DEVICE=fenix847mm just build)
# List the ids with `just devices`.

set shell := ["bash", "-c"]

# Device the watch targets build for; scripts/lib.sh reads it from the environment.
export DEVICE := env("DEVICE", "fenix9pro47mm")
# monkeyc type-check level: 0=off 1=gradual 2=informative 3=strict
export TYPECHECK := env("TYPECHECK", "3")
# Analytics recipes: DEMO=1 overwrites the simulator's history with a demo year.
DEMO := env("DEMO", "0")

# Show this help
help:
    @echo "RepFlow — your workout, your order."
    @echo
    @just --list --unsorted --list-heading ''
    @echo
    @echo "  DEVICE={{DEVICE}}   (override: just DEVICE=<id> build; list ids with 'just devices')"

# Check the development environment
doctor:
    @scripts/doctor.sh

# Install SDK, tooling and signing key for this OS
bootstrap:
    @case "$(uname -s)" in \
        Darwin) scripts/bootstrap-macos.sh ;; \
        Linux)  scripts/bootstrap-linux.sh ;; \
        *) echo "On Windows run: powershell -File scripts/bootstrap-windows.ps1"; exit 1 ;; \
    esac

# Create the developer signing key if it does not exist
key:
    @scripts/make-developer-key.sh

# List device ids RepFlow can be built for right now
devices:
    @scripts/devices.sh

# List every device definition installed locally
devices-all:
    @scripts/devices.sh --all

# List manifest products whose definitions are not installed
devices-missing:
    @scripts/devices.sh --missing

# Build a signed PRG for $DEVICE
build:
    @scripts/build.sh {{DEVICE}}

# Build every device declared in manifest.xml and installed locally
build-all:
    @scripts/build.sh --all

# Run every test — watch app and backend
test: test-watch test-backend

# Run the watch app's unit tests in the simulator
test-watch:
    @scripts/test.sh {{DEVICE}}

# Run the Garmin Connect backend's tests (skipped if not set up)
test-backend:
    @scripts/test-backend.sh

# Preview the exercise table that would be written to Garmin
sync-garmin-show activity="":
    @backend/.venv/bin/repflow-garmin show {{ if activity != "" { "--activity " + activity } else { "" } }}

# Write sets, reps and loads into the Garmin activity's exercise table
sync-garmin activity="":
    @backend/.venv/bin/repflow-garmin fill {{ if activity != "" { "--activity " + activity } else { "" } }}

# Preview the workout that would be posted to Hevy
sync-hevy-show activity="":
    @backend/.venv/bin/repflow-garmin hevy --dry-run {{ if activity != "" { "--activity " + activity } else { "" } }}

# Post the last RepFlow session to Hevy
sync-hevy activity="":
    @backend/.venv/bin/repflow-garmin hevy {{ if activity != "" { "--activity " + activity } else { "" } }}

# Create the backend virtualenv and install it
backend-setup:
    @python3 -m venv backend/.venv
    @backend/.venv/bin/pip -q install --upgrade pip
    @backend/.venv/bin/pip -q install -e 'backend[dev]'
    @echo "[OK]   backend ready — backend/.venv/bin/repflow-garmin --help"

# Pick a device and launch RepFlow in the simulator (`just sim <id>` skips the question)
sim device="":
    @REPFLOW_DETACH=1 scripts/run-simulator.sh {{device}}

# Same, but clear the session — keeping the seeded workouts
sim-fresh device="":
    @REPFLOW_DETACH=1 REPFLOW_RESET=1 scripts/run-simulator.sh {{device}}

# Same, but with nothing stored at all — a first-ever install
sim-empty device="":
    @REPFLOW_DETACH=1 REPFLOW_RESET=1 REPFLOW_NO_SEED=1 scripts/run-simulator.sh {{device}}

# Open RepFlow straight on Analytics in the simulator (DEMO=1 for demo data)
sim-analytics:
    @REPFLOW_LAUNCH=analytics REPFLOW_DEMO={{DEMO}} REPFLOW_DETACH=1 scripts/run-simulator.sh {{DEVICE}}

# The Analytics glance, full screen in the app, to work on its design (DEMO=1 for demo data)
glance-preview:
    @REPFLOW_LAUNCH=glance-preview REPFLOW_DEMO={{DEMO}} REPFLOW_DETACH=1 scripts/run-simulator.sh {{DEVICE}}

# The real glance, in the simulator's glance mode (Connect IQ 4+ devices)
glance:
    @scripts/glance.sh {{DEVICE}}

# Remember the simulator's workouts, so sim-fresh puts them back
sim-seed:
    @scripts/sim-seed.sh save

# Forget them again
sim-seed-forget:
    @scripts/sim-seed.sh forget

# Launch and stay attached, streaming the app's println output
sim-attach device="":
    @scripts/run-simulator.sh {{device}}

# Screenshot the simulator's watch face to build/sim-shot.png
shot:
    @scripts/shot.sh

# Capture the simulator display at native resolution (calibrate first)
store-shot name="calibrate":
    @scripts/store-shots.sh {{name}}

# Build and copy a release PRG to a USB-connected watch
sideload:
    @scripts/sideload.sh {{DEVICE}}

# Full release build: doctor, tests, all devices, .iq bundle
package:
    @scripts/package.sh

# Everything package does, plus the release checklist reminder
release-check:
    @scripts/package.sh
    @echo
    @echo "Now work through docs/RELEASE_CHECKLIST.md before submitting."

# Remove build output
clean:
    @rm -rf build
    @mkdir -p build
    @echo "build/ cleaned"
