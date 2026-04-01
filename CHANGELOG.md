# Changelog

All notable changes to this project are documented in this file.

The format is inspired by Keep a Changelog and this project follows Semantic Versioning.

## [1.3.7] - 2026-04-01

### Added

- Added a manual `Check for Updates…` action directly in the menu bar menu.
- Added a manual `Check for Updates…` button in Settings under the Updates section.

### Changed

- The manual update controls now reflect the current Sparkle session state and disable themselves while an update session is already running.

## [1.3.6] - 2026-04-01

### Fixed

- Corrected the Sparkle release-signing workflow for sandboxed builds by re-signing Sparkle helpers and XPC services explicitly instead of using a deep app re-sign, which could break in-app updates.
- Added release validation for Sparkle helper signing and quarantine state so broken updater bundles fail before publication.
- The menu bar `Open CoPaRe` action now reuses the existing main window instead of opening duplicate windows.

### Changed

- The main app scene now behaves as a single reusable window rather than a window group.
- CoPaRe now exposes the full app version and build number in both Settings and the menu bar panel.

## [1.3.5] - 2026-04-01

### Added

- Added a generated DMG installer background, including a HiDPI variant for Retina displays, so release packages can present a polished drag-to-Applications window without hand-maintained assets.

### Changed

- The release pipeline now builds a styled DMG with a bundled `Applications` shortcut, fixed icon placement, and a single-window install flow instead of a bare app-only disk image.
- Release packaging can now bootstrap a local `dmgbuild` toolchain automatically when one is not already available on the machine.

## [1.3.4] - 2026-04-01

### Fixed

- Restored Sparkle installer connectivity in release builds by preserving the app's expanded mach-lookup entitlements during the final Developer ID signing step.

### Changed

- Security verification now fails fast if a signed release still contains unresolved entitlement placeholders.

## [1.3.3] - 2026-04-01

### Changed

- CoPaRe now runs as a menu bar-only app and no longer shows a Dock icon while it is active.
- Applied the same menu bar-only launch behavior to the dedicated App Store build so both distribution channels stay aligned.

## [1.3.2] - 2026-03-06

### Fixed

- Restored unlock reliability on app startup by skipping snapshot restoration when no locked snapshot is present.
- Stabilized in-app update checks by switching Sparkle feed resolution to the tracked `release/appcast.xml` on `main`.

### Changed

- Added explicit error logging when snippet key cleanup fails during empty-store save flows.
- Added a shared `CoPaRe` scheme for consistent local/CI `xcodebuild test` execution without App Store target interference.

## [1.3.1] - 2026-03-05

### Added

- First-launch guided onboarding ("How to") redesigned as a complete interactive tour:
  - 4-step flow (overview, search/filter, actions, security profile)
  - required hands-on tasks to learn core actions
  - always available from app menu via `CoPaRe > Interactive How To…`

### Changed

- Masked likely secret/token-like captures in item previews to reduce accidental plaintext exposure in memory/UI.
- Reduced plaintext indexing scope for copied text/URL entries by keeping search terms limited to app-source metadata.
- Improved secure wipe UX with explicit confirmation and clear post-action status messaging.
- Added a dedicated `CoPaReAppStore` target/scheme plus `AppStore` configuration with separate entitlements/Info.plist and App Store update behavior (no in-app Sparkle updater UI, no Sparkle framework linkage in that build).

### Security

- Expanded secret-detection heuristics:
  - embedded JWT detection (inside larger text blocks)
  - broader token patterns (GitHub, Slack, AWS-style prefixes)
  - PGP private key block detection
- Hardened sensitive file-path checks by evaluating both the original path and the symlink-resolved target.
- Improved Keychain key-deletion flow for wipe operations by attempting direct deletion first and using authenticated fallback only when required.

## [1.3.0] - 2026-03-04

### Added

- Global launcher shortcut: `⌥⌘V` now opens CoPaRe and focuses search immediately.
- New `Copy as Plain Text` action for text, URL, and file entries (main list, detail pane, and menu bar panel).
- Source application visibility for captured entries:
  - shown in history cards
  - shown in detail header
  - shown in menu bar quick panel labels
- Optional on-device OCR indexing for copied images, so image entries can be found via text search.
- First-run security onboarding wizard with selectable presets:
  - `Balanced`
  - `Strict`
- Security preset selector in Settings for reapplying a policy at any time.

### Changed

- Extended search indexing to include source-app metadata and richer minimal terms for text/file captures.
- Image OCR indexing is now controlled by a dedicated Settings toggle and disabled automatically when image capture is off.
- Settings now persist and manage:
  - onboarding completion state
  - selected security preset
  - global shortcut enable/disable
  - OCR indexing enable/disable

### Security

- OCR-derived text is still passed through sensitive-content filtering when enabled, preventing indexing of likely secrets.
- Plain-text copy reuses the existing protected pasteboard markers (`ConcealedType` and `AutoGeneratedType`) to reduce accidental capture by other well-behaved clipboard tools.

## [1.2.1] - 2026-03-04

- Previous stable release (see Git history and release notes for full details).
