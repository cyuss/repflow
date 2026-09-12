#!/usr/bin/env bash
# Capture the Connect IQ Simulator's watch face to a PNG.
#
# The simulator is a GUI app with no screenshot CLI, so this locates its window,
# brings it to the front and crops the watch out of a screen grab.
#
# This is a development aid, not part of the build — but an important one: three
# layout bugs in this app were invisible to the compiler and to the unit suite
# and obvious in one screenshot. Look at the screen before believing a layout.
#
#   scripts/shot.sh [out.png]
#
# Needs imagemagick (brew install imagemagick).

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

OUT="${1:-$BUILD_DIR/sim-shot.png}"
command -v magick >/dev/null 2>&1 || die "needs imagemagick: brew install imagemagick"

simulator_running || die "The simulator is not running. Try: make sim"

# Ask the window where it is, rather than assuming — it moves between sessions.
GEOMETRY="$(osascript -e '
  tell application "System Events" to tell process "simulator"
    set frontmost to true
    get {position, size} of window 1
  end tell' 2>/dev/null || true)"
[ -n "$GEOMETRY" ] || die "Could not find the simulator window."
sleep 1

read -r WIN_X WIN_Y WIN_W WIN_H <<<"$(printf '%s' "$GEOMETRY" | tr -d ' ' | tr ',' ' ')"

# The watch sits in the upper portion of the window; crop generously around it
# and let the resize make the detail readable.
CROP_W=$((WIN_W - 40))
CROP_H=$((WIN_H * 45 / 100))
CROP_X=$((WIN_X + 20))
CROP_Y=$((WIN_Y + 20))

mkdir -p "$(dirname "$OUT")"
TMP="$(mktemp -t repflow-screen).png"
screencapture -o -x "$TMP"
magick "$TMP" -crop "${CROP_W}x${CROP_H}+${CROP_X}+${CROP_Y}" +repage -resize 200% "$OUT"
rm -f "$TMP"
ok "$OUT"
