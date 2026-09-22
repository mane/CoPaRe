# Distribution

This document keeps release and App Store publishing details out of the main README.

## Release channels

CoPaRe has two separate distribution shapes:

- GitHub manual-install build: the `CoPaRe GitHub Release` scheme builds the `CoPaRe GitHub` target with Sparkle enabled. Signed update archives and a signed, notarized DMG are published through GitHub Releases.
- Mac App Store build: the `CoPaRe` scheme builds the `CoPaRe` target without Sparkle. All configurations use `CoPaRe-AppStore-Info.plist` and `APP_STORE` compilation. Release and Distribution use `CoPaRe.AppStore.entitlements`, including direct Xcode and Xcode Cloud archives. Debug uses `CoPaRe.AppStore.Debug.entitlements` to allow debugger attachment; it has no network or Sparkle mach lookup permissions.

The two channels can publish different versions. The repository's marketing version describes the current source; `release/appcast.xml` describes the available GitHub updates.

Do not upload the Sparkle-enabled manual-install app to App Store Connect.

## Shared feature compatibility

The following features use the same implementation in both targets. They add no entitlements, external services, Accessibility permission, private APIs, or synthetic paste events.

| Feature | Implementation and sandbox behavior |
|---|---|
| Quick Copy | The existing public Carbon hotkey opens an AppKit `NSPanel`; `NSSearchField` handles search, arrows, Return and Escape. Copy uses `NSPasteboard`, and AppKit restores the previous app's focus. |
| Snippet editing | SwiftUI editors update the local snippet model and existing encrypted vault. Saving captured text or a URL as a snippet is explicit and leaves the original capture session-only. |
| Automatic locking | Local AppKit input events measure interaction within CoPaRe. Documented app/workspace notifications cover app focus loss, display/Mac sleep and user switching. LocalAuthentication and the existing Keychain protection handle unlock. |
| Clipboard expiry | A timer records the pasteboard change count for CoPaRe's own copy and clears it only while that count is still current. Newer copies are preserved. |
| Portable backups | Native save/open panels use the existing user-selected read/write entitlement. CommonCrypto PBKDF2-HMAC-SHA256 derives a key from the password; CryptoKit AES-256-GCM encrypts and authenticates the backup. No password or derived key is saved. |
| Copy Text from images | Vision recognizes text on the device after an explicit action. Results go directly to the copy action without becoming a persistent OCR index or clipboard-history entry. |

Automatic locking is optional and requires unlock protection. Inactivity means inactivity within CoPaRe, rather than system-wide input monitoring. Locking on focus loss also locks CoPaRe when Quick Copy returns to another app. There is no dependency on undocumented screen-lock notifications.

With snippet persistence and unlock protection enabled, pending snippet records and deletion markers are atomically checkpointed to `snippets-pending.json` inside the app's existing support container. CryptoKit authenticates and encrypts this file using the protected lock-snapshot key obtained during an authenticated session. It contains no captured clipboard history. Unlock recovers pending changes before showing the session and merges them with the normal snippet vault; the checkpoint is removed after a successful save. Secure Wipe removes the checkpoint and its protected key as well as the normal vault. This uses the existing sandbox container and Keychain access, with no additional entitlement.

The manager retains the protected snapshot key and the authenticated `LAContext` only while unlocked. Protected vault operations reuse that context with `interactionNotAllowed` enabled; they do not initiate another authentication prompt during the unlocked session. Locking discards the cached snapshot key and invalidates the context. The normal saved-snippets vault still requires an explicit load after startup, apart from restoring pending changes from the recovery file after authenticated unlock.

The App Store target continues to exclude Sparkle, its update configuration and updater-specific permissions. These implementation and bundle checks support the App Store submission; approval remains subject to Apple's review.

The App Store variant uses encryption supplied by macOS (`CryptoKit`, `CommonCrypto` and `Security`), with no bundled cryptographic implementation. Its `ITSAppUsesNonExemptEncryption = NO` declaration follows Apple's [operating-system-only encryption category](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/). Reassess that declaration if future dependencies or encryption implementations change.

## Feature validation before distribution

Run the unit suite against the isolated App Store host:

```bash
xcodebuild -project CoPaRe.xcodeproj -scheme CoPaRe \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:CoPaReTests test
```

UI tests use a separate defaults domain, private pasteboard, temporary vault and test keys. They require a logged-in macOS session with UI testing automation available:

```bash
xcodebuild -project CoPaRe.xcodeproj -scheme CoPaRe \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:CoPaReUITests test
```

Build both distribution configurations before signing or publishing:

```bash
xcodebuild -project CoPaRe.xcodeproj -scheme CoPaRe \
  -configuration Distribution -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/copare-validation-store CODE_SIGNING_ALLOWED=NO build

xcodebuild -project CoPaRe.xcodeproj -scheme 'CoPaRe GitHub Release' \
  -configuration Distribution -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/copare-validation-github CODE_SIGNING_ALLOWED=NO build

./scripts/app-store-build.sh --unsigned-check
```

These unsigned builds validate source and bundle shape, not distribution signatures. Use the signed channel-specific flow below for release artifacts. The App Store packaging check writes under `build/app-store/`; preserve any existing export you need before running it.

Exercise these workflows in both variants using non-sensitive test data:

1. Open Quick Copy with `⌥⌘V`, search by title/tag/app, move with arrows, and copy with Return. Check Escape, outside-click dismissal, previous-app focus, locked-state authentication, and access to the main window. Main-window filters should not change.
2. Create, edit and duplicate snippets, including multiline text with leading/trailing whitespace. Save a captured text/URL item as a snippet, review its title/body/tags, and verify persistence after an explicit vault reload. Locking or removing the source while an editor is open must not save stale content.
3. Enable unlock protection and automatic locking. Verify focus loss, sleep/user switching and the configured period without interaction in CoPaRe. Confirm capture pauses while locked and canceled authentication does not reveal history. Save, edit and delete snippets immediately before automatic lock, quit while locked, then relaunch and unlock: pending changes must survive, previously unloaded snippets must remain in the vault, and captured history must not return. Confirm Secure Wipe removes the recovery file and protected key.
4. Enable clipboard expiry, copy from CoPaRe, and verify clearing after the selected interval. Repeat while copying something newer in another app before expiry; that newer value must remain. Check one-time-copy behavior separately from system clipboard expiry.
5. Create an encrypted backup, restore it in a separate test collection or on another Mac, and check titles, whitespace, tags and pins. Verify duplicate handling and rejection of incorrect passwords, modified files and oversized input. Confirm the separate JSON export remains readable and both formats include only loaded snippets.
6. Use Copy Text on images containing text and on an image without text. Verify recognition/copy status, cancellation when changing selection or locking, and the absence of an OCR search index or added history entry.

## Release versioning

CoPaRe uses semantic versioning for release builds:

- `major` for breaking changes (`BREAKING CHANGE` in the commit body or conventional-commit `!:` markers)
- `minor` for new features (`feat:` commits, or commit subjects that start with `Add`, `Introduce`, or `Integrate`)
- `patch` for fixes, hardening, UI refinements, docs, packaging, and maintenance changes

The release baseline is tracked with annotated git tags named `vX.Y.Z`.
Version inference compares commits since the latest release tag.

Helpers:

```bash
./scripts/version.sh current
./scripts/version.sh next
./scripts/version.sh bump
./scripts/version.sh tag
```

Typical flow before cutting a new release:

```bash
./scripts/version.sh bump
git commit -am "Bump release to vX.Y.Z"
./scripts/version.sh tag
git push origin main --tags
```

## Signed DMG release flow

Use `scripts/release.sh` when you want a signed distribution DMG and a Sparkle-ready update archive.

The script:

- builds a Distribution app
- signs the app with your `Developer ID Application` certificate
- validates security entitlements
- creates `release/CoPaRe-vX.Y.Z.zip` from the signed app bundle for Sparkle
- refreshes `release/appcast.xml` using Sparkle's `generate_appcast` tool and your EdDSA update key, with only the current ZIP in a temporary generation directory
- creates a DMG in `dist/`
- signs the DMG
- optionally notarizes and staples it
- generates a SHA256 file next to the DMG
- optionally installs the verified app to `/Applications`

For safety, the release script does not replace an installed application by default. Pass `--install` only when you also want the fully verified build copied to `/Applications/CoPaRe.app` after packaging and verification finish.

Example:

```bash
./scripts/version.sh bump
git commit -am "Bump release to vX.Y.Z"
./scripts/version.sh tag
git push origin main --tags

./scripts/release.sh \
  --sign-identity "Developer ID Application: NAME SURNAME (TEAMID)" \
  --notary-profile "copare-notary"
```

One-time Sparkle setup before your first release:

```bash
xcodebuild -resolvePackageDependencies \
  -project CoPaRe.xcodeproj \
  -clonedSourcePackagesDirPath build/SourcePackages
./build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account io.copare.sparkle
```

Notes:

- `scripts/release.sh` uses `io.copare.sparkle` as the default Sparkle key account
- by default, Sparkle assets use the version-specific URL `https://github.com/mane/CoPaRe/releases/download/vX.Y.Z/`
- override `SPARKLE_DOWNLOAD_URL_PREFIX` only if you want to self-host update assets somewhere else
- the feed contains only the current release, so publication needs only its ZIP; older local ZIPs are preserved but do not enter the feed or generate delta dependencies
- the generated signed feed is copied byte-for-byte to `release/appcast.xml`; do not edit it after generation

Typical outputs:

- `release/CoPaRe-vX.Y.Z.zip`
- `release/appcast.xml`
- `dist/CoPaRe-vX.Y.Z.dmg`
- `dist/CoPaRe-vX.Y.Z.dmg.sha256`

## Mac App Store build flow

Use `scripts/app-store-build.sh` for a Mac App Store archive/package. It builds the `CoPaRe` target in a temporary project copy with Sparkle also removed from the package graph. The target's dedicated Info.plist and entitlements are used by both this script and direct Xcode archives. The script validates that no Sparkle framework, binary dependency, update keys, or mach lookup exceptions enter the App Store bundle, and checks that the privacy manifest is present.

Unsigned local shape check:

```bash
./scripts/app-store-build.sh --unsigned-check
```

Signed local export:

```bash
./scripts/app-store-build.sh --allow-provisioning-updates
```

For CLI signing with an App Store Connect API key:

```bash
./scripts/app-store-build.sh \
  --allow-provisioning-updates \
  --authentication-key-path /path/to/AuthKey_XXXXXXXXXX.p8 \
  --authentication-key-id XXXXXXXXXX \
  --authentication-key-issuer-id XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
```

Typical outputs:

- `build/app-store/archives/CoPaRe-vX.Y.Z-AppStore.xcarchive`
- `build/app-store/export/`
- `release/APP_STORE_SUBMISSION.md` contains the submission checklist and review/privacy drafts

Requirements:

- App Store Connect app record for the configured bundle ID
- Apple Distribution or Mac App Distribution signing assets for team `6246LWZM9N`
- a valid Mac App Store provisioning profile, or an Xcode account/API key that can create one with `--allow-provisioning-updates`

## Repository hygiene

Keep these files versioned:

- `release/appcast.xml`
- `release/RELEASE_NOTES_vX.Y.Z.md`
- `release/APP_STORE_METADATA_en-US.md`
- `release/APP_STORE_SUBMISSION.md`
- `release/app-store/screenshots/`

Do not commit generated local build outputs:

- `build/`
- `dist/`
- `DerivedData/`
- `release/*.zip`
- `release/*.delta`
- `.xcarchive`, `.xcresult`, `.ipa`, and `.pkg` files
