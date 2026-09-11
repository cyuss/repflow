#!/usr/bin/env bash
# Build a signed PRG and copy it to a USB-connected Garmin watch.
#
#   scripts/sideload.sh <device_id>
#
# The script never deletes anything on the watch: it only writes
# GARMIN/APPS/RepFlow.prg. See docs/DEVICE_TESTING.md.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

DEVICE="${1:-$DEFAULT_DEVICE}"

# 1. Build an explicitly-targeted, signed release PRG.
info "Building release PRG for $DEVICE..."
RELEASE=1 "$REPO_ROOT/scripts/build.sh" "$DEVICE"
PRG="$BUILD_DIR/RepFlow-$DEVICE.prg"
ok "PRG ready: $PRG"
echo

# 2. Look for a mounted Garmin volume — a watch in USB mass-storage mode has a
#    GARMIN/APPS directory at the root.
find_watch() {
  local base
  case "$(uname -s)" in
    Darwin) base="/Volumes" ;;
    Linux)  base="/media/$USER" ;;
    *)      return 1 ;;
  esac
  [ -d "$base" ] || return 1
  local vol
  for vol in "$base"/*; do
    [ -d "$vol/GARMIN/APPS" ] && { printf '%s' "$vol"; return 0; }
  done
  return 1
}

if ! WATCH="$(find_watch)"; then
  warn "No USB-connected Garmin watch found."
  echo
  printf '%sMANUAL STEP%s\n' "$C_BOLD" "$C_OFF"
  info "1. Connect the watch by USB and make sure it appears as a disk."
  info "   (Modern Fenix models may need MTP mode; see docs/DEVICE_TESTING.md.)"
  info "2. Copy the PRG into the watch's GARMIN/APPS folder:"
  info "     $PRG  ->  <WATCH>/GARMIN/APPS/RepFlow.prg"
  info "3. Eject the watch safely, then open RepFlow from the app list."
  exit 0
fi

ok "Found Garmin device at $WATCH"
DEST="$WATCH/GARMIN/APPS/RepFlow.prg"

if [ -t 0 ] && [ -z "${REPFLOW_ASSUME_YES:-}" ]; then
  printf 'Copy RepFlow to %s ? [y/N] ' "$DEST"
  read -r reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) info "Aborted — nothing was written."; exit 0 ;;
  esac
fi

cp "$PRG" "$DEST"
sync
ok "Copied to $DEST"
echo
info "Next: eject the watch safely, then open RepFlow from the watch's app list."
info "Run the smoke test in docs/SMOKE_TEST.md before calling the build good."
