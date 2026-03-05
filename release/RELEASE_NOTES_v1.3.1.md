# CoPaRe 1.3.1

CoPaRe 1.3.1 is a security hardening release focused on safer secret handling and clearer wipe behavior.

## Highlights

- Sensitive preview masking for likely secrets/tokens
- Narrower in-memory text indexing for copied text/URL items
- Expanded secret detection (embedded JWTs, broader token patterns, PGP private keys)
- Symlink-aware sensitive file-path filtering
- Improved secure-wipe flow with confirmation and explicit success/warning feedback

## Why this update matters

This release reduces the chance of accidental plaintext exposure in UI-visible metadata while preserving the fast clipboard workflow.
It also improves detection coverage for real-world developer secrets and makes destructive cleanup actions more transparent.

## Upgrade notes

- No migration steps required.
- Existing encrypted snippet vault data remains compatible.
- Recommended for all users, especially teams handling credentials, tokens, and infrastructure artifacts.
