# macOS SwiftUI App

This repository includes a native macOS app target, `CiscoVPNMac`, alongside the original Windows PowerShell/CMD implementation.

## Requirements

- macOS 14 or newer
- Swift toolchain from Xcode Command Line Tools
- Cisco Secure Client for macOS
- Cisco VPN CLI at `/opt/cisco/secureclient/bin/vpn`
- macOS built-in `/usr/bin/expect` for terminal-style Cisco login prompts

If Cisco installs the CLI somewhere else, launch with `CISCO_VPN_BIN=/path/to/vpn bash script/build_and_run.sh`.

## Run

```bash
swift run CiscoVPNCoreSelfTests
swift build
bash script/build_and_run.sh
```

The run script builds `CiscoVPNMac`, stages `dist/CiscoVPNMac.app`, signs that local development bundle, and launches it through LaunchServices. This gives the SwiftUI app a bundle identifier and avoids the automatic termination behavior seen when running the raw SwiftPM GUI executable directly.

If no valid Apple Development or Developer ID signing identity is available, `run` and `--verify` use an ad-hoc signature for the local development bundle. For a durable Finder-installed app, use a real code-signing identity.

## Build A macOS App Bundle

To create a release app bundle:

```bash
bash script/build_app.sh
open dist/CiscoVPNMac.app
```

`build_app.sh` wraps `script/build_and_run.sh --build-app`. It uses a real Apple Development or Developer ID identity when one is available. If no signing identity is available, it falls back to local ad-hoc signing so the bundle can still be inspected and launched on this Mac.

To install the built app to `/Applications` without using `sudo`:

```bash
bash script/install_to_applications.sh
```

The install script copies `dist/CiscoVPNMac.app` to `/Applications/Cisco VPN AutoConnect.app` and opens it. If `/Applications` is not writable by the current user, it exits with a clear message instead of escalating privileges.

To inspect available signing identities:

```bash
security find-identity -p codesigning -v
```

To choose a signing identity explicitly:

```bash
CISCO_VPN_CODESIGN_IDENTITY="Apple Development: Your Name (...)" bash script/build_app.sh
```

To sign an already-built bundle:

```bash
bash script/sign_app.sh
```

`script/build_and_run.sh --package` remains available for direct packaging. Without a valid identity it exits clearly unless ad-hoc signing is explicitly allowed:

```bash
CISCO_VPN_ALLOW_ADHOC_APP=1 bash script/build_and_run.sh --package
```

Ad-hoc signing is acceptable for local `run` and `--verify` on this machine. Use a real Apple Development or Developer ID identity for durable Finder installation or distribution.

## Storage

- Profile metadata is stored in `~/Library/Application Support/Cisco VPN AutoConnect/profiles.json`.
- Active profile selection is stored beside that file.
- Usernames, passwords, and TOTP secrets are stored in macOS Keychain under the `CiscoVPNAutoConnect` service.
- Logs redact saved username, password, and TOTP secret before displaying command output.
- **Reset saved credentials for this profile** deletes the current profile's Keychain item only. It does not delete profile metadata.

For isolated demos, screenshots, and tests that should not read real profile metadata, launch with `CISCO_VPN_PROFILE_ROOT=/tmp/some-demo-profile-root`. This changes only the profile metadata directory for that process. Use demo profile IDs that do not match real saved profiles if you also want to avoid Keychain lookups for existing items.

## Profile Subscription URLs

The macOS app can import VPN profile subscriptions from the sidebar **Add** menu. This is intentionally metadata-only:

- Allowed profile fields: name, server, group, port, protocol, DUO method, MFA strategy, and push target.
- Rejected credential-like fields: usernames, passwords, TOTP secrets, API keys, tokens, credentials, and similar fields.
- Remote subscriptions must use HTTPS. `http://localhost` is allowed for local development.

Imported subscriptions are neutral; the app does not promote or hard-code any provider platform.

## Doctor

The app includes a **Doctor** panel and toolbar action. It checks:

- Cisco VPN CLI path and whether `vpn stats` can run.
- `vpnagentd` process status.
- `/usr/bin/expect` availability.
- Active profile server, group, DUO method, and MFA strategy.
- Keychain presence for username, password, and TOTP.
- Password diagnostics by length and character-class flags only.
- System proxy state from `scutil --proxy`, including DKU fixed-proxy warnings.
- Network reachability status, which may be marked as skipped.

Doctor output never includes raw passwords, TOTP secrets, TOTP codes, or raw Keychain values. Use **Copy Diagnostics** to copy the Doctor report plus redacted logs.

## TOTP Advanced Fallback

DUO Push is the recommended daily path for DKU/Duke. TOTP is kept as an advanced fallback for accounts that already expose a standard `otpauth://totp/...` link or Base32 secret.

The advanced profile settings include **Import TOTP** for save-only setup. Supported inputs are standard `otpauth://totp/...` links and raw Base32 secrets. The app never displays the saved secret, and logs redact generated MFA values.

`duo://` activation links are not TOTP secrets and cannot be converted. For those accounts, keep **DUO Push**.

## Connection Notes

The app drives Cisco Secure Client through `vpn -s`, the macOS equivalent of the Windows `vpncli.exe -s` path. Connect uses `/usr/bin/expect` so Cisco sees a terminal-style session instead of a plain stdin pipe, then follows the upstream Windows tool's timed input sequence for group, username, password, and MFA.

Default Group submits an empty reply at Cisco's `Group: [-Default-]` prompt, which accepts the default group exactly like pressing Enter manually. Non-default groups are resolved from the live Cisco group menu when possible, with built-in fallbacks matching the Windows tool:

- `-Default-` -> press Enter
- `Library Resources Only` -> `1`
- `INTL-DUKE` -> `2`

Before connecting, the app runs a fast preflight for server, credentials, TOTP requirements, Cisco binary, and `/usr/bin/expect`. Missing required items stop before launching Cisco. The app then closes the Cisco Secure Client GUI and stale `vpn -s` processes because Cisco allows only one local client to own the connect capability.

For DUO Push, **MFA Strategy** defaults to **Auto**. Auto detects Cisco's MFA style: numeric menus receive `1`/`2`, second-password prompts receive `push`/`push2`, and auto-push flows wait without sending a stray option. Auto does not append Duo factors to the primary password field.

Use **passwordAppend** only when the server is known to require `password,push`, `password,push2`, or `password,<code>` in the primary password field. Use **waitOnly** when the server sends DUO Push automatically after the primary password. **MFA option** is only for multiple devices: leave it blank for the first phone, or enter `2` for the second device. It is not a phone suffix.

If Cisco returns `Login failed` before any DUO prompt, the app reports an auth failure before MFA and points you at NetID, Password, Group, and password character diagnostics instead of treating it as a DUO timeout.

For custom profiles, enter a numeric Cisco group menu value when the group name cannot be resolved by these presets.

When DKU VPN is connected, Cisco may publish both a PAC URL and fixed HTTP/HTTPS proxy settings into macOS. The DKU PAC can route public sites through the correct `proxy-china` or `proxy-intl` hosts, while a fixed `proxy-dku.oit.duke.edu:3128` fallback can reject normal public HTTPS sites. If Bing, Apple, or similar sites fail only after VPN connects, run **Doctor** and inspect **System proxy**. A durable fix belongs in the Cisco profile or school VPN policy, such as PAC-only behavior or `ProxySettings=IgnoreProxy`; editing Cisco's installed profile usually requires administrator privileges.

## Verification

```bash
swift run CiscoVPNCoreSelfTests
swift build
swift build -c release
bash script/build_and_run.sh --verify
bash script/build_app.sh
```

`--verify` smoke-tests the same app-bundle path used by `run`, so it catches the launch path users actually use.

When a signing identity is available, verify the app bundle path too:

```bash
bash script/build_and_run.sh --verify-app
codesign --verify --deep --strict --verbose=2 dist/CiscoVPNMac.app
```

Manual verification still requires a real VPN account and phone approval:

1. Open `/Applications/Cisco VPN AutoConnect.app`.
2. Run **Doctor** and confirm Cisco binary, expect, profile, and Keychain status.
3. Confirm `server`, `group`, DUO method, and MFA strategy.
4. Click **Connect**.
5. Approve DUO on your phone if prompted.

The self-test target avoids XCTest because this local SwiftPM toolchain does not expose XCTest or Swift Testing modules.

## License

This project is licensed under the MIT License. See `LICENSE`.
