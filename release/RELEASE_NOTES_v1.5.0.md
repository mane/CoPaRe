# CoPaRe 1.5.0

CoPaRe 1.5.0 makes everyday copying faster and gives saved snippets more flexibility, while keeping captured clipboard history session-only.

- **Quick Copy:** press `⌥⌘V`, search by preview, title, tags or source app, choose with the arrow keys, and press Return to copy. Escape dismisses the panel and restores focus.
- **Snippet editing:** create, edit, duplicate and tag snippets, or explicitly save captured text and URLs as a new snippet.
- **Encrypted backups:** export saved snippets in a portable, password-protected backup and restore them on another Mac. Readable JSON import and export remain available separately.
- **Text from images:** use Copy Text to recognize text locally with Apple Vision. Extracted text is not stored in history or a search index.
- **Automatic locking:** with unlock protection enabled, optionally lock when leaving CoPaRe, when the Mac sleeps, when switching users, or after inactivity inside the app.
- **Clipboard expiry:** optionally clear copies made by CoPaRe after a chosen interval, only if nothing newer has been copied.

This release also improves encrypted recovery of pending snippet changes, import validation, authentication handling, and capture-rule performance. The two distribution channels share these features; the App Store build receives updates through Apple and the GitHub build uses signed Sparkle updates.

Requires **macOS 26.2 or later**. The GitHub package is universal for Apple silicon and Intel Macs, signed with Developer ID and notarized by Apple.

Download the `.dmg` for manual installation; the `.zip` is the signed in-app update archive. The `.dmg.sha256` file contains the installer checksum.
