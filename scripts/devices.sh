#!/usr/bin/env bash
# List Garmin device ids, discovered from the installed SDK — never invented.
#
#   scripts/devices.sh            # devices RepFlow can currently be built for
#   scripts/devices.sh --all      # every device definition installed locally
#   scripts/devices.sh --known    # every device the SDK knows about (reference)
#   scripts/devices.sh --missing  # products in manifest.xml not installed here

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

manifest_products() {
  grep -o 'iq:product id="[^"]*"' "$REPO_ROOT/manifest.xml" | sed 's/.*id="//;s/"//'
}

case "${1:-}" in
  --all)
    installed_devices
    ;;
  --known)
    # Reference artwork bundled with the SDK. NOTE: this folder lags the real
    # device list (SDK 9.2.0 ships no Fenix 9 entries here even though the
    # device definitions exist), so prefer --all for anything authoritative.
    SDK_HOME="$(resolve_sdk)" || die "No Connect IQ SDK found."
    find "$SDK_HOME/resources/device-reference" -maxdepth 1 -mindepth 1 -type d \
      | sed 's|.*/||' | sort
    ;;
  --missing)
    for id in $(manifest_products); do
      [ -f "$DEVICES_DIR/$id/compiler.json" ] || echo "$id"
    done
    ;;
  *)
    buildable_devices
    ;;
esac
