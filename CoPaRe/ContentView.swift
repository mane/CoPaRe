import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: ClipboardManager
    @EnvironmentObject private var settings: SettingsStore
    @State private var selectedItemID: UUID?
    @State private var selectedPayload: ClipboardItemPayload?
    @State private var selectedPayloadItemID: UUID?
    @State private var selectedPayloadRefreshID = UUID()
    @State private var isShowingSnippetComposer = false
    @State private var snippetTitle = ""
    @State private var snippetBody = ""
    @FocusState private var searchFieldFocused: Bool

    private let selectedPayloadRetentionSeconds = 30.0

    private var selectedItem: ClipboardHistoryItem? {
        manager.item(with: selectedItemID)
    }

    private var panelColor: Color {
        Color(nsColor: NSColor.controlBackgroundColor)
    }

    private var panelBorderColor: Color {
        Color(nsColor: NSColor.separatorColor).opacity(0.75)
    }

    var body: some View {
        Group {
            if manager.isLocked {
                lockedView
            } else {
                HStack(alignment: .top, spacing: 12) {
                    sidebar
                        .frame(minWidth: 360, idealWidth: 430, maxWidth: 520)

                    detailPane
                        .frame(minWidth: 520, maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 1_040, minHeight: 700)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                if manager.hasSavedSnippetsAvailable && !manager.savedSnippetsLoaded {
                    Button("Load Saved Snippets") {
                        Task {
                            await manager.loadSavedSnippets()
                        }
                    }
                    .disabled(manager.isLocked)
                }

                Button("New Snippet") {
                    isShowingSnippetComposer = true
                }
                .disabled(manager.isLocked)

                if settings.lockProtectionEnabled {
                    if manager.isLocked {
                        Button("Unlock") {
                            Task {
                                await manager.unlock()
                            }
                        }
                    } else {
                        Button("Lock") {
                            manager.lock()
                        }
                    }
                }

                Button(manager.isMonitoringEnabled ? "Pause" : "Resume") {
                    manager.toggleMonitoring()
                }
                .disabled(manager.isLocked)

                Button("Clear Unpinned", role: .destructive) {
                    manager.clearHistory(keepPinned: true)
                }
                .disabled(manager.isLocked)
            }

            ToolbarItem {
                Button {
                    searchFieldFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Focus search")
                .disabled(manager.isLocked)
            }
        }
        .sheet(isPresented: $isShowingSnippetComposer) {
            snippetComposer
        }
        .onAppear {
            selectedItemID = manager.filteredItems.first?.id
            clearSelectedPayload()
        }
        .onChange(of: manager.filteredItems.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                selectedItemID = nil
                clearSelectedPayload()
                return
            }

            guard let selectedItemID else {
                self.selectedItemID = ids[0]
                clearSelectedPayload()
                return
            }

            if !ids.contains(selectedItemID) {
                self.selectedItemID = ids[0]
                clearSelectedPayload()
            }
        }
        .onChange(of: selectedItemID) { _, _ in
            clearSelectedPayload()
        }
        .onChange(of: manager.isLocked) { _, isLocked in
            if isLocked {
                clearSelectedPayload()
                return
            }
            selectedItemID = manager.filteredItems.first?.id ?? selectedItemID
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            clearSelectedPayload()
        }
        .onDisappear {
            clearSelectedPayload()
        }
        .task(id: selectedPayloadRefreshID) {
            guard selectedPayload != nil else {
                return
            }

            let delay = UInt64(selectedPayloadRetentionSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)

            guard !Task.isCancelled else {
                return
            }

            selectedPayload = nil
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Label("\(manager.items.count) items", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            panel {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search text, URLs, files, snippets", text: $manager.searchText)
                        .textFieldStyle(.plain)
                        .focused($searchFieldFocused)

                    if !manager.searchText.isEmpty {
                        Button {
                            manager.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                Label(manager.isMonitoringEnabled ? "Monitoring on" : "Monitoring paused", systemImage: manager.isMonitoringEnabled ? "waveform" : "pause.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if manager.securityCounters.sensitiveContentBlocked > 0 {
                    Label("\(manager.securityCounters.sensitiveContentBlocked) sensitive blocked", systemImage: "shield.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if manager.securityCounters.excludedApplicationSkips > 0 {
                    Label("\(manager.securityCounters.excludedApplicationSkips) app skips", systemImage: "app.badge")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if manager.securityCounters.expiredEntriesRemoved > 0 {
                    Label("\(manager.securityCounters.expiredEntriesRemoved) expired", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)

            Picker("Filter", selection: $manager.activeFilter) {
                ForEach(ClipboardFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            if manager.hasSavedSnippetsAvailable && !manager.savedSnippetsLoaded {
                panel {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Saved snippets are locked at rest")
                                .font(.subheadline.weight(.semibold))

                            Text("Load them only when you need them. This may trigger a single system authentication prompt.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Load") {
                            Task {
                                await manager.loadSavedSnippets()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            ScrollViewReader { proxy in
                ZStack {
                    List {
                        ForEach(manager.filteredItems) { item in
                            ClipboardRowView(
                                item: item,
                                isSelected: selectedItemID == item.id,
                                onCopy: { manager.copyToClipboard(item) },
                                onTogglePin: { manager.togglePin(itemID: item.id) },
                                onDelete: { manager.remove(itemID: item.id) }
                            )
                            .id(item.id)
                            .onTapGesture {
                                selectedItemID = item.id
                            }
                            .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .padding(2)
                    .onChange(of: manager.items.map(\.id)) { oldIDs, newIDs in
                        autoScrollToLatest(with: proxy, oldIDs: oldIDs, newIDs: newIDs)
                    }
                    .onAppear {
                        if let firstVisibleItemID = manager.filteredItems.first?.id {
                            DispatchQueue.main.async {
                                proxy.scrollTo(firstVisibleItemID, anchor: .top)
                            }
                        }
                    }

                    if manager.filteredItems.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Text("No clipboard items")
                                .font(.headline)

                            Text("Copy something on macOS to start history capture.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(22)
                    }
                }
                .background(panelColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(panelBorderColor, lineWidth: 0.9)
                )
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var lockedView: some View {
        panel {
            VStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("CoPaRe is locked")
                    .font(.title2.bold())

                Text("Unlock the app to view clipboard history, snippets, and security details.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if settings.lockProtectionEnabled {
                    Button("Unlock CoPaRe") {
                        Task {
                            await manager.unlock()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var detailPane: some View {
        Group {
            if let item = selectedItem {
                panel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.type.symbolName)
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.preview.isEmpty ? item.type.label : item.preview)
                                    .font(.title3.weight(.semibold))
                                    .lineLimit(2)

                                Text(item.isSnippet ? item.origin.label : item.type.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 3) {
                                Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        detailContent(for: item, payload: selectedPayload)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(14)
                            .background(Color(nsColor: NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        HStack(spacing: 10) {
                            if item.encryptedPayload != nil && selectedPayload == nil {
                                Button {
                                    revealSelectedPayload()
                                } label: {
                                    Label("Reveal Content", systemImage: "eye")
                                }
                                .buttonStyle(.bordered)
                            }

                            Button {
                                manager.copyToClipboard(item)
                            } label: {
                                Label("Copy Again", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.borderedProminent)

                            Button(item.isPinned ? "Unpin" : "Pin") {
                                manager.togglePin(itemID: item.id)
                            }
                            .buttonStyle(.bordered)

                            if item.type == .file {
                                Button("Reveal in Finder") {
                                    manager.revealFiles(of: item)
                                }
                                .buttonStyle(.bordered)
                            }

                            Spacer()

                            Button("Secure Delete", role: .destructive) {
                                manager.remove(itemID: item.id)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } else {
                panel {
                    VStack(spacing: 10) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text("Clipboard history")
                            .font(.title2.bold())

                        Text("Select an entry from the list to view and manage its content.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var snippetComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Snippet")
                .font(.title3.bold())

            TextField("Snippet title", text: $snippetTitle)

            Text("Snippet body")
                .font(.subheadline.weight(.semibold))

            TextEditor(text: $snippetBody)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .frame(minHeight: 180)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(panelBorderColor, lineWidth: 0.9)
                )

            HStack {
                Button("Cancel") {
                    resetSnippetComposer()
                }

                Spacer()

                Button("Save Snippet") {
                    manager.addSnippet(title: snippetTitle, body: snippetBody)
                    resetSnippetComposer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(snippetBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 480, height: 330)
    }

    @ViewBuilder
    private func detailContent(for item: ClipboardHistoryItem, payload: ClipboardItemPayload?) -> some View {
        switch item.type {
        case .text, .url:
            ScrollView {
                if let plainText = payload?.plainText {
                    Text(plainText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                } else {
                    protectedContentPlaceholder("Text content is hidden until you choose Reveal Content or Copy Again.")
                }
            }

        case .image:
            if let data = payload?.imagePNGData, let image = NSImage(data: data) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 420)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text(item.preview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                protectedContentPlaceholder("Image content is hidden until you choose Reveal Content or Copy Again.")
            }

        case .file:
            if let paths = payload?.filePaths {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(paths, id: \.self) { path in
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc")
                                        .foregroundStyle(.secondary)
                                    Text(path)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(panelColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                protectedContentPlaceholder("File paths are hidden until you choose Reveal Content or Copy Again.")
            }
        }
    }

    @ViewBuilder
    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(panelColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(panelBorderColor, lineWidth: 0.9)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func autoScrollToLatest(with proxy: ScrollViewProxy, oldIDs: [UUID], newIDs: [UUID]) {
        guard let newestItemID = newIDs.first else {
            return
        }

        guard oldIDs.first != newestItemID else {
            return
        }

        guard manager.filteredItems.contains(where: { $0.id == newestItemID }) else {
            return
        }

        selectedItemID = newestItemID

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(newestItemID, anchor: .top)
            }
        }
    }

    private func refreshSelectedPayload() {
        guard let item = selectedItem else {
            clearSelectedPayload()
            return
        }

        if selectedPayloadItemID == item.id, selectedPayload != nil {
            return
        }

        selectedPayload = item.decryptedPayload()
        selectedPayloadItemID = item.id
        selectedPayloadRefreshID = UUID()
    }

    private func revealSelectedPayload() {
        refreshSelectedPayload()
    }

    private func clearSelectedPayload() {
        selectedPayload = nil
        selectedPayloadItemID = nil
        selectedPayloadRefreshID = UUID()
    }

    private func protectedContentPlaceholder(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func resetSnippetComposer() {
        snippetTitle = ""
        snippetBody = ""
        isShowingSnippetComposer = false
    }
}
