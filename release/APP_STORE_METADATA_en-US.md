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

## macOS App Version 1.5.0

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
1.5.0

What's New:
CoPaRe 1.5.0 makes everyday copying faster and gives you more control over saved content:

- Quick Copy: press Option-Command-V, search, select with the arrow keys, and press Return to copy and return to your previous app.
- Edit and duplicate snippets, or save captured text and URLs as reusable snippets.
- Automatically lock when leaving CoPaRe, on display or Mac sleep, on user switching, or after inactivity in the app.
- Expire copies made by CoPaRe from the system clipboard while preserving anything copied afterward.
- Create password-protected snippet backups and restore them on another Mac.
- Copy text from images with on-device recognition.
- Recover pending snippet edits after locking and quitting, without saving captured clipboard history.
- More reliable imports, clearer transfer errors, and faster capture-rule handling.

Copyright:
© 2026 EDDY BOSCOLO

## App Review Information

Sign-in required:
No

Demo account:
Not applicable

Review notes:
CoPaRe is a sandboxed, local macOS menu bar clipboard utility. No account, subscription, server, Accessibility permission, or external updater is required. Updates for this build are delivered through the Mac App Store.

Captured clipboard history exists only for the current app session. Only text explicitly saved as snippets is eligible for encrypted persistence. A protected recovery file contains pending snippet records/deletion markers, never captured history. Saved snippets are loaded explicitly after startup; authenticated unlock also recovers pending changes.

Quick Copy uses the existing public Carbon global hotkey, an AppKit panel, and NSPasteboard. It copies content and restores the prior app's focus; it does not inject paste events or monitor other apps' keyboard input. Inactivity locking measures interaction within CoPaRe. Focus-loss, display/Mac sleep, and user-switch locking use documented AppKit/workspace events.

Image text recognition uses Vision locally after an explicit Copy Text action. Portable backups use only macOS CommonCrypto, CryptoKit, and Security frameworks. Native open/save panels use the existing user-selected file entitlement. Backups and readable JSON exports include only loaded snippets. The optional Search Web action sends selected text to a search engine through the default browser only when explicitly requested.

Suggested review steps:
1. Launch CoPaRe, complete or skip onboarding, and copy a short non-sensitive text sample in another app.
2. Press Option-Command-V, type to search, use the arrow keys, and press Return. Paste in your original app to verify the copy.
3. Open the main window from the menu bar. Select captured text, choose Save as Snippet, and review its title, body, and tags. Edit and duplicate the snippet.
4. In Settings, create an encrypted backup with a test password. Restore it with the same password. Duplicate snippets are not added again. Load Saved Snippets first if testing a vault saved in a previous session.
5. Copy an image containing text, select it in CoPaRe, reveal its content if needed, and choose Copy Text. Paste to verify recognition.
6. In Settings, enable unlock protection and automatic locking. Leave CoPaRe and reopen it; authenticate with the Mac's local authentication mechanism to unlock. Disable focus-loss locking while inspecting the main window alongside another app if desired.
7. Configure clipboard expiry, copy an item from CoPaRe, and verify expiry. Copy something newer in another app before the deadline to verify it is preserved.

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
1.5.0

Build:
21

Local package:
build/app-store/export/CoPaRe.pkg
