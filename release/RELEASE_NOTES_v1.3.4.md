# CoPaRe 1.3.4

CoPaRe 1.3.4 is a hotfix release for the in-app updater.

## Highlights

- Fixed the Sparkle installer connection failure seen during in-app updates in signed release builds.
- Preserved the correct mach service entitlements during release signing so Sparkle can talk to its installer helper again.
- Added a release-time safety check that rejects builds with unresolved entitlement placeholders.

## Upgrade notes

- If your current CoPaRe build shows "An error occurred while connecting to the installer", install 1.3.4 once from the GitHub release page.
- After that manual reinstall, future in-app updates should work normally again.
