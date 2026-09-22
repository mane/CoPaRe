import Foundation

nonisolated struct SnippetTransferDocument: Codable, Sendable {
    let version: Int
    let exportedAt: Date
    let snippets: [SnippetTransferItem]
}

nonisolated struct SnippetTransferItem: Codable, Sendable {
    let title: String
    let body: String
    let tags: [String]
    let createdAt: Date
    let updatedAt: Date
    let pinned: Bool
}

nonisolated enum SnippetTransferError: LocalizedError, Equatable {
    case unavailable
    case stateChanged
    case emptyExport
    case unreadableSnippet
    case unsupportedVersion(Int)
    case fileTooLarge
    case invalidDocument
    case readFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Unlock CoPaRe and wait for the vault operation to finish, then try again."
        case .stateChanged:
            return "The history or vault changed during the transfer. Please try again."
        case .emptyExport:
            return "There are no loaded snippets to export. Load your saved snippets first."
        case .unreadableSnippet:
            return "A snippet could not be decrypted. No export was written."
        case let .unsupportedVersion(version):
            return "Snippet file version \(version) is not supported by this version of CoPaRe."
        case .fileTooLarge:
            return "Snippet files must be 10 MB or smaller."
        case .invalidDocument:
            return "This file is not a valid CoPaRe snippet export."
        case .readFailed:
            return "The snippet file could not be read. Check its location and permissions."
        case .writeFailed:
            return "The snippet export could not be saved. Check the destination and permissions."
        }
    }
}

nonisolated enum SnippetTransfer {
    static let maximumFileBytes = 10_000_000

    private struct Header: Decodable {
        let version: Int
    }

    static func read(from url: URL) throws -> SnippetTransferDocument {
        try decode(readData(from: url, maximumBytes: maximumFileBytes))
    }

    static func readData(from url: URL, maximumBytes: Int) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            // Bound the read itself: a metadata size check alone can race a growing file.
            var buffer = Data()
            while let chunk = try handle.read(upToCount: min(64_000, maximumBytes + 1 - buffer.count)),
                  !chunk.isEmpty
            {
                buffer.append(chunk)
                guard buffer.count <= maximumBytes else {
                    throw SnippetTransferError.fileTooLarge
                }
            }
            return buffer
        } catch let error as SnippetTransferError {
            throw error
        } catch {
            throw SnippetTransferError.readFailed
        }

    }

    static func decode(_ data: Data) throws -> SnippetTransferDocument {
        guard data.count <= maximumFileBytes else {
            throw SnippetTransferError.fileTooLarge
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let header = try decoder.decode(Header.self, from: data)
            guard header.version == 1 else {
                throw SnippetTransferError.unsupportedVersion(header.version)
            }
            return try decoder.decode(SnippetTransferDocument.self, from: data)
        } catch let error as SnippetTransferError {
            throw error
        } catch {
            throw SnippetTransferError.invalidDocument
        }
    }

    static func write(_ document: SnippetTransferDocument, to url: URL) throws {
        try writeData(encode(document), to: url)
    }

    static func encode(_ document: SnippetTransferDocument) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(document)
            // Keep exports readable by the same bounded importer.
            guard data.count <= maximumFileBytes else {
                throw SnippetTransferError.fileTooLarge
            }
            return data
        } catch let error as SnippetTransferError {
            throw error
        } catch {
            throw SnippetTransferError.writeFailed
        }
    }

    static func writeData(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw SnippetTransferError.writeFailed
        }
    }
}
