import Foundation
import SwiftData

@Model
final class Book {
    @Attribute(.unique) var isbn: String
    var id: UUID
    var title: String
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

    // Debug/raw data
    var rawJSON: String?

    // Computed property for review threshold
    var needsReview: Bool {
        spineConfidence ?? 1.0 < 0.8
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
        rawJSON: String? = nil
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
        self.rawJSON = rawJSON
    }
}
