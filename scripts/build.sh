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

# ---------------------------------------------------------------------------
# Personal builds: a Hevy key baked in
#
# Typing a 36-character key on a phone is the one step between a sideloaded
# watch and Hevy working by itself. So a key left in secrets/hevy-key.txt (or in
# HEVY_API_KEY) becomes the default value of the hevyApiKey setting for this
# build only.
#
# The key never enters a tracked file. resources/properties.xml is edited in
# place, the build runs, and a trap puts it back — including when the build
# fails, when the SDK dies, and when the shell is interrupted. release-check
# refuses to package while a key is in play, because a published build hands
# every installer read and write over one person's whole training history.
# ---------------------------------------------------------------------------
PROPERTIES="$REPO_ROOT/resources/properties.xml"
KEY_SOURCE="$REPO_ROOT/source/HevyKey.mc"
PROPERTIES_BACKUP=""
KEY_SOURCE_BACKUP=""

restore_properties() {
  if [ -n "$PROPERTIES_BACKUP" ] && [ -f "$PROPERTIES_BACKUP" ]; then
    mv -f "$PROPERTIES_BACKUP" "$PROPERTIES"
    PROPERTIES_BACKUP=""
  fi
  if [ -n "$KEY_SOURCE_BACKUP" ] && [ -f "$KEY_SOURCE_BACKUP" ]; then
    mv -f "$KEY_SOURCE_BACKUP" "$KEY_SOURCE"
    KEY_SOURCE_BACKUP=""
  fi
}

hevy_key() {
  if [ -n "${HEVY_API_KEY:-}" ]; then
    printf '%s' "${HEVY_API_KEY}"
    return
  fi
  if [ -f "$REPO_ROOT/secrets/hevy-key.txt" ]; then
    tr -d '[:space:]' < "$REPO_ROOT/secrets/hevy-key.txt"
  fi
}

inject_hevy_key() {
  local key
  key="$(hevy_key)"
  [ -n "$key" ] || return 0
  # A key is a UUID. Anything else is a typo, and a typo silently baked into a
  # build is worse than no key at all.
  if ! printf '%s' "$key" | grep -qiE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
    die "The Hevy key does not look like a UUID. Check secrets/hevy-key.txt."
  fi
  PROPERTIES_BACKUP="$(mktemp)"
  KEY_SOURCE_BACKUP="$(mktemp)"
  cp "$PROPERTIES" "$PROPERTIES_BACKUP"
  cp "$KEY_SOURCE" "$KEY_SOURCE_BACKUP"
  trap 'restore_properties' EXIT INT TERM
  # Two places, because they reach the watch differently.
  #
  # The property is what the phone's settings pane shows, so a key put there is
  # visible and editable. But a property default only ever reaches a **first
  # install** — an update keeps whatever the property already held, which is how
  # a watch that had RepFlow before the key existed went on saying "No API key"
  # with the key sitting unread inside that very build.
  #
  # The constant has no such history and is read last, after anything the
  # athlete entered themselves.
  python3 - "$PROPERTIES" "$KEY_SOURCE" "$key" <<'PYEOF'
import re, sys
properties, source, key = sys.argv[1], sys.argv[2], sys.argv[3]

text = open(properties, encoding="utf-8").read()
patched, count = re.subn(
    r'(<property id="hevyApiKey"\s+type="string">)[^<]*(</property>)',
    lambda m: m.group(1) + key + m.group(2), text)
if count != 1:
    sys.exit("could not find the hevyApiKey property to inject into")
open(properties, "w", encoding="utf-8").write(patched)

text = open(source, encoding="utf-8").read()
patched, count = re.subn(r'(const COMPILED = ")[^"]*(";)',
                         lambda m: m.group(1) + key + m.group(2), text)
if count != 1:
    sys.exit("could not find HevyKey.COMPILED to inject into")
open(source, "w", encoding="utf-8").write(patched)
PYEOF
  info "Hevy key baked into this build (personal build — do not publish)"
}

inject_hevy_key

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
