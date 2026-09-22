import AppKit
import Combine
import Foundation
import SwiftUI

extension Notification.Name {
    static let copareFocusSearchRequested = Notification.Name("io.copare.app.focusSearchRequested")
    static let copareOpenOnboardingRequested = Notification.Name("io.copare.app.openOnboardingRequested")
}

@MainActor
final class WindowCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    private let mainWindowTitle = "CoPaRe"
    private var openMainWindowAction: (() -> Void)?
    private weak var manager: ClipboardManager?
    private var quickPanel: QuickClipboardPanel?
    private var previousApplication: NSRunningApplication?

    func setOpenMainWindowAction(_ action: @escaping () -> Void) {
        openMainWindowAction = action
    }

    func configureQuickPanel(manager: ClipboardManager) {
        self.manager = manager
    }

    func toggleQuickPanel() {
        if quickPanel?.isVisible == true {
            dismissQuickPanel(restorePreviousApplication: true)
            return
        }
        guard let manager else {
            openMainWindow(focusSearch: true)
            return
        }

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        previousApplication = frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? nil : frontmostApplication

        let panel = quickPanel ?? makeQuickPanel()
        quickPanel = panel
        // Recreate the view for each invocation: queries, selection and any error
        // are transient, and should not stay visible across a privacy lock.
        panel.contentView = NSHostingView(rootView: QuickClipboardView(
            manager: manager,
            onCopied: { [weak self] in self?.dismissQuickPanel(restorePreviousApplication: true) },
            onDismiss: { [weak self] in self?.dismissQuickPanel(restorePreviousApplication: true) },
            onOpenMainWindow: { [weak self] in self?.openMainWindow(focusSearch: true) },
            onUnlock: { [weak self, weak manager] in
                // Authentication owns its own system UI. Route it through the
                // persistent main window, so losing key status cannot hide it.
                self?.openMainWindow(focusSearch: true)
                Task { await manager?.unlock() }
            }
        ))
        positionQuickPanel(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func openMainWindow(focusSearch: Bool) {
        dismissQuickPanel(restorePreviousApplication: false)
        NSApp.activate(ignoringOtherApps: true)

        if let mainWindow = NSApp.windows.first(where: isMainWindow) {
            mainWindow.makeKeyAndOrderFront(nil)
        } else if let openMainWindowAction {
            openMainWindowAction()
        }

        if focusSearch {
            NotificationCenter.default.post(name: .copareFocusSearchRequested, object: nil)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === quickPanel else { return }
        // A click outside belongs to the newly selected app/window. Do not steal
        // its focus by restoring the app that was active when the picker opened.
        dismissQuickPanel(restorePreviousApplication: false)
    }

    private func dismissQuickPanel(restorePreviousApplication: Bool) {
        guard let panel = quickPanel else { return }
        let applicationToRestore = restorePreviousApplication ? previousApplication : nil
        previousApplication = nil
        // Clear the hosting view before ordering out, releasing visible metadata
        // and search text even when this reusable panel stays allocated.
        panel.contentView = nil
        panel.orderOut(nil)
        if let applicationToRestore, !applicationToRestore.isTerminated {
            applicationToRestore.activate(options: [])
        }
    }

    private func makeQuickPanel() -> QuickClipboardPanel {
        let panel = QuickClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "CoPaRe Quick Copy"
        panel.identifier = NSUserInterfaceItemIdentifier("quick-copy")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = true
        panel.hasShadow = true
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.dismissQuickPanel(restorePreviousApplication: true) }
        return panel
    }

    private func positionQuickPanel(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else {
            panel.center()
            return
        }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: max(frame.minY, frame.midY - panel.frame.height / 2 + frame.height * 0.12)
        ))
    }

    private func isMainWindow(_ window: NSWindow) -> Bool {
        if let identifier = window.identifier?.rawValue, identifier == "main" {
            return true
        }
        return window.title == mainWindowTitle
    }
}

@MainActor
private final class QuickClipboardPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
