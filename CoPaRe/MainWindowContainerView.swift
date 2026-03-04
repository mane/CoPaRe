import SwiftUI

struct MainWindowContainerView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var hotKeyService: GlobalHotKeyService
    @EnvironmentObject private var windowCoordinator: WindowCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView()
            .onAppear {
                windowCoordinator.setOpenMainWindowAction {
                    openWindow(id: "main")
                }

                hotKeyService.onHotKeyPressed = { [weak windowCoordinator] in
                    windowCoordinator?.openMainWindow(focusSearch: true)
                }
                hotKeyService.setEnabled(settings.globalShortcutEnabled)
            }
            .onChange(of: settings.globalShortcutEnabled) { _, enabled in
                hotKeyService.setEnabled(enabled)
            }
    }
}
