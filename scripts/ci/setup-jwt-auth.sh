#!/usr/bin/env bash
# setup-jwt-auth.sh — generate the certificate/key pair used by CI JWT auth
# against the Dev Hub (issue #1, docs/ci-setup.md).
#
# Usage: bash scripts/ci/setup-jwt-auth.sh [output-dir]
#
# Outputs:
#   server.key  — private key. NEVER commit; goes into the SF_JWT_KEY repo secret.
#   server.crt  — certificate. Uploaded to the JWT connected app in the Dev Hub.
set -euo pipefail

OUT_DIR="${1:-.}"
KEY_FILE="$OUT_DIR/server.key"
CRT_FILE="$OUT_DIR/server.crt"

if [ -e "$KEY_FILE" ] && ! [ "${OVERWRITE:-0}" = "1" ]; then
  echo "Refusing to overwrite existing $KEY_FILE (set OVERWRITE=1 to regenerate)."
  exit 1
fi

mkdir -p "$OUT_DIR"
openssl req -x509 -nodes -days 3650 \
  -newkey rsa:2048 \
  -keyout "$KEY_FILE" \
  -out "$CRT_FILE" \
  -subj "/CN=agentguard-ci" \
  -addext "subjectAltName=DNS:agentguard-ci.local"

chmod 600 "$KEY_FILE"
echo ""
echo "Generated:"
echo "  $CRT_FILE  -> upload in Dev Hub connected app ('Use digital signatures')"
echo "  $KEY_FILE  -> paste contents into the SF_JWT_KEY repository secret"
echo ""
echo "Next steps (full walkthrough): docs/ci-setup.md"
echo "  1. Create the connected app in your Dev Hub org"
echo "  2. Add secrets SF_JWT_KEY, SF_CLIENT_ID, SF_DEVHUB_USER (+ optional SF_DEVHUB_URL)"
echo "  3. Set repository variable SF_CI_ENABLED=true to activate the org CI jobs"
echo ""
echo "This file is git-ignored (.gitignore blocks server.key); verify with: git status --short"
