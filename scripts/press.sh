#!/usr/bin/env bash
# Send button presses to the Connect IQ Simulator.
#
# Development aid, for driving the app while looking at screenshots.
#
#   scripts/press.sh start            one press
#   scripts/press.sh down down start  a sequence
#
# Buttons: start (or enter), back (esc), up, down, menu (long UP), light.
#
# The presses are clicks on the buttons of the watch image, not keystrokes.
# Keystrokes look simpler and are not: the simulator only takes them when its
# window holds the keyboard focus, which a script cannot count on, and MENU has
# no key at all because it is a long press of UP.
#
# The watch image is drawn at a fixed size anchored to the top-left of the
# window — it does not scale when the window is resized — so a button sits at a
# fixed offset from the window's own corner. The offsets below were measured
# from a screen grab, one device at a time. An earlier version of this script
# computed them as a percentage of the window size, which put every press into
# the empty space beside the watch as soon as the window was resized.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

command -v cliclick >/dev/null 2>&1 || die "needs cliclick: brew install cliclick"
simulator_running || die "The simulator is not running. Try: make sim"

# Button offsets from the simulator window's top-left corner, per device:
#   light  up/menu  down  start  back
# To add a device: run `make shot`, find the buttons on the watch image, and
# write down where they are relative to the window corner.
offsets_for() {
  case "$1" in
    fenix6pro|fenix6spro|fenix6xpro)
      echo "32,205 17,298 37,393 379,198 376,388" ;;
    *)
      return 1 ;;
  esac
}

# Which device the simulator is showing. It records the answer itself.
sim_device() {
  local ini="$CIQ_HOME/simulator.ini"
  [ -f "$ini" ] || return 1
  sed -n 's/^LastUsedDevice=//p' "$ini" | tail -1
}

window_geometry() {
  osascript -e '
    tell application "System Events" to tell process "simulator"
      repeat with w in windows
        if name of w starts with "CIQ Simulator" then
          return {position of w, size of w}
        end if
      end repeat
    end tell' 2>/dev/null | tr -d ' ' | tr ',' ' '
}

DEVICE_ID="${REPFLOW_SIM_DEVICE:-$(sim_device || true)}"
[ -n "$DEVICE_ID" ] || die "Could not tell which device the simulator is showing."

if ! read -r O_LIGHT O_UP O_DOWN O_START O_BACK <<<"$(offsets_for "$DEVICE_ID")"; then
  fail "No button positions recorded for $DEVICE_ID."
  info "Add them to offsets_for() in $0 — the comment above says how."
  exit 1
fi

read -r WIN_X WIN_Y _ _ <<<"$(window_geometry)"
[ -n "${WIN_Y:-}" ] || die "Could not find the simulator window."

# Raising the window is not enough on its own: a click is what makes the
# simulator treat the press as coming from the front.
osascript -e 'tell application "System Events" to tell process "simulator" to set frontmost to true' >/dev/null 2>&1 || true
sleep 0.6

# "x,y" relative to the window, as absolute screen coordinates.
at() {
  local dx="${1%%,*}" dy="${1##*,}"
  printf '%s,%s' "$((WIN_X + dx))" "$((WIN_Y + dy))"
}

for button in "$@"; do
  case "$button" in
    light)              cliclick "c:$(at "$O_LIGHT")" >/dev/null ;;
    up)                 cliclick "c:$(at "$O_UP")" >/dev/null ;;
    down)               cliclick "c:$(at "$O_DOWN")" >/dev/null ;;
    start|enter|select) cliclick "c:$(at "$O_START")" >/dev/null ;;
    back|esc)           cliclick "c:$(at "$O_BACK")" >/dev/null ;;
    # MENU is a long press of UP. 1.5 s clears the firmware's threshold with
    # room to spare; anything near it is read as a short press instead.
    menu)               P="$(at "$O_UP")"; cliclick "dd:$P" w:1500 "du:$P" >/dev/null ;;
    *) die "Unknown button: $button (start|back|up|down|menu|light)" ;;
  esac
  sleep 1.2
done
