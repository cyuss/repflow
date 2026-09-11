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
