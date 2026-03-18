import Foundation
import SwiftData

/// Schema versioning for Book model
/// Enables safe, incremental model evolution without data loss

// MARK: - V1 Schema (frozen snapshot of original Book model)

enum BookSchemaV1: VersionedSchema {
    static let versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [BookV1.self]
    }

    /// Frozen snapshot of the original Book model at V1.
    /// Never modify this — it represents the on-disk schema for V1 users.
    @Model
    final class BookV1 {
        #Index<BookV1>([\.isbn], [\.addedDate])

        @Attribute(.unique) var isbn: String
        var id: UUID
        var title: String
        var author: String

        var coverUrl: URL?
        var format: String?
        var publisher: String?
        var publishedDate: Date?
        var pageCount: Int?

        var spineConfidence: Double?
        var addedDate: Date

        // V1: readingStatus stored as raw String
        var readingStatus: String?
        var dateRead: Date?
        var userRating: Int?

        var notes: String?
        var rawJSON: String?
        var enrichmentStatus: String?

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
}

// MARK: - V2 Schema (current — readingStatus typed as enum, added indexes)

enum BookSchemaV2: VersionedSchema {
    static let versionIdentifier: Schema.Version = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Book.self]
    }
}

// MARK: - Migration Plan

enum BookMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BookSchemaV1.self, BookSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// V1 → V2: readingStatus String? remains String? in storage.
    /// The type change to ReadingStatus? is handled at the Swift level only —
    /// SwiftData stores the enum's rawValue (String) on disk, so the on-disk
    /// format is identical. A lightweight migration is sufficient.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: BookSchemaV1.self,
        toVersion: BookSchemaV2.self
    )
}
