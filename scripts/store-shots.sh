#!/usr/bin/env bash
# Open the simulator's own screenshot export, pointed at the store assets folder.
#
#   scripts/store-shots.sh
#
# The Connect IQ Store wants the app's screen at the device's NATIVE resolution
# — 260x260 for a Fenix 6 Pro — not a photograph of the simulator window with a
# bezel around it. Only the simulator can produce that, through
# "File > Save Screen Capture". scripts/shot.sh is the development aid; this is
# the one whose output gets uploaded.
#
# The save panel itself is NOT driven from here. It is a native panel hosted by
# a Java application, and every reliable-looking way of typing into it turned
# out to send the keystrokes somewhere else. Rather than ship something that
# silently saves to the wrong place, this opens the panel, puts the right folder
# on the clipboard, and gets out of the way.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

simulator_running || die "The simulator is not running. Try: make sim"

OUT_DIR="$REPO_ROOT/store-assets/screenshots"
mkdir -p "$OUT_DIR"
BEFORE="$(ls -1 "$OUT_DIR" | wc -l | tr -d ' ')"

printf '%s' "$OUT_DIR" | pbcopy

osascript >/dev/null <<'APPLESCRIPT'
tell application "System Events" to tell process "simulator"
  set frontmost to true
  delay 0.4
  click menu item "Save Screen Capture" of menu 1 of menu bar item "File" of menu bar 1
end tell
APPLESCRIPT

echo
printf '%sMANUAL STEP%s\n' "$C_BOLD" "$C_OFF"
info "The simulator's save panel is open."
info "1. Press Cmd+Shift+G, then Cmd+V — the folder is already on your clipboard:"
info "     $OUT_DIR"
info "2. Name the shot after what it shows (set-screen, rest, recap-zones...)."
info "3. Save."
echo
info "Then run this again for the next screen. The Store wants 1-10 of them."
info "Current contents:"
ls -1 "$OUT_DIR" | grep -v '^\.' || info "  (none yet)"
