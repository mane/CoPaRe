# CoPaRe 1.3.5

CoPaRe 1.3.5 improves the installer experience for direct GitHub downloads.

## Highlights

- The DMG now opens as a proper drag-to-Applications installer instead of a bare window with only the app bundle inside.
- Added a polished installer background and fixed icon placement so the install flow feels like a modern macOS app package.
- The release pipeline now generates Retina-ready DMG artwork automatically and can bootstrap its own `dmgbuild` dependency when needed.

## Upgrade notes

- In-app Sparkle updates continue to work as fixed in 1.3.4.
- This release mostly improves the manual download/install path from GitHub Releases.
