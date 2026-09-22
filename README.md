# CoPaRe

CoPaRe is a source-available, privacy-first clipboard manager for macOS.
It keeps captured clipboard history session-only, stores only explicitly saved text snippets across restarts when enabled, and prioritizes secure defaults for everyday work.

[Website](https://copare.it/) | [Support](https://copare.it/support/) | [Privacy policy](https://copare.it/privacy/) | [Latest GitHub release](https://github.com/mane/CoPaRe/releases/latest) | [Changelog](CHANGELOG.md)

## Why CoPaRe

- Security-first design: session-only captured history, encrypted snippet vault, local authentication support
- Practical daily workflow: fast search, menu bar quick panel, global shortcut, one-click copy
- Clear privacy posture: no telemetry, no analytics SDKs, no cloud sync by default
- Production-ready distribution: signed, notarized manual-install build with Sparkle signed updates, plus a separate Mac App Store build flow

## What's new in 1.5.0

- Quick Copy with `⌥⌘V`, metadata search, and keyboard navigation.
- Create, edit, duplicate, and tag snippets, with portable password-protected backups.
- Copy text from images using on-device recognition.
- Optional automatic locking and expiry of copies made by CoPaRe.
- More reliable snippet recovery and isolated regression coverage.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.

## Screenshots

### Main window

![CoPaRe main window](docs/images/screenshot-main.jpg)

### Settings

![CoPaRe settings](docs/images/screenshot-settings.jpg)

### Menu bar actions

![CoPaRe menu bar panel](docs/images/screenshot-menubar.jpg)

## Download and install

### Install manually from GitHub Release

Use the prebuilt, signed and notarized manual-install package from GitHub Releases:

- [Latest release](https://github.com/mane/CoPaRe/releases/latest)

Step by step:

1. Open the latest release page and download:
   - `CoPaRe-vX.Y.Z.dmg`
   - optional integrity file: `CoPaRe-vX.Y.Z.dmg.sha256`
2. (Optional but recommended) Verify checksum:
   ```bash
   shasum -a 256 CoPaRe-vX.Y.Z.dmg
   ```
   Compare the output with the value in `CoPaRe-vX.Y.Z.dmg.sha256`.
3. Double-click the DMG to mount it.
4. In the same DMG window, drag `CoPaRe.app` onto the bundled `Applications` shortcut.
5. Open `Applications > CoPaRe`.
6. If macOS blocks first launch:
   - open `System Settings > Privacy & Security`
   - click `Open Anyway` for CoPaRe, then confirm once.

After install, CoPaRe can auto-check signed updates from the app menu (`CoPaRe > Check for Updates…`).

The GitHub release is the manual-install build and includes Sparkle updates. The Mac App Store build is prepared separately without Sparkle.

### Build from source

Requirements:

- macOS 26.2 or newer
- Xcode 26.3 or newer

Build:

```bash
xcodebuild -project CoPaRe.xcodeproj -scheme 'CoPaRe GitHub Release' -destination 'platform=macOS' build
```

Test:

```bash
xcodebuild -project CoPaRe.xcodeproj -scheme CoPaRe -destination 'platform=macOS' test
```

The `CoPaRe` scheme includes the unit and UI test targets and builds the App Store variant. The `CoPaRe GitHub Release` scheme builds the Sparkle-enabled app. Both use the same application source.

Hosted unit tests use an inert app host and isolated fixtures with private pasteboards, temporary vault files, and in-memory test keys. UI tests launch the real App Store interface in a separate test environment.

## Core features

This list describes version 1.5.0. App Store availability follows Apple's review and may differ from the GitHub release.

- Clipboard history for text, URLs, images, files, and folders
- First-launch guided "How to" onboarding with key actions and security overview
- Text snippets with editable titles, bodies and tags, duplication, and optional encrypted local persistence
- Explicit `Save as Snippet…` for captured text and URLs
- Compact `Quick Copy…` panel (`⌥⌘V`): search, select with arrow keys, copy with Return, and dismiss with Escape
- Password-protected snippet backups that can be restored on another Mac, alongside the existing readable JSON transfer format
- On-demand loading of the saved-snippets vault (`Load Saved Snippets`)
- Duplicate collapse with capture counters for repeated copies
- Fast search across visible previews and minimal local file labels
- Automatic preview masking for likely secret text/token captures
- Optional OCR scanning of copied images to block likely sensitive text
- On-demand `Copy Text` from captured images using local Vision recognition; extracted text is not indexed or saved as history
- Filters for `All`, `Pinned`, `Text`, `Images`, and `Files`
- Pin/unpin important entries
- Source-application label for each captured entry
- Per-app capture exclusions using bundle identifiers
- Entry time-to-live controls for captured, unpinned history items
- Optional one-time copy for unpinned history items
- Optional expiry of copies made by CoPaRe on the system clipboard, preserving anything copied later
- Optional local lock/unlock gate that removes the active history from the normal in-memory view path, pauses capture while locked, and uses local authentication to restore it
- Optional automatic locking when leaving CoPaRe, on display/Mac sleep or user switching, and after inactivity within CoPaRe
- `userPresence` protection for the saved-snippets vault when app lock is enabled
- One-click re-copy for every entry
- `Copy as Plain Text` for text, URL, and file entries
- Sparkle-based updates with background checks at launch
- Signed appcast feed plus EdDSA-signed update archives
- Sparkle installer flow with one-click verified update prompts
- Manual update check in the macOS app menu (`CoPaRe > Check for Updates…`)
- Menu bar access to Quick Copy and the full main window
- Menu bar actions for copy, pin/unpin, reveal in Finder, and secure delete
- Session-only clipboard capture with no automatic history-at-rest
- Secure wipe of in-memory history and saved snippets
- Local security event counters for blocked/skipped activity
- Launch at login support on macOS 13+

## Security at a glance

CoPaRe uses practical hardening appropriate for a local clipboard manager:

- App Sandbox enabled
- Release entitlement `com.apple.security.get-task-allow = false`
- Hardened runtime enabled for release distribution builds produced by `scripts/release.sh`
- Captured clipboard history remains session-only and is cleared when CoPaRe quits; explicitly saving text or a URL as a snippet creates a separate entry eligible for snippet persistence
- Runtime payloads are wrapped with an in-memory session key and revealed on demand for re-copy or focused detail view
- Locking CoPaRe temporarily removes the live history from the normal in-memory path, encrypts a RAM-only lock snapshot, and pauses clipboard capture until unlock
- The protected snapshot key and authenticated macOS authorization context are retained only during an unlocked session. Locking discards the cached key and invalidates that authorization; protected vault operations reuse it while unlocked without opening another authentication prompt
- Optional snippet persistence stores only explicitly saved text snippets in an encrypted vault stored in the app support container with restrictive local file permissions
- With persistence and unlock protection enabled, pending snippet changes and deletion markers also use an encrypted recovery file, so quitting while automatically locked does not discard them. This file never contains captured history and is removed after the normal vault save succeeds
- Portable backups use password-derived AES-256-GCM encryption; the password is not saved and only encrypted backup bytes are written to disk
- Search avoids indexing full text bodies in RAM; visible previews, tags and minimal file labels remain searchable, with source-app search also available in Quick Copy; likely secrets are auto-masked in previews
- Protected pasteboard-type detection for concealed/password-manager clipboard content
- No analytics or outbound telemetry code in the app source

Security limits, verification commands, and vulnerability reporting details are in [SECURITY.md](SECURITY.md).

## Distribution docs

- [Distribution and release workflow](docs/DISTRIBUTION.md)
- [App Store metadata draft](release/APP_STORE_METADATA_en-US.md)
- [App Store submission checklist](release/APP_STORE_SUBMISSION.md)

## Changelog

- See [CHANGELOG.md](CHANGELOG.md) for version-by-version release notes.

## Configuration reference

| Option | Description | Default |
|---|---|---|
| Filter potentially sensitive content | Blocks likely secrets and sensitive file paths from being stored | Enabled |
| Persist saved snippets on disk | Persists explicitly saved text snippets in an encrypted vault; captured clipboard history stays session-only | Enabled |
| One-time copy for unpinned history items | Removes an unpinned captured item after a successful re-copy | Disabled |
| Require unlock to view history | Locks the visible history behind local authentication and binds saved-snippets vault access to `userPresence` when enabled | Disabled |
| Lock when leaving CoPaRe or the Mac sleeps | With unlock protection enabled, locks on app focus loss, display/Mac sleep, and user switching | Enabled when protection is enabled |
| Lock after inactivity in CoPaRe | Measures keyboard, mouse, and scroll interaction within CoPaRe; requires unlock protection | 5 minutes |
| Clear copied system clipboard after | Clears a copy made by CoPaRe after 30 seconds, 1 minute, or 2 minutes, only if the pasteboard has not changed | Never |
| Launch at login | Starts CoPaRe automatically at login (macOS 13+) | Disabled |
| Capture images | Includes copied images in history | Enabled |
| Capture copied files/folders | Includes file URLs in history | Enabled |
| Polling interval | Clipboard polling cadence | 0.65s |
| Entry time-to-live | Auto-expires captured, unpinned items after a selected retention window | Never |
| Unpinned history limit | Maximum number of non-pinned entries kept | 250 |
| Per-App Exclusions | Newline-separated bundle identifiers that CoPaRe ignores during capture | Built-in password manager defaults |

The Strict security preset enables unlock protection, sets inactivity locking to 1 minute, and clears CoPaRe copies from the system clipboard after 30 seconds. These settings remain individually editable.

## Additional behavior

- Snippets are explicitly saved text entries and are not subject to automatic TTL expiration. `Edit Snippet…`, `Duplicate Snippet…`, and `Save as Snippet…` open an editor where the title, body and tags can be reviewed before saving. Saving a captured item as a snippet leaves its original history entry intact.
- The normal saved-snippets vault is not loaded automatically at startup; choose `Load Saved Snippets` to load it. Pending snippet changes in the encrypted recovery file are restored after authenticated unlock and merged into the existing vault; captured history is never recovered across app launches.
- Both backup formats contain only loaded snippets. Settings provides `Load Saved Snippets` before export.
- `Create Encrypted Backup…` requires a password of at least 12 characters. `Restore Encrypted Backup…` uses that password on any Mac and merges snippets, skipping duplicates; CoPaRe cannot recover a lost password. Encrypted files are limited to 14 MB and contain at most 10 MB of snippet data.
- The separate JSON import/export actions transfer readable snippet titles, bodies and tags, with a 10 MB file limit.
- Quick Copy keeps its search separate from the main window and never decrypts content for search. A successful copy or Escape returns focus to the previous app; selecting another app dismisses the panel. Unlocking from Quick Copy opens the main window for authentication.
- Automatic locking uses local app input and documented workspace notifications. With locking on focus loss enabled, switching away after Quick Copy also locks CoPaRe. It does not monitor keyboard input in other applications.
- System clipboard expiry applies only to content copied by CoPaRe and checks the pasteboard change count before clearing. History TTL, one-time copy, and secure wipe are separate controls; they do not themselves erase the system clipboard.
- `Copy Text` recognizes an image locally after an explicit action. It copies the recognized text without adding an OCR search index; leaving the item, hiding its contents, locking, or closing the view cancels pending recognition.
- Re-copied text and URLs are written back to the pasteboard with concealed/auto-generated markers to reduce capture by other well-behaved clipboard tools.
- Pinned items and snippets are preserved when you use the standard "Clear unpinned history" action.
- Captured clipboard history is always memory-only and is not restored after relaunch.
- Secure delete of individual entries removes them from the current session immediately.
- "Secure wipe entire history" removes all items, deletes the encrypted snippets vault file if present, and destroys the snippet encryption keys (crypto-shredding).
- Secure wipe shows a warning if one or more protected Keychain keys cannot be removed (for example if authentication is canceled).
- Security event counters are local-only and track blocked sensitive captures, excluded-app skips, expired entries, secure wipes, and unlock events.

## Repository layout

- `CoPaRe/` app source
- `CoPaReTests/` unit tests
- `CoPaReUITests/` UI tests
- `CoPaRe-Info.plist` GitHub app Info.plist containing Sparkle configuration
- `CoPaRe-AppStore-Info.plist` App Store app Info.plist without external updater configuration
- `docs/` project documentation and README screenshots
- `release/` signed `appcast.xml`, release notes, App Store metadata, and App Store screenshots; generated Sparkle archives are ignored
- `dist/` locally generated DMGs and checksums created by `scripts/release.sh` (not intended to stay versioned in git)
- `scripts/` versioning, release automation, and security verification helpers
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
