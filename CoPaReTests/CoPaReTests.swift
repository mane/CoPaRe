//
//  CoPaReTests.swift
//  CoPaReTests
//
//  Created by CoPaRe contributors.
//

import Foundation
import Testing
@testable import CoPaRe

struct CoPaReTests {

    @Test func encryptedClipboardPayloadRoundTrips() throws {
        let payload = ClipboardItemPayload(
            plainText: "copare test payload",
            imagePNGData: nil,
            filePaths: ["/tmp/example.txt"]
        )

        let sealed = try EncryptedClipboardPayload.seal(payload)
        let reopened = try sealed.open()

        #expect(reopened == payload)
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
    }

}
