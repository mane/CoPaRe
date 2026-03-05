# CoPaRe 1.3.1

CoPaRe 1.3.1 is a minor update focused on a more complete, intuitive interactive onboarding plus recent security hardening improvements.

## Highlights

- Redesigned interactive onboarding tour (4 guided steps + hands-on tasks)
- New app-menu entry to reopen the tour anytime: `CoPaRe > Interactive How To…`
- Sensitive preview masking for likely secrets/tokens
- Narrower in-memory text indexing for copied text/URL items
- Expanded secret detection (embedded JWTs, broader token patterns, PGP private keys)
- Symlink-aware sensitive file-path filtering
- Improved secure-wipe flow with confirmation and explicit success/warning feedback

## Why this update matters

This release improves first-run UX so users learn key actions quickly while preserving CoPaRe's security posture.
It also reduces accidental plaintext exposure in UI-visible metadata and improves detection coverage for real-world developer secrets.

## Upgrade notes

- No migration steps required.
- Existing encrypted snippet vault data remains compatible.
- Recommended for all users, especially teams handling credentials, tokens, and infrastructure artifacts.
