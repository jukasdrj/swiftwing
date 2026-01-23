import Foundation
import SwiftData

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

    /// Checks if a book with the given ISBN already exists in the library
    /// - Parameters:
    ///   - isbn: The ISBN to check
    ///   - context: SwiftData model context
    /// - Returns: The existing Book if found, nil otherwise
    /// - Throws: DuplicateDetectionError if the database query fails
    static func findDuplicate(isbn: String, in context: ModelContext) throws -> Book? {
        let predicate = #Predicate<Book> { book in
            book.isbn == isbn
        }

        let descriptor = FetchDescriptor<Book>(predicate: predicate)

        do {
            let results = try context.fetch(descriptor)
            return results.first
        } catch {
            print("❌ Duplicate detection failed: \(error)")
            throw DuplicateDetectionError.fetchFailed(error)
        }
    }
}
