import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "duplicate")

/// Utility for detecting duplicate books in the library
/// US-311: Duplicate Detection Warning
@MainActor
enum DuplicateDetection {
    /// Error types for duplicate detection
    enum DuplicateDetectionError: LocalizedError {
        case fetchFailed(Error)

        var errorDescription: String? {
            switch self {
            case .fetchFailed(let error):
                return "Failed to check for duplicate books: \(error.localizedDescription)"
            }
        }
    }

    /// Normalize a string for comparison: trim whitespace, case-insensitive, diacritic-insensitive
    static func normalizeForComparison(_ text: String) -> String {
        let folded = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return folded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Checks if a book with the given ISBN already exists in the library
    /// Falls back to title+author matching for ISBN-less books (UNKNOWN-prefixed ISBNs)
    /// - Parameters:
    ///   - isbn: The ISBN to check (optional, nil or UNKNOWN- triggers fallback to title+author)
    ///   - title: The book title (used for fallback matching)
    ///   - author: The book author (used for fallback matching)
    ///   - context: SwiftData model context
    /// - Returns: The existing Book if found, nil otherwise
    /// - Throws: DuplicateDetectionError if the database query fails
    static func findDuplicate(isbn: String?, title: String, author: String, in context: ModelContext) throws -> Book? {
        // Fast path: if isbn is non-nil and doesn't start with UNKNOWN-, try exact match
        if let isbn = isbn, !isbn.hasPrefix("UNKNOWN-") {
            let predicate = #Predicate<Book> { book in
                book.isbn == isbn
            }

            var descriptor = FetchDescriptor<Book>(predicate: predicate)
            descriptor.fetchLimit = 1

            do {
                let results = try context.fetch(descriptor)
                return results.first
            } catch {
                logger.error("Duplicate detection failed: \(error.localizedDescription, privacy: .public)")
                throw DuplicateDetectionError.fetchFailed(error)
            }
        }

        // Fallback path: normalize title+author and search in-memory
        let normalizedTitle = normalizeForComparison(title)
        let normalizedAuthor = normalizeForComparison(author)

        // Guard against empty normalized values
        guard !normalizedTitle.isEmpty && !normalizedAuthor.isEmpty else {
            return nil
        }

        // Fetch all books (no predicate because we can't use custom functions in #Predicate)
        let descriptor = FetchDescriptor<Book>()

        do {
            let allBooks = try context.fetch(descriptor)
            // Find first match by normalized title and author
            return allBooks.first { book in
                normalizeForComparison(book.title) == normalizedTitle &&
                normalizeForComparison(book.author) == normalizedAuthor
            }
        } catch {
            logger.error("Duplicate detection failed: \(error.localizedDescription, privacy: .public)")
            throw DuplicateDetectionError.fetchFailed(error)
        }
    }

    /// Legacy overload: Checks if a book with the given ISBN already exists in the library
    /// - Parameters:
    ///   - isbn: The ISBN to check
    ///   - context: SwiftData model context
    /// - Returns: The existing Book if found, nil otherwise
    /// - Throws: DuplicateDetectionError if the database query fails
    static func findDuplicate(isbn: String, in context: ModelContext) throws -> Book? {
        return try findDuplicate(isbn: isbn, title: "", author: "", in: context)
    }
}
