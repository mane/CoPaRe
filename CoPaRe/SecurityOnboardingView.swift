import SwiftUI

struct SecurityOnboardingView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPreset: SecurityPreset = .balanced
    @State private var stepIndex = 0

    private let totalSteps = 4

    private var isFirstStep: Bool {
        stepIndex == 0
    }

    private var isLastStep: Bool {
        stepIndex == totalSteps - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to CoPaRe")
                .font(.title2.bold())

            Text(stepSubtitle)
                .foregroundStyle(.secondary)

            stepIndicator
            stepContent

            HStack {
                if isFirstStep {
                    Button("Skip tutorial") {
                        settings.onboardingCompleted = true
                        dismiss()
                    }
                } else {
                    Button("Back") {
                        stepIndex -= 1
                    }
                }

                Spacer()

                if isLastStep {
                    Button("Apply \(selectedPreset.label)") {
                        settings.applySecurityPreset(selectedPreset, markOnboardingCompleted: true)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Next") {
                        stepIndex += 1
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 620)
        .interactiveDismissDisabled()
    }

    private var stepSubtitle: String {
        switch stepIndex {
        case 0:
            return "A quick guide to your clipboard history workflow."
        case 1:
            return "How to use the main actions in the app."
        case 2:
            return "What CoPaRe protects by default and what to expect."
        default:
            return "Choose the starting protection profile. You can change it later from Settings."
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index <= stepIndex ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: index == stepIndex ? 30 : 12, height: 6)
                    .animation(.easeInOut(duration: 0.18), value: stepIndex)
            }
            Spacer()
            Text("Step \(stepIndex + 1) of \(totalSteps)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch stepIndex {
        case 0:
            onboardingCard(title: "How it works") {
                featureRow(
                    symbol: "tray.full",
                    title: "Clipboard capture",
                    description: "Copy text, URLs, images, files, and folders on macOS to build session history."
                )
                featureRow(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: "Search and filter",
                    description: "Use search and filters (`All`, `Pinned`, `Text`, `Images`, `Files`) to find entries quickly."
                )
                featureRow(
                    symbol: "menubar.rectangle",
                    title: "Quick panel",
                    description: "Use the menu bar icon for fast copy/pin/delete actions without opening the full window."
                )
            }
        case 1:
            onboardingCard(title: "Main actions") {
                featureRow(
                    symbol: "doc.on.doc",
                    title: "Copy Again",
                    description: "Re-copy any entry with one click from list, detail pane, or menu bar panel."
                )
                featureRow(
                    symbol: "pin",
                    title: "Pin important items",
                    description: "Pinned entries stay at the top and are preserved when clearing unpinned history."
                )
                featureRow(
                    symbol: "plus.square.on.square",
                    title: "Create snippets",
                    description: "Use `New Snippet` for reusable text. Optional encrypted vault persistence is available."
                )
                featureRow(
                    symbol: "pause.circle",
                    title: "Pause monitoring",
                    description: "Temporarily stop capture with `Pause` when you don’t want new entries recorded."
                )
            }
        case 2:
            onboardingCard(title: "Security behavior") {
                featureRow(
                    symbol: "lock.shield",
                    title: "Session-only captured history",
                    description: "Captured clipboard history is memory-only and cleared on app quit."
                )
                featureRow(
                    symbol: "eye.slash",
                    title: "Sensitive-content blocker",
                    description: "When enabled, CoPaRe skips likely secrets and protected pasteboard types from password managers."
                )
                featureRow(
                    symbol: "person.crop.circle.badge.checkmark",
                    title: "Optional unlock gate",
                    description: "Enable `Require unlock to view history` to guard access with system authentication."
                )
                featureRow(
                    symbol: "gearshape",
                    title: "Fully configurable",
                    description: "You can change every option later in `Settings`."
                )
            }
        default:
            VStack(spacing: 12) {
                presetCard(for: .balanced)
                presetCard(for: .strict)
            }
        }
    }

    @ViewBuilder
    private func onboardingCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func featureRow(symbol: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func presetCard(for preset: SecurityPreset) -> some View {
        Button {
            selectedPreset = preset
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(preset.label)
                        .font(.headline)
                    Spacer()
                    if selectedPreset == preset {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Text(preset.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selectedPreset == preset
                            ? Color.accentColor.opacity(0.65)
                            : Color.secondary.opacity(0.2),
                        lineWidth: selectedPreset == preset ? 1.4 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
