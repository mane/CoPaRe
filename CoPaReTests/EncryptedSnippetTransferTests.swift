import Foundation
import Testing
@testable import CoPaRe

@MainActor
struct EncryptedSnippetTransferTests {
    private let password = "a portable backup passphrase"

    @Test func backupRestoresIntoAnIndependentVaultAndSkipsDuplicates() async throws {
        let source = try IsolatedClipboardFixture()
        source.manager.addSnippet(title: "Reusable", body: "  indented\ntext  ", tags: ["Work", "#Swift"])
        let item = try #require(source.manager.items.first)
        source.manager.togglePin(itemID: item.id)
        let destinationURL = source.directory.appendingPathComponent("portable.encrypted.json")
        try await source.manager.exportEncryptedSnippets(to: destinationURL, password: password)

        let destination = try IsolatedClipboardFixture()
        #expect(try await destination.manager.importEncryptedSnippets(from: destinationURL, password: password) == 1)
        let restored = try #require(destination.manager.items.first)
        #expect(restored.preview == "Reusable")
        #expect(restored.decryptedPayload()?.plainText == "  indented\ntext  ")
        #expect(restored.tags == ["work", "swift"])
        #expect(restored.isPinned)
        #expect(try await destination.manager.importEncryptedSnippets(from: destinationURL, password: password) == 0)
        #expect(destination.manager.items.count == 1)
    }

    @Test func wrongPasswordLeavesExistingSnippetsUntouched() async throws {
        let fixture = try IsolatedClipboardFixture()
        fixture.manager.addSnippet(title: "Keep", body: "already here")
        let url = fixture.directory.appendingPathComponent("backup.encrypted.json")
        try await fixture.manager.exportEncryptedSnippets(to: url, password: password)
        let existingIDs = fixture.manager.items.map(\.id)

        await #expect(throws: EncryptedSnippetBackupError.authenticationFailed) {
            try await fixture.manager.importEncryptedSnippets(from: url, password: "an incorrect password")
        }
        #expect(fixture.manager.items.map(\.id) == existingIDs)
    }

    @Test func cancelledExportNeverReplacesAnExistingDestination() async throws {
        let fixture = try IsolatedClipboardFixture()
        fixture.manager.addSnippet(title: "Example", body: "private body")
        let url = fixture.directory.appendingPathComponent("existing.encrypted.json")
        let original = Data("preserve this destination".utf8)
        try original.write(to: url)
        let task = Task { @MainActor in
            try await fixture.manager.exportEncryptedSnippets(to: url, password: password)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func cancelledRestoreNeverMutatesTheCollection() async throws {
        let source = try IsolatedClipboardFixture()
        source.manager.addSnippet(title: "Example", body: "private body")
        let url = source.directory.appendingPathComponent("backup.encrypted.json")
        try await source.manager.exportEncryptedSnippets(to: url, password: password)

        let destination = try IsolatedClipboardFixture()
        let task = Task { @MainActor in
            try await destination.manager.importEncryptedSnippets(from: url, password: password)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(destination.manager.items.isEmpty)
    }
}
