import Foundation

#if canImport(FoundationModels)
    import FoundationModels

    /// Actor-isolated service for extracting metadata from book spines using Foundation Models
    actor BookExtractionService {
        private let session: LanguageModelSession

        init() {
            // iOS 26: Initialize with a system message or usage context if needed
            self.session = LanguageModelSession()
        }

        /// Extract metadata using the @Generable BookSpineInfo struct
        /// - Parameter ocrText: The text recognized from the book spine
        /// - Returns: Structured BookSpineInfo
        func extract(from ocrText: String) async throws -> BookSpineInfo {
            // Check availability
            guard SystemLanguageModel.default.availability == .available else {
                throw ExtractionError.modelUnavailable
            }

            // Truncate input if necessary
            let maxInputLength = 12000
            let truncatedText = String(ocrText.prefix(maxInputLength))

            // Construct the prompt
            let prompt = """
                Extract book metadata from this OCR text:

                \(truncatedText)

                Return the result as a BookSpineInfo JSON object.
                """

            // Use the generating: parameter with the @Generable struct type
            // This is the key iOS 26 API change
            let response = try await session.respond(
                to: prompt,
                generating: BookSpineInfo.self
            )

            return response.content
        }
    }
#else
    /// Stub for when FoundationModels is not available
    actor BookExtractionService {
        init() {}

        func extract(from ocrText: String) async throws -> BookSpineInfo {
            // Return a mocked/empty result or fail safely
            // Since we are likely on an older OS or in a test environment without the SDK
            return BookSpineInfo()  // Returns default/empty struct
        }
    }
#endif

enum ExtractionError: Error {
    case modelUnavailable
    case extractionFailed(String)
}
