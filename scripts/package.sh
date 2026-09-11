#!/usr/bin/env bash
# Prepare a RepFlow release: verify, test, build every supported device, and
# collect the artifacts.
#
# This script does everything that can legitimately be automated. The final
# Connect IQ Store `.iq` bundle is produced by Garmin's own export tooling and
# this script stops and says so rather than fabricating a file.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

activate_sdk

RELEASE_DIR="$BUILD_DIR/release"
VERSION="$(grep -m1 '^## \[' "$REPO_ROOT/CHANGELOG.md" | sed 's/## \[//;s/\].*//' || echo unknown)"

printf '%sRepFlow release packaging — version %s%s\n\n' "$C_BOLD" "$VERSION" "$C_OFF"

# 1. Working tree state ------------------------------------------------
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
    warn "Working tree is dirty. Release builds should come from a clean tree."
    git -C "$REPO_ROOT" status --short | head -20
  else
    ok "Clean git working tree"
  fi
fi

# 2. Doctor ------------------------------------------------------------
info "Running environment checks..."
"$REPO_ROOT/scripts/doctor.sh" >/dev/null || die "doctor.sh reported problems — fix them before releasing."
ok "Environment checks passed"

# 3. Manifest sanity ---------------------------------------------------
MANIFEST="$REPO_ROOT/manifest.xml"
APP_ID="$(grep -o 'id="[0-9A-Fa-f]\{32\}"' "$MANIFEST" | head -1 | sed 's/id="//;s/"//')"
[ -n "$APP_ID" ] || die "Could not read the application UUID from manifest.xml"
ok "Application UUID: $APP_ID"
info "This UUID must never change for a published app (docs/SIGNING.md)."

PERMS="$(grep -c 'uses-permission' "$MANIFEST" || true)"
ok "Declared permissions: $PERMS"
grep -o 'uses-permission id="[^"]*"' "$MANIFEST" | sed 's/.*id="/       - /;s/"//'

PRODUCTS="$(grep -c 'iq:product id=' "$MANIFEST" || true)"
ok "Products declared in manifest: $PRODUCTS"
MISSING="$("$REPO_ROOT/scripts/devices.sh" --missing | tr '\n' ' ')"
if [ -n "${MISSING// /}" ]; then
  warn "Declared but not installed locally (cannot be verified here): $MISSING"
  info "Download them in the SDK Manager to build and ship every declared product."
fi

# 4. Tests -------------------------------------------------------------
TEST_DEVICE="$(buildable_devices | head -1)"
[ -n "$TEST_DEVICE" ] || die "No buildable device available — cannot run the test suite."
info "Running unit tests on $TEST_DEVICE..."
"$REPO_ROOT/scripts/test.sh" "$TEST_DEVICE" || die "Tests failed — release aborted."
ok "Unit tests passed"

# 5. Build every buildable device, release mode ------------------------
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
BUILT=0
for device in $(buildable_devices); do
  info "Building release PRG for $device..."
  RELEASE=1 "$REPO_ROOT/scripts/build.sh" "$device" >/dev/null || die "Build failed for $device"
  cp "$BUILD_DIR/RepFlow-$device.prg" "$RELEASE_DIR/"
  SIZE="$(wc -c < "$RELEASE_DIR/RepFlow-$device.prg" | tr -d ' ')"
  ok "$device — $SIZE bytes"
  BUILT=$((BUILT + 1))
done
[ "$BUILT" -gt 0 ] || die "Nothing was built."

# 6. Collect store assets ---------------------------------------------
cp -R "$REPO_ROOT/store-assets" "$RELEASE_DIR/store-assets"
cp "$REPO_ROOT/CHANGELOG.md" "$RELEASE_DIR/"
ok "Release artifacts collected in $RELEASE_DIR ($BUILT device binaries)"

# 7. The Connect IQ Store bundle --------------------------------------
# `monkeyc -e` ("--package-app") is the official CLI equivalent of VS Code's
# "Monkey C: Export Project". It builds every product declared in manifest.xml
# into a single .iq bundle, so every declared device definition must be
# installed locally for this step to succeed.
echo
IQ="$RELEASE_DIR/RepFlow-$VERSION.iq"
if [ -n "${MISSING// /}" ]; then
  warn "Skipping .iq export: these declared products are not installed:$MISSING"
  info "monkeyc -e needs every product in manifest.xml. Download them in the"
  info "SDK Manager, then re-run this script (or export from VS Code)."
  echo
  printf '%sNEXT MANUAL STEP:%s\n' "$C_BOLD" "$C_OFF"
  echo "Download the missing device definitions, then re-run scripts/package.sh"
  echo "(or: VS Code → Command Palette → Monkey C: Export Project)"
  exit 0
fi

info "Exporting Connect IQ Store bundle with monkeyc --package-app..."
if monkeyc -e -w -r \
    -f "$REPO_ROOT/monkey.jungle" \
    -o "$IQ" \
    -y "$DEVELOPER_KEY" \
    -l "${TYPECHECK:-2}"; then
  [ -f "$IQ" ] || die "monkeyc reported success but $IQ does not exist."
  ok "Store bundle created: $IQ ($(wc -c < "$IQ" | tr -d ' ') bytes)"
  echo
  printf '%sNEXT MANUAL STEP:%s\n' "$C_BOLD" "$C_OFF"
  echo "Upload $IQ at https://apps.garmin.com/developer/upload"
  info "Full submission checklist: docs/CONNECT_IQ_DEPLOYMENT.md"
else
  fail "monkeyc --package-app failed — no .iq file was produced."
  echo
  printf '%sFALLBACK MANUAL STEP:%s\n' "$C_BOLD" "$C_OFF"
  echo "VS Code → Command Palette → Monkey C: Export Project"
  exit 1
fi
