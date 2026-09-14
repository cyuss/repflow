#!/usr/bin/env bash
# Keep a copy of the simulator's RepFlow storage, so a fresh run starts with
# the athlete's workouts already in it.
#
#   scripts/sim-seed.sh save      remember what the simulator holds right now
#   scripts/sim-seed.sh restore   put it back
#   scripts/sim-seed.sh forget    throw the copy away
#   scripts/sim-seed.sh status    say what is remembered (the default)
#
# Why this exists: importing from Hevy takes a phone, a key and half a minute,
# and `make sim-fresh` wipes it along with everything else. Testing a screen
# needs a watch that has workouts on it, and re-importing before every run is a
# tax on the thing you were actually trying to look at.
#
# What is copied is the simulator's own storage files, written by the app
# through Application.Storage — no format is invented here and nothing is
# fabricated: whatever the watch would have held, the simulator holds.
#
# The copy lives in secrets/ and is never committed. It contains the athlete's
# routines, their loads and their session history, which is their training
# diary and nobody else's business.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

SEED_DIR="$REPO_ROOT/secrets/sim-seed"
APPS="${TMPDIR:-/tmp}/com.garmin.connectiq/GARMIN/APPS"

# The simulator does not name app storage after the PRG you pushed — running
# RepFlow-fenix6pro.prg writes REPFLOW-TEST-FENIX6PRO.* — so everything here
# matches a case-insensitive RepFlow prefix, exactly as clear_sim_app_data does.
seed_names() {
  local f
  for f in "$SEED_DIR"/DATA/* "$SEED_DIR"/OBJSTORE/*; do
    [ -e "$f" ] && basename "$f"
  done
}

cmd_save() {
  [ -d "$APPS" ] || die "The simulator has never run here — nothing to save."

  local found=0 f
  rm -rf "$SEED_DIR"
  mkdir -p "$SEED_DIR/DATA" "$SEED_DIR/OBJSTORE"

  for f in "$APPS"/DATA/[Rr][Ee][Pp][Ff][Ll][Oo][Ww]*; do
    [ -e "$f" ] || continue
    cp -R "$f" "$SEED_DIR/DATA/"
    found=$((found + 1))
  done
  for f in "$APPS"/DATA/MEDIA/OBJSTORE/[Rr][Ee][Pp][Ff][Ll][Oo][Ww]*; do
    [ -e "$f" ] || continue
    cp -R "$f" "$SEED_DIR/OBJSTORE/"
    found=$((found + 1))
  done

  if [ "$found" -eq 0 ]; then
    rm -rf "$SEED_DIR"
    die "RepFlow has stored nothing in the simulator yet. Import from Hevy first."
  fi

  # The simulator holds storage in memory and writes it out as it goes, so a
  # save taken while the app is mid-write copies half a file. Say so rather
  # than pretend the copy is a snapshot of a quiet moment.
  ok "Remembered $found storage file(s) in secrets/sim-seed."
  info "Taken while the simulator was running? Close the app first if it looks stale."
}

cmd_restore() {
  [ -d "$SEED_DIR" ] || return 0

  mkdir -p "$APPS/DATA" "$APPS/DATA/MEDIA/OBJSTORE"
  local f restored=0
  for f in "$SEED_DIR"/DATA/*; do
    [ -e "$f" ] || continue
    cp -R "$f" "$APPS/DATA/"
    restored=$((restored + 1))
  done
  for f in "$SEED_DIR"/OBJSTORE/*; do
    [ -e "$f" ] || continue
    rm -rf "$APPS/DATA/MEDIA/OBJSTORE/$(basename "$f")"
    cp -R "$f" "$APPS/DATA/MEDIA/OBJSTORE/"
    restored=$((restored + 1))
  done
  [ "$restored" -gt 0 ] && ok "Restored $restored storage file(s) into the simulator."
  return 0
}

cmd_forget() {
  rm -rf "$SEED_DIR"
  ok "Forgot the simulator seed."
}

cmd_status() {
  if [ ! -d "$SEED_DIR" ]; then
    info "No simulator seed saved. Import from Hevy in the simulator, then:"
    info "  make sim-seed"
    return 0
  fi
  ok "Simulator seed in secrets/sim-seed:"
  seed_names | sed 's/^/       /'
}

case "${1:-status}" in
  save)    cmd_save ;;
  restore) cmd_restore ;;
  forget)  cmd_forget ;;
  status)  cmd_status ;;
  *)       die "Usage: sim-seed.sh [save|restore|forget|status]" ;;
esac
