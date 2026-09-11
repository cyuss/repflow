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
info "Pushing RepFlow to the simulator..."
if [ -n "${REPFLOW_DETACH:-}" ]; then
  if monkeydo_retry "$BUILD_DIR/sim-$DEVICE.log" "$PRG" "$DEVICE" >/dev/null; then
    ok "RepFlow pushed to the simulator on $DEVICE (detached)."
    info "App output: $BUILD_DIR/sim-$DEVICE.log"
    exit 0
  fi
  fail "Could not reach the simulator."
  exit 1
fi

info "monkeydo stays attached while the app runs — Ctrl-C to detach."
if monkeydo "$PRG" "$DEVICE"; then
  ok "RepFlow session on $DEVICE ended."
else
  fail "monkeydo could not reach the simulator."
  info "Make sure the simulator window is open, then run:"
  info "  monkeydo \"$PRG\" $DEVICE"
  exit 1
fi
