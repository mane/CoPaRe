# CoPaRe 1.4.1

CoPaRe 1.4.1 is a privacy and release hardening update for the manually installed GitHub build.

- Fixes sandbox permissions for snippet export/import workflows that need user-selected write access.
- Prevents clipboard content copied during privacy pause or lock from being captured later when monitoring resumes.
- Preserves saved snippets when persistence runs before the saved snippet vault is loaded.
- Blocks signed URLs and URL credentials with token-like values from being stored or previewed.
- Moves image OCR filtering off the pasteboard polling path for smoother image capture.
- Fails release packaging when notarized Gatekeeper validation does not pass.
