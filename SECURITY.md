# Security Policy

## Supported versions

Security fixes are applied to the latest `main` branch.

## Security posture

CoPaRe is built with defense-in-depth controls appropriate for a local clipboard manager.

Implemented controls:

- App Sandbox enabled
- Hardened Runtime enabled for release builds
- Release entitlement `com.apple.security.get-task-allow = false`
- Captured clipboard history is session-only and is never written to disk
- Runtime payloads are wrapped with an in-memory session key and revealed on demand
- Optional snippet persistence stores only user-authored snippets in an encrypted vault at rest in the app support container with restrictive local file permissions
- No automatic Keychain access in the normal app launch path; Keychain is touched only when saving or explicitly loading the encrypted snippets vault
- When app lock is enabled, the saved-snippets vault key is stored with `userPresence`, so macOS requires system authentication before releasing that key
- Re-copied text is marked with concealed/auto-generated pasteboard types to discourage capture by other well-behaved clipboard tools
- No telemetry/tracking code paths in app source

## What CoPaRe does not claim

- It does not guarantee detection of every secret copied to clipboard.
- It cannot protect clipboard data if the logged-in macOS session is already compromised.
- It is not a replacement for endpoint hardening (EDR, patching, account security, OS hardening).

## Verify security controls locally

Run:

```bash
./scripts/security-check.sh /Applications/CoPaRe.app
```

You can also inspect entitlements directly:

```bash
codesign -d --entitlements :- /Applications/CoPaRe.app
```

Expected release value:

- `com.apple.security.get-task-allow` must be `false`

## Reporting a vulnerability

Please do not disclose vulnerabilities publicly before a fix is available.

Include:

- impact and attack scenario
- reproduction steps
- affected commit/version
- suggested mitigation (if available)
