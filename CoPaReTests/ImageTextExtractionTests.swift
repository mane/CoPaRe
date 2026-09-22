import AppKit
import Foundation
import Testing
@testable import CoPaRe

@MainActor
struct ImageTextExtractionTests {
    @Test func accurateExtractionReadsGeneratedImageLocally() async throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 700,
            pixelsHigh: 150,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 700, height: 150).fill()
        ("Clipboard text example" as NSString).draw(
            at: NSPoint(x: 25, y: 50),
            withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black]
        )
        NSGraphicsContext.restoreGraphicsState()
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let text = try await ImageOCRService().extractText(fromPNGData: data)
        #expect(text.lowercased().contains("clipboard text example"))
    }

    @Test func extractionRejectsMalformedImage() async {
        await #expect(throws: ImageTextExtractionError.invalidImage) {
            try await ImageOCRService().extractText(fromPNGData: Data("not an image".utf8))
        }
    }

    @Test func cancelledExtractionNeverStartsRecognition() async {
        let task = Task {
            try await ImageOCRService().extractText(fromPNGData: Data())
        }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test func successfulRequestHandsTextDirectlyToCopyAction() async {
        let controller = ImageTextExtractionController { _ in "Line one\nLine two" }
        var copied: String?
        await controller.extractAndCopy(imageData: Data()) { text in
            copied = text
            return true
        }.value
        #expect(copied == "Line one\nLine two")
        #expect(controller.status == .copied)
    }

    @Test func invalidatedRequestDiscardsEvenNonCooperativeRecognition() async {
        let recognizer = DelayedTextRecognizer()
        let controller = ImageTextExtractionController { data in
            try await recognizer.recognize(data)
        }
        var copyWasCalled = false
        let task = controller.extractAndCopy(imageData: Data()) { _ in
            copyWasCalled = true
            return true
        }
        await recognizer.waitUntilStarted()
        controller.cancel()
        await recognizer.finish()
        await task.value
        #expect(!copyWasCalled)
        #expect(controller.status == .idle)
    }

    @Test func copyRejectedByLifecycleGuardDoesNotReportSuccess() async {
        let controller = ImageTextExtractionController { _ in "Discard me" }
        await controller.extractAndCopy(imageData: Data()) { _ in false }.value
        #expect(controller.status == .idle)
    }

    @Test func replacedRequestCannotOverwriteNewerClipboardResult() async {
        let delayed = DelayedTextRecognizer()
        let controller = ImageTextExtractionController { data in
            if data.isEmpty {
                return try await delayed.recognize(data)
            }
            return "Current result"
        }
        var copied: [String] = []
        let oldTask = controller.extractAndCopy(imageData: Data()) { text in
            copied.append(text)
            return true
        }
        await delayed.waitUntilStarted()
        await controller.extractAndCopy(imageData: Data([1])) { text in
            copied.append(text)
            return true
        }.value
        await delayed.finish()
        await oldTask.value
        #expect(copied == ["Current result"])
        #expect(controller.status == .copied)
    }

    @Test func noTextHasDistinctFeedbackWithoutCopying() async {
        let controller = ImageTextExtractionController { _ in
            throw ImageTextExtractionError.noText
        }
        var copyWasCalled = false
        await controller.extractAndCopy(imageData: Data()) { _ in
            copyWasCalled = true
            return true
        }.value
        #expect(!copyWasCalled)
        #expect(controller.status == .noText)
    }
}

private actor DelayedTextRecognizer {
    private var continuation: CheckedContinuation<String, Error>?
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?

    func recognize(_ data: Data) async throws -> String {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish() {
        continuation?.resume(returning: "Sensitive result that must be discarded")
        continuation = nil
    }
}
