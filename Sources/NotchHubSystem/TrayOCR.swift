import AppKit
import Vision

/// Text recognition over a captured image, using the on-device Vision engine.
///
/// Everything runs on-device — nothing leaves the Mac. The result is the text
/// the Tray can search and show for a screenshot.
enum TrayOCR {

    /// Recognizes the text in `image`, joined line by line.
    ///
    /// Returns an empty string when Vision is unavailable or finds nothing.
    /// Safe to call from any queue; it blocks only its own caller.
    static func recognizeText(in image: NSImage) -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            return lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        } catch {
            return ""
        }
    }
}
