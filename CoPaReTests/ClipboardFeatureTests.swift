import AppKit
import Foundation
import Testing
@testable import CoPaRe

@MainActor
struct ClipboardFeatureTests {
    @Test func editSnippetPreservesIdentityCreationAndPinAndRejectsStaleCopy() throws {
        let fixture = try IsolatedClipboardFixture()
        let id = try #require(fixture.manager.addSnippet(title: "Old", body: "original body", tags: ["old"]))
        fixture.manager.togglePin(itemID: id)
        let before = try #require(fixture.manager.item(with: id))
        #expect(fixture.manager.updateSnippet(itemID: id, title: "Updated", body: "  edited\nbody\n", tags: ["New", "#new"]))
        let after = try #require(fixture.manager.item(with: id))
        #expect(after.id == before.id)
        #expect(after.createdAt == before.createdAt)
        #expect(after.pinnedAt == before.pinnedAt)
        #expect(after.tags == ["new"])
        #expect(after.decryptedPayload()?.plainText == "  edited\nbody\n")
        #expect(!fixture.manager.copyToClipboard(before))
        #expect(fixture.manager.copyToClipboard(after))
        #expect(fixture.pasteboard.string(forType: .string) == "  edited\nbody\n")
        #expect(!fixture.manager.updateSnippet(itemID: id, title: "Bad", body: " \n", tags: []))
        #expect(fixture.manager.item(with: id)?.preview == "Updated")
    }

    @Test func promotingAndDuplicatingKeepTheOriginalAndRequireExplicitCreation() throws {
        let fixture = try IsolatedClipboardFixture()
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setString("https://example.org/help", forType: .string)
        fixture.captureService.pollPasteboard()
        let capture = try #require(fixture.manager.items.first)
        #expect(!fixture.manager.updateSnippet(itemID: capture.id, title: "URL", body: "changed", tags: []))
        let body = try #require(capture.decryptedPayload()?.plainText)
        let snippetID = try #require(fixture.manager.addSnippet(title: "Help", body: body, tags: ["docs"]))
        let duplicateID = try #require(fixture.manager.addSnippet(title: "Help copy", body: body, tags: ["docs"]))
        #expect(snippetID != duplicateID)
        #expect(fixture.manager.items.count == 3)
        #expect(fixture.manager.item(with: capture.id)?.origin == .captured)
    }

    @Test func clipboardExpiryClearsOnlyTheOwnedCopyAfterItsDeadline() throws {
        let fixture = try IsolatedClipboardFixture()
        fixture.settings.clipboardClearInterval = .thirtySeconds
        #expect(fixture.captureService.writeString("CoPaRe copy"))
        fixture.captureService.clearExpiredClipboard(now: Date().addingTimeInterval(10))
        #expect(fixture.pasteboard.string(forType: .string) == "CoPaRe copy")
        fixture.captureService.clearExpiredClipboard(now: Date().addingTimeInterval(31))
        #expect(fixture.pasteboard.string(forType: .string) == nil)
        fixture.captureService.pollPasteboard()
        #expect(fixture.manager.items.isEmpty)
    }

    @Test func clipboardExpiryPreservesNewerCopiesEvenWithIdenticalText() throws {
        let fixture = try IsolatedClipboardFixture()
        fixture.settings.clipboardClearInterval = .thirtySeconds
        #expect(fixture.captureService.writeString("same text"))
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setString("same text", forType: .string)
        fixture.captureService.clearExpiredClipboard(now: Date().addingTimeInterval(31))
        #expect(fixture.pasteboard.string(forType: .string) == "same text")
        #expect(fixture.captureService.writeString("another CoPaRe copy"))
        fixture.settings.clipboardClearInterval = .never
        fixture.captureService.clearExpiredClipboard(now: Date().addingTimeInterval(300))
        #expect(fixture.pasteboard.string(forType: .string) == "another CoPaRe copy")
    }

    @Test func automaticLockPreservesUnsavedChangesWithoutAccessingVaultKeys() async throws {
        let fixture = try IsolatedClipboardFixture(lockProtection: true)
        await fixture.manager.unlock()
        #expect(!fixture.manager.isLocked)
        let id = try #require(fixture.manager.addSnippet(title: "Unsaved", body: "session body"))
        fixture.keys.failLoading(true)
        #expect(fixture.manager.lockAutomatically())
        #expect(fixture.manager.isLocked)
        #expect(fixture.manager.items.isEmpty)
        #expect(fixture.keys.loadCount == 0)
        #expect(fixture.manager.addSnippet(title: "Blocked", body: "blocked") == nil)
        await fixture.manager.unlock()
        #expect(!fixture.manager.isLocked)
        #expect(fixture.manager.item(with: id)?.decryptedPayload()?.plainText == "session body")
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    @Test func systemEventDuringAuthenticationPreventsLateUnlock() async throws {
        var continuation: CheckedContinuation<Bool, Never>?
        let fixture = try IsolatedClipboardFixture(lockProtection: true, authenticateForUnlock: { _ in
            await withCheckedContinuation { continuation = $0 }
        })
        let unlock = Task { await fixture.manager.unlock() }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        let completion = try #require(continuation)
        #expect(fixture.manager.isUnlocking)
        #expect(fixture.manager.lockAutomatically())
        completion.resume(returning: true)
        await unlock.value
        #expect(fixture.manager.isLocked)
        #expect(!fixture.manager.isUnlocking)
    }

    @Test func pendingSnippetEditsSurviveRestartWhileAutomaticallyLocked() async throws {
        let fixture = try IsolatedClipboardFixture(persistHistory: true, lockProtection: true)
        await fixture.manager.unlock()
        let id = try #require(fixture.manager.addSnippet(title: "Recover me", body: "unsaved edit", tags: ["work"]))
        fixture.manager.togglePin(itemID: id)
        // Do not yield to the queued vault writer: simulate switching away and
        // quitting immediately after Save.
        #expect(fixture.manager.lockAutomatically())
        #expect(fixture.checkpointStore.exists)
        let recoveredStore = SnippetStore(fileURL: fixture.fileURL, keyOperations: fixture.keys.operations)
        let restored = ClipboardManager(
            settings: fixture.settings, snippetStore: recoveredStore, checkpointStore: fixture.checkpointStore,
            captureService: fixture.captureService, startsAutomatically: false,
            lockSnapshotKeyLoader: { _ in fixture.snapshotKey }, lockSnapshotKeyDeleter: {},
            authenticateForUnlock: { _ in true }, rotateSessionKey: {}
        )
        #expect(restored.items.isEmpty)
        await restored.unlock()
        let item = try #require(restored.item(with: id))
        #expect(item.preview == "Recover me")
        #expect(item.tags == ["work"])
        #expect(item.isPinned)
        #expect(item.decryptedPayload()?.plainText == "unsaved edit")
        for _ in 0..<100 where fixture.checkpointStore.exists { await Task.yield() }
        #expect(!fixture.checkpointStore.exists)
        #expect(await recoveredStore.loadSnippetRecords()?.first?.id == id)
    }

    @Test func wipeRemovesPendingRecoveryAndInvokesSnapshotKeyDeletion() async throws {
        var deletions = 0
        let fixture = try IsolatedClipboardFixture(persistHistory: true, lockProtection: true, snapshotKeyDeleter: { deletions += 1 })
        await fixture.manager.unlock()
        fixture.manager.addSnippet(title: "Remove", body: "remove on wipe")
        #expect(fixture.manager.lockAutomatically())
        #expect(fixture.checkpointStore.exists)
        fixture.manager.secureWipeEntireHistory()
        for _ in 0..<100 where fixture.manager.isVaultTransitioning { await Task.yield() }
        #expect(!fixture.manager.isVaultTransitioning)
        #expect(!fixture.manager.secureWipeFailed)
        #expect(!fixture.checkpointStore.exists)
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))
        #expect(fixture.manager.isLocked)
        #expect(deletions == 1)
    }

    @Test func inactivityUsesAppActivityAndHonorsDisabledProtection() throws {
        let fixture = try IsolatedClipboardFixture(lockProtection: true)
        fixture.settings.autoLockInterval = .oneMinute
        var now = Date()
        var reasons: [AutoLockService.Reason] = []
        let service = AutoLockService(settings: fixture.settings, now: { now }) { reasons.append($0) }
        now.addTimeInterval(45)
        service.recordActivity()
        now.addTimeInterval(45)
        service.checkInactivity()
        #expect(reasons.isEmpty)
        now.addTimeInterval(16)
        service.checkInactivity()
        #expect(reasons == [.inactivity])
        fixture.settings.lockOnSystemEvents = false
        service.systemBecameUnavailable()
        #expect(reasons.count == 1)
        fixture.settings.autoLockInterval = .never
        now.addTimeInterval(900)
        service.checkInactivity()
        #expect(reasons.count == 1)
    }
}
