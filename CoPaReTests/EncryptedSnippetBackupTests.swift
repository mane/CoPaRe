import Foundation
import Testing
@testable import CoPaRe

struct EncryptedSnippetBackupTests {
    private let password = "correct horse battery staple"

    private func document() -> SnippetTransferDocument {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        return SnippetTransferDocument(version: 1, exportedAt: date, snippets: [
            SnippetTransferItem(title: "Private title", body: "  very private body\nwith whitespace  ", tags: ["work", "swift"], createdAt: date, updatedAt: date, pinned: true)
        ])
    }

    @Test func portableRoundTripPreservesAllContentAndRandomizesCiphertext() throws {
        let original = document()
        let first = try EncryptedSnippetBackup.encrypt(document: original, password: password)
        let second = try EncryptedSnippetBackup.encrypt(document: original, password: password)
        #expect(first != second)
        let visibleFile = try #require(String(data: first, encoding: .utf8))
        #expect(!visibleFile.contains("Private title"))
        #expect(!visibleFile.contains("very private body"))
        #expect(!visibleFile.contains(password))

        let restored = try EncryptedSnippetBackup.decrypt(data: first, password: password)
        #expect(restored.version == 1)
        #expect(restored.exportedAt == original.exportedAt)
        let snippet = try #require(restored.snippets.first)
        #expect(snippet.title == original.snippets[0].title)
        #expect(snippet.body == original.snippets[0].body)
        #expect(snippet.tags == original.snippets[0].tags)
        #expect(snippet.createdAt == original.snippets[0].createdAt)
        #expect(snippet.updatedAt == original.snippets[0].updatedAt)
        #expect(snippet.pinned)
    }

    @Test func wrongPasswordAndTamperedCiphertextReportSameFailure() throws {
        let data = try EncryptedSnippetBackup.encrypt(document: document(), password: password)
        #expect(throws: EncryptedSnippetBackupError.authenticationFailed) {
            try EncryptedSnippetBackup.decrypt(data: data, password: "another password entirely")
        }
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sealedString = try #require(json["sealed"] as? String)
        var sealed = try #require(Data(base64Encoded: sealedString))
        sealed[sealed.count - 1] ^= 1
        json["sealed"] = sealed.base64EncodedString()
        let modified = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: EncryptedSnippetBackupError.authenticationFailed) {
            try EncryptedSnippetBackup.decrypt(data: modified, password: password)
        }
    }

    @Test func metadataIsAuthenticatedAndKDFWorkIsBounded() throws {
        let data = try EncryptedSnippetBackup.encrypt(document: document(), password: password)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["iterations"] = EncryptedSnippetBackup.iterations + 1
        let changedMetadata = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: EncryptedSnippetBackupError.authenticationFailed) {
            try EncryptedSnippetBackup.decrypt(data: changedMetadata, password: password)
        }
        for count in [0, EncryptedSnippetBackup.iterations - 1, EncryptedSnippetBackup.maximumIterations + 1, Int.max] {
            json["iterations"] = count
            let malicious = try JSONSerialization.data(withJSONObject: json)
            #expect(throws: EncryptedSnippetBackupError.invalidBackup) {
                try EncryptedSnippetBackup.decrypt(data: malicious, password: password)
            }
        }
        json["iterations"] = EncryptedSnippetBackup.iterations
        json["salt"] = Data([1, 2]).base64EncodedString()
        let shortSalt = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: EncryptedSnippetBackupError.invalidBackup) {
            try EncryptedSnippetBackup.decrypt(data: shortSalt, password: password)
        }
    }

    @Test func unsupportedMalformedAndOversizedFilesAreRejected() throws {
        let future = Data(#"{"format":"CoPaRe encrypted snippets","version":2}"#.utf8)
        #expect(throws: EncryptedSnippetBackupError.unsupportedVersion(2)) {
            try EncryptedSnippetBackup.decrypt(data: future, password: password)
        }
        #expect(throws: EncryptedSnippetBackupError.invalidBackup) {
            try EncryptedSnippetBackup.decrypt(data: Data("not JSON".utf8), password: password)
        }
        #expect(throws: EncryptedSnippetBackupError.fileTooLarge) {
            try EncryptedSnippetBackup.decrypt(data: Data(repeating: 0, count: EncryptedSnippetBackup.maximumFileBytes + 1), password: password)
        }
    }

    @Test func passwordLimitsApplyBeforeEncryption() throws {
        #expect(throws: EncryptedSnippetBackupError.passwordTooShort) {
            try EncryptedSnippetBackup.encrypt(document: document(), password: "short")
        }
        #expect(throws: EncryptedSnippetBackupError.passwordTooLong) {
            try EncryptedSnippetBackup.encrypt(document: document(), password: String(repeating: "a", count: EncryptedSnippetBackup.maximumPasswordBytes + 1))
        }
    }

    @Test func encryptedFileIsPrivateAndOversizedReadIsBounded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("backup.encrypted.json")
        let encrypted = try EncryptedSnippetBackup.encrypt(document: document(), password: password)
        try EncryptedSnippetBackup.write(data: encrypted, to: url)
        #expect(try EncryptedSnippetBackup.read(from: url) == encrypted)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(EncryptedSnippetBackup.maximumFileBytes + 1))
        try handle.close()
        #expect(throws: EncryptedSnippetBackupError.fileTooLarge) {
            try EncryptedSnippetBackup.read(from: url)
        }
    }
}
