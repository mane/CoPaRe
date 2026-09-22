import AppKit
import Foundation
import Testing
@testable import CoPaRe

@MainActor
struct SnippetStoreTests {
    private func record(body: String = "vault-only regression content") -> SnippetPersistenceRecord {
        SnippetPersistenceRecord(
            id: UUID(), preview: "Fixture", body: body,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            pinnedAt: Date(timeIntervalSince1970: 1_500), tags: ["test", "vault"]
        )
    }

    @Test(arguments: [false, true])
    func encryptedVaultRoundTripsAcrossStoreInstances(requireUserPresence: Bool) async throws {
        let fixture = try IsolatedClipboardFixture()
        let original = record()
        #expect(await fixture.store.saveSnippets([original], requireUserPresence: requireUserPresence, generation: 1))

        let bytes = try Data(contentsOf: fixture.fileURL)
        #expect(!String(decoding: bytes, as: UTF8.self).contains(original.body))
        let permissions = try FileManager.default.attributesOfItem(atPath: fixture.fileURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)

        let reopened = SnippetStore(fileURL: fixture.fileURL, keyOperations: fixture.keys.operations)
        #expect(await reopened.loadSnippetRecords() == [original])
        let items = try #require(await reopened.loadSnippets())
        #expect(items.count == 1)
        #expect(items.first?.id == original.id)
        #expect(items.first?.decryptedPayload()?.plainText == original.body)
        #expect(items.first?.isSnippet == true)
        #expect(items.first?.isPinned == true)
        #expect(items.first?.tags == original.tags)
    }

    @Test(arguments: ["ciphertext", "tag"])
    func tamperingFailsAuthentication(field: String) async throws {
        let fixture = try IsolatedClipboardFixture()
        #expect(await fixture.store.saveSnippets([record()], requireUserPresence: false, generation: 1))
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.fileURL)) as? [String: Any])
        let encoded = try #require(envelope[field] as? String)
        var bytes = try #require(Data(base64Encoded: encoded))
        bytes[bytes.startIndex] ^= 1
        envelope[field] = bytes.base64EncodedString()
        try JSONSerialization.data(withJSONObject: envelope).write(to: fixture.fileURL)

        #expect(await fixture.store.loadSnippetRecords() == nil)
        #expect(await fixture.store.hasSavedSnippets())
    }

    @Test func rejectsUnknownVersionAndKeyServiceBeforeLookingUpKeys() async throws {
        let fixture = try IsolatedClipboardFixture()
        #expect(await fixture.store.saveSnippets([record()], requireUserPresence: false, generation: 1))
        let original = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.fileURL)) as? [String: Any])
        let priorLookups = fixture.keys.loadCount

        var unsupportedVersion = original
        unsupportedVersion["version"] = 99
        try JSONSerialization.data(withJSONObject: unsupportedVersion).write(to: fixture.fileURL)
        #expect(await fixture.store.loadSnippetRecords() == nil)
        #expect(fixture.keys.loadCount == priorLookups)

        var unknownService = original
        unknownService["keyService"] = "io.example.unrelated-key"
        try JSONSerialization.data(withJSONObject: unknownService).write(to: fixture.fileURL)
        #expect(await fixture.store.loadSnippetRecords() == nil)
        #expect(fixture.keys.loadCount == priorLookups)
    }

    @Test func staleOperationsCannotOverwriteOrResurrectDeletedVault() async throws {
        let fixture = try IsolatedClipboardFixture()
        let current = record(body: "current generation")
        let stale = record(body: "stale generation")
        #expect(await fixture.store.saveSnippets([current], requireUserPresence: false, generation: 3))
        #expect(await !fixture.store.saveSnippets([stale], requireUserPresence: false, generation: 2))
        #expect(await !fixture.store.clearSnippetsFile(generation: 3))
        #expect(await fixture.store.loadSnippetRecords() == [current])
        #expect(await fixture.store.clearSnippetsFile(generation: 4))
        #expect(await !fixture.store.saveSnippets([stale], requireUserPresence: false, generation: 3))
        #expect(await !fixture.store.hasSavedSnippets())
        #expect(fixture.keys.keyCount == 0)
    }

    @Test func emptySaveDeletesBothKeyVariants() async throws {
        let fixture = try IsolatedClipboardFixture()
        let original = record()
        #expect(await fixture.store.saveSnippets([original], requireUserPresence: false, generation: 1))
        #expect(await fixture.store.saveSnippets([original], requireUserPresence: true, generation: 2))
        #expect(fixture.keys.keyCount == 2)

        #expect(await fixture.store.saveSnippets([], requireUserPresence: true, generation: 3))
        #expect(await !fixture.store.hasSavedSnippets())
        #expect(fixture.keys.keyCount == 0)
    }

    @Test func failedKeyAccessPreservesPreviouslyWrittenVault() async throws {
        let fixture = try IsolatedClipboardFixture()
        let original = record()
        #expect(await fixture.store.saveSnippets([original], requireUserPresence: false, generation: 1))
        let originalBytes = try Data(contentsOf: fixture.fileURL)
        fixture.keys.failLoading(true)

        #expect(await !fixture.store.saveSnippets([record(body: "replacement")], requireUserPresence: false, generation: 2))
        #expect(try Data(contentsOf: fixture.fileURL) == originalBytes)
        #expect(await fixture.store.loadSnippetRecords() == nil)
        fixture.keys.failLoading(false)
        #expect(await fixture.store.loadSnippetRecords() == [original])
    }

    @Test func cleanupReportsKeyFailureAndCanBeRetried() async throws {
        let fixture = try IsolatedClipboardFixture()
        #expect(await fixture.store.saveSnippets([record()], requireUserPresence: false, generation: 1))
        fixture.keys.failDeletion(true)
        #expect(await !fixture.store.clearSnippetsFile(generation: 2))
        #expect(await !fixture.store.hasSavedSnippets())
        #expect(fixture.keys.keyCount == 1)

        fixture.keys.failDeletion(false)
        #expect(await fixture.store.clearSnippetsFile(generation: 3))
        #expect(fixture.keys.keyCount == 0)
    }

    @Test func isolatedCaptureDeduplicatesAndOneTimeCopyUsesPrivatePasteboard() throws {
        let fixture = try IsolatedClipboardFixture()
        fixture.settings.oneTimeCopyEnabled = true
        let text = "  fixture clipboard text\n"
        // A new clipboard write starts by taking ownership; setString alone
        // updates data without necessarily advancing the polling change count.
        fixture.pasteboard.clearContents()
        #expect(fixture.pasteboard.setString(text, forType: .string))
        fixture.captureService.pollPasteboard()
        let firstCapture = try #require(fixture.manager.items.first)
        #expect(firstCapture.captureCount == 1)
        fixture.pasteboard.clearContents()
        #expect(fixture.pasteboard.setString(text, forType: .string))
        fixture.captureService.pollPasteboard()

        let item = try #require(fixture.manager.items.first)
        #expect(fixture.manager.items.count == 1)
        #expect(item.id == firstCapture.id)
        #expect(item.captureCount == 2)
        fixture.manager.copyToClipboard(item)
        #expect(fixture.pasteboard.string(forType: .string) == text)
        #expect(fixture.manager.items.isEmpty)
        fixture.captureService.pollPasteboard()
        #expect(fixture.manager.items.isEmpty)
        #expect(fixture.keys.keyCount == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    @Test func resumingMonitoringSkipsContentCopiedWhilePaused() throws {
        let fixture = try IsolatedClipboardFixture()
        fixture.manager.isMonitoringEnabled = false
        #expect(fixture.pasteboard.setString("copied while paused", forType: .string))
        fixture.manager.isMonitoringEnabled = true
        fixture.captureService.pollPasteboard()
        #expect(fixture.manager.items.isEmpty)

        fixture.pasteboard.clearContents()
        #expect(fixture.pasteboard.setString("copied after resuming", forType: .string))
        fixture.captureService.pollPasteboard()
        #expect(fixture.manager.items.first?.decryptedPayload()?.plainText == "copied after resuming")
    }
}
