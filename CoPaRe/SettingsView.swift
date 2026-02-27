import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var manager: ClipboardManager

    private var panelColor: Color {
        Color(nsColor: NSColor.controlBackgroundColor)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionCard(title: "Security") {
                    Toggle("Filter potentially sensitive text", isOn: $settings.filterSensitiveContent)
                    Toggle("Persist encrypted history on disk", isOn: $settings.persistHistory)
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)

                    if !settings.persistHistory {
                        Text("Private session mode is active: history remains only in memory and is deleted on app quit.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                sectionCard(title: "Capture") {
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

                sectionCard(title: "Storage") {
                    Stepper(value: $settings.historyLimit, in: 20...1_000, step: 10) {
                        Text("Unpinned history limit: \(settings.historyLimit)")
                    }
                }

                sectionCard(title: "Danger Zone") {
                    Button("Delete entire history", role: .destructive) {
                        manager.clearHistory(keepPinned: false)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .frame(width: 580, height: 560)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}
