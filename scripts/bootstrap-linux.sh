#!/usr/bin/env bash
# Set up a RepFlow development environment on Linux.
#
# The Connect IQ SDK is distributed as a zip; device definitions still come from
# the (GUI, signed-in) SDK Manager.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[ "$(uname -s)" = "Linux" ] || die "This script is for Linux."

# Detect the package manager --------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
  PM_INSTALL="sudo apt-get install -y"
  JDK_PKG="openjdk-17-jdk"
elif command -v dnf >/dev/null 2>&1; then
  PM_INSTALL="sudo dnf install -y"
  JDK_PKG="java-17-openjdk-devel"
elif command -v pacman >/dev/null 2>&1; then
  PM_INSTALL="sudo pacman -S --noconfirm"
  JDK_PKG="jdk17-openjdk"
elif command -v zypper >/dev/null 2>&1; then
  PM_INSTALL="sudo zypper install -y"
  JDK_PKG="java-17-openjdk-devel"
else
  die "Unsupported distribution: install a JDK 11+, curl, unzip and openssl manually."
fi
ok "Package manager detected"

# Java -------------------------------------------------------------------
JAVA_MAJOR="$(java -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' || true)"
if [ -z "$JAVA_MAJOR" ] || [ "$JAVA_MAJOR" -lt 11 ]; then
  info "Installing $JDK_PKG (needs sudo)..."
  $PM_INSTALL "$JDK_PKG"
fi
ok "Java $(java -version 2>&1 | head -1)"

for tool in curl unzip openssl; do
  command -v "$tool" >/dev/null 2>&1 || $PM_INSTALL "$tool"
done

# Connect IQ SDK ---------------------------------------------------------
if resolve_sdk >/dev/null 2>&1; then
  ok "Connect IQ SDK already installed ($(cat "$(resolve_sdk)/bin/version.txt"))"
else
  FEED="https://developer.garmin.com/downloads/connect-iq/sdks"
  TMP="$(mktemp -d)"
  info "Fetching the Connect IQ SDK catalogue..."
  curl -fsSL "$FEED/sdks.json" -o "$TMP/sdks.json" || die "Could not reach Garmin's SDK feed."
  ZIP="$(python3 -c "import json;print(json.load(open('$TMP/sdks.json'))[-1]['linux'])")"
  VER="$(python3 -c "import json;print(json.load(open('$TMP/sdks.json'))[-1]['version'])")"
  info "Downloading Connect IQ SDK $VER..."
  curl -fL "$FEED/$ZIP" -o "$TMP/sdk.zip" || die "SDK download failed."
  DEST="$CIQ_HOME/Sdks/connectiq-sdk-lin-$VER"
  mkdir -p "$DEST"
  unzip -q "$TMP/sdk.zip" -d "$DEST"
  rm -rf "$TMP"
  chmod +x "$DEST/bin/"* 2>/dev/null || true
  mkdir -p "$CIQ_HOME"
  printf '%s/' "$DEST" > "$CIQ_HOME/current-sdk.cfg"
  ok "Connect IQ SDK $VER installed at $DEST"
  info "The Linux simulator also needs 32-bit/GTK libraries on some distros;"
  info "see docs/ENVIRONMENT.md if the simulator refuses to start."
fi

# Developer signing key --------------------------------------------------
"$REPO_ROOT/scripts/make-developer-key.sh"

echo
if [ "$(installed_devices | wc -l | tr -d ' ')" -eq 0 ]; then
  warn "No device definitions installed — RepFlow cannot be compiled without them."
  printf '%sMANUAL STEP (requires your Garmin account):%s\n' "$C_BOLD" "$C_OFF"
  info "Download the Connect IQ SDK Manager from"
  info "  https://developer.garmin.com/connect-iq/sdk/"
  info "sign in, and download the device definitions you target."
fi

echo
"$REPO_ROOT/scripts/doctor.sh" || true
