#!/usr/bin/env bash
# Run RepFlow's glance — the real one, in the simulator's glance mode.
#
#   scripts/glance.sh [device]          (default: $DEVICE, else the default device)
#
# The simulator has no command-line switch for glance mode: it is Settings >
# Glance Launch Mode, stored in simulator.ini. run-simulator.sh rewrites that
# line and restarts the simulator when needed (see sim_glance_mode in lib.sh),
# so the app starts as its glance, with the
# glance's memory limit (32 to 64 KB) — the only way to find out whether it
# fits. START on the glance opens the app on Analytics. Every other sim recipe
# puts the simulator back in normal mode.
#
# Glances exist for watch apps from Connect IQ 4 (Fenix 7 and later). A Fenix 6
# is refused here rather than launched into a full app that looks like a
# failed glance.
#
# The glance shows what the app last wrote for it. For demo figures, run
# `just DEMO=1 sim-analytics` once first: the data stays in the simulator.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

DEVICE="${1:-$DEFAULT_DEVICE}"
require_device_installed "$DEVICE"

VERSION="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(d["partNumbers"][0]["connectIQVersion"])
' "$DEVICES_DIR/$DEVICE/compiler.json" 2>/dev/null || echo 0)"
MAJOR="${VERSION%%.*}"
if [ "${MAJOR:-0}" -lt 4 ]; then
  die "$DEVICE runs Connect IQ $VERSION: watch apps only have glances from Connect IQ 4. Try: just glance-memory fenix9pro47mm"
fi

REPFLOW_GLANCE=1 REPFLOW_DETACH=1 "$REPO_ROOT/scripts/run-simulator.sh" "$DEVICE"
info "START on the glance opens RepFlow on Analytics."
