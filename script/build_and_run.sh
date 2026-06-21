#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CiscoVPNMac"
BUNDLE_ID="dev.jujube.CiscoVPNMac"
MIN_SYSTEM_VERSION="14.0"
BUILD_CONFIGURATION="${CISCO_VPN_BUILD_CONFIGURATION:-debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/assets/CiscoVPNMac.icns"
APP_LOG="/tmp/cisco-vpn-mac.log"
VERIFY_LOG="/tmp/cisco-vpn-mac-verify.log"
BUILD_BINARY=""
SIGN_IDENTITY="${CISCO_VPN_CODESIGN_IDENTITY:-}"
SIGN_KEYCHAIN="${CISCO_VPN_CODESIGN_KEYCHAIN:-}"
ALLOW_ADHOC_APP="${CISCO_VPN_ALLOW_ADHOC_APP:-0}"
USER_APPLICATIONS_DIR="$HOME/Applications"
INSTALLED_APP_BUNDLE="$USER_APPLICATIONS_DIR/Cisco VPN AutoConnect.app"
INSTALLED_LAUNCHER="$USER_APPLICATIONS_DIR/Cisco VPN AutoConnect.command"
SYSTEM_APPLICATIONS_DIR="/Applications"
SYSTEM_APP_BUNDLE="$SYSTEM_APPLICATIONS_DIR/Cisco VPN AutoConnect.app"

cd "$ROOT_DIR"

build_binary() {
  swift build -c "$BUILD_CONFIGURATION" --product "$APP_NAME"
  BUILD_BINARY="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME"
}

detect_sign_identity() {
  if [ -n "$SIGN_IDENTITY" ]; then
    return 0
  fi

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
}

require_or_select_sign_identity() {
  if [ "$ALLOW_ADHOC_APP" = "1" ]; then
    SIGN_IDENTITY="-"
    return 0
  fi

  detect_sign_identity
  if [ -n "$SIGN_IDENTITY" ]; then
    return 0
  fi

  cat >&2 <<EOF
No valid macOS code-signing identity was found.

To build a Finder-launchable app, install/select full Xcode and create an
Apple Development certificate, then run:

  CISCO_VPN_CODESIGN_IDENTITY="Apple Development: Your Name (...)" bash "$0" --package

For an ad-hoc bundle used only for structure inspection, run:

  CISCO_VPN_ALLOW_ADHOC_APP=1 bash "$0" --package

The default local development launcher still works:

  bash "$0" run
EOF
  return 1
}

quit_running_instances() {
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 &
  local quit_pid=$!
  for _ in {1..20}; do
    if ! kill -0 "$quit_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  if kill -0 "$quit_pid" >/dev/null 2>&1; then
    kill "$quit_pid" >/dev/null 2>&1 || true
  fi
  wait "$quit_pid" 2>/dev/null || true

  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    local process_path
    process_path="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    case "$process_path" in
      "$APP_BINARY"|"$ROOT_DIR"/.build/*/"$APP_NAME")
        kill "$pid" >/dev/null 2>&1 || true
        ;;
    esac
  done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)
}

write_launcher_command() {
  local command_file="$1"
  mkdir -p "$(dirname "$command_file")"
  cat >"$command_file" <<EOF
#!/usr/bin/env bash
cd "$ROOT_DIR"
exec /bin/bash "$ROOT_DIR/script/build_and_run.sh" run
EOF
  chmod +x "$command_file"
}

write_finder_launcher_hint() {
  mkdir -p "$DIST_DIR"
  rm -rf "$APP_BUNDLE"
  write_launcher_command "$DIST_DIR/Run CiscoVPNMac.command"
}

launch_build_binary() {
  nohup "$BUILD_BINARY" >"$APP_LOG" 2>&1 &
  local app_pid=$!
  disown "$app_pid" >/dev/null 2>&1 || true
  sleep 1
  if kill -0 "$app_pid" >/dev/null 2>&1; then
    echo "Launched $APP_NAME from $BUILD_BINARY"
    echo "Log: $APP_LOG"
    return 0
  fi

  wait "$app_pid" 2>/dev/null || true
  echo "$APP_NAME exited during launch. Log follows:" >&2
  sed -n '1,160p' "$APP_LOG" >&2 || true
  return 1
}

package_bundle() {
  require_or_select_sign_identity
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp -X "$BUILD_BINARY" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  if [ -f "$APP_ICON_SOURCE" ]; then
    cp -X "$APP_ICON_SOURCE" "$APP_RESOURCES/CiscoVPNMac.icns"
  fi

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Cisco VPN AutoConnect</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>CiscoVPNMac</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Cisco VPN AutoConnect</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

  printf 'APPL????' >"$APP_CONTENTS/PkgInfo"
  if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP_BUNDLE" >/dev/null
  else
    if [ -n "$SIGN_KEYCHAIN" ]; then
      codesign --force --options runtime --timestamp=none --keychain "$SIGN_KEYCHAIN" --sign "$SIGN_IDENTITY" "$APP_BUNDLE" >/dev/null
    else
      codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP_BUNDLE" >/dev/null
    fi
  fi
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  echo "Packaged $APP_BUNDLE"
  if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "Warning: this app is ad-hoc signed and may be blocked by macOS Gatekeeper."
  else
    echo "Signed with: $SIGN_IDENTITY"
  fi
}

package_bundle_for_local_run() {
  detect_sign_identity
  if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="-"
  fi
  package_bundle
}

open_app_bundle() {
  /usr/bin/open -n "$APP_BUNDLE" >/dev/null 2>&1
  for _ in {1..16}; do
    while IFS= read -r pid; do
      [ -n "$pid" ] || continue
      local process_path
      process_path="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
      if [ "$process_path" = "$APP_BINARY" ]; then
        echo "Launched $APP_BUNDLE"
        return 0
      fi
    done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)
    sleep 0.5
  done

  echo "$APP_BUNDLE did not stay running after LaunchServices opened it." >&2
  echo "Check signing details with:" >&2
  echo "  codesign -dvvv --entitlements :- \"$APP_BUNDLE\"" >&2
  return 1
}

install_to_user_applications() {
  mkdir -p "$USER_APPLICATIONS_DIR"
  detect_sign_identity
  if [ -n "$SIGN_IDENTITY" ] || [ "$ALLOW_ADHOC_APP" = "1" ]; then
    package_bundle
    rm -rf "$INSTALLED_APP_BUNDLE"
    ditto --noextattr --noacl "$APP_BUNDLE" "$INSTALLED_APP_BUNDLE"
    echo "Installed app bundle: $INSTALLED_APP_BUNDLE"
    return 0
  fi

  rm -rf "$INSTALLED_APP_BUNDLE"
  write_launcher_command "$INSTALLED_LAUNCHER"
  echo "Installed launcher: $INSTALLED_LAUNCHER"
  echo "No valid code-signing identity was found, so this Mac cannot install a reliable Finder-launchable .app yet."
  echo "Create an Apple Development certificate, then rerun: bash $0 --install"
}

install_to_system_applications() {
  package_bundle
  rm -rf "$SYSTEM_APP_BUNDLE"
  ditto --noextattr --noacl "$APP_BUNDLE" "$SYSTEM_APP_BUNDLE"
  echo "Installed app bundle: $SYSTEM_APP_BUNDLE"
}

verify_build_binary() {
  "$BUILD_BINARY" >"$VERIFY_LOG" 2>&1 &
  local verify_pid=$!
  sleep 2
  if kill -0 "$verify_pid" >/dev/null 2>&1; then
    kill "$verify_pid" >/dev/null 2>&1 || true
    wait "$verify_pid" 2>/dev/null || true
    return 0
  fi

  echo "$APP_NAME did not stay running for the 2-second smoke test" >&2
  sed -n '1,160p' "$VERIFY_LOG" >&2 || true
  return 1
}

case "$MODE" in
  run)
    quit_running_instances
    build_binary
    write_finder_launcher_hint
    package_bundle_for_local_run
    open_app_bundle
    ;;
  --debug|debug)
    build_binary
    lldb -- "$BUILD_BINARY"
    ;;
  --logs|logs)
    quit_running_instances
    build_binary
    write_finder_launcher_hint
    launch_build_binary
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    quit_running_instances
    build_binary
    write_finder_launcher_hint
    launch_build_binary
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    build_binary
    package_bundle_for_local_run
    open_app_bundle
    quit_running_instances
    ;;
  --package|package|--build-app|build-app)
    BUILD_CONFIGURATION="${CISCO_VPN_BUILD_CONFIGURATION:-release}"
    build_binary
    package_bundle
    ;;
  --open-app|open-app)
    BUILD_CONFIGURATION="${CISCO_VPN_BUILD_CONFIGURATION:-release}"
    quit_running_instances
    build_binary
    package_bundle
    open_app_bundle
    ;;
  --verify-app|verify-app)
    BUILD_CONFIGURATION="${CISCO_VPN_BUILD_CONFIGURATION:-release}"
    build_binary
    package_bundle
    open_app_bundle
    quit_running_instances
    ;;
  --install|install)
    BUILD_CONFIGURATION="${CISCO_VPN_BUILD_CONFIGURATION:-release}"
    build_binary
    install_to_user_applications
    ;;
  --install-system|install-system)
    BUILD_CONFIGURATION="${CISCO_VPN_BUILD_CONFIGURATION:-release}"
    build_binary
    install_to_system_applications
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--package|--build-app|--open-app|--verify-app|--install|--install-system]" >&2
    exit 2
    ;;
esac
