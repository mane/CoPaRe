import AppKit
import Combine
import Foundation

extension Notification.Name {
    static let copareFocusSearchRequested = Notification.Name("io.copare.app.focusSearchRequested")
    static let copareOpenOnboardingRequested = Notification.Name("io.copare.app.openOnboardingRequested")
}

@MainActor
final class WindowCoordinator: ObservableObject {
    private var openMainWindowAction: (() -> Void)?

    func setOpenMainWindowAction(_ action: @escaping () -> Void) {
        openMainWindowAction = action
    }

    func openMainWindow(focusSearch: Bool) {
        NSApp.activate(ignoringOtherApps: true)

        if let openMainWindowAction {
            openMainWindowAction()
        } else if let firstWindow = NSApp.windows.first {
            firstWindow.makeKeyAndOrderFront(nil)
        }

        if focusSearch {
            NotificationCenter.default.post(name: .copareFocusSearchRequested, object: nil)
        }
    }
}
