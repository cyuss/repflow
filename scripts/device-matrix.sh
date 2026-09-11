#!/usr/bin/env bash
# Generate the device capability matrix from the INSTALLED device definitions.
#
# Everything printed here is read out of Garmin's own compiler.json /
# simulator.json for each device — nothing is hand-written or guessed.
#
#   scripts/device-matrix.sh            # markdown table for the manifest products
#   scripts/device-matrix.sh --all      # every installed device

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [ "${1:-}" = "--all" ]; then
  DEVICES="$(installed_devices)"
else
  DEVICES="$(buildable_devices)"
fi

if [ -z "$DEVICES" ]; then
  echo "No device definitions installed. See docs/ENVIRONMENT.md." >&2
  exit 1
fi

printf '%s\n' "$DEVICES" | DEVICES_DIR="$DEVICES_DIR" python3 -c '
import json, os, sys

devices_dir = os.environ["DEVICES_DIR"]
ids = [line.strip() for line in sys.stdin if line.strip()]

def load(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {}

print("| Device | Name | Resolution | Shape | Display | App memory | Buttons | Touch | API level |")
print("|---|---|---|---|---|---|---|---|---|")

for did in ids:
    comp = load(os.path.join(devices_dir, did, "compiler.json"))
    sim = load(os.path.join(devices_dir, did, "simulator.json"))

    res = comp.get("resolution") or {}
    resolution = "%sx%s" % (res.get("width", "?"), res.get("height", "?"))

    display = sim.get("display") or {}
    shape = display.get("shape", "?")
    touch = "yes" if display.get("isTouch") else "no"

    # Watch-app memory budget, in KB.
    mem = "?"
    for app in comp.get("appTypes", []) or []:
        if app.get("type") == "watchApp" and app.get("memoryLimit"):
            mem = "%d KB" % (int(app["memoryLimit"]) // 1024)

    # Physical keys, de-duplicated (menu is a hold of another key).
    seen, buttons = set(), []
    for key in sim.get("keys", []) or []:
        kid = key.get("id")
        if kid and kid not in seen:
            seen.add(kid)
            buttons.append(kid)
    buttons = ", ".join(buttons) if buttons else "none"

    api = (comp.get("deviceGroup") or "?").replace("API level ", "")
    name = (comp.get("displayName") or did)

    print("| `%s` | %s | %s | %s | %s | %s | %s | %s | %s |" % (
        did, name, resolution, shape, comp.get("displayType", "?"),
        mem, buttons, touch, api))
'
