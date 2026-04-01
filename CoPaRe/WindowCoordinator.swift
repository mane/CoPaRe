import AppKit
import Combine
import Foundation

extension Notification.Name {
    static let copareFocusSearchRequested = Notification.Name("io.copare.app.focusSearchRequested")
    static let copareOpenOnboardingRequested = Notification.Name("io.copare.app.openOnboardingRequested")
}

@MainActor
final class WindowCoordinator: ObservableObject {
    private let mainWindowTitle = "CoPaRe"
    private var openMainWindowAction: (() -> Void)?

    func setOpenMainWindowAction(_ action: @escaping () -> Void) {
        openMainWindowAction = action
    }

    func openMainWindow(focusSearch: Bool) {
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

    private func isMainWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible else {
            return false
        }

        if let identifier = window.identifier?.rawValue, identifier == "main" {
            return true
        }

        return window.title == mainWindowTitle
    }
}
