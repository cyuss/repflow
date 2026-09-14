#!/usr/bin/env bash
# Report on the RepFlow development environment.
# Exits non-zero when something required to build is missing.

set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
set +e

PROBLEMS=0
note_problem() { PROBLEMS=$((PROBLEMS + 1)); }

printf '%sRepFlow environment%s\n\n' "$C_BOLD" "$C_OFF"

# --- Host -------------------------------------------------------------
info "OS:    $(uname -s) $(uname -r) ($(uname -m))"
info "Shell: ${SHELL:-unknown}"
echo

# --- Java -------------------------------------------------------------
# Garmin documents Java 11 or newer for the Connect IQ SDK.
if command -v java >/dev/null 2>&1; then
  JAVA_RAW="$(java -version 2>&1 | head -1)"
  JAVA_MAJOR="$(printf '%s' "$JAVA_RAW" | sed -n 's/.*version "\([0-9]*\).*/\1/p')"
  if [ -n "$JAVA_MAJOR" ] && [ "$JAVA_MAJOR" -ge 11 ]; then
    ok "Java ($JAVA_RAW)"
  else
    fail "Java is too old, Connect IQ needs 11+: $JAVA_RAW"; note_problem
  fi
else
  fail "Java not found. Install a JDK 11+ (brew install --cask temurin)."; note_problem
fi

# --- SDK --------------------------------------------------------------
if SDK_HOME="$(resolve_sdk)"; then
  export PATH="$SDK_HOME/bin:$PATH"
  ok "Connect IQ SDK $(cat "$SDK_HOME/bin/version.txt" 2>/dev/null || echo '?')"
  info "$SDK_HOME"
else
  fail "Connect IQ SDK not found under $CIQ_HOME/Sdks"; note_problem
  info "Run scripts/bootstrap-macos.sh to install it."
fi

for tool in monkeyc monkeydo connectiq; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool"
  else
    fail "$tool not on PATH (expected in \$SDK_HOME/bin)"; note_problem
  fi
done

# --- Signing key ------------------------------------------------------
if [ -f "$DEVELOPER_KEY" ]; then
  ok "developer signing key"
  info "$DEVELOPER_KEY"
  if git -C "$REPO_ROOT" ls-files --error-unmatch "$DEVELOPER_KEY" >/dev/null 2>&1; then
    fail "The signing key is tracked by git. Remove it from the index immediately."; note_problem
  fi
else
  fail "No developer signing key at $DEVELOPER_KEY"; note_problem
  info "Create one with: scripts/make-developer-key.sh   (see docs/SIGNING.md)"
fi

# --- Devices ----------------------------------------------------------
DEVICE_COUNT="$(installed_devices | wc -l | tr -d ' ')"
if [ "$DEVICE_COUNT" -gt 0 ]; then
  ok "device definitions ($DEVICE_COUNT installed)"
  BUILDABLE="$(buildable_devices | tr '\n' ' ')"
  if [ -n "${BUILDABLE// /}" ]; then
    ok "required device definitions"
    info "buildable from manifest.xml: $BUILDABLE"
  else
    fail "None of the products in manifest.xml are installed locally."; note_problem
    info "Installed: $(installed_devices | tr '\n' ' ')"
  fi
else
  fail "No device definitions installed in $DEVICES_DIR"; note_problem
  info "Open the Connect IQ SDK Manager, sign in with a Garmin account and"
  info "download the device definitions. See docs/ENVIRONMENT.md."
fi

# --- Optional tooling -------------------------------------------------
echo
for tool in git make just openssl; do
  if command -v "$tool" >/dev/null 2>&1; then ok "$tool"; else warn "$tool not found (optional)"; fi
done
if [ -d "/Applications/Visual Studio Code.app" ] || command -v code >/dev/null 2>&1; then
  ok "VS Code (for Monkey C extension / .iq export)"
else
  warn "VS Code not found — needed only for 'Monkey C: Export Project'"
fi

# --- Secrets ----------------------------------------------------------
#
# The one thing in this repository that would be unrecoverable if committed.
# A Hevy key is read and write over a whole training history, it cannot be
# scoped, and git remembers.
#
# Checked precisely rather than broadly. A scan for anything UUID-shaped fires
# on the Hevy exercise ids used as test fixtures and on the app's own UUID, and
# a check that cries wolf is a check nobody reads. There is exactly one place a
# key can end up in a build — the default value of the hevyApiKey property — so
# that is what is checked, in the committed copy rather than the working one,
# because scripts/build.sh edits the working copy on purpose.
echo
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  COMMITTED_KEY="$(git -C "$REPO_ROOT" show HEAD:resources/properties.xml 2>/dev/null \
      | sed -n 's/.*<property id="hevyApiKey"[^>]*>\([^<]*\)<.*/\1/p' || true)"
  if [ -n "$COMMITTED_KEY" ]; then
    fail "A Hevy API key is committed in resources/properties.xml"; note_problem
    info "Every clone and every build carries it. See secrets/README.md."
  else
    ok "No API key committed"
  fi

  if [ -s "$REPO_ROOT/secrets/hevy-key.txt" ]; then
    if git -C "$REPO_ROOT" check-ignore -q secrets/hevy-key.txt; then
      warn "Personal build: a Hevy key will be baked in (not publishable)"
    else
      fail "secrets/hevy-key.txt is NOT ignored by git"; note_problem
    fi
  fi
fi

echo
if [ "$PROBLEMS" -eq 0 ]; then
  printf '%sEnvironment ready.%s\n' "$C_GREEN" "$C_OFF"
  exit 0
fi
printf '%s%d problem(s) found.%s\n' "$C_RED" "$PROBLEMS" "$C_OFF"
exit 1
