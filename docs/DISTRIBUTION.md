# Distribution

This document keeps release and App Store publishing details out of the main README.

## Release channels

CoPaRe has two separate distribution shapes:

- GitHub manual-install build: signed and notarized DMG, Sparkle enabled, signed update archives published through GitHub Releases.
- Mac App Store build: Sparkle removed, App Store entitlements enabled, exported through Xcode/App Store Connect.

Do not upload the Sparkle-enabled manual-install app to App Store Connect.

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
- refreshes `release/appcast.xml` using Sparkle's `generate_appcast` tool and your EdDSA update key
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
- by default, Sparkle assets are generated for `https://github.com/mane/CoPaRe/releases/latest/download/`
- override `SPARKLE_DOWNLOAD_URL_PREFIX` only if you want to self-host update assets somewhere else

Typical outputs:

- `release/CoPaRe-vX.Y.Z.zip`
- `release/*.delta` when Sparkle can generate a delta from a previous build
- `release/appcast.xml`
- `dist/CoPaRe-vX.Y.Z.dmg`
- `dist/CoPaRe-vX.Y.Z.dmg.sha256`

## Mac App Store build flow

Use `scripts/app-store-build.sh` for a Mac App Store archive/package. This flow builds a temporary project copy with Sparkle removed, strips Sparkle update keys from `Info.plist`, compiles with `APP_STORE`, and uses the App Store entitlements file.

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
