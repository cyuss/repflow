#!/usr/bin/env bash
# Build RepFlow and run it in the Connect IQ Simulator.
#
#   scripts/run-simulator.sh [device_id]
#
# Garmin's simulator is a GUI application; this script launches it and pushes
# the built PRG to it with monkeydo. If the GUI cannot be started (headless
# session, no display) the script says exactly what to do by hand.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

activate_sdk

DEVICE="${1:-$DEFAULT_DEVICE}"
require_device_installed "$DEVICE"

# 1. Compile
info "Building for $DEVICE..."
"$REPO_ROOT/scripts/build.sh" "$DEVICE"
PRG="$BUILD_DIR/RepFlow-$DEVICE.prg"

# Optionally start from a clean slate. Without this the app resumes whatever
# session was stored, which is rarely what you want when you are looking at a
# screen.
#
# The simulator caches app storage in memory and writes it back when the app
# starts, so deleting the files is not enough on its own — it has to be
# restarted as well.
if [ -n "${REPFLOW_RESET:-}" ]; then
  info "Resetting the app's stored session..."
  pkill -f "ConnectIQ.app/Contents/MacOS" >/dev/null 2>&1 || true
  pkill -x simulator >/dev/null 2>&1 || true
  sleep 3
  clear_sim_app_data
fi

# 2. Launch the simulator if it is not already up
if simulator_running; then
  ok "Connect IQ Simulator already running."
elif ! ensure_simulator; then
  fail "Could not launch the Connect IQ Simulator automatically."
  info "Start it by hand, then run:"
  info "  monkeydo \"$PRG\" $DEVICE"
  exit 1
fi

# 3. Push and run
#
# monkeydo stays attached for as long as the app runs, relaying println() output
# to this terminal. That is what you want interactively — press Ctrl-C to detach
# (the app keeps running in the simulator). Set REPFLOW_DETACH=1 to return to the
# shell immediately instead.
# Clear the shared crash log so anything found afterwards belongs to THIS run.
clear_ciq_log

info "Pushing RepFlow to the simulator..."
if [ -n "${REPFLOW_DETACH:-}" ]; then
  # monkeydo stays attached for as long as the app runs, so detaching means
  # backgrounding it and then checking what the run recorded.
  monkeydo "$PRG" "$DEVICE" > "$BUILD_DIR/sim-$DEVICE.log" 2>&1 &
  sleep 8
  if grep -q "Unable to connect to simulator" "$BUILD_DIR/sim-$DEVICE.log" 2>/dev/null; then
    fail "Could not reach the simulator."
    info "Output: $BUILD_DIR/sim-$DEVICE.log"
    exit 1
  fi
  report_ciq_crash || exit 1
  ok "RepFlow is running in the simulator on $DEVICE (detached), no crash recorded."
  info "App output: $BUILD_DIR/sim-$DEVICE.log"
  exit 0
fi

info "monkeydo stays attached while the app runs — Ctrl-C to detach."
if monkeydo "$PRG" "$DEVICE"; then
  report_ciq_crash || exit 1
  ok "RepFlow session on $DEVICE ended with no crash recorded."
else
  fail "monkeydo could not reach the simulator."
  info "Make sure the simulator window is open, then run:"
  info "  monkeydo \"$PRG\" $DEVICE"
  exit 1
fi
