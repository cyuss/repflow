#!/usr/bin/env bash
# Capture the simulator's display, at the device's native resolution.
#
#   scripts/store-shots.sh calibrate        once, with the SET screen showing
#   scripts/store-shots.sh <name>           then, one per screen worth showing
#
# Writes store-assets/screenshots/<device>-<name>.png at exactly the device's
# resolution — 260x260 for a Fenix 6 Pro. The Connect IQ Store wants the screen
# the watch draws, not a photograph of the simulator window with a bezel around
# it. scripts/shot.sh is the development aid; this is what gets uploaded.
#
# How it finds the display, without guessing:
#
#   Every RepFlow exercise screen draws a full grey circle at radius
#   (size / 2 - 5) with a pen 5 wide — see Theme.drawProgressRing. Its inner
#   edge is therefore at radius (size / 2 - 7.5), enclosing a black disc of
#   exactly (size - 15) pixels. Measuring that disc in a screen capture gives
#   both the centre of the display and the capture's scale, from geometry the
#   app itself guarantees rather than from a number typed in here.
#
#   The measurement is then checked against the resolution the device
#   definition declares. If they disagree the script refuses rather than
#   producing a plausible-looking screenshot of the wrong region.
#
# Everything outside the round display is masked to black. A round watch has no
# pixels in the corners of its framebuffer, and the simulator paints its device
# artwork there; leaving that in would put bezel in a store screenshot.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

NAME="${1:-}"
[ -n "$NAME" ] || die "Usage: scripts/store-shots.sh calibrate | <name>"
case "$NAME" in
  */*|.*) die "Name must be a plain file name: $NAME" ;;
esac

command -v magick >/dev/null 2>&1 || die "needs imagemagick: brew install imagemagick"
simulator_running || die "The simulator is not running. Try: make sim"

DEVICE="${DEVICE:-$(cat "$BUILD_DIR/.last-device" 2>/dev/null || echo "$DEFAULT_DEVICE")}"
CAL_FILE="$BUILD_DIR/.display-$DEVICE"

# The resolution the device definition declares — the value the capture has to
# agree with.
RESOLUTION="$(python3 -c "
import json, sys
try:
    c = json.load(open('$DEVICES_DIR/$DEVICE/compiler.json'))
    r = c.get('resolution') or {}
    w, h = r.get('width'), r.get('height')
    print(min(w, h) if w and h else '')
except Exception:
    print('')
")"
[ -n "$RESOLUTION" ] || die "Could not read the resolution of $DEVICE. Is its definition installed?"

# ---------------------------------------------------------------- capture ---

window_capture() {
  local geo
  geo="$(osascript -e 'tell application "System Events" to tell process "simulator"
      set frontmost to true
      get {position, size} of window 1
    end tell' 2>/dev/null | tr -d ' ')"
  [ -n "$geo" ] || die "Could not find the simulator window."
  IFS=, read -r WIN_X WIN_Y WIN_W WIN_H <<<"$geo"
  sleep 0.6
  local raw
  raw="$(mktemp -t repflow-cap).png"
  screencapture -o -x "$raw"
  magick "$raw" -crop "${WIN_W}x${WIN_H}+${WIN_X}+${WIN_Y}" +repage "$1"
  rm -f "$raw"
}

# ------------------------------------------------------------- calibrate ----

if [ "$NAME" = "calibrate" ]; then
  WIN="$(mktemp -t repflow-win).png"
  window_capture "$WIN"

  # The largest black component that is smaller than the display itself is the
  # disc inside the progress ring.
  EXPECTED=$((RESOLUTION - 15))
  BOX="$(magick "$WIN" -colorspace Gray -threshold 18% \
      -define connected-components:verbose=true \
      -define connected-components:area-threshold=10000 \
      -connected-components 8 null: 2>&1 \
    | awk -v want="$EXPECTED" '
        $NF ~ /graya\(0/ {
          split($2, a, /[x+]/)
          w = a[1]; h = a[2]
          if (w == want && h == want) { print $2; exit }
        }')"
  rm -f "$WIN"

  [ -n "$BOX" ] || die "Could not find a ${EXPECTED}px disc. Show RepFlow's SET screen, then run this again."

  # box is WxH+X+Y of the inner disc; the display is RESOLUTION centred on it.
  read -r BW BH BX BY <<<"$(printf '%s' "$BOX" | tr 'x+' '  ')"
  CX=$((BX + BW / 2))
  CY=$((BY + BH / 2))
  DX=$((CX - RESOLUTION / 2))
  DY=$((CY - RESOLUTION / 2))
  mkdir -p "$BUILD_DIR"
  printf '%s %s %s\n' "$RESOLUTION" "$DX" "$DY" > "$CAL_FILE"
  ok "Display for $DEVICE: ${RESOLUTION}x${RESOLUTION} at +${DX}+${DY} (window-relative)"
  info "Measured from a ${BW}px disc, which is what Theme.drawProgressRing encloses."
  info "Now: scripts/store-shots.sh <name> for each screen."
  exit 0
fi

# ----------------------------------------------------------------- shoot ----

[ -f "$CAL_FILE" ] || die "Not calibrated for $DEVICE. Show the SET screen and run: scripts/store-shots.sh calibrate"
read -r SIZE DX DY < "$CAL_FILE"

OUT_DIR="$REPO_ROOT/store-assets/screenshots"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/$DEVICE-$NAME.png"

WIN="$(mktemp -t repflow-win).png"
window_capture "$WIN"

RADIUS=$((SIZE / 2))
magick "$WIN" -crop "${SIZE}x${SIZE}+${DX}+${DY}" +repage \
  \( -size "${SIZE}x${SIZE}" xc:black -fill white \
     -draw "circle ${RADIUS},${RADIUS} ${RADIUS},0" -alpha copy \) \
  -compose CopyOpacity -composite \
  -background black -alpha remove -alpha off \
  "$OUT"
rm -f "$WIN"

ok "$OUT  ($(magick identify -format '%wx%h' "$OUT"))"
