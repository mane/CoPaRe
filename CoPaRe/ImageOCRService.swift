import AppKit
import Foundation
import ImageIO
import Vision

nonisolated enum ImageTextExtractionError: Error, Equatable {
    case invalidImage
    case noText
}

struct ImageOCRService: Sendable {
    nonisolated init() {}

    /// An explicit, local extraction. Unlike the fast privacy scan below,
    /// this preserves line breaks and favors recognition accuracy.
    nonisolated func extractText(fromPNGData data: Data) async throws -> String {
        try Task.checkCancellation()
        let cancellation = ImageOCRCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw ImageTextExtractionError.invalidImage
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.minimumTextHeight = 0.005
            try cancellation.register(request)
            defer { cancellation.finish() }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            try Task.checkCancellation()

            let lines = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else {
                throw ImageTextExtractionError.noText
            }
            return lines.joined(separator: "\n")
        }

        return try await withTaskCancellationHandler {
            let text = try await worker.value
            try Task.checkCancellation()
            return text
        } onCancel: {
            cancellation.cancel()
            worker.cancel()
        }
    }

    nonisolated func recognizedText(fromPNGData data: Data) -> String? {
        guard #available(macOS 13.0, *) else {
            return nil
        }

        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results else {
            return nil
        }

        let lines = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .map { $0.condensingWhitespace() }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return nil
        }

        return lines.joined(separator: " ")
    }
}

/// VNRequest cancellation is safe to request while Vision is working. The
/// lock also covers cancellation arriving before the request is registered.
private final class ImageOCRCancellation: @unchecked Sendable {
    private nonisolated let lock = NSLock()
    private nonisolated(unsafe) var request: VNRequest?
    private nonisolated(unsafe) var isCancelled = false

    nonisolated init() {}

    nonisolated func register(_ request: VNRequest) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { throw CancellationError() }
        self.request = request
    }

    nonisolated func finish() {
        lock.lock()
        request = nil
        lock.unlock()
    }

    nonisolated func cancel() {
        lock.lock()
        isCancelled = true
        let activeRequest = request
        lock.unlock()
        activeRequest?.cancel()
    }
}
