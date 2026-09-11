#!/usr/bin/env bash
# Create a Garmin-compatible developer signing key (RSA 4096, PKCS#8 DER).
#
# The key is written OUTSIDE the repository and is never overwritten: losing or
# replacing it makes it impossible to publish updates to an app already on the
# Connect IQ Store. See docs/SIGNING.md.

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

KEY_DIR="$(dirname "$DEVELOPER_KEY")"
PEM_KEY="${DEVELOPER_KEY%.der}.pem"

if [ -f "$DEVELOPER_KEY" ]; then
  ok "Developer key already exists — leaving it untouched."
  info "$DEVELOPER_KEY"
  info "NEVER regenerate this key once RepFlow is published. See docs/SIGNING.md."
  exit 0
fi

command -v openssl >/dev/null 2>&1 || die "openssl is required to generate a developer key."

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

info "Generating a 4096-bit RSA developer key..."
openssl genrsa -out "$PEM_KEY" 4096 2>/dev/null
# monkeyc expects an unencrypted PKCS#8 key in DER form.
openssl pkcs8 -topk8 -inform PEM -outform DER -in "$PEM_KEY" -out "$DEVELOPER_KEY" -nocrypt
chmod 600 "$PEM_KEY" "$DEVELOPER_KEY"

ok "Developer key created."
info "DER (used by monkeyc): $DEVELOPER_KEY"
info "PEM (backup source):   $PEM_KEY"
echo
warn "Back this key up now, somewhere private and durable (password manager,"
warn "encrypted backup). Losing it means you can never ship an update to a"
warn "published RepFlow listing — you would have to publish a new app."
