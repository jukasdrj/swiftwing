import Foundation

#if canImport(FoundationModels)
    import FoundationModels

    @Generable
    struct BookSpineInfo: Sendable, Codable {
        @Guide(description: "The book's title, cleaned of OCR artifacts")
        var title: String

        @Guide(description: "Primary author's full name (First Last format)")
        var author: String

        @Guide(description: "Additional authors if present on spine (array of full names)")
        var coauthors: [String]

        @Guide(description: "ISBN-10 or ISBN-13 if found in text (digits only)")
        var isbn: String?

        @Guide(description: "Publisher name if visible on spine")
        var publisher: String?

        @Guide(description: "Extraction quality: high, medium, or low")
        var confidence: String

        var confidenceLevel: ConfidenceLevel {
            ConfidenceLevel(rawValue: confidence) ?? .low
        }
    }

    enum ConfidenceLevel: String, Codable {
        case high, medium, low

        var score: Float {
            switch self {
            case .high: return 0.9
            case .medium: return 0.7
            case .low: return 0.5
            }
        }
    }

    // MARK: - Mapper to BookMetadata

    extension BookSpineInfo {
        func toBookMetadata() -> BookMetadata {
            BookMetadata(
                title: title,
                author: author,
                isbn: isbn ?? "",
                coverUrl: nil,
                publisher: publisher,
                publishedDate: nil,
                pageCount: nil,
                format: nil,
                confidence: Double(confidenceLevel.score),
                enrichmentStatus: .success
            )
        }
    }
#else
    // Fallback for when FoundationModels isn't available
    struct BookSpineInfo: Sendable, Codable {
        var title: String = ""
        var author: String = ""
        var coauthors: [String] = []
        var isbn: String?
        var publisher: String?
        var confidence: String = "low"

        var confidenceLevel: ConfidenceLevel {
            ConfidenceLevel(rawValue: confidence) ?? .low
        }

        func toBookMetadata() -> BookMetadata {
            BookMetadata(
                title: title,
                author: author,
                isbn: isbn ?? "",
                coverUrl: nil,
                publisher: publisher,
                publishedDate: nil,
                pageCount: nil,
                format: nil,
                confidence: 0.5,
                enrichmentStatus: .success
            )
        }
    }

    enum ConfidenceLevel: String, Codable {
        case high, medium, low
    }
#endif
