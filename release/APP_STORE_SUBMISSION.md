# Mac App Store Submission

## Current Target

- App: CoPaRe
- Version: 1.4.4
- Build: 18
- Bundle ID: io.copare.app
- Team ID: 6246LWZM9N
- Category: Productivity
- Distribution: Mac App Store build, separate from the GitHub/Sparkle build

## Prepared In This Repository

- `scripts/app-store-build.sh` creates a temporary App Store project copy with Sparkle removed from the project graph.
- `APP_STORE` compilation disables the in-app Sparkle updater UI and status flow.
- App Store export strips Sparkle `SU*` keys from `Info.plist`.
- `CoPaRe/CoPaRe.AppStore.entitlements` enables sandboxing and user-selected file access without Sparkle mach lookup exceptions.
- `CoPaRe/PrivacyInfo.xcprivacy` is bundled as an app resource and declares required-reason API usage for file timestamps and UserDefaults.

## Local Verification

Run this whenever the App Store path changes:

```bash
./scripts/app-store-build.sh --unsigned-check
```

Create a signed local App Store archive/export after signing is configured:

```bash
./scripts/app-store-build.sh --allow-provisioning-updates
```

Upload directly to App Store Connect after signing/API credentials are configured:

```bash
./scripts/app-store-build.sh --allow-provisioning-updates --upload
```

Or with an explicit App Store Connect API key:

```bash
./scripts/app-store-build.sh \
  --allow-provisioning-updates \
  --authentication-key-path /path/to/AuthKey_XXXXXXXXXX.p8 \
  --authentication-key-id XXXXXXXXXX \
  --authentication-key-issuer-id XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX \
  --upload
```

## App Review Notes Draft

CoPaRe is a local macOS menu bar clipboard utility. Clipboard capture and history management run locally on the device. Captured history is session-only unless the user explicitly saves snippets; saved snippets are stored in an encrypted local vault. The app does not require an account, server, subscription, or external updater in the App Store build. Updates for this build are delivered through the Mac App Store. The global shortcut and launch-at-login behavior are user-controlled in Settings.

## What's New Draft

CoPaRe 1.4.4 improves reliability and privacy:

- Safer app locking and encrypted snippet persistence.
- Secure Delete now stays deleted, including snippets not yet loaded.
- Stronger sensitive-content filtering for images and per-app capture rules.
- More reliable shortcuts, onboarding, settings, and clipboard actions.

## App Privacy Draft

- Tracking: No
- Data collected: None
- Third-party advertising: No
- Account required: No

Use this draft only if the submitted product remains local-only and no analytics, crash reporting, telemetry, cloud sync, or third-party SDK data collection is added before submission.

## Manual App Store Connect Items

- Verify the existing App Store Connect record for bundle ID `io.copare.app` and Apple ID `6771382344`.
- Create the macOS version `1.4.4`, select build `18`, and copy the What's New text above.
- Ensure the primary category in App Store Connect is Productivity, matching `LSApplicationCategoryType`.
- Add screenshots for macOS.
- Add description, keywords, support URL, marketing URL if desired, copyright, age rating, price, and availability.
- Confirm the privacy questionnaire matches the local-only behavior above.
- Confirm all current Apple Developer Program agreements are accepted.
- Configure signing for team `6246LWZM9N`: Xcode account/API key plus Apple Development/Apple Distribution or Mac App Distribution assets and a Mac App Store provisioning profile.
