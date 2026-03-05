import SwiftUI

struct SecurityOnboardingView: View {
    private struct DemoItem: Identifiable {
        let id: UUID
        let type: ClipboardItemType
        let title: String
        let subtitle: String
    }

    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPreset: SecurityPreset = .balanced
    @State private var stepIndex = 0
    @State private var demoFilter: ClipboardFilter = .all
    @State private var demoSearchText = ""
    @State private var demoSelectedItemID: UUID?
    @State private var didUseSearch = false
    @State private var didUseFilter = false
    @State private var didSelectItem = false
    @State private var didCopyItem = false
    @State private var didPinItem = false
    @State private var didPauseMonitoring = false
    @State private var demoPinnedIDs = Set<UUID>()
    @State private var demoMonitoringEnabled = true

    private let totalSteps = 4
    private let demoItems: [DemoItem] = [
        DemoItem(
            id: UUID(uuidString: "9A9B1488-8819-4B90-BFC8-A704F6B3E5E4")!,
            type: .text,
            title: "swift build -c release",
            subtitle: "Text"
        ),
        DemoItem(
            id: UUID(uuidString: "11BD4EA9-3F76-4D4F-A67A-A351CF92A0E0")!,
            type: .url,
            title: "https://github.com/mane/CoPaRe/releases",
            subtitle: "URL"
        ),
        DemoItem(
            id: UUID(uuidString: "A55B6D97-1332-4432-92D9-F42F086F0A94")!,
            type: .image,
            title: "Image 1120x772",
            subtitle: "Image"
        ),
        DemoItem(
            id: UUID(uuidString: "C2A3D26C-C66A-43C2-A40B-7A9F2B991E89")!,
            type: .file,
            title: "/Users/demo/Documents/manual.pdf",
            subtitle: "File"
        )
    ]

    private var isFirstStep: Bool {
        stepIndex == 0
    }

    private var isLastStep: Bool {
        stepIndex == totalSteps - 1
    }

    private var canAdvanceFromCurrentStep: Bool {
        switch stepIndex {
        case 1:
            return didUseSearch && didUseFilter && didSelectItem
        case 2:
            return didCopyItem && didPinItem && didPauseMonitoring
        default:
            return true
        }
    }

    private var selectedDemoItem: DemoItem? {
        guard let demoSelectedItemID else {
            return filteredDemoItems.first ?? demoItems.first
        }
        return demoItems.first(where: { $0.id == demoSelectedItemID })
    }

    private var filteredDemoItems: [DemoItem] {
        let base = demoItems.filter { item in
            switch demoFilter {
            case .all:
                return true
            case .pinned:
                return demoPinnedIDs.contains(item.id)
            case .text:
                return item.type == .text || item.type == .url
            case .image:
                return item.type == .image
            case .file:
                return item.type == .file
            }
        }

        let query = demoSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else {
            return base
        }

        return base.filter { item in
            item.title.lowercased().contains(query) || item.subtitle.lowercased().contains(query)
        }
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
                    Button("Skip") {
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
                    Button("Finish with \(selectedPreset.label)") {
                        settings.applySecurityPreset(selectedPreset, markOnboardingCompleted: true)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(stepIndex == 0 ? "Start Tour" : "Continue") {
                        stepIndex += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvanceFromCurrentStep)
                }
            }

            if !isLastStep, !canAdvanceFromCurrentStep {
                Text("Complete the required actions to continue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(20)
        .frame(width: 700)
        .interactiveDismissDisabled()
        .onAppear {
            ensureDemoSelection()
        }
        .onChange(of: stepIndex) { _, _ in
            ensureDemoSelection()
        }
        .onChange(of: demoFilter) { _, _ in
            didUseFilter = true
            ensureDemoSelection()
        }
        .onChange(of: demoSearchText) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                didUseSearch = true
            }
            ensureDemoSelection()
        }
    }

    private var stepSubtitle: String {
        switch stepIndex {
        case 0:
            return "Quick overview of CoPaRe and where to find key controls."
        case 1:
            return "Try search and filters to find one entry."
        case 2:
            return "Use the core actions on one selected item."
        default:
            return "Review security behavior and choose your default profile."
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
            onboardingCard(title: "Quick overview") {
                featureRow(
                    symbol: "list.bullet.rectangle",
                    title: "Left panel: history",
                    description: "Search, filter, and select captured items."
                )
                featureRow(
                    symbol: "rectangle.and.text.magnifyingglass",
                    title: "Right panel: details",
                    description: "Reveal, copy again, pin, or delete the selected item."
                )
                featureRow(
                    symbol: "menubar.rectangle",
                    title: "Menu bar shortcuts",
                    description: "Open CoPaRe fast and run quick actions without opening the main window."
                )
            }
        case 1:
            interactiveFindStep
        case 2:
            interactiveActionsStep
        default:
            onboardingCard(title: "Security and profile") {
                featureRow(
                    symbol: "eye.slash",
                    title: "Sensitive blocker",
                    description: "Skips likely secrets and protected pasteboard types."
                )
                featureRow(
                    symbol: "lock.doc",
                    title: "Encrypted persistence",
                    description: "Saved snippets/history use encryption and keychain-protected keys."
                )
                featureRow(
                    symbol: "person.badge.key",
                    title: "Optional unlock gate",
                    description: "You can require system authentication to view history."
                )

                Divider()

                Text("Choose a starting profile (editable later in Settings):")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    presetCard(for: .balanced)
                    presetCard(for: .strict)
                }
            }
        }
    }

    private var interactiveFindStep: some View {
        onboardingCard(title: "Mini demo: find an item") {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search demo items", text: $demoSearchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Picker("Filter", selection: $demoFilter) {
                ForEach(ClipboardFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(filteredDemoItems) { item in
                        Button {
                            demoSelectedItemID = item.id
                            didSelectItem = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.type.symbolName)
                                    .frame(width: 28, height: 28)
                                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .lineLimit(1)
                                        .font(.subheadline.weight(.semibold))
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                (demoSelectedItemID == item.id ? Color.accentColor.opacity(0.14) : Color(nsColor: NSColor.textBackgroundColor)),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder((demoSelectedItemID == item.id ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.2)), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 190)

            checklistRow("Use search (type at least 2 chars)", done: didUseSearch)
            checklistRow("Change filter at least once", done: didUseFilter)
            checklistRow("Select one item", done: didSelectItem)
        }
    }

    private var interactiveActionsStep: some View {
        onboardingCard(title: "Mini demo: item actions") {
            Text("Required: Copy, Pin and Pause at least once.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let item = selectedDemoItem {
                HStack(spacing: 10) {
                    Image(systemName: item.type.symbolName)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .lineLimit(1)
                            .font(.subheadline.weight(.semibold))
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 10) {
                Button(didCopyItem ? "Copied" : "Copy Again") {
                    didCopyItem = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!didSelectItem)

                Button((selectedDemoItem.map { demoPinnedIDs.contains($0.id) } ?? false) ? "Unpin" : "Pin") {
                    guard let id = selectedDemoItem?.id else {
                        return
                    }
                    if demoPinnedIDs.contains(id) {
                        demoPinnedIDs.remove(id)
                    } else {
                        demoPinnedIDs.insert(id)
                    }
                    didPinItem = true
                }
                .buttonStyle(.bordered)
                .disabled(!didSelectItem)

                Button(demoMonitoringEnabled ? "Pause Monitoring" : "Resume Monitoring") {
                    demoMonitoringEnabled.toggle()
                    didPauseMonitoring = true
                }
                .buttonStyle(.bordered)
            }

            checklistRow("Copy Again clicked", done: didCopyItem)
            checklistRow("Pin/Unpin clicked", done: didPinItem)
            checklistRow("Pause/Resume clicked", done: didPauseMonitoring)
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

    private func checklistRow(_ text: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.accentColor : .secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func ensureDemoSelection() {
        let visibleIDs = Set(filteredDemoItems.map(\.id))
        if let demoSelectedItemID, visibleIDs.contains(demoSelectedItemID) {
            return
        }
        demoSelectedItemID = filteredDemoItems.first?.id ?? demoItems.first?.id
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
