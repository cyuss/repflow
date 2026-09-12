#!/usr/bin/env bash
# Send button presses to the Connect IQ Simulator.
#
# Development aid, for driving the app while looking at screenshots.
#
#   scripts/press.sh start            one press
#   scripts/press.sh down down start  a sequence
#
# Buttons: start (or enter), back (esc), up, down, menu (long UP).
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

simulator_running || die "The simulator is not running. Try: make sim"

focus() {
  osascript -e 'tell application "System Events" to tell process "simulator" to set frontmost to true' >/dev/null 2>&1 || true
  sleep 0.4
}

key() {
  osascript -e "tell application \"System Events\" to key code $1" >/dev/null 2>&1
  sleep 1.2
}

# MENU is a long press of UP, which has no key equivalent — click the button on
# the watch image instead, positioned from the window's own geometry.
long_up() {
  command -v cliclick >/dev/null 2>&1 || die "MENU needs cliclick: brew install cliclick"
  local geometry
  geometry="$(osascript -e '
    tell application "System Events" to tell process "simulator"
      get {position, size} of window 1
    end tell' 2>/dev/null)"
  local wx wy ww wh
  read -r wx wy ww wh <<<"$(printf '%s' "$geometry" | tr -d ' ' | tr ',' ' ')"
  # The UP/MENU button sits on the left edge, a little above the middle of the
  # watch image, which occupies the top ~45% of the window.
  local x=$((wx + ww * 5 / 100))
  local y=$((wy + wh * 17 / 100))
  cliclick "dd:${x},${y}" w:1300 "du:${x},${y}" >/dev/null
  sleep 1.2
}

focus
for button in "$@"; do
  case "$button" in
    start|enter|select) key 36 ;;
    back|esc)           key 53 ;;
    up)                 key 126 ;;
    down)               key 125 ;;
    menu)               long_up ;;
    *) die "Unknown button: $button (start|back|up|down|menu)" ;;
  esac
done
