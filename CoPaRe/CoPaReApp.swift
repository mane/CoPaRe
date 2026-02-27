import SwiftUI

@main
struct CoPaReApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var manager: ClipboardManager

    init() {
        let settingsStore = SettingsStore()
        _settings = StateObject(wrappedValue: settingsStore)
        _manager = StateObject(wrappedValue: ClipboardManager(settings: settingsStore))
    }

    var body: some Scene {
        WindowGroup("CoPaRe", id: "main") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(manager)
        }
        .defaultSize(width: 1_120, height: 740)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(manager)
        }

        MenuBarExtra("CoPaRe", systemImage: "paperclip.circle.fill") {
            MenuBarContentView()
                .environmentObject(manager)
        }
        .menuBarExtraStyle(.menu)
    }
}
