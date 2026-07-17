import AppKit
import Foundation
import Vision

func cgImage(from image: NSImage) -> CGImage? {
    var rect = CGRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: ocr_vision.swift <image-path>\n", stderr)
    exit(2)
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])

guard let image = NSImage(contentsOf: imageURL), let cgImage = cgImage(from: image) else {
    fputs("failed to load image: \(imageURL.path)\n", stderr)
    exit(1)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
request.recognitionLanguages = ["ko-KR", "en-US", "ja-JP"]

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

do {
    try handler.perform([request])
} catch {
    fputs("ocr failed: \(error)\n", stderr)
    exit(1)
}

let observations = (request.results ?? []).sorted { lhs, rhs in
    let yDelta = abs(lhs.boundingBox.minY - rhs.boundingBox.minY)
    if yDelta > 0.015 {
        return lhs.boundingBox.minY > rhs.boundingBox.minY
    }
    return lhs.boundingBox.minX < rhs.boundingBox.minX
}

let lines = observations.compactMap { observation in
    observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines)
}.filter { !$0.isEmpty }

print(lines.joined(separator: "\n"))
