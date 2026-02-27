import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var manager: ClipboardManager

    var body: some View {
        Form {
            Section("Security") {
                Toggle("Filter potentially sensitive text", isOn: $settings.filterSensitiveContent)
                Toggle("Persist encrypted history on disk", isOn: $settings.persistHistory)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)

                if !settings.persistHistory {
                    Text("Private session mode is active: history remains only in memory and is deleted on app quit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Capture") {
                Toggle("Capture images", isOn: $settings.captureImages)
                Toggle("Capture copied files/folders", isOn: $settings.captureFiles)

                HStack {
                    Text("Polling interval")
                    Spacer()
                    Text("\(settings.pollInterval, specifier: "%.2f")s")
                        .foregroundStyle(.secondary)
                }

                Slider(value: $settings.pollInterval, in: 0.25...2.0, step: 0.05)
            }

            Section("Storage") {
                Stepper(value: $settings.historyLimit, in: 20...1_000, step: 10) {
                    Text("Unpinned history limit: \(settings.historyLimit)")
                }
            }

            Section("Danger Zone") {
                Button("Delete entire history", role: .destructive) {
                    manager.clearHistory(keepPinned: false)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
