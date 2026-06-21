#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/dist/CiscoVPNMac.app}"
SIGN_IDENTITY="${CISCO_VPN_CODESIGN_IDENTITY:-}"
SIGN_KEYCHAIN="${CISCO_VPN_CODESIGN_KEYCHAIN:-}"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "Missing app bundle: $APP_BUNDLE" >&2
  echo "Run script/build_app.sh first." >&2
  exit 1
fi

if [ -z "$SIGN_IDENTITY" ]; then
  if [ -n "$SIGN_KEYCHAIN" ]; then
    SIGN_IDENTITY="$(
      security find-identity -p codesigning -v "$SIGN_KEYCHAIN" 2>/dev/null \
        | awk -F '"' '/^[[:space:]]*[0-9]+\)/ { print $2; exit }'
    )"
  else
    SIGN_IDENTITY="$(
      security find-identity -p codesigning -v 2>/dev/null \
        | awk -F '"' '/^[[:space:]]*[0-9]+\)/ { print $2; exit }'
    )"
  fi
fi

if [ -z "$SIGN_IDENTITY" ]; then
  if [ "${CISCO_VPN_ALLOW_ADHOC_APP:-0}" != "1" ]; then
    echo "No code-signing identity found. Set CISCO_VPN_ALLOW_ADHOC_APP=1 for local ad-hoc signing." >&2
    exit 1
  fi
  SIGN_IDENTITY="-"
fi

if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP_BUNDLE"
else
  if [ -n "$SIGN_KEYCHAIN" ]; then
    codesign --force --options runtime --timestamp=none --keychain "$SIGN_KEYCHAIN" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
  else
    codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
  fi
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
echo "Signed: $APP_BUNDLE"
