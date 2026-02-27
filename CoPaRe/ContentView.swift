import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: ClipboardManager
    @State private var selectedItemID: UUID?
    @State private var selectedPayload: ClipboardItemPayload?
    @State private var selectedPayloadRefreshID = UUID()
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
        HStack(alignment: .top, spacing: 12) {
            sidebar
                .frame(minWidth: 360, idealWidth: 430, maxWidth: 520)

            detailPane
                .frame(minWidth: 520, maxWidth: .infinity)
        }
        .padding(14)
        .frame(minWidth: 1_040, minHeight: 700)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button(manager.isMonitoringEnabled ? "Pause" : "Resume") {
                    manager.toggleMonitoring()
                }

                Button("Clear Unpinned", role: .destructive) {
                    manager.clearHistory(keepPinned: true)
                }
            }

            ToolbarItem {
                Button {
                    searchFieldFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Focus search")
            }
        }
        .onAppear {
            selectedItemID = manager.filteredItems.first?.id
            refreshSelectedPayload()
        }
        .onChange(of: manager.filteredItems.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                selectedItemID = nil
                selectedPayload = nil
                return
            }

            guard let selectedItemID else {
                self.selectedItemID = ids[0]
                refreshSelectedPayload()
                return
            }

            if !ids.contains(selectedItemID) {
                self.selectedItemID = ids[0]
            }

            refreshSelectedPayload()
        }
        .onChange(of: selectedItemID) { _, _ in
            refreshSelectedPayload()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            clearSelectedPayload()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard selectedPayload == nil else {
                return
            }
            refreshSelectedPayload()
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
            HStack(spacing: 10) {
                Text("CoPaRe")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Spacer()

                Label("\(manager.items.count) items", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            panel {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search text, URLs, files", text: $manager.searchText)
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

                if manager.blockedSensitiveCaptureCount > 0 {
                    Label("\(manager.blockedSensitiveCaptureCount) blocked", systemImage: "shield.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 2)

            Picker("Filter", selection: $manager.activeFilter) {
                ForEach(ClipboardFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)

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

                                Text(item.type.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 3) {
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
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

                            Button("Delete", role: .destructive) {
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
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    Text("Protected content unavailable. Use Copy Again to restore it to the clipboard.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("Protected image unavailable. Use Copy Again to restore it to the clipboard.")
                    .foregroundStyle(.secondary)
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
                Text("Protected file list unavailable. Use Copy Again to restore it to the clipboard.")
                    .foregroundStyle(.secondary)
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
        selectedPayload = selectedItem?.decryptedPayload()
        selectedPayloadRefreshID = UUID()
    }

    private func clearSelectedPayload() {
        selectedPayload = nil
        selectedPayloadRefreshID = UUID()
    }
}

#Preview {
    ContentView()
        .environmentObject(SettingsStore())
        .environmentObject(ClipboardManager(settings: SettingsStore()))
}
