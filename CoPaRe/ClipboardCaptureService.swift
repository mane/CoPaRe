import AppKit
import CryptoKit
import Foundation

struct CapturedClipboardItem {
    let type: ClipboardItemType
    let preview: String
    let plainText: String?
    let imagePNGData: Data?
    let filePaths: [String]?
    let digest: String
    let byteSize: Int
    let sourceBundleIdentifier: String?
}

@MainActor
final class ClipboardCaptureService {
    var onCapture: ((CapturedClipboardItem) -> Void)?
    var onSensitiveContentSkipped: (() -> Void)?

    private let pasteboard: NSPasteboard
    private let settings: SettingsStore

    private var timer: Timer?
    private var lastChangeCount: Int
    private var digestToIgnoreOnce: String?

    private let maxPayloadBytes = 2_000_000
    private let maxTextCharacters = 20_000

    var isMonitoringEnabled = true

    init(pasteboard: NSPasteboard = .general, settings: SettingsStore) {
        self.pasteboard = pasteboard
        self.settings = settings
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        schedulePollingTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func applySettings() {
        schedulePollingTimer()
    }

    func writeToPasteboard(item: ClipboardHistoryItem) {
        pasteboard.clearContents()

        var expectedDigestToIgnore: String?

        switch item.type {
        case .text, .url:
            if let text = item.plainText {
                pasteboard.setString(text, forType: .string)
                expectedDigestToIgnore = digest(data: Data(text.utf8))
            }
        case .image:
            if let data = item.imagePNGData {
                // Keep exact PNG bytes to avoid re-encoding drift that would break deduplication.
                pasteboard.setData(data, forType: .png)
                expectedDigestToIgnore = digest(data: data)
            }
        case .file:
            let urls = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            if !urls.isEmpty {
                pasteboard.writeObjects(urls)
                let joined = urls
                    .map { ($0 as URL).path }
                    .joined(separator: "\n")
                expectedDigestToIgnore = digest(data: Data(joined.utf8))
            }
        }

        digestToIgnoreOnce = expectedDigestToIgnore
    }

    private func schedulePollingTimer() {
        timer?.invalidate()

        let interval = settings.pollInterval
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPasteboard()
            }
        }
        newTimer.tolerance = min(0.2, interval * 0.25)

        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func pollPasteboard() {
        guard isMonitoringEnabled else {
            return
        }

        let newChangeCount = pasteboard.changeCount
        guard newChangeCount != lastChangeCount else {
            return
        }

        lastChangeCount = newChangeCount

        guard let capture = readCapture() else {
            return
        }

        if digestToIgnoreOnce == capture.digest {
            digestToIgnoreOnce = nil
            return
        }

        onCapture?(capture)
    }

    private func readCapture() -> CapturedClipboardItem? {
        if settings.captureFiles, let fileCapture = readFileCapture() {
            return fileCapture
        }

        if let textCapture = readTextCapture() {
            return textCapture
        }

        if settings.captureImages, let imageCapture = readImageCapture() {
            return imageCapture
        }

        return nil
    }

    private func readTextCapture() -> CapturedClipboardItem? {
        guard let rawText = pasteboard.string(forType: .string) else {
            return nil
        }

        let sanitized = rawText
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitized.isEmpty else {
            return nil
        }

        if settings.filterSensitiveContent, SensitiveContentDetector.shouldBlock(text: sanitized) {
            onSensitiveContentSkipped?()
            return nil
        }

        let textToStore = String(sanitized.prefix(maxTextCharacters))
        let data = Data(textToStore.utf8)
        guard data.count <= maxPayloadBytes else {
            return nil
        }

        let type: ClipboardItemType
        if let url = URL(string: textToStore), url.scheme != nil {
            type = .url
        } else {
            type = .text
        }

        return CapturedClipboardItem(
            type: type,
            preview: textToStore.previewSnippet(),
            plainText: textToStore,
            imagePNGData: nil,
            filePaths: nil,
            digest: digest(data: data),
            byteSize: data.count,
            sourceBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
    }

    private func readFileCapture() -> CapturedClipboardItem? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            return nil
        }

        let normalizedPaths = urls
            .map(\.path)
            .filter { !$0.isEmpty }
            .prefix(30)

        guard !normalizedPaths.isEmpty else {
            return nil
        }

        let paths = Array(normalizedPaths)
        let joined = paths.joined(separator: "\n")
        let data = Data(joined.utf8)

        guard data.count <= maxPayloadBytes else {
            return nil
        }

        let preview: String
        if paths.count == 1 {
            preview = URL(fileURLWithPath: paths[0]).lastPathComponent
        } else {
            preview = "\(paths.count) files"
        }

        return CapturedClipboardItem(
            type: .file,
            preview: preview,
            plainText: nil,
            imagePNGData: nil,
            filePaths: paths,
            digest: digest(data: data),
            byteSize: data.count,
            sourceBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
    }

    private func readImageCapture() -> CapturedClipboardItem? {
        let imageData = pasteboard.data(forType: .png) ?? {
            guard let tiffData = pasteboard.data(forType: .tiff), let image = NSImage(data: tiffData) else {
                return nil
            }
            return image.coparePNGData()
        }()

        guard let pngData = imageData else {
            return nil
        }

        guard pngData.count <= maxPayloadBytes else {
            return nil
        }

        guard let image = NSImage(data: pngData) else {
            return nil
        }

        let size = image.size
        let preview = "Image \(Int(size.width))x\(Int(size.height))"

        return CapturedClipboardItem(
            type: .image,
            preview: preview,
            plainText: nil,
            imagePNGData: pngData,
            filePaths: nil,
            digest: digest(data: pngData),
            byteSize: pngData.count,
            sourceBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
    }

    private func digest(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

private extension NSImage {
    func coparePNGData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
