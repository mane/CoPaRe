import AppKit
import Combine
import SwiftUI

/// Owns the native menu so its width does not depend on the current history.
@MainActor
final class MenuBarController: ObservableObject {
    static let width: CGFloat = 400

    let menu: NSMenu
    private var statusItem: NSStatusItem?
    private var lifecycleObservers = Set<AnyCancellable>()

    init<Content: View>(content: Content) {
        let menu = NSHostingMenu(rootView: content)
        // The preview/source budgets in MenuBarContentView leave room for native
        // menu margins and arrows, so no title can expand this minimum width.
        menu.minimumWidth = Self.width
        menu.font = NSFont.menuFont(ofSize: 0)
        self.menu = menu

        NotificationCenter.default.publisher(for: NSApplication.didFinishLaunchingNotification)
            .sink { [weak self] _ in self?.installIfNeeded() }
            .store(in: &lifecycleObservers)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.removeStatusItem() }
            .store(in: &lifecycleObservers)

        if NSApplication.shared.isRunning {
            installIfNeeded()
        }
    }

    isolated deinit {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func installIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "paperclip.circle.fill", accessibilityDescription: "CoPaRe")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.setAccessibilityLabel("CoPaRe")
        item.button?.setAccessibilityIdentifier("CoPaReStatusItem")
        item.menu = menu
        statusItem = item
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }
}
