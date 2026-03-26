import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "data-sync")

/// Centralises all SwiftData write operations for book persistence.
///
/// ModelContext and DuplicateDetection are both @MainActor-bound, so the public
/// methods are @MainActor. @MainActor callers invoke them synchronously without
/// crossing actor boundaries.
@MainActor
final class DataSyncActor {

    // MARK: - Shared instance

    static let shared = DataSyncActor()

    private init() {}

    // MARK: - Insert

    /// Insert a pending book result into the store, skipping duplicates.
    /// Returns true if the book was saved, false if it was a duplicate.
    @discardableResult
    func save(book: PendingBookResult, in context: ModelContext) throws -> Bool {
        let isbn = book.resolvedISBN

        if let existing = try DuplicateDetection.findDuplicate(isbn: isbn, in: context) {
            logger.info("DataSyncActor: skipping duplicate '\(book.resolvedTitle, privacy: .public)' (isbn: \(existing.isbn, privacy: .public))")
            return false
        }

        context.insert(makeBook(from: book))
        try context.save()
        logger.info("DataSyncActor: saved '\(book.resolvedTitle, privacy: .public)'")
        return true
    }

    /// Insert multiple pending book results, skipping any duplicates.
    /// Returns the count of books actually saved.
    @discardableResult
    func saveAll(books: [PendingBookResult], in context: ModelContext) throws -> Int {
        var saved = 0

        for book in books {
            let isbn = book.resolvedISBN
            if (try? DuplicateDetection.findDuplicate(isbn: isbn, in: context)) != nil {
                logger.info("DataSyncActor: skipping duplicate '\(book.resolvedTitle, privacy: .public)'")
                continue
            }
            context.insert(makeBook(from: book))
            saved += 1
        }

        if saved > 0 {
            try context.save()
        }

        logger.info("DataSyncActor: saveAll — saved \(saved, privacy: .public) of \(books.count, privacy: .public)")
        return saved
    }

    // MARK: - Private helpers

    private func makeBook(from pending: PendingBookResult) -> Book {
        let publishedDate: Date?
        if let dateString = pending.metadata.publishedDate {
            publishedDate = ISO8601DateFormatter().date(from: dateString)
        } else {
            publishedDate = nil
        }

        return Book(
            title: pending.resolvedTitle,
            author: pending.resolvedAuthor,
            isbn: pending.resolvedISBN,
            coverUrl: pending.metadata.coverUrl,
            format: pending.metadata.format,
            publisher: pending.metadata.publisher,
            publishedDate: publishedDate,
            pageCount: pending.metadata.pageCount,
            spineConfidence: pending.metadata.confidence,
            addedDate: Date(),
            rawJSON: pending.rawJSON,
            enrichmentStatus: pending.metadata.enrichmentStatus?.rawValue
        )
    }
}
