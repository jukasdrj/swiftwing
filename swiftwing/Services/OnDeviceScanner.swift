import CoreGraphics
import Foundation
import ImageIO
import os
import Vision

private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "on-device-scan")

enum OnDeviceScanError: LocalizedError, Sendable {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "Could not read the photo for on-device scanning"
        }
    }
}

/// On-device extraction result. `ocrText` is the review-queue provenance string.
struct OnDeviceScanOutcome: Sendable, Equatable {
    var metadata: BookMetadata
    var ocrText: String?
}

struct RecognizedLine: Sendable, Equatable {
    var text: String
    /// Vision normalized rect, origin at the bottom left.
    var boundingBox: CGRect
}

protocol BookSpineExtracting: Sendable {
    func extract(_ imageData: Data) async throws -> OnDeviceScanOutcome
}

/// Longest line is the title. A "by …" line is the author; otherwise the following line.
enum SpineHeuristic {
    static func titleAndAuthor(from lines: [String]) -> (title: String?, author: String?) {
        let trimmed = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let titlePool = trimmed.filter { !$0.lowercased().hasPrefix("by ") }
        let longestPool = titlePool.max(by: { $0.count < $1.count })
        let longestAny = trimmed.max(by: { $0.count < $1.count })
        guard let title = longestPool ?? longestAny else {
            return (nil, nil)
        }

        if let byLine = trimmed.first(where: { $0.lowercased().hasPrefix("by ") }) {
            let name = String(byLine.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, name.isEmpty ? nil : name)
        }

        guard let titleIndex = trimmed.firstIndex(of: title) else {
            return (title, nil)
        }
        let following = trimmed.index(after: titleIndex)
        guard following < trimmed.endIndex else {
            return (title, nil)
        }
        return (title, trimmed[following])
    }
}

/// Review-gated metadata. A missing title or author stays `reviewNeeded` so the queue accepts it.
enum OnDeviceMetadataAssembler {
    static func assemble(
        title: String?,
        author: String?,
        isbn: String?,
        ocrLines: [String]
    ) -> OnDeviceScanOutcome {
        let cleanTitle = nonempty(title)
        let cleanAuthor = nonempty(author)
        let status: EnrichmentStatus = (cleanTitle == nil || cleanAuthor == nil) ? .reviewNeeded : .success
        let joined = ocrLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let metadata = BookMetadata(
            title: cleanTitle,
            author: cleanAuthor,
            isbn: normalizedISBN(isbn),
            confidence: nil,
            enrichmentStatus: status
        )
        return OnDeviceScanOutcome(metadata: metadata, ocrText: joined.isEmpty ? nil : joined)
    }

    static func normalizedISBN(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let upper = raw.uppercased()
        let digits = upper.filter(\.isNumber)
        if digits.count == 13 || digits.count == 10 {
            return digits
        }
        if digits.count == 9, upper.last == "X" {
            return digits + "X"
        }
        return nil
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

actor OnDeviceScanner: BookSpineExtracting {
    func extract(_ imageData: Data) async throws -> OnDeviceScanOutcome {
        let lines = try recognizeText(in: imageData)
        let isbn = detectBarcode(in: imageData)
        let texts = lines.map(\.text)
        let guessed = SpineHeuristic.titleAndAuthor(from: texts)
        return OnDeviceMetadataAssembler.assemble(
            title: guessed.title,
            author: guessed.author,
            isbn: isbn,
            ocrLines: texts
        )
    }

    func recognizeText(in imageData: Data) throws -> [RecognizedLine] {
        let image = try cgImage(from: imageData)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        return observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return RecognizedLine(text: trimmed, boundingBox: observation.boundingBox)
        }
    }

    func detectBarcode(in imageData: Data) -> String? {
        guard let image = try? cgImage(from: imageData) else { return nil }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.ean13, .ean8]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logger.error("Barcode detection failed: \(error.localizedDescription)")
            return nil
        }
        return request.results?.compactMap(\.payloadStringValue).first
    }

    private func cgImage(from imageData: Data) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw OnDeviceScanError.unreadableImage
        }
        return image
    }
}
