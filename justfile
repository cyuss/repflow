# RepFlow — your workout, your order.
#
# Override the build target on any recipe:
#   just build fenix847mm

device := env_var_or_default("DEVICE", "fenix6pro")
typecheck := env_var_or_default("TYPECHECK", "3")

# Show the available recipes
default:
    @just --list

# Check the development environment
doctor:
    scripts/doctor.sh

# Install SDK, tooling and signing key for this OS
bootstrap:
    #!/usr/bin/env bash
    case "$(uname -s)" in
      Darwin) scripts/bootstrap-macos.sh ;;
      Linux)  scripts/bootstrap-linux.sh ;;
      *) echo "On Windows run: powershell -File scripts/bootstrap-windows.ps1"; exit 1 ;;
    esac

# Create the developer signing key if it does not exist
key:
    scripts/make-developer-key.sh

# List device ids RepFlow can be built for right now
devices:
    scripts/devices.sh

# List every device definition installed locally
devices-all:
    scripts/devices.sh --all

# List manifest products whose definitions are not installed
devices-missing:
    scripts/devices.sh --missing

# Build a signed PRG for a device
build target=device:
    TYPECHECK={{typecheck}} scripts/build.sh {{target}}

# Build every device declared in manifest.xml and installed locally
build-all:
    TYPECHECK={{typecheck}} scripts/build.sh --all

# Run the unit tests in the simulator
test target=device:
    TYPECHECK={{typecheck}} scripts/test.sh {{target}}
    scripts/test-backend.sh

# Run only the watch app's tests
test-watch target=device:
    TYPECHECK={{typecheck}} scripts/test.sh {{target}}

# Run only the Garmin Connect / Hevy backend's tests
test-backend:
    scripts/test-backend.sh

# Install the backend that syncs a finished session (one time)
backend-setup:
    python3 -m venv backend/.venv
    backend/.venv/bin/pip -q install --upgrade pip
    backend/.venv/bin/pip -q install -e 'backend[dev]'
    @echo "[OK]   backend ready"

# Preview the exercise table that would be written to Garmin Connect
sync-garmin-show activity="":
    backend/.venv/bin/repflow-garmin show {{ if activity == "" { "" } else { "--activity " + activity } }}

# Write sets, reps and loads into the Garmin activity's exercise table
sync-garmin activity="":
    backend/.venv/bin/repflow-garmin fill {{ if activity == "" { "" } else { "--activity " + activity } }}

# Preview the workout that would be posted to Hevy
sync-hevy-show activity="":
    backend/.venv/bin/repflow-garmin hevy --dry-run {{ if activity == "" { "" } else { "--activity " + activity } }}

# Post the last RepFlow session to Hevy (asks for the API key)
sync-hevy activity="":
    backend/.venv/bin/repflow-garmin hevy {{ if activity == "" { "" } else { "--activity " + activity } }}

# Build and launch RepFlow in the simulator (returns to the prompt)
sim target=device:
    REPFLOW_DETACH=1 scripts/run-simulator.sh {{target}}

# Same, but clear the app's stored session first
sim-fresh target=device:
    REPFLOW_DETACH=1 REPFLOW_RESET=1 scripts/run-simulator.sh {{target}}

# Launch and stay attached, streaming the app's println output
sim-attach target=device:
    scripts/run-simulator.sh {{target}}

# Screenshot the simulator's watch face to build/sim-shot.png
shot:
    scripts/shot.sh

# Build and copy a release PRG to a USB-connected watch
sideload target=device:
    scripts/sideload.sh {{target}}

# Full release build: doctor, tests, all devices, .iq bundle
package:
    scripts/package.sh

# Everything package does, plus the release checklist reminder
release-check:
    scripts/package.sh
    @echo ""
    @echo "Now work through docs/RELEASE_CHECKLIST.md before submitting."

# Remove build output
clean:
    rm -rf build && mkdir -p build && echo "build/ cleaned"
