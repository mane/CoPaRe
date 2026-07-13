//
//  CoPaReTests.swift
//  CoPaReTests
//
//  Created by CoPaRe contributors.
//

import AppKit
import Foundation
import Testing
@testable import CoPaRe

struct CoPaReTests {

    @MainActor @Test func encryptedClipboardPayloadRoundTrips() throws {
        let payload = ClipboardItemPayload(
            plainText: "copare test payload",
            imagePNGData: nil,
            filePaths: ["/tmp/example.txt"]
        )

        let sealed = try EncryptedClipboardPayload.seal(payload)
        let reopened = try sealed.open()

        #expect(reopened == payload)
    }

    @MainActor @Test func encryptedClipboardPayloadRejectsUnknownVersions() throws {
        let payload = ClipboardItemPayload(
            plainText: "versioned payload",
            imagePNGData: nil,
            filePaths: nil
        )
        let sealed = try EncryptedClipboardPayload.seal(payload)
        let unsupported = EncryptedClipboardPayload(
            version: sealed.version + 1,
            keyService: sealed.keyService,
            nonce: sealed.nonce,
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )

        #expect(throws: (any Error).self) {
            try unsupported.open()
        }
    }

    @Test func blocksProtectedPasteboardSignalsAndSensitiveFiles() {
        #expect(SensitiveContentDetector.shouldBlock(pasteboardTypes: ["org.nspasteboard.ConcealedType"]))
        #expect(SensitiveContentDetector.shouldBlock(pasteboardTypes: ["com.agilebits.onepassword.clipboard"]))
        #expect(SensitiveContentDetector.shouldBlock(filePath: "/Users/test/.ssh/id_ed25519"))
        #expect(SensitiveContentDetector.shouldBlock(filePath: "/Users/test/vpn/work.ovpn"))
        #expect(!SensitiveContentDetector.shouldBlock(filePath: "/Users/test/Documents/notes.txt"))
    }

    @Test func blocksEmbeddedSecretsAndSymlinkedSensitiveTargets() throws {
        #expect(SensitiveContentDetector.shouldBlock(text: "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abcdefghi123456789.jklmnopq123456789"))
        #expect(SensitiveContentDetector.shouldBlock(text: "-----BEGIN PGP PRIVATE KEY BLOCK-----"))

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("copare-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let target = tempRoot.appendingPathComponent(".env")
        try "TOKEN=super-secret".write(to: target, atomically: true, encoding: .utf8)

        let symlink = tempRoot.appendingPathComponent("notes.txt")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)

        #expect(SensitiveContentDetector.shouldBlock(filePath: symlink.path))
    }

    @Test func masksTokenLikePreviewStrings() {
        #expect(SensitiveContentDetector.shouldMaskPreview(text: "AKIAIOSFODNN7EXAMPLE123456"))
        #expect(SensitiveContentDetector.shouldMaskPreview(text: "Q3VzdG9tVG9rZW5fMDEyMzQ1Njc4OTAxMjM0NQ=="))
        #expect(!SensitiveContentDetector.shouldMaskPreview(text: "Deployment notes for sprint planning"))
    }

    @Test func blocksSensitiveURLCredentials() {
        let signedURL = "https://example.com/download?X-Amz-Signature=abcdef1234567890abcdef1234567890&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE"
        let credentialURL = "https://user:secret-password-value@example.com/private"

        #expect(SensitiveContentDetector.shouldBlock(text: signedURL))
        #expect(SensitiveContentDetector.shouldMaskPreview(text: signedURL))
        #expect(SensitiveContentDetector.shouldBlock(text: credentialURL))
        #expect(!SensitiveContentDetector.shouldMaskPreview(text: "https://example.com/docs/release-notes"))
    }

    @Test func buildSearchIndexKeepsOnlyMinimalFileMetadata() {
        let textSearchIndex = ClipboardHistoryItem.makeSearchIndex(
            for: .text,
            preview: "Preview"
        )
        let fileSearchIndex = ClipboardHistoryItem.makeSearchIndex(
            for: .file,
            preview: "  id_ed25519.pub  "
        )

        #expect(textSearchIndex == nil)
        #expect(fileSearchIndex == "id_ed25519.pub")
    }

    @Test func clipboardItemTTLExposesExpectedDurations() {
        #expect(ClipboardItemTTL.never.interval == nil)
        #expect(ClipboardItemTTL.thirtySeconds.interval == 30)
        #expect(ClipboardItemTTL.fiveMinutes.interval == 300)
        #expect(ClipboardItemTTL.oneHour.interval == 3_600)
    }

    @Test func clipboardTagsNormalizeAndDeduplicate() {
        let tags = ClipboardHistoryItem.parseTags(" Work, #Swift; work\nPrivacy C# ")

        #expect(tags == ["work", "swift", "privacy", "c#"])
    }

    @MainActor
    @Test func settingsNormalizeExcludedApps() {
        let suiteName = "io.copare.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = SettingsStore(defaults: defaults)
        settings.excludedAppsRawText = " COM.1PASSWORD.1PASSWORD \ncom.bitwarden.desktop\ncom.bitwarden.desktop\n"

        #expect(settings.excludedBundleIdentifiers.contains("com.1password.1password"))
        #expect(settings.excludedBundleIdentifiers.contains("com.bitwarden.desktop"))
        #expect(settings.excludedBundleIdentifiers.count == 2)
        #expect(defaults.string(forKey: "excludedAppsRawText") == "com.1password.1password\ncom.bitwarden.desktop")
    }

    @MainActor
    @Test func settingsClampInvalidStoredNumericValues() {
        let suiteName = "io.copare.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(-10, forKey: "historyLimit")
        defaults.set(Double.nan, forKey: "pollInterval")
        defaults.set(5_000, forKey: "perAppHistoryLimit")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = SettingsStore(defaults: defaults)

        #expect(settings.historyLimit == 20)
        #expect(settings.pollInterval == 0.65)
        #expect(settings.perAppHistoryLimit == 500)
        #expect(defaults.integer(forKey: "historyLimit") == 20)
        #expect(defaults.double(forKey: "pollInterval") == 0.65)
        #expect(defaults.integer(forKey: "perAppHistoryLimit") == 500)
    }

    @MainActor
    @Test func settingsRejectNonFiniteRuntimePollingIntervals() {
        let suiteName = "io.copare.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(1.25, forKey: "pollInterval")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = SettingsStore(defaults: defaults)
        var changeCount = 0
        settings.onChange = {
            changeCount += 1
        }

        settings.pollInterval = .nan

        #expect(settings.pollInterval == 0.65)
        #expect(defaults.double(forKey: "pollInterval") == 0.65)
        #expect(changeCount == 1)
    }

    @MainActor
    @Test func capturesWebURLsAsURLsAndFileURLsAsFiles() throws {
        let suiteName = "io.copare.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.copare.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
        }

        let settings = SettingsStore(defaults: defaults)
        let service = ClipboardCaptureService(
            pasteboard: pasteboard,
            settings: settings,
            sourceBundleIdentifierProvider: { "com.example.browser" }
        )
        let webURL = try #require(URL(string: "https://example.com/docs"))
        #expect(pasteboard.writeObjects([webURL as NSURL]))
        #expect(pasteboard.string(forType: .URL) == webURL.absoluteString)
        let webCapture = service.readCapture()

        #expect(webCapture?.type == .url)
        #expect(try webCapture?.encryptedPayload?.open().plainText == webURL.absoluteString)

        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("copare-example-\(UUID().uuidString).txt")
        try "example".write(to: fileURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([fileURL as NSURL]))
        let pastedFileURLs = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        #expect(pastedFileURLs?.first?.isFileURL == true)
        let fileCapture = service.readCapture()

        #expect(fileCapture?.type == .file)
        #expect(try fileCapture?.encryptedPayload?.open().filePaths == [fileURL.path])
    }

    @MainActor
    @Test func settingsParsePerAppCaptureRules() {
        let suiteName = "io.copare.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = SettingsStore(defaults: defaults)
        settings.appCaptureRulesRawText = """
        com.example.secret ignore
        com.example.editor text-only ttl:15m
        com.example.chat 5m
        """

        #expect(settings.appCaptureRule(for: "com.example.secret")?.ignoresCapture == true)
        #expect(settings.appCaptureRule(for: "com.example.editor")?.textOnly == true)
        #expect(settings.appCaptureRule(for: "com.example.editor")?.ttl == .fifteenMinutes)
        #expect(settings.appCaptureRule(for: "com.example.chat")?.ttl == .fiveMinutes)
    }

    @MainActor
    @Test func snippetsPreserveUserWhitespace() {
        let suiteName = "io.copare.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(false, forKey: "persistHistory")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = SettingsStore(defaults: defaults)
        let manager = ClipboardManager(settings: settings)
        let body = "  indented value\n"

        manager.addSnippet(title: "", body: body)

        #expect(manager.items.first?.decryptedPayload()?.plainText == body)
    }

    @MainActor
    @Test func snippetsStoreNormalizedTags() {
        let suiteName = "io.copare.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(false, forKey: "persistHistory")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = SettingsStore(defaults: defaults)
        let manager = ClipboardManager(settings: settings)

        manager.addSnippet(title: "Tagged", body: "body", tags: ["Work", "#swift", "work"])

        #expect(manager.items.first?.tags == ["work", "swift"])
        #expect(manager.filteredItems.first?.preview == "Tagged")
        manager.searchText = "#swift"
        #expect(manager.filteredItems.first?.preview == "Tagged")
    }

}
