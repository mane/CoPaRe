import Foundation
import Testing
@testable import CoPaRe

@MainActor
struct SnippetTransferTests {
    @Test func exportImportPreservesContentTagsAndPinsWithoutDuplicates() async throws {
        let source = try IsolatedClipboardFixture()
        source.manager.addSnippet(title: "Example", body: "  line one\nline two\n", tags: ["Work", "#swift"])
        let original = try #require(source.manager.items.first)
        source.manager.togglePin(itemID: original.id)

        let url = source.directory.appendingPathComponent("export.json")
        try source.manager.exportSnippets(to: url)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)

        let destination = try IsolatedClipboardFixture()
        #expect(try await destination.manager.importSnippets(from: url) == 1)
        let restored = try #require(destination.manager.items.first)
        #expect(restored.preview == "Example")
        #expect(restored.decryptedPayload()?.plainText == "  line one\nline two\n")
        #expect(restored.tags == ["work", "swift"])
        #expect(restored.isPinned)
        #expect(try await destination.manager.importSnippets(from: url) == 0)
        #expect(destination.manager.items.count == 1)
    }

    @Test func unsupportedVersionDoesNotMutateHistory() async throws {
        let fixture = try IsolatedClipboardFixture()
        fixture.manager.addSnippet(title: "Keep", body: "existing content")
        let ids = fixture.manager.items.map(\.id)
        let url = fixture.directory.appendingPathComponent("future.json")
        try Data(#"{"version":2,"newSchema":true}"#.utf8).write(to: url)

        await #expect(throws: SnippetTransferError.unsupportedVersion(2)) {
            try await fixture.manager.importSnippets(from: url)
        }
        #expect(fixture.manager.items.map(\.id) == ids)
    }

    @Test func malformedAndMissingFilesReportErrors() async throws {
        let fixture = try IsolatedClipboardFixture()
        let url = fixture.directory.appendingPathComponent("invalid.json")
        try Data(#"{"version":1,"snippets":"invalid"}"#.utf8).write(to: url)
        await #expect(throws: SnippetTransferError.invalidDocument) {
            try await fixture.manager.importSnippets(from: url)
        }
        try FileManager.default.removeItem(at: url)
        await #expect(throws: SnippetTransferError.readFailed) {
            try await fixture.manager.importSnippets(from: url)
        }
        #expect(fixture.manager.items.isEmpty)
    }

    @Test func oversizedImportIsRejectedBeforeDecoding() async throws {
        let fixture = try IsolatedClipboardFixture()
        let url = fixture.directory.appendingPathComponent("oversized.json")
        #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(SnippetTransfer.maximumFileBytes + 1))
        try handle.close()

        await #expect(throws: SnippetTransferError.fileTooLarge) {
            try await fixture.manager.importSnippets(from: url)
        }
        #expect(fixture.manager.items.isEmpty)
    }

    @Test func emptyExportDoesNotReplaceExistingFile() async throws {
        let fixture = try IsolatedClipboardFixture()
        let url = fixture.directory.appendingPathComponent("existing.json")
        let original = Data("keep this file".utf8)
        try original.write(to: url)
        #expect(throws: SnippetTransferError.emptyExport) {
            try fixture.manager.exportSnippets(to: url)
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func cancelledImportDoesNotAddSnippets() async throws {
        let fixture = try IsolatedClipboardFixture()
        let url = fixture.directory.appendingPathComponent("cancelled.json")
        let now = Date()
        try SnippetTransfer.write(
            SnippetTransferDocument(version: 1, exportedAt: now, snippets: [
                SnippetTransferItem(title: "Example", body: "body", tags: [], createdAt: now, updatedAt: now, pinned: false)
            ]),
            to: url
        )
        let task = Task { @MainActor in
            try await fixture.manager.importSnippets(from: url)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(fixture.manager.items.isEmpty)
    }
}
