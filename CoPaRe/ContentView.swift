import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: ClipboardManager
    @State private var selectedItemID: UUID?
    @FocusState private var searchFieldFocused: Bool

    private var selectedItem: ClipboardHistoryItem? {
        manager.item(with: selectedItemID)
    }

    var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 390, idealWidth: 430, maxWidth: 520)

            detailPane
                .frame(minWidth: 420)
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.14, blue: 0.18),
                    Color(red: 0.03, green: 0.08, blue: 0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.12)
        )
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
        }
        .onChange(of: manager.filteredItems.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                selectedItemID = nil
                return
            }

            guard let selectedItemID else {
                self.selectedItemID = ids[0]
                return
            }

            if !ids.contains(selectedItemID) {
                self.selectedItemID = ids[0]
            }
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

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
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Picker("Filter", selection: $manager.activeFilter) {
                ForEach(ClipboardFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            ScrollViewReader { proxy in
                List(selection: $selectedItemID) {
                    ForEach(manager.filteredItems) { item in
                        ClipboardRowView(
                            item: item,
                            isSelected: selectedItemID == item.id,
                            onCopy: { manager.copyToClipboard(item) },
                            onTogglePin: { manager.togglePin(itemID: item.id) },
                            onDelete: { manager.remove(itemID: item.id) }
                        )
                        .tag(item.id)
                        .id(item.id)
                    }
                }
                .listStyle(.inset)
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
            }
        }
        .padding(14)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item = selectedItem {
                HStack(alignment: .top) {
                    Label(item.type.label, systemImage: item.type.symbolName)
                        .font(.title3.weight(.semibold))

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(item.byteSize) bytes")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                detailBody(for: item)

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button("Copy Again") {
                        manager.copyToClipboard(item)
                    }

                    Button(item.isPinned ? "Unpin" : "Pin") {
                        manager.togglePin(itemID: item.id)
                    }

                    if item.type == .file {
                        Button("Reveal in Finder") {
                            manager.revealFiles(of: item)
                        }
                    }

                    Spacer()

                    Button("Delete", role: .destructive) {
                        manager.remove(itemID: item.id)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Clipboard history")
                        .font(.title2.bold())
                    Text("Copy something on macOS to start building secure history.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CoPaRe")
                .font(.system(size: 30, weight: .black, design: .rounded))

            HStack(spacing: 10) {
                Label("\(manager.items.count) items", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.caption)

                Label(manager.isMonitoringEnabled ? "Monitoring on" : "Monitoring paused", systemImage: manager.isMonitoringEnabled ? "waveform" : "pause.fill")
                    .font(.caption)

                if manager.blockedSensitiveCaptureCount > 0 {
                    Label("\(manager.blockedSensitiveCaptureCount) sensitive blocked", systemImage: "shield.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .foregroundStyle(.secondary)
        }
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

    @ViewBuilder
    private func detailBody(for item: ClipboardHistoryItem) -> some View {
        switch item.type {
        case .text, .url:
            ScrollView {
                Text(item.plainText ?? item.preview)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .padding(14)
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

        case .image:
            if let data = item.imagePNGData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 380)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            } else {
                Text("Image data unavailable")
                    .foregroundStyle(.secondary)
            }

        case .file:
            if let paths = item.filePaths {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(paths, id: \.self) { path in
                            Button(path) {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            }
                            .buttonStyle(.link)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            } else {
                Text("No files available")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SettingsStore())
        .environmentObject(ClipboardManager(settings: SettingsStore()))
}
