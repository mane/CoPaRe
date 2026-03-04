import SwiftUI

struct SecurityOnboardingView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPreset: SecurityPreset = .balanced

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Security Setup")
                .font(.title2.weight(.bold))

            Text("Choose the starting protection profile for CoPaRe. You can change it later from Settings.")
                .foregroundStyle(.secondary)

            presetCard(for: .balanced)
            presetCard(for: .strict)

            HStack {
                Button("Skip for now") {
                    settings.onboardingCompleted = true
                    dismiss()
                }

                Spacer()

                Button("Apply \(selectedPreset.label)") {
                    settings.applySecurityPreset(selectedPreset, markOnboardingCompleted: true)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 560)
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
