# Mac App Store Submission

## Current Target

- App: CoPaRe
- Version: 1.5.1
- Build: 22
- Bundle ID: io.copare.app
- Apple ID: 6771382344
- Team ID: 6246LWZM9N
- Category: Productivity
- Distribution: Mac App Store build, separate from the GitHub/Sparkle build
- Release behavior: automatically release after App Review approval, preserving the existing listing's setting

## Prepared In This Repository

- `scripts/app-store-build.sh` creates a temporary App Store project copy and builds the dedicated `CoPaRe` target without Sparkle.
- `APP_STORE` compilation disables the in-app Sparkle updater UI and status flow.
- Every App Store configuration uses `CoPaRe-AppStore-Info.plist`; packaging rejects any Sparkle `SU*` keys instead of relying on export-time removal.
- `CoPaRe/CoPaRe.AppStore.entitlements` enables sandboxing and user-selected file access without network permissions or Sparkle mach lookup exceptions. Debug has a separate entitlement file for debugger attachment.
- `CoPaRe/PrivacyInfo.xcprivacy` is bundled as an app resource and declares required-reason API usage for file timestamps and UserDefaults.
- The menu bar layout and lifecycle fix shares its implementation with the GitHub target and uses public macOS APIs without new permissions. See `docs/DISTRIBUTION.md` for implementation details and manual verification scenarios.
- The current English listing, release notes, review instructions, and encryption explanation are in `release/APP_STORE_METADATA_en-US.md`.

## Local Verification

Run this whenever the App Store path changes. Preserve any existing `build/app-store/export/` package first because the script replaces its working and export directories.

```bash
./scripts/app-store-build.sh --unsigned-check
```

Create a signed App Store archive/package using the configured Xcode account:

```bash
./scripts/app-store-build.sh --allow-provisioning-updates
```

Upload directly to App Store Connect with the configured Xcode account:

```bash
./scripts/app-store-build.sh --allow-provisioning-updates --upload
```

Or provide an App Store Connect API key explicitly:

```bash
./scripts/app-store-build.sh \
  --allow-provisioning-updates \
  --authentication-key-path /path/to/AuthKey_XXXXXXXXXX.p8 \
  --authentication-key-id XXXXXXXXXX \
  --authentication-key-issuer-id XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX \
  --upload
```

The upload only delivers a build. Wait for processing, select the build in the macOS version, and submit that version for App Review separately. Do not upload the Sparkle-enabled GitHub target.

## What's New

CoPaRe 1.5.1 improves the menu bar experience:

- Keeps the clipboard menu at a consistent width for empty, short, and long history items.
- Shows long previews and source-app names on one line with an ellipsis, while preserving the full content when copied.
- Keeps CoPaRe available from the menu bar after closing its main window.

## App Privacy And Encryption

- Tracking: No
- Data collected: None
- Third-party advertising: No
- Account required: No
- Recognition and clipboard processing happen on the Mac.
- Optional Search Web opens the user's default browser with selected text only after an explicit action.
- Clipboard captures are session-only. Only explicitly saved snippets can persist in the encrypted vault or protected pending-change recovery file.
- Backups are encrypted using macOS CommonCrypto and CryptoKit. Readable JSON export remains a distinct user-selected action.
- `ITSAppUsesNonExemptEncryption` is `NO` under Apple's operating-system-only encryption category. Reassess if a bundled cryptographic implementation or other encryption use is introduced.

## App Store Connect Release Steps

1. Open the CoPaRe record for Apple ID `6771382344` and confirm bundle ID `io.copare.app`.
2. Create macOS version `1.5.1` and apply the English metadata, What's New, and detailed review notes from `APP_STORE_METADATA_en-US.md`.
3. Preserve existing review contact details, price, availability, category, and age-rating information unless Apple requires a specific update.
4. Verify existing macOS screenshots remain accurate for the submitted interface and add current screenshots when needed.
5. Upload the App Store build and wait until `1.5.1 (22)` finishes processing. Select that exact build for the new version.
6. Confirm App Privacy and encryption declarations match the implementation described above. Check any outstanding agreement or questionnaire requirements presented by Apple.
7. Keep automatic release after approval selected. Add the version for review and complete the review submission.
8. Record the resulting App Review status. A successful upload or submission is not yet a public App Store release; distribution starts after Apple approves and releases the version.

## Previous Release Verification

On 2026-09-23, Apple's public catalog and the authenticated CoPaRe App Store Connect page showed version `1.4.4` ready for distribution, with selected build `20`. The public release date was 2026-07-13. A local Apple Distribution signing identity and a matching Mac Team Store provisioning profile for `io.copare.app` were present; the profile expires on 2027-05-14. These observations establish the starting state, not the outcome of the `1.5.0` upload or review submission.

## Previous Submission Result

On 2026-09-23, App Store Connect completed processing for `1.5.0 (21)` and the build was selected for macOS version `1.5.0`. The updated English metadata and review instructions were saved, and the version was submitted to App Review after the updated public website was deployed.

- Confirmed submission result: `1 Item Submitted`
- Confirmed version status: `Waiting for Review`
- Release setting: automatically release after approval, to all users immediately
- Review submission: https://appstoreconnect.apple.com/apps/6771382344/distribution/reviewsubmissions/details/3e050ad6-f0a9-48f5-81d4-8cd85d72af64

This records successful submission, not Apple approval or public App Store availability of `1.5.0`.

## Current Release Verification

On 2026-10-27, Apple's public catalog and App Store Connect confirmed CoPaRe (`io.copare.app`, Apple ID `6771382344`) at version `1.5.0`, released on 2026-09-23 and ready for distribution. The highest build visible in TestFlight before this release was `21`.

macOS version `1.5.1` was created in App Store Connect and its What's New and App Review notes were saved. Automatic release after approval and immediate distribution to all users remain selected.

- GitHub `1.5.1` is published: https://github.com/mane/CoPaRe/releases/tag/v1.5.1
- App Store archive `1.5.1 (22)` compiled and passed the bundle-shape checks.
- A local App Store package was exported successfully at `build/app-store/export-local-v1.5.1/CoPaRe.pkg`. Its app uses Apple Distribution signing and the matching App Store provisioning profile; the installer signature was also verified.
- The direct upload failed with `Failed to Use Accounts`: Xcode requires renewed App Store Connect account access. The Xcode GUI additionally requires installation of its system components before Accounts is available.
- Build `22` has **not** been uploaded or submitted for App Review. Renew Xcode account access, upload the prepared build, then select it on version `1.5.1` and complete the review submission. Update this section with the verified result.
