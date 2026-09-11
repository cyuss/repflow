#!/usr/bin/env bash
# Build a signed RepFlow PRG.
#
#   scripts/build.sh                  # DEFAULT_DEVICE, debug
#   scripts/build.sh fenix847mm       # explicit device
#   RELEASE=1 scripts/build.sh ...    # release build (-r)
#   scripts/build.sh --all            # every device in manifest.xml that is installed

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

activate_sdk

[ -f "$DEVELOPER_KEY" ] || die "No developer key at $DEVELOPER_KEY. Run scripts/make-developer-key.sh"

mkdir -p "$BUILD_DIR"

build_one() {
  local device="$1"
  require_device_installed "$device"
  local out="$BUILD_DIR/RepFlow-$device.prg"
  local args=(
    -f "$REPO_ROOT/monkey.jungle"
    -o "$out"
    -y "$DEVELOPER_KEY"
    -d "$device"
    -l "${TYPECHECK:-3}"
    --warn
  )
  if [ -n "${RELEASE:-}" ]; then
    args+=(-r)
  fi
  info "monkeyc -d $device ${RELEASE:+(release)}"
  monkeyc "${args[@]}"
  ok "$out"
}

if [ "${1:-}" = "--all" ]; then
  DEVICES="$(buildable_devices)"
  [ -n "$DEVICES" ] || die "No devices from manifest.xml are installed. See docs/ENVIRONMENT.md."
  FAILED=""
  for d in $DEVICES; do
    if ! build_one "$d"; then
      FAILED="$FAILED $d"
    fi
  done
  if [ -n "$FAILED" ]; then
    die "Failed for:$FAILED"
  fi
  ok "All devices built."
else
  build_one "${1:-$DEFAULT_DEVICE}"
fi
