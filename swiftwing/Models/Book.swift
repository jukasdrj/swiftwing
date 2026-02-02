import Foundation
import SwiftData

// Epic 5: Reading status tracking
public enum ReadingStatus: String, Codable {
    case toRead = "to_read"
    case reading = "reading"
    case completed = "completed"
    case dnf = "did_not_finish"
}

@Model
public final class Book {
    @Attribute(.unique) var isbn: String
    public var id: UUID
    public var title: String
    var author: String

    // Epic 3 - Full metadata fields
    var coverUrl: URL?
    var format: String?
    var publisher: String?
    var publishedDate: Date?
    var pageCount: Int?

    // AI confidence scoring
    var spineConfidence: Double?

    // Tracking
    var addedDate: Date

    // Epic 5: Reading status tracking (UI deferred to Epic 5)
    var readingStatus: String? // Stores ReadingStatus rawValue
    var dateRead: Date?
    var userRating: Int? // 1-5 stars

    // Personal annotations
    var notes: String?

    // Debug/raw data
    var rawJSON: String?

    // Talaria enrichment status tracking (Epic 4)
    var enrichmentStatus: String?

    // Computed property for review threshold
    var needsReview: Bool {
        spineConfidence ?? 1.0 < 0.8
    }

    // Computed property for enrichment review needs
    var needsEnrichmentReview: Bool {
        enrichmentStatus == "review_needed" || enrichmentStatus == "not_found"
    }

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        isbn: String,
        coverUrl: URL? = nil,
        format: String? = nil,
        publisher: String? = nil,
        publishedDate: Date? = nil,
        pageCount: Int? = nil,
        spineConfidence: Double? = nil,
        addedDate: Date = Date(),
        readingStatus: String? = nil,
        dateRead: Date? = nil,
        userRating: Int? = nil,
        notes: String? = nil,
        rawJSON: String? = nil,
        enrichmentStatus: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.isbn = isbn
        self.coverUrl = coverUrl
        self.format = format
        self.publisher = publisher
        self.publishedDate = publishedDate
        self.pageCount = pageCount
        self.spineConfidence = spineConfidence
        self.addedDate = addedDate
        self.readingStatus = readingStatus
        self.dateRead = dateRead
        self.userRating = userRating
        self.notes = notes
        self.rawJSON = rawJSON
        self.enrichmentStatus = enrichmentStatus
    }
}
