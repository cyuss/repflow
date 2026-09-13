#!/usr/bin/env bash
#
# Run the backend's tests.
#
# The backend is optional: it fills in Garmin Connect's native exercise table
# after a session, and the watch app is complete without it. So a machine with
# no virtualenv is not a failure — it is a machine that has not set the backend
# up, and `make test` should still pass there.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
venv="$here/backend/.venv"

if [[ ! -x "$venv/bin/python" ]]; then
    echo "[skip] backend tests — no virtualenv."
    echo "       Set it up with: make backend-setup"
    exit 0
fi

cd "$here/backend"
"$venv/bin/python" -m pytest tests -q
