# CoPaRe 1.3.2

CoPaRe 1.3.2 is a patch release focused on reliability and release engineering stability.

## Highlights

- Fixed unlock flow at startup when no locked snapshot is available.
- Fixed updater feed resolution to use the repository-backed appcast source.
- Added stronger internal logging for snippet-key cleanup failures.
- Added a shared `CoPaRe` scheme to make `xcodebuild test` behavior deterministic across local and CI environments.

## Upgrade notes

- No manual migration is required.
- Existing history and snippet vault data remain compatible.
