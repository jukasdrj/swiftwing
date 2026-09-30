import CoreGraphics
import Foundation
import FoundationModels
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
    /// Top-candidate confidence, 0...1.
    var confidence: Float = 0
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
        ocrLines: [String],
        extraction: BookExtraction? = nil
    ) -> OnDeviceScanOutcome {
        let modelTitle = nonempty(extraction?.title)
        let modelAuthor = nonempty(extraction?.author)
        let cleanTitle: String?
        let cleanAuthor: String?
        if let modelTitle, let modelAuthor {
            cleanTitle = modelTitle
            cleanAuthor = modelAuthor
        } else {
            cleanTitle = nonempty(title)
            cleanAuthor = nonempty(author)
        }
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
        let started = CFAbsoluteTimeGetCurrent()
        let decoded = try decodeScanImage(from: imageData)
        let image = decoded.image
        let pixelWidth = image.width
        let pixelHeight = image.height
        let byteCount = imageData.count
        let exif = decoded.exifOrientation
        let imageSummary = "On-device image \(pixelWidth)x\(pixelHeight) \(byteCount)B exif \(exif)"
        logger.info("\(imageSummary, privacy: .public)")

        let ocrStarted = CFAbsoluteTimeGetCurrent()
        let lines = try recognizeLines(in: image)
        let ocrMs = milliseconds(since: ocrStarted)
        let confidences = lines.map(\.confidence)
        let meanConfidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Float(confidences.count)
        let minConfidence = confidences.min() ?? 0
        let lineCount = lines.count
        let meanText = String(format: "%.2f", meanConfidence)
        let minText = String(format: "%.2f", minConfidence)
        let ocrSummary = "On-device OCR \(ocrMs)ms lines \(lineCount) mean \(meanText) min \(minText)"
        logger.info("\(ocrSummary, privacy: .public)")

        let barcodeStarted = CFAbsoluteTimeGetCurrent()
        let isbn = barcodePayload(in: image)
        let barcodeMs = milliseconds(since: barcodeStarted)
        let foundBarcode = isbn != nil
        logger.info(
            "On-device barcode \(barcodeMs, privacy: .public)ms found \(foundBarcode, privacy: .public)"
        )

        let texts = lines.map(\.text)
        let guessed = SpineHeuristic.titleAndAuthor(from: texts)
        let modelStarted = CFAbsoluteTimeGetCurrent()
        let extraction = await disambiguate(lines: texts, image: image)
        let modelMs = milliseconds(since: modelStarted)
        let source = extraction == nil ? "heuristic" : "model"
        logger.info(
            "On-device model \(modelMs, privacy: .public)ms source \(source, privacy: .public)"
        )

        let outcome = OnDeviceMetadataAssembler.assemble(
            title: guessed.title,
            author: guessed.author,
            isbn: isbn,
            ocrLines: texts,
            extraction: extraction
        )
        let totalMs = milliseconds(since: started)
        let title = outcome.metadata.title ?? ""
        let author = outcome.metadata.author ?? ""
        let status = String(describing: outcome.metadata.enrichmentStatus)
        let heuristicTitle = guessed.title ?? ""
        let heuristicAuthor = guessed.author ?? ""
        let resultSummary = "On-device result \(totalMs)ms status \(status) title \(title) author \(author)"
        logger.info("\(resultSummary, privacy: .public)")
        logger.info(
            "On-device heuristic title \(heuristicTitle, privacy: .public) author \(heuristicAuthor, privacy: .public)"
        )
        return outcome
    }

    private func milliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    func recognizeText(in imageData: Data) throws -> [RecognizedLine] {
        try recognizeLines(in: decodeScanImage(from: imageData).image)
    }

    func detectBarcode(in imageData: Data) -> String? {
        guard let image = try? decodeScanImage(from: imageData).image else { return nil }
        return barcodePayload(in: image)
    }

    private func recognizeLines(in image: CGImage) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let trimmed = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return RecognizedLine(
                text: trimmed,
                boundingBox: observation.boundingBox,
                confidence: candidate.confidence
            )
        }
    }

    private func barcodePayload(in image: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.ean13, .ean8]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            let message = error.localizedDescription
            logger.error("Barcode detection failed: \(message, privacy: .public)")
            return nil
        }
        return request.results?.compactMap(\.payloadStringValue).first
    }

    /// Foundation Models only when Apple Intelligence is available. Any failure keeps the OCR heuristic.
    private func disambiguate(lines: [String], image: CGImage) async -> BookExtraction? {
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else {
            if case let .unavailable(reason) = availability {
                let reasonText = String(describing: reason)
                logger.info("On-device model unavailable: \(reasonText, privacy: .public)")
            }
            return nil
        }
        let transcript = lines.joined(separator: "\n")
        let instructions = """
        The OCR lines from this book spine are:
        \(transcript)
        Identify the book's title and author in the image.
        """
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(
                generating: BookExtraction.self,
                options: GenerationOptions(samplingMode: .greedy)
            ) {
                instructions
                Attachment(image)
            }
            let content = response.content
            let modelTitle = content.title
            let modelAuthor = content.author
            guard !modelTitle.isEmpty, !modelAuthor.isEmpty else {
                logger.info("On-device model returned an empty title or author; using the OCR heuristic")
                return nil
            }
            logger.info(
                "On-device model title \(modelTitle, privacy: .public) author \(modelAuthor, privacy: .public)"
            )
            return content
        } catch {
            let message = error.localizedDescription
            logger.error("On-device model failed: \(message, privacy: .public)")
            return nil
        }
    }

    /// Upright pixels. Vision and the on-device model both assume the buffer is already rotated.
    func decodeScanImage(from imageData: Data) throws -> (image: CGImage, exifOrientation: Int) {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw OnDeviceScanError.unreadableImage
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = Self.exifOrientation(props)
        let width = Self.propertyCGFloat(props, key: kCGImagePropertyPixelWidth)
        let height = Self.propertyCGFloat(props, key: kCGImagePropertyPixelHeight)
        let longest = Int(max(width, height).rounded(.up))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(longest, 1),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw OnDeviceScanError.unreadableImage
        }
        return (image, orientation)
    }

    private static func exifOrientation(_ props: [CFString: Any]?) -> Int {
        guard let raw = props?[kCGImagePropertyOrientation] else { return 1 }
        if let number = raw as? NSNumber {
            return number.intValue
        }
        if let number = raw as? Int {
            return number
        }
        return 1
    }

    private static func propertyCGFloat(_ props: [CFString: Any]?, key: CFString) -> CGFloat {
        guard let raw = props?[key] else { return 0 }
        if let number = raw as? CGFloat {
            return number
        }
        if let number = raw as? NSNumber {
            return CGFloat(number.doubleValue)
        }
        if let number = raw as? Int {
            return CGFloat(number)
        }
        return 0
    }
}
