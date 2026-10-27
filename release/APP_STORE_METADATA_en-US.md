# App Store Connect Metadata - English (U.S.)

## App Information

App name:
CoPaRe

Subtitle:
Private Clipboard Manager

Primary category:
Productivity

Secondary category:
Utilities

Content rights:
CoPaRe does not contain, show, or access third-party content supplied by the developer. Clipboard content is supplied locally by the user.

Age rating notes:
No objectionable content supplied by the developer, gambling, unrestricted embedded web browser, commerce, user-generated public content, or account system.

Pricing:
Free

## macOS App Version 1.5.1

Screenshots:
- release/app-store/screenshots/en-US/mac/01-private-clipboard-history.png
- release/app-store/screenshots/en-US/mac/02-privacy-controls.png
- release/app-store/screenshots/en-US/mac/03-guided-onboarding.png

Promotional Text:
Find your copies faster with Quick Copy. Edit reusable snippets, extract text from images, and carry encrypted backups between Macs. Private, local, and account-free.

Description:
CoPaRe is a private clipboard manager for macOS.

Keep recent copies close at hand without turning your clipboard into a permanent archive. Captured history stays in your current session and is cleared when CoPaRe quits. Choose which useful text to keep as reusable snippets in an encrypted local vault.

QUICK COPY, FROM YOUR KEYBOARD
Press Option-Command-V to open a compact search panel. Find an item, move through results with the arrow keys, and press Return to copy it and return to your previous app. Use the menu bar or main window to browse text, links, images, and file references.

SNIPPETS THAT FIT YOUR WORK
Create, edit, duplicate, and tag reusable text. Turn a captured text item or URL into a snippet with an explicit Save as Snippet action. Create password-protected backups of loaded snippets and restore them on another Mac. Readable JSON import and export remain available as a separate choice.

TEXT FROM IMAGES
Select an image and choose Copy Text to recognize its text on your Mac. Recognition runs locally when you request it, without creating a stored OCR index.

CONTROL WHAT STAYS
Pause capture, exclude apps, set per-app capture rules, and choose retention intervals. Pin items for the current session. Sensitive-content filtering helps skip likely secrets and protected pasteboard data.

OPTIONAL AUTOMATIC PROTECTION
Require local system authentication to unlock CoPaRe. Enable locking when you leave the app, when the display or Mac sleeps, when users switch, or after inactivity within CoPaRe. Set copied content to expire from the system clipboard; CoPaRe clears only its own unchanged copy and preserves anything copied afterward.

LOCAL BY DESIGN
No account, cloud sync, analytics, advertising SDKs, or telemetry. Saved snippets are encrypted at rest. Pending snippet edits are protected by encrypted recovery when locking, so they can survive a quit without saving captured history.

CoPaRe copies selected content back to the clipboard; paste it using your usual app shortcut. It uses public macOS APIs and does not require Accessibility permission. The optional Search Web action opens a search in your default browser only when you choose it.

Requires macOS 26.2 or later.

Keywords:
clipboard,history,copy,paste,snippets,privacy,ocr,backup,keyboard,productivity

Support URL:
https://copare.it/support/

Marketing URL:
https://copare.it/

Version:
1.5.1

What's New:
CoPaRe 1.5.1 improves the menu bar experience:

- Keeps the clipboard menu at a consistent width for empty, short, and long history items.
- Shows long previews and source-app names on one line with an ellipsis, while preserving the full content when copied.
- Keeps CoPaRe available from the menu bar after closing its main window.

Copyright:
© 2026 EDDY BOSCOLO

## App Review Information

Sign-in required:
No

Demo account:
Not applicable

Review notes:
CoPaRe is a sandboxed, local macOS menu bar clipboard utility. No account, subscription, server, Accessibility permission, or external updater is required. Updates for this build are delivered through the Mac App Store.

Version 1.5.1 is a menu bar layout and lifecycle fix. The app now owns its native status item using public AppKit NSStatusItem and SwiftUI NSHostingMenu APIs. The menu has a consistent width, and long history previews and source-app names are shortened only for display. Copied content remains unchanged. Closing the main window leaves the menu bar utility running.

Clipboard retention, snippet encryption, permissions, data collection, pricing, and the rest of the functionality are unchanged from 1.5.0. Captured history stays in the current session; only explicitly saved snippets are eligible for encrypted persistence. The App Store build remains sandboxed, with no external updater.

Suggested review steps:
1. Launch CoPaRe and complete or skip onboarding if shown.
2. Open the CoPaRe menu bar icon with an empty or short history and note the menu width.
3. Copy a long, non-sensitive, multiline text sample in another app. Open the menu again: it retains the same width, and the preview stays on one line with an ellipsis as needed.
4. Select the item from the menu and paste it in the original app. Confirm the full text, including its original line breaks, is preserved.
5. Open and then close the main CoPaRe window. Confirm the menu bar icon still works and can reopen the main window.
6. Press Option-Command-V to verify Quick Copy remains available. If unlock protection is enabled, authenticate locally when prompted.

Contact first name:
Eddy

Contact last name:
Boscolo

Contact phone:
Preserve the existing App Store Connect App Review contact number.

Contact email:
Preserve the existing App Store Connect App Review contact email.

## App Privacy

Privacy Policy URL:
https://copare.it/privacy/

User Privacy Choices URL:
https://copare.it/privacy/#privacy-choices

Tracking:
No

Data collected:
None

Data linked to the user:
None

Data used to track the user:
None

Third-party advertising:
No

Analytics:
No

Crash data:
No third-party crash reporting. Any crash reports are handled by Apple's system mechanisms if the user has opted in at the OS/App Store level.

## Export Compliance

Uses encryption:
Yes, using encryption supplied by macOS only.

Encryption explanation:
CoPaRe uses Apple's CryptoKit, CommonCrypto, and Security frameworks for local data protection. Saved snippets and pending snippet recovery use authenticated encryption and Keychain protection. Portable password-protected backups use PBKDF2-HMAC-SHA256 through CommonCrypto and AES-256-GCM through CryptoKit. No cryptographic implementation is bundled with the app. There is no VPN, secure messaging, DRM, cryptocurrency, proprietary network encryption, or server-side processing.

Declaration:
ITSAppUsesNonExemptEncryption is NO. The app uses the operating-system-only encryption category documented by Apple: https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/

## Build Selection

App Store Apple ID:
6771382344

Bundle ID:
io.copare.app

Version:
1.5.1

Build:
22

Local package:
build/app-store/export-local-v1.5.1/CoPaRe.pkg
