#!/usr/bin/env bash
# Build and run the RepFlow unit tests (Garmin "Run No Evil" test framework).
#
#   scripts/test.sh [device_id] [test_name]
#
# Tests execute inside the Connect IQ Simulator, which is a GUI application, so
# the simulator is started automatically and left running.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

activate_sdk

DEVICE="${1:-$DEFAULT_DEVICE}"
TEST_NAME="${2:-}"
require_device_installed "$DEVICE"
[ -f "$DEVELOPER_KEY" ] || die "No developer key at $DEVELOPER_KEY. Run scripts/make-developer-key.sh"

mkdir -p "$BUILD_DIR"
PRG="$BUILD_DIR/RepFlow-test-$DEVICE.prg"

# -t compiles the (:test) annotated code into the binary.
info "Building test binary for $DEVICE..."
monkeyc \
  -f "$REPO_ROOT/monkey.jungle" \
  -o "$PRG" \
  -y "$DEVELOPER_KEY" \
  -d "$DEVICE" \
  -l "${TYPECHECK:-2}" \
  --warn \
  -t
ok "Test binary built: $PRG"

simulator_running() {
  if [ "$(uname -s)" = "Darwin" ]; then
    pgrep -f "ConnectIQ.app/Contents/MacOS" >/dev/null 2>&1
  else
    pgrep -f "$SDK_HOME/bin/simulator" >/dev/null 2>&1
  fi
}

if ! simulator_running; then
  info "Starting Connect IQ Simulator..."
  connectiq >/dev/null 2>&1 || die "Could not start the simulator. Start it, then re-run this script."
  for _ in $(seq 1 30); do
    simulator_running && break
    sleep 1
  done
fi

LOG="$BUILD_DIR/test-$DEVICE.log"
info "Running tests on $DEVICE..."
set +e
if [ -n "$TEST_NAME" ]; then
  monkeydo "$PRG" "$DEVICE" -t "$TEST_NAME" 2>&1 | tee "$LOG"
else
  monkeydo "$PRG" "$DEVICE" -t 2>&1 | tee "$LOG"
fi
set -e

echo
# monkeydo exits 0 even when tests fail, so the summary line is authoritative.
# Run No Evil prints one of:
#   PASSED (passed=18, failed=0, errors=0)
#   FAILED (passed=13, failed=0, errors=5)
SUMMARY="$(grep -E '^(PASSED|OK|FAILED) \(passed=' "$LOG" | tail -1)"

if [ -z "$SUMMARY" ]; then
  fail "Could not determine the test outcome. Full output in $LOG"
  exit 1
fi

info "$(grep -E '^Ran [0-9]+ test' "$LOG" | tail -1)"
if [ "${SUMMARY#FAILED}" != "$SUMMARY" ]; then
  fail "Tests FAILED — $SUMMARY"
  echo
  info "Failing tests:"
  grep -E '^\S+ +(FAIL|ERROR)$' "$LOG" | sed 's/^/       /'
  info "Full output: $LOG"
  exit 1
fi

ok "Tests PASSED — $SUMMARY"
exit 0
