import AppKit
import SwiftUI
import Testing
@testable import CoPaRe

@MainActor
struct MenuBarLayoutTests {
    @Test func nativeMenuKeepsItsWidthAndSingleRowHeightAsContentChanges() async throws {
        let fixture = try IsolatedClipboardFixture(lockProtection: true)
        let controller = MenuBarController(content:
            MenuBarContentView()
                .defaultAppStorage(fixture.defaults)
                .environmentObject(fixture.manager)
                .environmentObject(AppUpdateChecker())
                .environmentObject(WindowCoordinator())
        )
        let menu = controller.menu

        // Measure the real hosting menu, including native margins and arrows.
        try await refresh(menu)
        #expect(menu.size.width == 400)
        #expect(menu.item(withTitle: "CoPaRe is locked") != nil)
        await fixture.manager.unlock()
        try await refresh(menu)
        #expect(menu.size.width == 400)
        #expect(menu.item(withTitle: "No clipboard history yet") != nil)

        let body = "Full original text\n" + String(repeating: "Keep every character. ", count: 100)
        let id = try #require(fixture.manager.addSnippet(title: "Short title", body: body))
        try await refresh(menu)
        #expect(menu.size.width == 400)
        let singleRowHeight = menu.size.height

        for title in [
            String(repeating: "A long clipboard preview ", count: 20),
            "https://example.org/" + String(repeating: "long-path-", count: 50),
            String(repeating: "中文👨‍👩‍👧‍👦\n\t", count: 40)
        ] {
            #expect(fixture.manager.updateSnippet(itemID: id, title: title, body: body, tags: []))
            try await refresh(menu)
            let entry = try #require(menu.items.first { $0.submenu?.item(withTitle: "Copy") != nil })
            #expect(menu.size.width == 400)
            #expect(menu.size.height == singleRowHeight)
            #expect(entry.title.hasSuffix("…"))
            #expect(!entry.title.contains(where: { $0.isNewline || $0 == "\t" }))
        }

        // Exercise the hosted menu action using only the fixture's private pasteboard.
        let submenu = try #require(menu.items.first { $0.submenu?.item(withTitle: "Copy") != nil }?.submenu)
        submenu.performActionForItem(at: submenu.indexOfItem(withTitle: "Copy"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.pasteboard.string(forType: .string) == body)

        let snippet = try #require(fixture.manager.item(with: id))
        fixture.manager.remove(itemID: id)
        fixture.captureService.onCapture?(CapturedClipboardItem(
            type: .text,
            preview: String(repeating: "Captured preview\n\t", count: 30),
            searchIndex: nil,
            thumbnailPNGData: nil,
            encryptedPayload: snippet.encryptedPayload,
            digest: "menu-layout-capture",
            byteSize: body.utf8.count,
            sourceBundleIdentifier: "io.copare." + String(repeating: "Very-Long-App-", count: 20)
        ))
        try await refresh(menu)
        let capture = try #require(fixture.manager.menuItems.first)
        #expect(!capture.isSnippet)
        #expect(try #require(fixture.manager.sourceApplicationName(for: capture)).count > 80)
        #expect(menu.size.width == 400)
        #expect(menu.size.height == singleRowHeight)
        let captureEntry = try #require(menu.items.first { $0.submenu?.item(withTitle: "Copy") != nil })
        #expect(captureEntry.title.hasSuffix("…"))
        #expect(!captureEntry.title.contains(where: { $0.isNewline || $0 == "\t" }))
        withExtendedLifetime(controller) {}
    }

    private func refresh(_ menu: NSMenu) async throws {
        menu.update()
        try await Task.sleep(for: .milliseconds(100))
        menu.update()
        for item in menu.items { item.submenu?.update() }
    }
}
