#!/usr/bin/env bash
# Set up a RepFlow development environment on macOS.
#
# Installs (only what is missing): a JDK, the Connect IQ SDK, the SDK Manager,
# VS Code + the Garmin Monkey C extension, and a developer signing key.
#
# Nothing outside the Connect IQ directories and ~/.garmin is modified, and no
# shell configuration file is edited: scripts/lib.sh puts the SDK on PATH for
# the commands that need it.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[ "$(uname -s)" = "Darwin" ] || die "This script is for macOS. Use bootstrap-linux.sh or bootstrap-windows.ps1."

# Homebrew ------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  die "Homebrew is required. Install it from https://brew.sh and re-run."
fi
ok "Homebrew"

# Java ----------------------------------------------------------------
JAVA_MAJOR="$(java -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' || true)"
if [ -z "$JAVA_MAJOR" ] || [ "$JAVA_MAJOR" -lt 11 ]; then
  info "Installing a JDK (Connect IQ requires Java 11+)..."
  brew install --cask temurin
fi
ok "Java $(java -version 2>&1 | head -1)"

# Connect IQ SDK ------------------------------------------------------
if resolve_sdk >/dev/null 2>&1; then
  ok "Connect IQ SDK already installed ($(cat "$(resolve_sdk)/bin/version.txt"))"
else
  info "Fetching the Connect IQ SDK catalogue from Garmin..."
  FEED="https://developer.garmin.com/downloads/connect-iq/sdks"
  TMP="$(mktemp -d)"
  curl -fsSL "$FEED/sdks.json" -o "$TMP/sdks.json" \
    || die "Could not reach Garmin's SDK feed. Install the SDK with the SDK Manager instead."

  # Latest entry in the feed is the newest SDK.
  DMG="$(python3 -c "
import json,sys
d=json.load(open('$TMP/sdks.json'))
print(d[-1]['mac'])
")"
  VER="$(python3 -c "
import json
d=json.load(open('$TMP/sdks.json'))
print(d[-1]['version'])
")"
  info "Downloading Connect IQ SDK $VER..."
  curl -fL "$FEED/$DMG" -o "$TMP/sdk.dmg" || die "SDK download failed."

  info "Installing..."
  MOUNT="$(hdiutil attach -nobrowse -readonly "$TMP/sdk.dmg" | tail -1 | cut -f3-)"
  SRC="$(find "$MOUNT" -maxdepth 1 -mindepth 1 -type d -name 'connectiq-sdk-*' | head -1)"
  [ -n "$SRC" ] || { hdiutil detach "$MOUNT" >/dev/null; die "Unexpected SDK image layout."; }
  mkdir -p "$CIQ_HOME/Sdks"
  DEST="$CIQ_HOME/Sdks/$(basename "$SRC")"
  cp -R "$SRC" "$DEST"
  hdiutil detach "$MOUNT" >/dev/null
  rm -rf "$TMP"
  chmod +x "$DEST/bin/"* 2>/dev/null || true
  printf '%s/' "$DEST" > "$CIQ_HOME/current-sdk.cfg"
  ok "Connect IQ SDK $VER installed at $DEST"
fi

# SDK Manager — needed to download device definitions ------------------
if [ -d "/Applications/SdkManager.app" ]; then
  ok "Connect IQ SDK Manager"
else
  info "Installing the Connect IQ SDK Manager..."
  brew install --cask connectiq-sdk-manager || warn "SDK Manager install failed; install it by hand."
fi

# VS Code + Monkey C extension ----------------------------------------
if [ -d "/Applications/Visual Studio Code.app" ] || command -v code >/dev/null 2>&1; then
  ok "VS Code"
else
  info "Installing VS Code..."
  brew install --cask visual-studio-code || warn "VS Code install failed (optional)."
fi
if command -v code >/dev/null 2>&1; then
  if code --list-extensions 2>/dev/null | grep -qi "garmin.monkey-c"; then
    ok "Monkey C VS Code extension"
  else
    info "Installing the Garmin Monkey C VS Code extension..."
    code --install-extension garmin.monkey-c >/dev/null 2>&1 \
      && ok "Monkey C extension installed" \
      || warn "Could not install the Monkey C extension automatically."
  fi
else
  warn "The 'code' command is not on PATH — install the Monkey C extension from"
  warn "the VS Code Extensions panel (search for 'Monkey C' by Garmin)."
fi

# Developer signing key -----------------------------------------------
"$REPO_ROOT/scripts/make-developer-key.sh"

# Device definitions --------------------------------------------------
echo
if [ "$(installed_devices | wc -l | tr -d ' ')" -eq 0 ]; then
  warn "No device definitions installed yet — RepFlow cannot be compiled without them."
  echo
  printf '%sMANUAL STEP (requires your Garmin account):%s\n' "$C_BOLD" "$C_OFF"
  info "1. Open /Applications/SdkManager.app"
  info "2. Sign in with your Garmin developer account and accept the SDK licence"
  info "3. Open the 'Devices' tab and download the devices you target"
  info "   (at minimum: fenix6pro, fenix847mm, fenix8pro47mm)"
  info "4. Re-run scripts/doctor.sh"
  echo
  info "Garmin only distributes device definitions through the signed-in SDK"
  info "Manager, so this step cannot be automated."
else
  ok "Device definitions: $(installed_devices | wc -l | tr -d ' ') installed"
fi

echo
"$REPO_ROOT/scripts/doctor.sh" || true
