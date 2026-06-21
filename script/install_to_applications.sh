#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/CiscoVPNMac.app"
DEST="/Applications/Cisco VPN AutoConnect.app"
APP_NAME="CiscoVPNMac"
BUNDLE_ID="dev.jujube.CiscoVPNMac"

quit_running_app() {
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

  for _ in {1..30}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done

  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    kill "$pid" >/dev/null 2>&1 || true
  done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)
}

if [ ! -d "$APP_BUNDLE" ]; then
  echo "Missing $APP_BUNDLE. Run script/build_app.sh first." >&2
  exit 1
fi

if [ ! -w "/Applications" ]; then
  echo "/Applications is not writable by the current user. This script will not use sudo." >&2
  echo "Install manually or rerun from an account with write permission." >&2
  exit 1
fi

quit_running_app
rm -rf "$DEST"
ditto --noextattr --noacl "$APP_BUNDLE" "$DEST"
/usr/bin/open -n "$DEST"
echo "Installed app bundle: $DEST"
