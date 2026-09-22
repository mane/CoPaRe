import AppKit
import Foundation
import Combine
import LocalAuthentication
import CryptoKit
import OSLog

enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all
    case pinned
    case text
    case image
    case file

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "All"
        case .pinned:
            return "Pinned"
        case .text:
            return "Text"
        case .image:
            return "Images"
        case .file:
            return "Files"
        }
    }
}

struct SecurityEventCounters: Equatable {
    var sensitiveContentBlocked = 0
    var excludedApplicationSkips = 0
    var expiredEntriesRemoved = 0
    var secureWipes = 0
    var unlockEvents = 0
    var privacyPauses = 0

    var totalBlocked: Int {
        sensitiveContentBlocked + excludedApplicationSkips
    }
}

private struct LockedClipboardSnapshot: Codable {
    let version: Int
    let lockedAt: Date
    let items: [LockedClipboardSnapshotItem]
}

private struct LockedClipboardSnapshotItem: Codable {
    let id: UUID
    let type: ClipboardItemType
    let createdAt: Date
    let updatedAt: Date
    let pinnedAt: Date?
    let expiresAt: Date?
    let preview: String
    let searchIndex: String?
    let thumbnailPNGData: Data?
    let payload: ClipboardItemPayload?
    let digest: String
    let byteSize: Int
    let origin: ClipboardItemOrigin
    let captureCount: Int
    let sourceBundleIdentifier: String?
    let tags: [String]
}

private struct LockedClipboardEnvelope {
    let nonce: Data
    let ciphertext: Data
    let tag: Data
}

private enum PreparedLockedSnapshot {
    case empty
    case encrypted(LockedClipboardEnvelope)

    var envelope: LockedClipboardEnvelope? {
        switch self {
        case .empty:
            return nil
        case let .encrypted(envelope):
            return envelope
        }
    }
}

@MainActor
final class ClipboardManager: ObservableObject {
    @Published private(set) var items: [ClipboardHistoryItem] = [] {
        didSet { contentRevision += 1 }
    }
    @Published var searchText = ""
    @Published var activeFilter: ClipboardFilter = .all
    @Published var isMonitoringEnabled = true {
        didSet {
            syncCaptureServiceMonitoringState()
        }
    }
    @Published private(set) var securityCounters = SecurityEventCounters()
    @Published private(set) var isLocked: Bool
    @Published private(set) var hasSavedSnippetsAvailable = false
    @Published private(set) var savedSnippetsLoaded = true
    @Published private(set) var secureWipeMessage: String?
    @Published private(set) var secureWipeFailed = false
    @Published private(set) var privacyPauseUntil: Date?
    @Published private(set) var isVaultTransitioning = false {
        didSet {
            if !isVaultTransitioning, automaticLockPending {
                automaticLockPending = false
                lockAutomatically()
            }
        }
    }
    @Published private(set) var isUnlocking = false
    @Published private(set) var lockFailureMessage: String?

    let settings: SettingsStore

    private let snippetStore: SnippetStore
    private let checkpointStore: SnippetCheckpointStore
    private let captureService: ClipboardCaptureService
    private let startsAutomatically: Bool
    private let logger = Logger(subsystem: "io.copare.app", category: "lock")
    private let lockSnapshotKeyLoader: (LAContext?) throws -> SymmetricKey
    private let lockSnapshotKeyDeleter: () throws -> Void
    private let authenticateForUnlock: (LAContext) async throws -> Bool
    private let rotateSessionKey: () -> Void
    private var autoLockService: AutoLockService?
    // Available only during an authenticated unlocked session. Automatic lock
    // can seal immediately without attempting Keychain UI on a sleeping Mac.
    private var unlockedSnapshotKey: SymmetricKey?
    private var automaticLockPending = false
    private var securityEventGeneration = 0
    private var activeAuthenticationContext: LAContext?
    private var unlockedAuthenticationContext: LAContext?

    private var persistTask: Task<Void, Never>?
    private var expirationTimer: Timer?
    private var privacyPauseTimer: Timer?
    private var lockedSnapshotEnvelope: LockedClipboardEnvelope?
    private var vaultOperationGeneration = 0
    private var contentRevision = 0
    private var settingsGeneration = 0
    private var pendingSnippetDeletionIDs: Set<UUID> = []
    private var disabledPersistenceCleanupFailed = false
    private var appliedLockProtectionEnabled: Bool
    private var appliedPersistenceEnabled: Bool

    init(
        settings: SettingsStore,
        snippetStore: SnippetStore = SnippetStore(),
        checkpointStore: SnippetCheckpointStore = SnippetCheckpointStore(),
        captureService: ClipboardCaptureService? = nil,
        startsAutomatically: Bool = true,
        lockSnapshotKeyLoader: @escaping (LAContext?) throws -> SymmetricKey = { context in
            try KeychainKeyProvider(
                service: "io.copare.app.lock-snapshot",
                requiresUserPresence: true,
                cacheInMemory: false
            ).loadOrCreateKey(authenticationContext: context)
        },
        lockSnapshotKeyDeleter: @escaping () throws -> Void = {
            try KeychainKeyProvider(service: "io.copare.app.lock-snapshot", requiresUserPresence: true, cacheInMemory: false).deleteKey()
        },
        authenticateForUnlock: @escaping (LAContext) async throws -> Bool = { context in
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock CoPaRe to view clipboard history")
        },
        rotateSessionKey: @escaping () -> Void = { EncryptedClipboardPayload.rotateSessionProtectionKey() }
    ) {
        self.settings = settings
        self.snippetStore = snippetStore
        self.checkpointStore = checkpointStore
        self.captureService = captureService ?? ClipboardCaptureService(settings: settings)
        self.startsAutomatically = startsAutomatically
        self.lockSnapshotKeyLoader = lockSnapshotKeyLoader
        self.lockSnapshotKeyDeleter = lockSnapshotKeyDeleter
        self.authenticateForUnlock = authenticateForUnlock
        self.rotateSessionKey = rotateSessionKey
        isLocked = settings.lockProtectionEnabled
        appliedLockProtectionEnabled = settings.lockProtectionEnabled
        appliedPersistenceEnabled = settings.persistHistory

        self.captureService.onCapture = { [weak self] capture in
            self?.handleCapture(capture)
        }

        self.captureService.onSensitiveContentSkipped = { [weak self] in
            self?.mutateSecurityCounters { $0.sensitiveContentBlocked += 1 }
        }

        self.captureService.onExcludedApplicationSkipped = { [weak self] in
            self?.mutateSecurityCounters { $0.excludedApplicationSkips += 1 }
        }

        settings.onChange = { [weak self] in
            self?.applySettingsChanges()
        }

        syncCaptureServiceMonitoringState()
        if startsAutomatically {
            let autoLockService = AutoLockService(settings: settings) { [weak self] reason in
                guard let self else { return }
                // Authentication's own focus changes are not user inactivity.
                guard reason == .system || !self.isUnlocking else { return }
                self.lockAutomatically()
            }
            self.autoLockService = autoLockService
            autoLockService.start()
            self.captureService.start()
            configureExpirationTimer()

            Task {
                await loadInitialState()
            }
        }
    }

    isolated deinit {
        persistTask?.cancel()
        expirationTimer?.invalidate()
        privacyPauseTimer?.invalidate()
    }

    var filteredItems: [ClipboardHistoryItem] {
        guard !isLocked, !isVaultTransitioning else {
            return []
        }

        let filtered = items.filter { item in
            switch activeFilter {
            case .all:
                return true
            case .pinned:
                return item.isPinned
            case .text:
                return item.type == .text || item.type == .url
            case .image:
                return item.type == .image
            case .file:
                return item.type == .file
            }
        }

        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !query.isEmpty else {
            return filtered
        }

        return filtered.filter { item in
            if item.preview.lowercased().contains(query) {
                return true
            }
            if item.tags.contains(where: { $0.contains(query) || "#\($0)".contains(query) }) {
                return true
            }
            if let searchIndex = item.searchIndex?.lowercased(), searchIndex.contains(query) {
                return true
            }
            return false
        }
    }

    var menuItems: [ClipboardHistoryItem] {
        guard !isLocked, !isVaultTransitioning else {
            return []
        }
        return Array(items.prefix(8))
    }

    var isPrivacyPaused: Bool {
        guard let privacyPauseUntil else {
            return false
        }
        return privacyPauseUntil > Date()
    }

    var privacyPauseStatus: String? {
        guard let privacyPauseUntil, privacyPauseUntil > Date() else {
            return nil
        }

        let remaining = max(0, Int(privacyPauseUntil.timeIntervalSinceNow.rounded(.up)))
        if remaining >= 60 {
            return "\(Int(ceil(Double(remaining) / 60.0)))m"
        }
        return "\(remaining)s"
    }

    func item(with id: UUID?) -> ClipboardHistoryItem? {
        guard !isLocked, !isVaultTransitioning, let id else {
            return nil
        }
        return items.first(where: { $0.id == id })
    }

    func sourceApplicationName(for item: ClipboardHistoryItem) -> String? {
        SourceApplicationResolver.displayName(for: item.sourceBundleIdentifier)
    }

    @discardableResult
    func copyToClipboard(_ item: ClipboardHistoryItem) -> Bool {
        guard let current = self.item(with: item.id), current.digest == item.digest else {
            return false
        }

        guard captureService.writeToPasteboard(item: current) else {
            return false
        }

        if settings.oneTimeCopyEnabled, !item.isPinned, !item.isSnippet {
            remove(itemID: item.id, immediatelyPersist: true)
        }
        return true
    }

    @discardableResult
    func copyRecognizedText(_ text: String, from itemID: UUID) -> Bool {
        guard let item = item(with: itemID), item.type == .image,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              captureService.writeString(text) else { return false }
        if settings.oneTimeCopyEnabled, !item.isPinned {
            remove(itemID: itemID, immediatelyPersist: true)
        }
        return true
    }

    func copyAsPlainText(_ item: ClipboardHistoryItem) {
        guard !isLocked, !isVaultTransitioning else {
            return
        }

        guard captureService.writePlainTextToPasteboard(item: item) else {
            return
        }

        if settings.oneTimeCopyEnabled, !item.isPinned, !item.isSnippet {
            remove(itemID: item.id, immediatelyPersist: true)
        }
    }

    func copyCleanText(_ item: ClipboardHistoryItem) {
        guard !isLocked,
              !isVaultTransitioning,
              let text = plainTextRepresentation(for: item)?.condensingWhitespace(),
              !text.isEmpty
        else {
            return
        }

        guard captureService.writeString(text) else {
            return
        }

        if settings.oneTimeCopyEnabled, !item.isPinned, !item.isSnippet {
            remove(itemID: item.id, immediatelyPersist: true)
        }
    }

    func copyAsMarkdown(_ item: ClipboardHistoryItem) {
        guard !isLocked,
              !isVaultTransitioning,
              let markdown = markdownRepresentation(for: item)
        else {
            return
        }

        guard captureService.writeString(markdown) else {
            return
        }

        if settings.oneTimeCopyEnabled, !item.isPinned, !item.isSnippet {
            remove(itemID: item.id, immediatelyPersist: true)
        }
    }

    func openURL(_ item: ClipboardHistoryItem) {
        guard !isLocked, !isVaultTransitioning, let url = urlRepresentation(for: item) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func searchWeb(for item: ClipboardHistoryItem) {
        guard !isLocked,
              !isVaultTransitioning,
              let query = plainTextRepresentation(for: item)?.previewSnippet(maxLength: 300),
              !query.isEmpty
        else {
            return
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func qrCodeText(for item: ClipboardHistoryItem) -> String? {
        guard !isLocked, !isVaultTransitioning else {
            return nil
        }

        if let url = urlRepresentation(for: item)?.absoluteString {
            return url
        }
        return plainTextRepresentation(for: item)
    }

    func toggleMonitoring() {
        isMonitoringEnabled.toggle()
    }

    func pauseCapture(for duration: TimeInterval) {
        guard duration > 0 else {
            return
        }

        privacyPauseUntil = Date().addingTimeInterval(duration)
        mutateSecurityCounters { $0.privacyPauses += 1 }
        configurePrivacyPauseTimer()
        syncCaptureServiceMonitoringState()
    }

    func resumeCapture() {
        privacyPauseUntil = nil
        privacyPauseTimer?.invalidate()
        privacyPauseTimer = nil
        syncCaptureServiceMonitoringState()
    }

    @discardableResult
    func lock() async -> Bool {
        securityEventGeneration += 1
        return await lock(expectedSettingsGeneration: settingsGeneration)
    }

    /// Seals session data synchronously without prompting for authentication.
    /// Pending persisted snippet edits also use the encrypted recovery checkpoint.
    @discardableResult
    func lockAutomatically() -> Bool {
        guard settings.lockProtectionEnabled else { return false }
        securityEventGeneration += 1
        activeAuthenticationContext?.invalidate()
        unlockedAuthenticationContext?.invalidate()
        unlockedAuthenticationContext = nil
        guard !isLocked else { return true }
        guard !isVaultTransitioning else {
            automaticLockPending = true
            return false
        }
        guard items.isEmpty || unlockedSnapshotKey != nil,
              let snapshot = prepareLockedSnapshot(availableKeyOnly: true) else {
            reportLockFailure("Automatic locking could not protect the session. Lock CoPaRe manually to retry.")
            return false
        }
        guard checkpointPendingSnippetChanges() else { return false }
        persistTask?.cancel()
        persistTask = nil
        _ = nextVaultOperationGeneration()
        lockedSnapshotEnvelope = snapshot.envelope
        items = []
        searchText = ""
        unlockedSnapshotKey = nil
        unlockedAuthenticationContext?.invalidate()
        unlockedAuthenticationContext = nil
        rotateSessionKey()
        isLocked = true
        syncCaptureServiceMonitoringState()
        return true
    }

    func dismissLockFailure() {
        lockFailureMessage = nil
    }

    @discardableResult
    private func lock(expectedSettingsGeneration: Int) async -> Bool {
        guard settings.lockProtectionEnabled, !isLocked else {
            return isLocked
        }
        guard !isVaultTransitioning,
              expectedSettingsGeneration == settingsGeneration
        else {
            return false
        }
        guard checkpointPendingSnippetChanges() else { return false }

        lockFailureMessage = nil
        isVaultTransitioning = true
        persistTask?.cancel()
        persistTask = nil
        _ = nextVaultOperationGeneration()
        syncCaptureServiceMonitoringState()

        defer {
            isVaultTransitioning = false
            if !isLocked {
                refreshCapturedItemExpiryAndPrune()
            }
            syncCaptureServiceMonitoringState()
        }

        guard var recordsToPersist = snippetPersistenceRecords(from: items) else {
            reportLockFailure("Some history could not be protected. CoPaRe stayed unlocked.")
            return false
        }
        let deletionIDsToPersist = pendingSnippetDeletionIDs
        recordsToPersist.removeAll { deletionIDsToPersist.contains($0.id) }

        guard let preparedSnapshot = prepareLockedSnapshot() else {
            recordsToPersist.removeAll(keepingCapacity: false)
            reportLockFailure("Authentication was canceled or the lock key was unavailable. CoPaRe stayed unlocked.")
            return false
        }

        var keepSavedSnippetsUnloaded = false
        if settings.persistHistory {
            let hasStoredSnippets = await snippetStore.hasSavedSnippets()
            if hasStoredSnippets {
                guard let storedRecords = await snippetStore.loadSnippetRecords(authenticationContext: unlockedAuthenticationContext) else {
                    recordsToPersist.removeAll(keepingCapacity: false)
                    reportLockFailure("Saved snippets could not be opened. CoPaRe stayed unlocked.")
                    return false
                }
                let mergedRecords = mergedSnippetRecordsForPersistence(
                    currentRecords: recordsToPersist,
                    storedRecords: storedRecords,
                    excluding: deletionIDsToPersist
                )
                keepSavedSnippetsUnloaded = mergedRecords.count > recordsToPersist.count
                recordsToPersist = mergedRecords
            }
        }

        guard !Task.isCancelled,
              lockTransitionIsCurrent(expectedSettingsGeneration: expectedSettingsGeneration)
        else {
            await restoreRegularSnippetPersistenceAfterAbortedLock(recordsToPersist)
            recordsToPersist.removeAll(keepingCapacity: false)
            reportLockFailure("Locking was canceled before it completed.")
            return false
        }

        if settings.persistHistory {
            let saveGeneration = nextVaultOperationGeneration()
            let saved = await snippetStore.saveSnippets(
                recordsToPersist,
                requireUserPresence: true,
                generation: saveGeneration,
                authenticationContext: unlockedAuthenticationContext
            )
            guard saved else {
                recordsToPersist.removeAll(keepingCapacity: false)
                reportLockFailure("Saved snippets could not be protected. CoPaRe stayed unlocked.")
                return false
            }
            pendingSnippetDeletionIDs.subtract(deletionIDsToPersist)

            guard !Task.isCancelled,
                  lockTransitionIsCurrent(expectedSettingsGeneration: expectedSettingsGeneration)
            else {
                await restoreRegularSnippetPersistenceAfterAbortedLock(recordsToPersist)
                recordsToPersist.removeAll(keepingCapacity: false)
                reportLockFailure("Locking was canceled before it completed.")
                return false
            }

            hasSavedSnippetsAvailable = !recordsToPersist.isEmpty
            savedSnippetsLoaded = !keepSavedSnippetsUnloaded
            clearSnippetCheckpointAfterPersistence()
        }

        // Do not retain plaintext persistence records across the lock commit.
        recordsToPersist.removeAll(keepingCapacity: false)
        lockedSnapshotEnvelope = preparedSnapshot.envelope
        items = []
        searchText = ""
        unlockedSnapshotKey = nil
        unlockedAuthenticationContext?.invalidate()
        unlockedAuthenticationContext = nil
        rotateSessionKey()
        isLocked = true
        syncCaptureServiceMonitoringState()
        return true
    }

    func unlock() async {
        guard settings.lockProtectionEnabled, isLocked, !isVaultTransitioning, !isUnlocking else {
            return
        }

        let context = LAContext()
        activeAuthenticationContext = context
        isUnlocking = true
        let securityGeneration = securityEventGeneration
        defer {
            isUnlocking = false
            activeAuthenticationContext = nil
            if isLocked { context.invalidate() }
        }
        do {
            let success = try await authenticateForUnlock(context)

            if success, !Task.isCancelled, securityGeneration == securityEventGeneration,
               !isVaultTransitioning, settings.lockProtectionEnabled,
               !startsAutomatically || !settings.lockOnSystemEvents || NSApp.isActive {
                guard restoreAfterUnlock(using: context) else {
                    return
                }

                unlockedAuthenticationContext = context
                context.interactionNotAllowed = true
                isLocked = false
                autoLockService?.recordActivity()
                syncCaptureServiceMonitoringState()
                mutateSecurityCounters { $0.unlockEvents += 1 }
                if items.contains(where: \.isSnippet) || !pendingSnippetDeletionIDs.isEmpty {
                    scheduleSnippetPersist(immediately: true)
                }
            }
        } catch {
            return
        }
    }

    func togglePin(itemID: UUID) {
        guard !isLocked, !isVaultTransitioning else {
            return
        }

        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        let isSnippetItem = items[index].isSnippet

        if items[index].isPinned {
            items[index].pinnedAt = nil
            items[index].expiresAt = expirationDate(
                for: items[index].origin,
                from: Date(),
                sourceBundleIdentifier: items[index].sourceBundleIdentifier,
                preview: items[index].preview
            )
        } else {
            items[index].pinnedAt = Date()
            items[index].expiresAt = nil
        }

        sortAndTrim()
        if isSnippetItem {
            scheduleSnippetPersist(immediately: true)
        }
    }

    func remove(itemID: UUID, immediatelyPersist: Bool = true) {
        guard !isLocked, !isVaultTransitioning else {
            return
        }

        let originalCount = items.count
        let removedSnippet = items.first(where: { $0.id == itemID })?.isSnippet ?? false
        if removedSnippet {
            pendingSnippetDeletionIDs.insert(itemID)
        }
        items.removeAll(where: { $0.id == itemID })
        guard items.count != originalCount else {
            return
        }

        sortAndTrim()

        guard removedSnippet else {
            return
        }

        if immediatelyPersist {
            scheduleSnippetPersist(immediately: true)
        } else {
            scheduleSnippetPersist(immediately: false)
        }
    }

    func clearHistory(keepPinned: Bool) {
        guard !isLocked, !isVaultTransitioning else {
            return
        }

        if keepPinned {
            items = items.filter { $0.isPinned || $0.isSnippet }
            sortAndTrim()
            if items.contains(where: \.isSnippet) {
                scheduleSnippetPersist(immediately: true)
            }
        } else {
            secureWipeEntireHistory()
        }
    }

    func secureWipeEntireHistory() {
        guard !isVaultTransitioning else {
            return
        }

        isVaultTransitioning = true
        securityEventGeneration += 1
        activeAuthenticationContext?.invalidate()
        unlockedAuthenticationContext?.invalidate()
        unlockedAuthenticationContext = nil
        unlockedSnapshotKey = nil
        isLocked = settings.lockProtectionEnabled
        items = []
        persistTask?.cancel()
        persistTask = nil
        let generation = nextVaultOperationGeneration()
        lockedSnapshotEnvelope = nil
        rotateSessionKey()
        captureService.resetPasteboardBaseline()
        mutateSecurityCounters { $0.secureWipes += 1 }
        secureWipeMessage = nil
        secureWipeFailed = false
        syncCaptureServiceMonitoringState()

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.isVaultTransitioning = false
                if !self.isLocked {
                    self.refreshCapturedItemExpiryAndPrune()
                }
                self.syncCaptureServiceMonitoringState()
            }

            var checkpointCleared = true
            do {
                try checkpointStore.clear()
            } catch {
                checkpointCleared = false
            }
            // Attempt crypto-shredding even if removing the ciphertext failed.
            do { try lockSnapshotKeyDeleter() } catch { checkpointCleared = false }
            let vaultCleared = await snippetStore.clearSnippetsFile(generation: generation)
            let wipeSucceeded = checkpointCleared && vaultCleared
            guard generation == vaultOperationGeneration else {
                return
            }
            if wipeSucceeded {
                secureWipeMessage = "Secure wipe completed. History and vault keys were removed."
                secureWipeFailed = false
                hasSavedSnippetsAvailable = false
                savedSnippetsLoaded = true
                pendingSnippetDeletionIDs.removeAll()
            } else {
                let stillHasSavedSnippets = await snippetStore.hasSavedSnippets()
                guard generation == vaultOperationGeneration else {
                    return
                }
                hasSavedSnippetsAvailable = stillHasSavedSnippets || checkpointStore.exists
                savedSnippetsLoaded = !stillHasSavedSnippets
                secureWipeMessage = "Secure wipe could not remove all saved snippet data or vault keys (authentication may have been canceled). Run wipe again and approve the macOS prompt."
                secureWipeFailed = true
            }
        }
    }

    @discardableResult
    func addSnippet(title: String, body: String, tags: [String] = []) -> UUID? {
        guard !isLocked, !isVaultTransitioning else {
            return nil
        }

        let now = Date()
        guard let item = makeSnippet(title: title, body: body, tags: tags, createdAt: now, updatedAt: now) else {
            return nil
        }

        items.insert(item, at: 0)
        sortAndTrim()
        scheduleSnippetPersist(immediately: true)
        return item.id
    }

    @discardableResult
    func updateSnippet(itemID: UUID, title: String, body: String, tags: [String]) -> Bool {
        guard let original = item(with: itemID), original.isSnippet,
              let index = items.firstIndex(where: { $0.id == itemID }),
              var replacement = makeSnippet(id: itemID, title: title, body: body, tags: tags,
                                            createdAt: original.createdAt, updatedAt: Date()) else { return false }
        replacement.pinnedAt = original.pinnedAt
        items[index] = replacement
        sortAndTrim()
        scheduleSnippetPersist(immediately: true)
        return true
    }

    func exportSnippets(to url: URL) throws {
        // No suspension between plaintext access and the atomic commit.
        try SnippetTransfer.write(makeSnippetTransferDocument(), to: url)
    }

    func exportEncryptedSnippets(to url: URL, password: String) async throws {
        try validateTransferAvailability()
        let generation = vaultOperationGeneration
        let revision = contentRevision
        // Derive only the password key in the worker. Snippets stay encrypted
        // throughout this suspension, including if lock/wipe occurs meanwhile.
        let worker = Task.detached(priority: .userInitiated) {
            try EncryptedSnippetBackup.prepareEncryption(password: password)
        }
        let context = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
        try validateTransferState(generation: generation, revision: revision)
        let data = try EncryptedSnippetBackup.encrypt(document: makeSnippetTransferDocument(), using: context)
        try EncryptedSnippetBackup.write(data: data, to: url)
    }

    @discardableResult
    func importEncryptedSnippets(from url: URL, password: String) async throws -> Int {
        try validateTransferAvailability()
        let generation = vaultOperationGeneration
        let revision = contentRevision
        let worker = Task.detached(priority: .userInitiated) {
            let data = try EncryptedSnippetBackup.read(from: url)
            return try EncryptedSnippetBackup.prepareDecryption(data: data, password: password)
        }
        let context = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
        try validateTransferState(generation: generation, revision: revision)
        return importSnippetDocument(try EncryptedSnippetBackup.decrypt(using: context))
    }

    private func validateTransferAvailability() throws {
        try Task.checkCancellation()
        guard !isLocked, !isVaultTransitioning else {
            throw SnippetTransferError.unavailable
        }
    }

    private func validateTransferState(generation: Int, revision: Int) throws {
        try validateTransferAvailability()
        guard generation == vaultOperationGeneration, revision == contentRevision else {
            throw SnippetTransferError.stateChanged
        }
    }

    private func makeSnippetTransferDocument() throws -> SnippetTransferDocument {
        try validateTransferAvailability()

        let exportItems = try items
            .filter(\.isSnippet)
            .map { item -> SnippetTransferItem in
                guard let plainText = item.decryptedPayload()?.plainText else {
                    throw SnippetTransferError.unreadableSnippet
                }

                return SnippetTransferItem(
                    title: item.preview,
                    body: plainText,
                    tags: item.tags,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt,
                    pinned: item.isPinned
                )
            }

        guard !exportItems.isEmpty else {
            throw SnippetTransferError.emptyExport
        }

        return SnippetTransferDocument(
            version: 1,
            exportedAt: Date(),
            snippets: exportItems
        )

    }

    @discardableResult
    func importSnippets(from url: URL) async throws -> Int {
        try validateTransferAvailability()
        let generation = vaultOperationGeneration
        let revision = contentRevision
        let worker = Task.detached(priority: .userInitiated) {
            try SnippetTransfer.readData(from: url, maximumBytes: SnippetTransfer.maximumFileBytes)
        }
        let data = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
        try validateTransferState(generation: generation, revision: revision)
        return importSnippetDocument(try SnippetTransfer.decode(data))
    }

    private func importSnippetDocument(_ document: SnippetTransferDocument) -> Int {
        let existingDigests = Set(items.filter(\.isSnippet).map(\.digest))
        var imported = [ClipboardHistoryItem]()
        var importedDigests = Set<String>()

        for snippet in document.snippets {
            guard let item = makeSnippet(
                title: snippet.title,
                body: snippet.body,
                tags: snippet.tags,
                createdAt: snippet.createdAt,
                updatedAt: snippet.updatedAt
            ) else {
                continue
            }

            guard !existingDigests.contains(item.digest),
                  importedDigests.insert(item.digest).inserted
            else {
                continue
            }

            var mutableItem = item
            if snippet.pinned {
                mutableItem.pinnedAt = snippet.updatedAt
            }
            imported.append(mutableItem)
        }

        guard !imported.isEmpty else {
            return 0
        }

        items.insert(contentsOf: imported, at: 0)
        sortAndTrim()
        scheduleSnippetPersist(immediately: true)
        return imported.count
    }

    private func makeSnippet(
        id: UUID = UUID(),
        title: String,
        body: String,
        tags: [String],
        createdAt: Date,
        updatedAt: Date
    ) -> ClipboardHistoryItem? {
        let normalizedBody = body
            .replacingOccurrences(of: "\u{0000}", with: "")

        guard !normalizedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .previewSnippet(maxLength: 80)
        let normalizedTags = ClipboardHistoryItem.normalizedTags(tags)

        let preview: String
        if normalizedTitle.isEmpty {
            if SensitiveContentDetector.shouldMaskPreview(text: normalizedBody) {
                preview = "Sensitive snippet hidden"
            } else {
                preview = normalizedBody.previewSnippet(maxLength: 80)
            }
        } else {
            preview = normalizedTitle
        }
        let payload = ClipboardItemPayload(
            plainText: normalizedBody,
            imagePNGData: nil,
            filePaths: nil
        )

        guard let encryptedPayload = try? EncryptedClipboardPayload.seal(payload) else {
            return nil
        }

        let searchTerms = ([preview] + normalizedTags.map { "#\($0)" })
            .joined(separator: " ")
            .condensingWhitespace()

        return ClipboardHistoryItem(
            id: id,
            type: .text,
            createdAt: createdAt,
            updatedAt: updatedAt,
            pinnedAt: nil,
            expiresAt: nil,
            preview: preview,
            searchIndex: String(searchTerms.prefix(160)),
            thumbnailPNGData: nil,
            encryptedPayload: encryptedPayload,
            digest: digest(for: "snippet:\(preview)\n\(normalizedBody)\n\(normalizedTags.joined(separator: ","))"),
            byteSize: Data(normalizedBody.utf8).count,
            origin: .snippet,
            captureCount: 1,
            sourceBundleIdentifier: nil,
            tags: normalizedTags
        )
    }

    func revealFiles(of item: ClipboardHistoryItem) {
        guard !isLocked, !isVaultTransitioning else {
            return
        }

        guard let paths = item.decryptedPayload()?.filePaths, !paths.isEmpty else {
            return
        }

        let urls = paths.map { URL(fileURLWithPath: $0) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func loadSavedSnippets() async {
        guard !isLocked, !isVaultTransitioning else {
            return
        }

        guard settings.persistHistory else {
            return
        }

        let generation = vaultOperationGeneration
        guard let stored = await snippetStore.loadSnippets(authenticationContext: unlockedAuthenticationContext) else {
            return
        }
        guard generation == vaultOperationGeneration,
              !isLocked,
              !isVaultTransitioning,
              settings.persistHistory
        else {
            return
        }
        let currentSnippets = items.filter(\.isSnippet)
        let currentSnippetIDs = Set(currentSnippets.map(\.id))
        let mergedSnippets = currentSnippets + stored.filter {
            !pendingSnippetDeletionIDs.contains($0.id) && !currentSnippetIDs.contains($0.id)
        }

        items = items.filter { !$0.isSnippet } + mergedSnippets
        sortAndTrim()
        hasSavedSnippetsAvailable = !mergedSnippets.isEmpty
        savedSnippetsLoaded = true
        if !pendingSnippetDeletionIDs.isEmpty {
            scheduleSnippetPersist(immediately: true)
        }
    }

    private func handleCapture(_ capture: CapturedClipboardItem) {
        guard !isLocked, !isVaultTransitioning else {
            return
        }

        let now = capture.capturedAt
        let expirationDate = expirationDate(
            for: .captured,
            from: now,
            sourceBundleIdentifier: capture.sourceBundleIdentifier,
            preview: capture.preview
        )

        if let existingIndex = items.firstIndex(where: { $0.digest == capture.digest && $0.type == capture.type }) {
            items[existingIndex].updatedAt = now
            items[existingIndex].expiresAt = items[existingIndex].isPinned
                ? nil
                : expirationDate
            items[existingIndex].captureCount += 1
            items[existingIndex].sourceBundleIdentifier = capture.sourceBundleIdentifier
            items[existingIndex].searchIndex = capture.searchIndex
            sortAndTrim()
            return
        }

        let item = ClipboardHistoryItem(
            type: capture.type,
            createdAt: now,
            updatedAt: now,
            pinnedAt: nil,
            expiresAt: expirationDate,
            preview: capture.preview,
            searchIndex: capture.searchIndex,
            thumbnailPNGData: capture.thumbnailPNGData,
            encryptedPayload: capture.encryptedPayload,
            digest: capture.digest,
            byteSize: capture.byteSize,
            origin: .captured,
            captureCount: 1,
            sourceBundleIdentifier: capture.sourceBundleIdentifier
        )

        items.insert(item, at: 0)
        sortAndTrim()
    }

    private func applySettingsChanges() {
        settingsGeneration += 1
        let expectedSettingsGeneration = settingsGeneration
        let lockProtectionChanged = settings.lockProtectionEnabled != appliedLockProtectionEnabled
        appliedLockProtectionEnabled = settings.lockProtectionEnabled
        let persistenceChanged = settings.persistHistory != appliedPersistenceEnabled
        appliedPersistenceEnabled = settings.persistHistory

        if startsAutomatically {
            captureService.applySettings()
            configureExpirationTimer()
        }

        if !isVaultTransitioning {
            for index in items.indices where !items[index].isSnippet && !items[index].isPinned {
                items[index].expiresAt = expirationDate(
                    for: items[index].origin,
                    from: items[index].updatedAt,
                    sourceBundleIdentifier: items[index].sourceBundleIdentifier,
                    preview: items[index].preview
                )
            }
        }

        if !settings.persistHistory {
            if persistenceChanged || disabledPersistenceCleanupFailed {
                scheduleDisabledPersistenceCleanup()
            }
        } else {
            disabledPersistenceCleanupFailed = false
        }

        if settings.lockProtectionEnabled {
            if lockProtectionChanged, !isLocked {
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    let locked = await self.lock(expectedSettingsGeneration: expectedSettingsGeneration)
                    guard !locked,
                          !self.isLocked,
                          self.settings.lockProtectionEnabled
                    else {
                        return
                    }

                    if self.settings.securityPreset == .strict {
                        self.settings.applySecurityPreset(.balanced)
                    } else {
                        self.settings.lockProtectionEnabled = false
                    }
                }
                return
            } else {
                syncCaptureServiceMonitoringState()
            }
        } else {
            guard !isLocked else {
                // Disabling protection must never expose or strand a locked
                // snapshot without authenticating and restoring it first.
                appliedLockProtectionEnabled = true
                settings.lockProtectionEnabled = true
                return
            }

            if lockProtectionChanged, settings.persistHistory {
                if !isVaultTransitioning {
                    Task { @MainActor [weak self] in
                        guard let self else {
                            return
                        }

                        let migrated = await self.migrateSavedSnippetsToRegularKey(
                            expectedSettingsGeneration: expectedSettingsGeneration
                        )
                        guard !migrated,
                              !self.isLocked,
                              !self.settings.lockProtectionEnabled,
                              self.settings.persistHistory
                        else {
                            return
                        }

                        // Keep protection enabled if the protected vault could
                        // not be opened or re-encrypted with the regular key.
                        self.appliedLockProtectionEnabled = true
                        self.settings.lockProtectionEnabled = true
                    }
                }
                return
            }
            syncCaptureServiceMonitoringState()
        }

        guard !isVaultTransitioning else {
            return
        }

        _ = pruneExpiredItems()
        sortAndTrim()

        if settings.persistHistory {
            if items.contains(where: \.isSnippet) {
                scheduleSnippetPersist()
            } else {
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    let generation = self.vaultOperationGeneration
                    let hasSavedSnippets = await self.snippetStore.hasSavedSnippets()
                    guard generation == self.vaultOperationGeneration,
                          self.settings.persistHistory
                    else {
                        return
                    }
                    self.hasSavedSnippetsAvailable = hasSavedSnippets || self.checkpointStore.exists
                    self.savedSnippetsLoaded = !self.hasSavedSnippetsAvailable
                }
            }
        }
    }

    private func loadInitialState() async {
        let generation = vaultOperationGeneration
        if settings.persistHistory {
            let hasSavedSnippets = await snippetStore.hasSavedSnippets()
            guard generation == vaultOperationGeneration,
                  settings.persistHistory
            else {
                return
            }
            hasSavedSnippetsAvailable = hasSavedSnippets || checkpointStore.exists
            savedSnippetsLoaded = !hasSavedSnippetsAvailable
        } else {
            persistTask?.cancel()
            persistTask = nil
            let cleanupGeneration = nextVaultOperationGeneration()
            await performDisabledPersistenceCleanup(generation: cleanupGeneration)
        }
    }

    private func scheduleDisabledPersistenceCleanup() {
        guard !settings.persistHistory else {
            return
        }

        persistTask?.cancel()
        persistTask = nil
        disabledPersistenceCleanupFailed = false
        let cleanupGeneration = nextVaultOperationGeneration()
        Task { @MainActor [weak self] in
            await self?.performDisabledPersistenceCleanup(generation: cleanupGeneration)
        }
    }

    private func performDisabledPersistenceCleanup(generation: Int) async {
        var checkpointCleared = true
        do { try checkpointStore.clear() } catch { checkpointCleared = false }
        let vaultCleared = await snippetStore.clearSnippetsFile(generation: generation)
        let succeeded = checkpointCleared && vaultCleared
        guard generation == vaultOperationGeneration, !settings.persistHistory else {
            return
        }

        if succeeded {
            hasSavedSnippetsAvailable = false
            savedSnippetsLoaded = true
            pendingSnippetDeletionIDs.removeAll()
            disabledPersistenceCleanupFailed = false
            if lockFailureMessage?.hasPrefix("Saved snippet cleanup") == true {
                lockFailureMessage = nil
            }
            return
        }

        let stillHasSavedSnippets = await snippetStore.hasSavedSnippets()
        guard generation == vaultOperationGeneration, !settings.persistHistory else {
            return
        }

        hasSavedSnippetsAvailable = stillHasSavedSnippets || checkpointStore.exists
        savedSnippetsLoaded = !stillHasSavedSnippets
        disabledPersistenceCleanupFailed = true
        reportLockFailure(
            "Saved snippet cleanup was incomplete. Some vault data or keys may remain; toggle saving on and off again or relaunch, then approve the macOS authentication prompt."
        )
    }

    private func configureExpirationTimer() {
        expirationTimer?.invalidate()
        expirationTimer = nil

        var candidateIntervals = [
            settings.itemTTL.interval,
            settings.maskedContentTTL.interval,
        ].compactMap { $0 }
        candidateIntervals.append(contentsOf: settings.appCaptureRules.values.compactMap { $0.ttl?.interval })

        guard let ttl = candidateIntervals.min(), ttl > 0 else {
            return
        }

        let interval = max(5.0, min(60.0, ttl / 2))
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleExpirationSweep()
            }
        }
        timer.tolerance = min(5.0, interval * 0.25)
        RunLoop.main.add(timer, forMode: .common)
        expirationTimer = timer
    }

    private func configurePrivacyPauseTimer() {
        privacyPauseTimer?.invalidate()
        privacyPauseTimer = nil

        guard let privacyPauseUntil else {
            return
        }

        let remaining = max(0.25, privacyPauseUntil.timeIntervalSinceNow)
        let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resumeCapture()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        privacyPauseTimer = timer
    }

    private func handleExpirationSweep() {
        guard !isLocked, !isVaultTransitioning else {
            return
        }

        guard pruneExpiredItems() else {
            return
        }

        sortAndTrim()
    }

    private func refreshCapturedItemExpiryAndPrune() {
        for index in items.indices where !items[index].isSnippet && !items[index].isPinned {
            items[index].expiresAt = expirationDate(
                for: items[index].origin,
                from: items[index].updatedAt,
                sourceBundleIdentifier: items[index].sourceBundleIdentifier,
                preview: items[index].preview
            )
        }
        _ = pruneExpiredItems()
        sortAndTrim()
    }

    @discardableResult
    private func pruneExpiredItems(now: Date = Date()) -> Bool {
        let originalCount = items.count
        items.removeAll { item in
            guard !item.isPinned, !item.isSnippet, let expiresAt = item.expiresAt else {
                return false
            }
            return expiresAt <= now
        }

        let removed = originalCount - items.count
        if removed > 0 {
            mutateSecurityCounters { $0.expiredEntriesRemoved += removed }
            return true
        }
        return false
    }

    private func sortAndTrim() {
        let snippets = items
            .filter(\.isSnippet)
            .sorted { $0.updatedAt > $1.updatedAt }

        let pinned = items
            .filter { $0.isPinned && !$0.isSnippet }
            .sorted { lhs, rhs in
                (lhs.pinnedAt ?? lhs.updatedAt) > (rhs.pinnedAt ?? rhs.updatedAt)
            }

        let regularCandidates = items
            .filter { !$0.isPinned && !$0.isSnippet }
            .sorted { $0.updatedAt > $1.updatedAt }

        var perAppCounts: [String: Int] = [:]
        let perAppLimit = max(1, settings.perAppHistoryLimit)
        let regular = regularCandidates.filter { item in
            let key = item.sourceBundleIdentifier ?? "__unknown__"
            let count = perAppCounts[key, default: 0]
            guard count < perAppLimit else {
                return false
            }
            perAppCounts[key] = count + 1
            return true
        }

        items = snippets + pinned + Array(regular.prefix(settings.historyLimit))
    }

    private func expirationDate(
        for origin: ClipboardItemOrigin,
        from date: Date,
        sourceBundleIdentifier: String?,
        preview: String
    ) -> Date? {
        guard origin == .captured else {
            return nil
        }

        let baseTTL = settings.appCaptureRule(for: sourceBundleIdentifier)?.ttl ?? settings.itemTTL
        var interval = baseTTL.interval
        if (preview.localizedCaseInsensitiveContains("sensitive") || SensitiveContentDetector.shouldMaskPreview(text: preview)),
           let sensitiveInterval = settings.maskedContentTTL.interval
        {
            interval = min(interval ?? sensitiveInterval, sensitiveInterval)
        }

        guard let interval else {
            return nil
        }

        return date.addingTimeInterval(interval)
    }

    private func scheduleSnippetPersist(immediately: Bool = false) {
        persistTask?.cancel()
        persistTask = nil

        guard settings.persistHistory else {
            return
        }
        guard !isLocked, !isVaultTransitioning else {
            return
        }

        guard checkpointPendingSnippetChanges() else { return }

        let generation = nextVaultOperationGeneration()
        let requireUserPresence = settings.lockProtectionEnabled
        persistTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if !immediately {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            guard !Task.isCancelled else {
                return
            }

            guard generation == self.vaultOperationGeneration,
                  self.settings.persistHistory,
                  !self.isLocked,
                  !self.isVaultTransitioning,
                  let currentRecords = self.snippetPersistenceRecords(from: self.items)
            else {
                return
            }

            let deletionIDsToPersist = self.pendingSnippetDeletionIDs
            var recordsToPersist = currentRecords.filter { !deletionIDsToPersist.contains($0.id) }
            var keepSavedSnippetsUnloaded = false

            if self.hasSavedSnippetsAvailable, !self.savedSnippetsLoaded {
                guard let storedRecords = await self.snippetStore.loadSnippetRecords(authenticationContext: self.unlockedAuthenticationContext) else {
                    self.hasSavedSnippetsAvailable = true
                    self.savedSnippetsLoaded = false
                    return
                }
                guard !Task.isCancelled,
                      generation == self.vaultOperationGeneration,
                      self.settings.persistHistory,
                      !self.isLocked,
                      !self.isVaultTransitioning
                else {
                    return
                }

                let mergedRecords = self.mergedSnippetRecordsForPersistence(
                    currentRecords: recordsToPersist,
                    storedRecords: storedRecords,
                    excluding: deletionIDsToPersist
                )
                keepSavedSnippetsUnloaded = mergedRecords.count > recordsToPersist.count
                recordsToPersist = mergedRecords
            }

            let saved = await self.snippetStore.saveSnippets(
                recordsToPersist,
                requireUserPresence: requireUserPresence,
                generation: generation,
                authenticationContext: self.unlockedAuthenticationContext
            )
            guard saved else {
                if generation == self.vaultOperationGeneration,
                   self.settings.persistHistory,
                   !self.isLocked,
                   !self.isVaultTransitioning
                {
                    self.reportLockFailure(
                        "Saved snippet changes could not be written. They remain available in this session; make another snippet change to retry."
                    )
                }
                return
            }

            guard !Task.isCancelled,
                  generation == self.vaultOperationGeneration,
                  self.settings.persistHistory,
                  !self.isLocked,
                  !self.isVaultTransitioning
            else {
                return
            }

            self.hasSavedSnippetsAvailable = !recordsToPersist.isEmpty
            self.savedSnippetsLoaded = !keepSavedSnippetsUnloaded
            self.pendingSnippetDeletionIDs.subtract(deletionIDsToPersist)
            self.clearSnippetCheckpointAfterPersistence()
        }
    }

    /// Persist only manual snippet changes before an asynchronous save or lock.
    /// This journal survives quitting while locked and never contains captures.
    private func checkpointPendingSnippetChanges() -> Bool {
        guard settings.persistHistory, settings.lockProtectionEnabled || checkpointStore.exists else { return true }
        guard let key = unlockedSnapshotKey else {
            // Enabling protection uses the transactional manual-lock path first.
            if checkpointStore.exists {
                reportLockFailure("Unlock CoPaRe to recover pending snippet changes before saving more changes.")
                return false
            }
            return true
        }
        guard let records = snippetPersistenceRecords(from: items) else { return false }
        if records.isEmpty, pendingSnippetDeletionIDs.isEmpty, !checkpointStore.exists { return true }
        do {
            try checkpointStore.save(records: records, deletedIDs: pendingSnippetDeletionIDs, using: key)
            return true
        } catch {
            reportLockFailure("Pending snippet changes could not be saved safely. Keep CoPaRe open and retry. \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private func clearSnippetCheckpointAfterPersistence() -> Bool {
        do { try checkpointStore.clear(); return true }
        catch {
            reportLockFailure("Snippets were saved, but their recovery file could not be removed. \(error.localizedDescription)")
            return false
        }
    }

    private func migrateSavedSnippetsToRegularKey(
        expectedSettingsGeneration: Int
    ) async -> Bool {
        guard !isLocked,
              !isVaultTransitioning,
              !settings.lockProtectionEnabled,
              settings.persistHistory,
              expectedSettingsGeneration == settingsGeneration
        else {
            return false
        }
        guard checkpointPendingSnippetChanges() else { return false }

        isVaultTransitioning = true
        persistTask?.cancel()
        persistTask = nil
        _ = nextVaultOperationGeneration()
        syncCaptureServiceMonitoringState()

        defer {
            isVaultTransitioning = false
            if !isLocked {
                refreshCapturedItemExpiryAndPrune()
            }
            syncCaptureServiceMonitoringState()
        }

        guard var recordsToPersist = snippetPersistenceRecords(from: items) else {
            reportLockFailure("Saved snippets could not be re-encrypted. Protection remains enabled.")
            return false
        }
        let deletionIDsToPersist = pendingSnippetDeletionIDs
        recordsToPersist.removeAll { deletionIDsToPersist.contains($0.id) }

        var keepSavedSnippetsUnloaded = false
        let hasStoredSnippets = await snippetStore.hasSavedSnippets()
        if hasStoredSnippets {
            guard let storedRecords = await snippetStore.loadSnippetRecords(authenticationContext: unlockedAuthenticationContext) else {
                recordsToPersist.removeAll(keepingCapacity: false)
                reportLockFailure("Saved snippets could not be opened. Protection remains enabled.")
                return false
            }
            let mergedRecords = mergedSnippetRecordsForPersistence(
                currentRecords: recordsToPersist,
                storedRecords: storedRecords,
                excluding: deletionIDsToPersist
            )
            keepSavedSnippetsUnloaded = mergedRecords.count > recordsToPersist.count
            recordsToPersist = mergedRecords
        }

        guard !Task.isCancelled,
              expectedSettingsGeneration == settingsGeneration,
              !settings.lockProtectionEnabled,
              settings.persistHistory,
              !isLocked,
              isVaultTransitioning
        else {
            recordsToPersist.removeAll(keepingCapacity: false)
            reportLockFailure("The vault change was canceled because settings changed.")
            return false
        }

        let saveGeneration = nextVaultOperationGeneration()
        let saved = await snippetStore.saveSnippets(
            recordsToPersist,
            requireUserPresence: false,
            generation: saveGeneration,
            authenticationContext: unlockedAuthenticationContext
        )
        let hasRecords = !recordsToPersist.isEmpty
        recordsToPersist.removeAll(keepingCapacity: false)

        guard saved else {
            reportLockFailure("Saved snippets could not be re-encrypted. Protection remains enabled.")
            return false
        }
        pendingSnippetDeletionIDs.subtract(deletionIDsToPersist)

        // The migration is complete even if an unrelated setting changed
        // after the atomic store write, provided protection is still off.
        guard !settings.lockProtectionEnabled, settings.persistHistory, !isLocked else {
            return false
        }

        hasSavedSnippetsAvailable = hasRecords
        savedSnippetsLoaded = !keepSavedSnippetsUnloaded
        guard clearSnippetCheckpointAfterPersistence() else { return false }
        unlockedSnapshotKey = nil
        unlockedAuthenticationContext?.invalidate()
        unlockedAuthenticationContext = nil
        return true
    }

    @discardableResult
    private func restoreRegularSnippetPersistenceAfterAbortedLock(
        _ records: [SnippetPersistenceRecord]
    ) async -> Bool {
        guard !settings.lockProtectionEnabled, settings.persistHistory else {
            return true
        }

        let deletionIDsToPersist = pendingSnippetDeletionIDs
        let retainedRecords = records.filter { !deletionIDsToPersist.contains($0.id) }
        let saveGeneration = nextVaultOperationGeneration()
        let saved = await snippetStore.saveSnippets(
            retainedRecords,
            requireUserPresence: false,
            generation: saveGeneration,
            authenticationContext: unlockedAuthenticationContext
        )
        if saved {
            pendingSnippetDeletionIDs.subtract(deletionIDsToPersist)
            if !settings.lockProtectionEnabled, settings.persistHistory {
                hasSavedSnippetsAvailable = !retainedRecords.isEmpty
            }
            return true
        }

        // A protected store must not be presented as unprotected if the
        // compensating migration failed.
        if !settings.lockProtectionEnabled, settings.persistHistory {
            appliedLockProtectionEnabled = true
            settings.lockProtectionEnabled = true
        }
        return false
    }

    private func lockTransitionIsCurrent(expectedSettingsGeneration: Int) -> Bool {
        expectedSettingsGeneration == settingsGeneration
            && settings.lockProtectionEnabled
            && !isLocked
            && isVaultTransitioning
    }

    private func nextVaultOperationGeneration() -> Int {
        vaultOperationGeneration += 1
        return vaultOperationGeneration
    }

    private func reportLockFailure(_ message: String) {
        logger.error("\(message, privacy: .public)")
        lockFailureMessage = message
    }

    private func snippetPersistenceRecords(
        from sourceItems: [ClipboardHistoryItem]
    ) -> [SnippetPersistenceRecord]? {
        var records: [SnippetPersistenceRecord] = []
        for item in sourceItems where item.isSnippet {
            guard let body = item.decryptedPayload()?.plainText else {
                return nil
            }
            records.append(
                SnippetPersistenceRecord(
                    id: item.id,
                    preview: item.preview,
                    body: body,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt,
                    pinnedAt: item.pinnedAt,
                    tags: item.tags
                )
            )
        }
        return records
    }

    private func mergedSnippetRecordsForPersistence(
        currentRecords: [SnippetPersistenceRecord],
        storedRecords: [SnippetPersistenceRecord],
        excluding deletionIDs: Set<UUID>
    ) -> [SnippetPersistenceRecord] {
        let retainedCurrentRecords = currentRecords.filter { !deletionIDs.contains($0.id) }
        let currentIDs = Set(retainedCurrentRecords.map(\.id))
        let currentDigests = Set(retainedCurrentRecords.map(\.digest))
        let uniqueStoredRecords = storedRecords.filter { record in
            !deletionIDs.contains(record.id)
                && !currentIDs.contains(record.id)
                && !currentDigests.contains(record.digest)
        }

        return retainedCurrentRecords + uniqueStoredRecords
    }

    private func plainTextRepresentation(for item: ClipboardHistoryItem) -> String? {
        let payload = item.decryptedPayload()
        switch item.type {
        case .text, .url:
            return payload?.plainText
        case .file:
            guard let filePaths = payload?.filePaths, !filePaths.isEmpty else {
                return nil
            }
            return filePaths.joined(separator: "\n")
        case .image:
            return nil
        }
    }

    private func urlRepresentation(for item: ClipboardHistoryItem) -> URL? {
        guard item.type == .url,
              let rawText = item.decryptedPayload()?.plainText?.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }
        return URL(string: rawText)
    }

    private func markdownRepresentation(for item: ClipboardHistoryItem) -> String? {
        switch item.type {
        case .url:
            guard let url = urlRepresentation(for: item) else {
                return nil
            }
            let title = item.preview.isEmpty || item.preview.hasPrefix("Sensitive") ? url.absoluteString : item.preview
            return "[\(title)](\(url.absoluteString))"
        case .text:
            return item.decryptedPayload()?.plainText
        case .file:
            guard let filePaths = item.decryptedPayload()?.filePaths, !filePaths.isEmpty else {
                return nil
            }
            return filePaths.map { path in
                let url = URL(fileURLWithPath: path)
                return "- [\(url.lastPathComponent)](\(url.absoluteString))"
            }
            .joined(separator: "\n")
        case .image:
            return nil
        }
    }

    private func digest(for text: String) -> String {
        let data = Data(text.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func mutateSecurityCounters(_ update: (inout SecurityEventCounters) -> Void) {
        var counters = securityCounters
        update(&counters)
        securityCounters = counters
    }

    private func syncCaptureServiceMonitoringState() {
        if let privacyPauseUntil, privacyPauseUntil <= Date() {
            self.privacyPauseUntil = nil
            privacyPauseTimer?.invalidate()
            privacyPauseTimer = nil
        }

        captureService.isMonitoringEnabled = isMonitoringEnabled
            && !isLocked
            && !isVaultTransitioning
            && privacyPauseUntil == nil
    }

    private func prepareLockedSnapshot(availableKeyOnly: Bool = false) -> PreparedLockedSnapshot? {
        guard !items.isEmpty else {
            return .empty
        }

        var snapshotItems: [LockedClipboardSnapshotItem] = []
        snapshotItems.reserveCapacity(items.count)
        for item in items {
            let payload = item.decryptedPayload()
            guard item.encryptedPayload == nil || payload != nil else {
                logger.error("Unable to decrypt an item while preparing the lock snapshot")
                return nil
            }

            snapshotItems.append(
                LockedClipboardSnapshotItem(
                    id: item.id,
                    type: item.type,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt,
                    pinnedAt: item.pinnedAt,
                    expiresAt: item.expiresAt,
                    preview: item.preview,
                    searchIndex: item.searchIndex,
                    thumbnailPNGData: item.thumbnailPNGData,
                    payload: payload,
                    digest: item.digest,
                    byteSize: item.byteSize,
                    origin: item.origin,
                    captureCount: item.captureCount,
                    sourceBundleIdentifier: item.sourceBundleIdentifier,
                    tags: item.tags
                )
            )
        }

        let snapshot = LockedClipboardSnapshot(
            version: 1,
            lockedAt: Date(),
            items: snapshotItems
        )

        let encryptionKey: SymmetricKey
        do {
            if let unlockedSnapshotKey {
                encryptionKey = unlockedSnapshotKey
            } else if availableKeyOnly {
                return nil
            } else {
                encryptionKey = try lockSnapshotKeyLoader(nil)
            }
        } catch {
            logger.error("Unable to load lock snapshot key: \(String(describing: error), privacy: .public)")
            return nil
        }

        guard let envelope = try? sealLockedSnapshot(snapshot, using: encryptionKey) else {
            return nil
        }

        return .encrypted(envelope)
    }

    private func sealLockedSnapshot(
        _ snapshot: LockedClipboardSnapshot,
        using key: SymmetricKey
    ) throws -> LockedClipboardEnvelope {
        let data = try JSONEncoder().encode(snapshot)
        let sealed = try AES.GCM.seal(data, using: key)

        return LockedClipboardEnvelope(
            nonce: sealed.nonce.withUnsafeBytes { Data($0) },
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )
    }

    private func restoreAfterUnlock(using context: LAContext) -> Bool {
        let persistentKey: SymmetricKey

        do {
            persistentKey = try lockSnapshotKeyLoader(context)
        } catch {
            logger.error("Unable to access lock snapshot key after unlock: \(String(describing: error), privacy: .public)")
            return false
        }

        var restoredItems: [ClipboardHistoryItem]
        var recoveredDeletionIDs = pendingSnippetDeletionIDs
        var recoveredCheckpoint = false
        do {
            restoredItems = try lockedSnapshotEnvelope.map { try openLockedSnapshot($0, using: persistentKey) } ?? []
            if settings.persistHistory, let checkpoint = try checkpointStore.load(using: persistentKey) {
                recoveredDeletionIDs.formUnion(checkpoint.deletedIDs)
                let recoveredIDs = Set(checkpoint.records.map(\.id))
                restoredItems.removeAll { recoveredDeletionIDs.contains($0.id) || recoveredIDs.contains($0.id) }
                for record in checkpoint.records where !recoveredDeletionIDs.contains(record.id) {
                    guard var item = makeSnippet(id: record.id, title: record.preview, body: record.body,
                                                 tags: record.tags, createdAt: record.createdAt, updatedAt: record.updatedAt) else {
                        throw SnippetCheckpointError.invalidCheckpoint
                    }
                    item.pinnedAt = record.pinnedAt
                    restoredItems.append(item)
                }
                recoveredCheckpoint = true
            }
        } catch {
            reportLockFailure("The protected session could not be restored. \(error.localizedDescription)")
            return false
        }

        items = restoredItems
        pendingSnippetDeletionIDs = recoveredDeletionIDs
        if recoveredCheckpoint {
            hasSavedSnippetsAvailable = true
            // Merge with the existing vault before committing/removing recovery.
            savedSnippetsLoaded = false
        }
        refreshCapturedItemExpiryAndPrune()
        lockedSnapshotEnvelope = nil
        unlockedSnapshotKey = persistentKey
        return true
    }

    private func openLockedSnapshot(
        _ envelope: LockedClipboardEnvelope,
        using key: SymmetricKey
    ) throws -> [ClipboardHistoryItem] {
        let nonce = try AES.GCM.Nonce(data: envelope.nonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: envelope.ciphertext,
            tag: envelope.tag
        )
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        let snapshot = try JSONDecoder().decode(LockedClipboardSnapshot.self, from: decryptedData)
        guard snapshot.version == 1 else {
            throw CocoaError(.coderReadCorrupt)
        }

        return try snapshot.items.map { item in
            let runtimePayload: EncryptedClipboardPayload?
            if let payload = item.payload {
                runtimePayload = try EncryptedClipboardPayload.seal(payload)
            } else {
                runtimePayload = nil
            }

            return ClipboardHistoryItem(
                id: item.id,
                type: item.type,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                pinnedAt: item.pinnedAt,
                expiresAt: item.expiresAt,
                preview: item.preview,
                searchIndex: item.searchIndex,
                thumbnailPNGData: item.thumbnailPNGData,
                encryptedPayload: runtimePayload,
                digest: item.digest,
                byteSize: item.byteSize,
                origin: item.origin,
                captureCount: item.captureCount,
                sourceBundleIdentifier: item.sourceBundleIdentifier,
                tags: item.tags
            )
        }
    }
}
