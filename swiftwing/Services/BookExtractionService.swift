import Foundation
import FoundationModels

actor BookExtractionService {
    private let session: LanguageModelSession
    private var isProcessing = false
    private var requestQueue: [(String, CheckedContinuation<BookSpineInfo, Error>)] = []

    init() {
        session = LanguageModelSession {
            """
            You are a book metadata extraction specialist. Extract structured information
            from OCR-scanned book spines and covers.

            Common OCR errors to handle:
            - Character confusion: 0/O, 1/l/I, 5/S
            - Split words: "TH E" instead of "THE"
            - Merged words: "TheGreat" instead of "The Great"
            - Vertical text read incorrectly

            Guidelines:
            - Title: The main title of the book, cleaned and corrected
            - Author: Primary author's full name
            - Coauthors: List other authors if visible
            - ISBN: Extract ISBN-10 or ISBN-13 if detected
            - Publisher: Publisher name if visible on spine
            - Confidence: Rate your extraction quality (high/medium/low)

            Always provide your best interpretation even with noisy text.
            Return empty strings for fields you cannot determine.
            """
        }
    }

    /// Extract metadata with automatic queueing for concurrent requests
    func extract(from ocrText: String) async throws -> BookSpineInfo {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await enqueueRequest(ocrText: ocrText, continuation: continuation)
            }
        }
    }

    private func enqueueRequest(ocrText: String, continuation: CheckedContinuation<BookSpineInfo, Error>) {
        requestQueue.append((ocrText, continuation))

        if !isProcessing {
            Task {
                await processQueue()
            }
        }
    }

    private func processQueue() async {
        isProcessing = true

        while !requestQueue.isEmpty {
            let (ocrText, continuation) = requestQueue.removeFirst()

            do {
                let result = try await performExtraction(ocrText: ocrText)
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }

        isProcessing = false
    }

    private func performExtraction(ocrText: String) async throws -> BookSpineInfo {
        // Check availability
        guard SystemLanguageModel.default.availability == .available else {
            throw ExtractionError.modelUnavailable
        }

        // Truncate if needed (leave ~1000 tokens for output)
        let maxInputLength = 12000  // ~3000 tokens
        let truncatedText = String(ocrText.prefix(maxInputLength))

        let prompt = """
            Extract book metadata from this OCR text:

            \(truncatedText)

            Return empty strings for fields that cannot be determined.
            """

        let response = try await session.respond(
            to: prompt,
            generating: BookSpineInfo.self
        )

        return response.content
    }
}

enum ExtractionError: Error, Equatable {
    case modelUnavailable
    case extractionFailed(String)
    case timeout
}
