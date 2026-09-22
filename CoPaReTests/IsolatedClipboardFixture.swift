import AppKit
import CryptoKit
import Foundation
import LocalAuthentication
@testable import CoPaRe

/// Every test gets a private pasteboard, defaults domain, vault path, and key store.
@MainActor
final class IsolatedClipboardFixture {
    let directory: URL
    let fileURL: URL
    let defaults: UserDefaults
    let settings: SettingsStore
    let keys: InMemorySnippetKeys
    let store: SnippetStore
    let checkpointStore: SnippetCheckpointStore
    let pasteboard: NSPasteboard
    let captureService: ClipboardCaptureService
    let manager: ClipboardManager
    let snapshotKey: SymmetricKey
    private let suiteName: String

    init(persistHistory: Bool = false, lockProtection: Bool = false,
         snapshotKeyDeleter: @escaping () throws -> Void = {},
         authenticateForUnlock: @escaping (LAContext) async throws -> Bool = { _ in true }) throws {
        let identifier = "io.copare.tests.\(UUID().uuidString)"
        suiteName = identifier
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier, isDirectory: true)
        fileURL = directory.appendingPathComponent("snippets.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: identifier)!
        defaults.set(persistHistory, forKey: "persistHistory")
        defaults.set(lockProtection, forKey: "lockProtectionEnabled")
        defaults.set(false, forKey: "globalShortcutEnabled")
        settings = SettingsStore(defaults: defaults)
        keys = InMemorySnippetKeys()
        store = SnippetStore(fileURL: fileURL, keyOperations: keys.operations)
        checkpointStore = SnippetCheckpointStore(fileURL: directory.appendingPathComponent("snippets-pending.json"))
        pasteboard = NSPasteboard(name: .init(identifier))
        captureService = ClipboardCaptureService(
            pasteboard: pasteboard,
            settings: settings,
            sourceBundleIdentifierProvider: { "io.copare.test-source" }
        )
        snapshotKey = SymmetricKey(size: .bits256)
        let snapshotKey = self.snapshotKey
        manager = ClipboardManager(
            settings: settings,
            snippetStore: store,
            checkpointStore: checkpointStore,
            captureService: captureService,
            startsAutomatically: false,
            lockSnapshotKeyLoader: { _ in snapshotKey },
            lockSnapshotKeyDeleter: snapshotKeyDeleter,
            authenticateForUnlock: authenticateForUnlock,
            // Lock tests must not rotate another fixture's process-wide runtime key.
            // Snapshot AES-GCM encryption and authenticated restoration remain real.
            rotateSessionKey: {}
        )
    }

    isolated deinit {
        captureService.stop()
        pasteboard.clearContents()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Only key custody is replaced: SnippetStore still encodes and authenticates real AES-GCM files.
final class InMemorySnippetKeys: @unchecked Sendable {
    enum Failure: Error { case injected }

    private let lock = NSLock()
    private nonisolated(unsafe) var keyData: [String: SymmetricKey] = [:]
    private nonisolated(unsafe) var shouldFailDeletion = false
    private nonisolated(unsafe) var shouldFailLoading = false
    private nonisolated(unsafe) var accessedServices: [String] = []

    nonisolated init() {}

    nonisolated var operations: SnippetKeyOperations {
        SnippetKeyOperations(
            loadOrCreate: { [self] service, _, _ in try load(service) },
            delete: { [self] service, _ in try delete(service) }
        )
    }

    nonisolated var keyCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return keyData.count
    }

    nonisolated var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return accessedServices.count
    }

    nonisolated func failDeletion(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        shouldFailDeletion = value
    }

    nonisolated func failLoading(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        shouldFailLoading = value
    }

    private nonisolated func load(_ service: String) throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        accessedServices.append(service)
        if shouldFailLoading { throw Failure.injected }
        if let key = keyData[service] { return key }
        let key = SymmetricKey(size: .bits256)
        keyData[service] = key
        return key
    }

    private nonisolated func delete(_ service: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if shouldFailDeletion { throw Failure.injected }
        keyData[service] = nil
    }
}
