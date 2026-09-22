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
- Locking CoPaRe temporarily removes live history from the normal in-memory path, encrypts a RAM-only lock snapshot, and pauses clipboard capture until unlock
- Preview text is auto-masked for likely secret/token-like captures
- Search indexing avoids storing full plaintext bodies for copied text/URL entries
- Optional snippet persistence stores only user-authored snippets in an encrypted vault at rest in the app support container with restrictive local file permissions
- Keychain access is used for snippet-vault operations, lock/unlock, and cleanup; ordinary clipboard capture does not access Keychain
- When app lock is enabled, the saved-snippets vault key is stored with `userPresence`, so macOS requires system authentication before releasing that key
- The manager retains the protected lock-snapshot key and an authenticated `LAContext` during the unlocked session. Protected vault operations reuse that context with `interactionNotAllowed` enabled; locking discards the cached key and invalidates the context
- With snippet persistence and unlock protection enabled, pending manual snippet changes and deletion markers are encrypted in a local recovery file before asynchronous saving or automatic lock. The recovery file uses the protected snapshot key and never contains captured history. Pending changes are recovered after authenticated unlock and the file is removed after a successful normal-vault save
- Secure Wipe removes the recovery file and attempts deletion of its protected key as well as the normal snippet-vault keys; incomplete cleanup is reported
- Sensitive file-path filtering evaluates both original and symlink-resolved paths
- Frontmost app exclusion rules prevent capture from configured bundle identifiers
- Focused detail payloads are cleared when the app resigns active and after a short timeout
- Re-copied text is marked with concealed/auto-generated pasteboard types to discourage capture by other well-behaved clipboard tools
- In-app updates are handled by Sparkle using a signed appcast feed and EdDSA-signed archives
- Outbound network access is limited to Sparkle update checks against the configured appcast feed and downloading signed update archives when an update is accepted
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
