#!/usr/bin/env bash
# Capture the Connect IQ Simulator's watch face to a PNG.
#
# The simulator is a GUI app with no screenshot CLI, so this grabs the screen
# and crops the watch. Development aid only — not part of the build.
#
#   scripts/shot.sh out.png [crop]      crop defaults to 460x560+2560+120
set -euo pipefail
OUT="${1:-/tmp/repflow-shot.png}"
CROP="${2:-460x560+2560+120}"
command -v magick >/dev/null 2>&1 || { echo "needs imagemagick: brew install imagemagick" >&2; exit 1; }
TMP="$(mktemp -t repflow-screen).png"
screencapture -o -x "$TMP"
magick "$TMP" -crop "$CROP" +repage -resize 300% "$OUT"
rm -f "$TMP"
echo "$OUT"
