#!/usr/bin/env bash
# Shared helpers for the RepFlow scripts. Source this; do not execute it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Where Garmin's tooling keeps the SDKs and downloaded device definitions.
case "$(uname -s)" in
  Darwin) CIQ_HOME="$HOME/Library/Application Support/Garmin/ConnectIQ" ;;
  *)      CIQ_HOME="${CIQ_HOME:-$HOME/.Garmin/ConnectIQ}" ;;
esac

DEVICES_DIR="$CIQ_HOME/Devices"

# The developer signing key lives OUTSIDE the repository. See docs/SIGNING.md.
DEVELOPER_KEY="${REPFLOW_DEVELOPER_KEY:-$HOME/.garmin/repflow/developer_key.der}"

BUILD_DIR="$REPO_ROOT/build"

# Default build target. Override with DEVICE=<id> or `make build DEVICE=<id>`.
DEFAULT_DEVICE="${DEVICE:-fenix6pro}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BOLD=""; C_OFF=""
fi

ok()    { printf '%s[OK]%s   %s\n' "$C_GREEN" "$C_OFF" "$*"; }
warn()  { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_OFF" "$*"; }
fail()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_OFF" "$*"; }
info()  { printf '       %s\n' "$*"; }
die()   { fail "$*"; exit 1; }

# Resolve the active SDK directory, honouring current-sdk.cfg.
resolve_sdk() {
  if [ -n "${CIQ_SDK_HOME:-}" ] && [ -x "$CIQ_SDK_HOME/bin/monkeyc" ]; then
    printf '%s' "${CIQ_SDK_HOME%/}"
    return 0
  fi
  local cfg="$CIQ_HOME/current-sdk.cfg"
  if [ -f "$cfg" ]; then
    local sdk
    sdk="$(tr -d '\n\r' < "$cfg")"
    sdk="${sdk%/}"
    if [ -x "$sdk/bin/monkeyc" ]; then
      printf '%s' "$sdk"
      return 0
    fi
  fi
  # Fall back to the newest SDK present.
  local newest
  newest="$(find "$CIQ_HOME/Sdks" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -1)"
  if [ -n "$newest" ] && [ -x "$newest/bin/monkeyc" ]; then
    printf '%s' "$newest"
    return 0
  fi
  return 1
}

# Put the SDK's bin on PATH for the current shell only — never edits dotfiles.
activate_sdk() {
  SDK_HOME="$(resolve_sdk)" || die "No Connect IQ SDK found. Run scripts/bootstrap-macos.sh (or doctor.sh for details)."
  export SDK_HOME
  export PATH="$SDK_HOME/bin:$PATH"
  SDK_VERSION="$(cat "$SDK_HOME/bin/version.txt" 2>/dev/null || echo unknown)"
  export SDK_VERSION
}

# Device ids that are BOTH listed in manifest.xml and installed locally.
buildable_devices() {
  local manifest="$REPO_ROOT/manifest.xml"
  [ -d "$DEVICES_DIR" ] || return 0
  grep -o 'iq:product id="[^"]*"' "$manifest" | sed 's/.*id="//;s/"//' | while read -r id; do
    [ -f "$DEVICES_DIR/$id/compiler.json" ] && echo "$id"
  done
}

installed_devices() {
  [ -d "$DEVICES_DIR" ] || return 0
  find "$DEVICES_DIR" -maxdepth 2 -name compiler.json 2>/dev/null \
    | sed "s|$DEVICES_DIR/||;s|/compiler.json||" | sort
}

require_device_installed() {
  local id="$1"
  if [ ! -f "$DEVICES_DIR/$id/compiler.json" ]; then
    fail "Device '$id' is not installed."
    info "Installed devices: $(installed_devices | tr '\n' ' ')"
    info "Download more with the Connect IQ SDK Manager (see docs/ENVIRONMENT.md)."
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Connect IQ Simulator
# ---------------------------------------------------------------------------

simulator_running() {
  pgrep -f "ConnectIQ.app/Contents/MacOS" >/dev/null 2>&1 \
    || pgrep -x simulator >/dev/null 2>&1
}

# Launch the simulator if it is not already up. Being "up" as a process does not
# mean it is ready to accept a push, so callers must still retry — see
# monkeydo_retry below.
ensure_simulator() {
  if simulator_running; then
    return 0
  fi
  info "Starting Connect IQ Simulator..."
  connectiq >/dev/null 2>&1 || return 1
  local i
  for i in $(seq 1 30); do
    simulator_running && break
    sleep 1
  done
  # Give the freshly started GUI a moment to open its listening socket.
  sleep 3
  return 0
}

# Push to the simulator, retrying while it is still coming up.
# "Unable to connect to simulator" is what monkeydo prints in that window, and
# it still exits 0, so the output has to be inspected rather than the status.
#   monkeydo_retry <log file> <prg> <device> [extra monkeydo args...]
monkeydo_retry() {
  local log="$1"; shift
  local attempt
  for attempt in 1 2 3 4 5; do
    set +e
    monkeydo "$@" > "$log" 2>&1
    set -e
    if ! grep -q "Unable to connect to simulator" "$log"; then
      cat "$log"
      return 0
    fi
    if [ "$attempt" -lt 5 ]; then
      info "Simulator not ready yet (attempt $attempt/5) — retrying..."
      ensure_simulator || true
      sleep 4
    fi
  done
  cat "$log"
  return 1
}

# ---------------------------------------------------------------------------
# Simulator crash log
#
# monkeydo reports "Encountered an app crash" by reading the simulator's shared
# crash log, which EVERY binary writes to — the -test build included, and
# sometimes only flushed after the run that produced it has ended. A record left
# by an earlier run is therefore reported against a later, healthy one.
#
# These helpers make the signal deterministic: clear the log before a run, and
# read back only what that run actually wrote.
# ---------------------------------------------------------------------------

ciq_log_path() {
  printf '%s' "${TMPDIR:-/tmp}/com.garmin.connectiq/GARMIN/APPS/LOGS/CIQ_LOG.YML"
}

clear_ciq_log() {
  local log
  log="$(ciq_log_path)"
  [ -f "$log" ] && : > "$log"
  return 0
}

# Print any crash recorded since clear_ciq_log, and return 1 when there was one.
report_ciq_crash() {
  local log
  log="$(ciq_log_path)"
  if [ ! -s "$log" ]; then
    return 0
  fi
  fail "The simulator recorded a crash:"
  sed 's/^/       /' "$log"
  info "Full log: $log"
  return 1
}

# ---------------------------------------------------------------------------
# Simulator app data
# ---------------------------------------------------------------------------

# Wipe RepFlow's persisted storage in the simulator, so the next launch starts
# from the workout picker instead of resuming whatever session was left behind.
#
# Matched by a RepFlow-prefixed glob rather than the exact PRG name: the
# simulator does NOT name app storage after the binary you pushed (running
# RepFlow-fenix6pro.prg writes REPFLOW-TEST-FENIX6PRO.DAT), so an exact match
# silently does nothing. The glob still never touches another app's data.
clear_sim_app_data() {
  local apps="${TMPDIR:-/tmp}/com.garmin.connectiq/GARMIN/APPS"
  [ -d "$apps" ] || return 0

  local f
  for f in "$apps"/DATA/[Rr][Ee][Pp][Ff][Ll][Oo][Ww]*; do
    [ -e "$f" ] && rm -rf "$f"
  done
  for f in "$apps"/DATA/MEDIA/OBJSTORE/[Rr][Ee][Pp][Ff][Ll][Oo][Ww]*; do
    [ -e "$f" ] && rm -rf "$f"
  done
  return 0
}

# ---------------------------------------------------------------------------
# Interactive device picker
# ---------------------------------------------------------------------------

# Print a numbered list of buildable devices and read a choice on stdin.
# The chosen id goes to stdout; everything the human reads goes to stderr, so
# the caller can use this in a $(...).
choose_device() {
  local devices=()
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && devices+=("$line")
  done < <(buildable_devices)

  if [ "${#devices[@]}" -eq 0 ]; then
    die "No devices installed. See docs/ENVIRONMENT.md."
  fi

  # Remember the last choice, so the common case is one keypress.
  local last_file="$BUILD_DIR/.last-device"
  local last=""
  [ -f "$last_file" ] && last="$(cat "$last_file")"

  printf '\n%sChoose a device%s\n\n' "$C_BOLD" "$C_OFF" >&2
  local i
  for i in "${!devices[@]}"; do
    local marker="  "
    [ "${devices[$i]}" = "$last" ] && marker="${C_GREEN}*${C_OFF} "
    printf '  %s%2d) %s\n' "$marker" "$((i + 1))" "${devices[$i]}" >&2
  done

  local prompt="number"
  if [ -n "$last" ]; then
    prompt="number, or Enter for $last"
  fi

  local choice
  while true; do
    printf '\n  %s: ' "$prompt" >&2
    read -r choice || choice=""

    if [ -z "$choice" ] && [ -n "$last" ]; then
      printf '%s' "$last"
      return 0
    fi
    # A device id typed in full is fine too.
    if [ -f "$DEVICES_DIR/$choice/compiler.json" ]; then
      printf '%s' "$choice" > "$last_file" 2>/dev/null || true
      printf '%s' "$choice"
      return 0
    fi
    if printf '%s' "$choice" | grep -qE '^[0-9]+$' \
       && [ "$choice" -ge 1 ] && [ "$choice" -le "${#devices[@]}" ]; then
      local picked="${devices[$((choice - 1))]}"
      mkdir -p "$BUILD_DIR"
      printf '%s' "$picked" > "$last_file" 2>/dev/null || true
      printf '%s' "$picked"
      return 0
    fi
    printf '  %sNot a choice on the list.%s\n' "$C_YELLOW" "$C_OFF" >&2
  done
}
