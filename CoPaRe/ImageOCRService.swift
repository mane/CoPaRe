import AppKit
import Foundation
import Vision

struct ImageOCRService {
    func recognizedText(fromPNGData data: Data) -> String? {
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
