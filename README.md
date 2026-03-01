# CoPaRe

CoPaRe is a security-focused clipboard manager for macOS.
It keeps captured clipboard history session-only, stores only user-authored snippets across restarts when enabled, and avoids bundling personal signing metadata in the public source repository.

## Screenshots

### Main window

![CoPaRe main window](docs/images/screenshot-main.jpg)

### Settings

![CoPaRe settings](docs/images/screenshot-settings.jpg)

### Menu bar quick panel

![CoPaRe menu bar panel](docs/images/screenshot-menubar.jpg)

## Download and install

### Option 1: Use the bundled archive

This repository includes a prebuilt archive in `release/`:

- `release/CoPaRe-v1.1.0.zip`

What it contains:

- `CoPaRe.app`
- ad-hoc signature (`TeamIdentifier=not set`) so no personal Developer ID details are embedded in the public repository
- hardened runtime flag enabled in the bundled app signature
- note: a macOS `.app` is a bundle directory, so for GitHub release assets you should upload a `.zip` or `.dmg`, not the raw bundle

Install:

```bash
mkdir -p /tmp/CoPaRe-install
ditto -x -k release/CoPaRe-v1.1.0.zip /tmp/CoPaRe-install
rm -rf /Applications/CoPaRe.app
cp -R /tmp/CoPaRe-install/CoPaRe.app /Applications/CoPaRe.app
open /Applications/CoPaRe.app
```

Notes:

- Because the bundled archive is not Developer ID notarized, macOS may require `Right click > Open` on first launch.
- If you want a notarized DMG, generate it with `scripts/release.sh` as described below.

### Option 2: Build from source

Requirements:

- macOS
- Xcode 17 or newer

Build:

```bash
xcodebuild -project CoPaRe.xcodeproj -scheme CoPaRe -destination 'platform=macOS' build
```

Test:

```bash
xcodebuild -project CoPaRe.xcodeproj -scheme CoPaRe -destination 'platform=macOS' test
```

## Core features

- Clipboard history for text, URLs, images, files, and folders
- Manual snippets with optional encrypted local persistence
- On-demand loading of the saved-snippets vault (`Load Saved Snippets`)
- Duplicate collapse with capture counters for repeated copies
- Fast search across visible previews and minimal local file labels
- Filters for `All`, `Pinned`, `Text`, `Images`, and `Files`
- Pin/unpin important entries
- Per-app capture exclusions using bundle identifiers
- Entry time-to-live controls for captured, unpinned history items
- Optional one-time copy for unpinned history items
- Optional local lock/unlock gate before history is shown, with `userPresence` protection for the saved-snippets vault when enabled
- One-click re-copy for every entry
- Menu bar quick panel for fast access
- Menu bar actions for copy, pin/unpin, reveal in Finder, and secure delete
- Session-only clipboard capture with no automatic history-at-rest
- Secure wipe of in-memory history and saved snippets
- Local security event counters for blocked/skipped activity
- Launch at login support on macOS 13+

## Security posture

CoPaRe uses practical hardening appropriate for a local clipboard manager:

- App Sandbox enabled
- Release entitlement `com.apple.security.get-task-allow = false`
- Hardened runtime enabled for release distribution builds produced by `scripts/release.sh`
- Captured clipboard history is never written to disk and is cleared when CoPaRe quits
- Runtime payloads are wrapped with an in-memory session key and revealed on demand for re-copy or focused detail view
- Optional snippet persistence stores only user-authored snippets in an encrypted vault stored in the app support container with restrictive local file permissions
- Search avoids indexing full text bodies in RAM; only visible previews and minimal file labels remain searchable
- Protected pasteboard-type detection for concealed/password-manager clipboard content
- Re-copied text is marked with concealed/auto-generated pasteboard types to discourage capture by other well-behaved clipboard tools
- Sensitive file-path filtering for likely secret material (`.key`, `.pem`, `.ovpn`, `.ssh`, `.gnupg`)
- Frontmost app exclusion rules prevent capture from configured bundle identifiers
- Focused detail payload cleared when the app resigns active and after a short timeout
- No automatic Keychain access in the normal application launch path; Keychain is touched only when saving or explicitly loading the encrypted snippets vault
- When app lock is enabled, the saved-snippets vault key is stored with `userPresence`, so macOS requires system authentication before releasing that key
- No analytics or outbound telemetry code in the app source

## Security model limits

- No clipboard manager can reliably detect every secret copied by a user.
- The optional search experience is intentionally narrower than traditional clipboard managers because CoPaRe avoids retaining full plaintext bodies in RAM for global indexing.
- If the logged-in macOS session is already compromised, clipboard contents can still be exposed.
- CoPaRe is not a replacement for OS hardening, endpoint protection, or account security.

## Verify security locally

Validate an installed app:

```bash
./scripts/security-check.sh /Applications/CoPaRe.app
```

Or build a fresh local Release bundle and verify it automatically:

```bash
./scripts/security-check.sh
```

Additional details: see [SECURITY.md](SECURITY.md).

## Signed DMG release flow

Use `scripts/release.sh` when you want a signed distribution DMG.

The script:

- builds a Release app
- signs the app with your `Developer ID Application` certificate
- validates security entitlements
- optionally installs the app to `/Applications`
- creates a DMG in `dist/`
- signs the DMG
- optionally notarizes and staples it
- generates a SHA256 file next to the DMG

Example:

```bash
./scripts/release.sh \
  --sign-identity "Developer ID Application: NAME SURNAME (TEAMID)" \
  --notary-profile "copare-notary"
```

Typical outputs:

- `dist/CoPaRe-v1.1.0.dmg`
- `dist/CoPaRe-v1.1.0.dmg.sha256`

## Configuration reference

| Option | Description | Default |
|---|---|---|
| Filter potentially sensitive content | Blocks likely secrets and sensitive file paths from being stored | Enabled |
| Persist saved snippets on disk | Persists only manually created snippets in an encrypted vault; captured clipboard history always stays session-only | Enabled |
| One-time copy for unpinned history items | Removes an unpinned captured item after a successful re-copy | Disabled |
| Require unlock to view history | Locks the visible history behind local authentication and binds saved-snippets vault access to `userPresence` when enabled | Disabled |
| Launch at login | Starts CoPaRe automatically at login (macOS 13+) | Disabled |
| Capture images | Includes copied images in history | Enabled |
| Capture copied files/folders | Includes file URLs in history | Enabled |
| Polling interval | Clipboard polling cadence | 0.65s |
| Entry time-to-live | Auto-expires captured, unpinned items after a selected retention window | Never |
| Unpinned history limit | Maximum number of non-pinned entries kept | 250 |
| Per-App Exclusions | Newline-separated bundle identifiers that CoPaRe ignores during capture | Built-in password manager defaults |

## Additional behavior

- Snippets are manually created text entries and are not subject to automatic TTL expiration.
- Saved snippets are not auto-loaded at app launch; they are loaded only when you explicitly choose `Load Saved Snippets`.
- Re-copied text and URLs are written back to the pasteboard with concealed/auto-generated markers to reduce capture by other well-behaved clipboard tools.
- Pinned items and snippets are preserved when you use the standard "Clear unpinned history" action.
- Captured clipboard history is always memory-only and is not restored after relaunch.
- Secure delete of individual entries removes them from the current session immediately.
- "Secure wipe entire history" removes all items, best-effort overwrites and deletes the encrypted snippets vault, deletes the snippet encryption key, and clears any legacy encrypted history file from older versions.
- Security event counters are local-only and track blocked sensitive captures, excluded-app skips, expired entries, secure wipes, and unlock events.

## Repository layout

- `CoPaRe/` app source
- `CoPaReTests/` unit tests
- `CoPaReUITests/` UI tests
- `docs/images/` screenshots used in this README
- `release/` prebuilt public archive included in the repository
- `scripts/` release automation and security verification helpers
- `LICENSE` CoPaRe Community License 1.0
- `NOTICE` required attribution and origin notice that redistributions must keep

## Contributing

1. Fork the repository.
2. Create a feature branch.
3. Add tests for behavior changes where practical.
4. Include security impact notes in your pull request.

## Security reporting

Please avoid public disclosure until a fix is available.

Include:

- impact and attack scenario
- reproduction steps
- affected commit or version
- suggested mitigation (if available)

## License

CoPaRe is distributed under the CoPaRe Community License 1.0. See [LICENSE](LICENSE).

This means:

- individuals and companies may use, modify, and run the software, including for internal business use
- redistributions in source or binary form are allowed only when they are free of charge
- redistributions must preserve the `LICENSE` and `NOTICE` files
- redistributions must clearly preserve attribution to the CoPaRe project and state whether the software was modified
- no one may generate profit, fees, margins, or other commercial benefit from redistributing CoPaRe or derivative works under the default repository terms

Important:

- this is source-available software, not OSI-approved open source
- commercial redistribution rights are reserved unless the copyright holders grant separate written permission

## Commercial redistribution

If you want to sell CoPaRe, include it in a paid bundle, ship it as part of a paid service, or otherwise monetize redistribution of CoPaRe:

- the default repository terms do not allow that
- you need separate written permission from the copyright holders before distribution
- internal company use that does not redistribute the software remains allowed under the included license terms
