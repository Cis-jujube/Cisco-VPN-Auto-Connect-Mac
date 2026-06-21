#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "${CISCO_VPN_CODESIGN_IDENTITY:-}" ] && [ -z "${CISCO_VPN_ALLOW_ADHOC_APP:-}" ]; then
  if ! security find-identity -p codesigning -v 2>/dev/null | grep -q '^[[:space:]]*[0-9])'; then
    export CISCO_VPN_ALLOW_ADHOC_APP=1
  fi
fi

exec /bin/bash "$ROOT_DIR/script/build_and_run.sh" --build-app
