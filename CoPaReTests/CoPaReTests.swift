//
//  CoPaReTests.swift
//  CoPaReTests
//
//  Created by CoPaRe contributors.
//

import Testing
@testable import CoPaRe

struct CoPaReTests {

    @Test func encryptedClipboardPayloadRoundTrips() throws {
        let payload = ClipboardItemPayload(
            plainText: "copare test payload",
            imagePNGData: nil,
            filePaths: ["/tmp/example.txt"]
        )

        let sealed = try EncryptedClipboardPayload.seal(payload, service: "io.copare.tests")
        let reopened = try sealed.open(service: "io.copare.tests")

        #expect(reopened == payload)
    }

    @Test func blocksProtectedPasteboardSignalsAndSensitiveFiles() {
        #expect(SensitiveContentDetector.shouldBlock(pasteboardTypes: ["org.nspasteboard.ConcealedType"]))
        #expect(SensitiveContentDetector.shouldBlock(pasteboardTypes: ["com.agilebits.onepassword.clipboard"]))
        #expect(SensitiveContentDetector.shouldBlock(filePath: "/Users/test/.ssh/id_ed25519"))
        #expect(SensitiveContentDetector.shouldBlock(filePath: "/Users/test/vpn/work.ovpn"))
        #expect(!SensitiveContentDetector.shouldBlock(filePath: "/Users/test/Documents/notes.txt"))
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

}
