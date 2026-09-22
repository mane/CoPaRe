import CryptoKit
import Foundation
import Testing
@testable import CoPaRe

struct SnippetCheckpointStoreTests {
    private func makeStore() throws -> SnippetCheckpointStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoPaReCheckpointTests-\(UUID().uuidString)", isDirectory: true)
        return SnippetCheckpointStore(fileURL: directory.appendingPathComponent("snippets-pending.json"))
    }

    private func record() -> SnippetPersistenceRecord {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        return SnippetPersistenceRecord(id: UUID(), preview: "Private checkpoint title", body: "  pending snippet body\n", createdAt: date, updatedAt: date, pinnedAt: date, tags: ["work", "swift"])
    }

    @Test func checkpointSurvivesStoreRecreationWithCompleteMetadataAndTombstones() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let key = SymmetricKey(size: .bits256)
        let snippet = record()
        let deletedID = UUID()
        #expect(!store.exists)
        #expect(try store.load(using: key) == nil)
        try store.save(records: [snippet], deletedIDs: [deletedID], using: key)

        let restarted = SnippetCheckpointStore(fileURL: store.fileURL)
        let restored = try #require(try restarted.load(using: key))
        #expect(restored.records == [snippet])
        #expect(restored.deletedIDs == [deletedID])
        let diskText = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!diskText.contains(snippet.preview))
        #expect(!diskText.contains(snippet.body))
        #expect(!diskText.contains(deletedID.uuidString))
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try restarted.clear()
        #expect(!store.exists)
        try restarted.clear()
    }

    @Test func deletionOnlyCheckpointIsRetained() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let key = SymmetricKey(size: .bits256)
        let deletedID = UUID()
        try store.save(records: [], deletedIDs: [deletedID], using: key)
        let restored = try #require(try store.load(using: key))
        #expect(restored.records.isEmpty)
        #expect(restored.deletedIDs == [deletedID])
    }

    @Test func wrongKeyOrTamperingNeverDeletesRecoveryData() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let key = SymmetricKey(size: .bits256)
        try store.save(records: [record()], deletedIDs: [], using: key)
        #expect(throws: SnippetCheckpointError.authenticationFailed) {
            try store.load(using: SymmetricKey(size: .bits256))
        }
        #expect(store.exists)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
        let sealedString = try #require(json["sealed"] as? String)
        var sealed = try #require(Data(base64Encoded: sealedString))
        sealed[sealed.count - 1] ^= 1
        json["sealed"] = sealed.base64EncodedString()
        try JSONSerialization.data(withJSONObject: json).write(to: store.fileURL)
        #expect(throws: SnippetCheckpointError.authenticationFailed) { try store.load(using: key) }
        #expect(store.exists)
    }

    @Test func futureMalformedAndOversizedFilesRemainAvailableForRecovery() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let key = SymmetricKey(size: .bits256)
        try Data(#"{"version":2}"#.utf8).write(to: store.fileURL)
        #expect(throws: SnippetCheckpointError.unsupportedVersion(2)) { try store.load(using: key) }
        try Data("not JSON".utf8).write(to: store.fileURL)
        #expect(throws: SnippetCheckpointError.invalidCheckpoint) { try store.load(using: key) }
        let handle = try FileHandle(forWritingTo: store.fileURL)
        try handle.truncate(atOffset: UInt64(SnippetCheckpointStore.maximumFileBytes + 1))
        try handle.close()
        #expect(throws: SnippetCheckpointError.fileTooLarge) { try store.load(using: key) }
        #expect(store.exists)
    }
}
