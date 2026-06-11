import Testing
import Foundation
import SwiftData
@testable import swiftwing

@Suite("DuplicateDetection")
@MainActor
struct DuplicateDetectionTests {

    private func makeContext() throws -> ModelContext {
        try makeSwiftDataContext()
    }

    @Test func findDuplicateReturnsNilWhenEmpty() throws {
        let context = try makeContext()
        let result = try DuplicateDetection.findDuplicate(isbn: "9780000000000", in: context)
        #expect(result == nil)
    }

    @Test func findDuplicateReturnsBookWhenExists() throws {
        let context = try makeContext()
        let book = Book(title: "Test", author: "Author", isbn: "9780000000001")
        context.insert(book)
        try context.save()

        let result = try #require(try DuplicateDetection.findDuplicate(isbn: "9780000000001", in: context))
        #expect(result.title == "Test")
    }

    @Test func findDuplicateReturnsNilForDifferentISBN() throws {
        let context = try makeContext()
        let book = Book(title: "Test", author: "Author", isbn: "9780000000001")
        context.insert(book)
        try context.save()

        let result = try DuplicateDetection.findDuplicate(isbn: "9780000000002", in: context)
        #expect(result == nil)
    }

    @Test func findDuplicateMatchesExactISBN() throws {
        let context = try makeContext()
        let book1 = Book(title: "Book One", author: "Author A", isbn: "9780000000010")
        let book2 = Book(title: "Book Two", author: "Author B", isbn: "9780000000020")
        context.insert(book1)
        context.insert(book2)
        try context.save()

        let result = try #require(try DuplicateDetection.findDuplicate(isbn: "9780000000010", in: context))
        #expect(result.title == "Book One")

        let result2 = try #require(try DuplicateDetection.findDuplicate(isbn: "9780000000020", in: context))
        #expect(result2.title == "Book Two")
    }

    // MARK: - Error Path Tests

    @Test func findDuplicate_collisionPath_detectedSuccessfully() throws {
        let context = try makeContext()
        let existingBook = Book(title: "Existing Book", author: "Author", isbn: "9780000000099")
        context.insert(existingBook)
        try context.save()

        // Attempt to find the same ISBN that exists in the database
        let duplicateISBN = "9780000000099"
        let result = try DuplicateDetection.findDuplicate(isbn: duplicateISBN, in: context)

        // Should detect collision and return the existing book
        #expect(result != nil)
        #expect(result?.title == "Existing Book")
    }

    // MARK: - Fallback Matching Tests (ISBN-less books via title+author)

    @Test func findDuplicate_fallbackMatch_twoScansOfSameISBNlessBook() throws {
        let context = try makeContext()
        let uuid1 = UUID()
        let book = Book(title: "Dune Messiah", author: "Frank Herbert", isbn: "UNKNOWN-\(uuid1.uuidString)")
        context.insert(book)
        try context.save()

        let uuid2 = UUID()
        let result = try DuplicateDetection.findDuplicate(
            isbn: "UNKNOWN-\(uuid2.uuidString)",
            title: "Dune Messiah",
            author: "Frank Herbert",
            in: context
        )

        #expect(result != nil)
        #expect(result?.title == "Dune Messiah")
        #expect(result?.author == "Frank Herbert")
    }

    @Test func findDuplicate_fallbackMatch_differentISBNlessBooks() throws {
        let context = try makeContext()
        let uuid1 = UUID()
        let book = Book(title: "Dune Messiah", author: "Frank Herbert", isbn: "UNKNOWN-\(uuid1.uuidString)")
        context.insert(book)
        try context.save()

        let uuid2 = UUID()
        let result = try DuplicateDetection.findDuplicate(
            isbn: "UNKNOWN-\(uuid2.uuidString)",
            title: "Foundation",
            author: "Isaac Asimov",
            in: context
        )

        #expect(result == nil)
    }

    @Test func findDuplicate_isbnTakesPrecedence_sameNormalizedTitleButDifferentISBN() throws {
        let context = try makeContext()
        let sameTitle = Book(title: "Dune Messiah", author: "Frank Herbert", isbn: "9780000000001")
        context.insert(sameTitle)
        try context.save()

        // Query with real ISBN (not UNKNOWN), which doesn't match
        let result = try DuplicateDetection.findDuplicate(
            isbn: "9780000000002",
            title: "Dune Messiah",
            author: "Frank Herbert",
            in: context
        )

        // Should return nil because real ISBN doesn't match (no fallback for real ISBN)
        #expect(result == nil)
    }

    @Test func findDuplicate_normalization_caseDifference() throws {
        let context = try makeContext()
        let book = Book(title: "Dune Messiah", author: "Frank Herbert", isbn: "UNKNOWN-uuid1")
        context.insert(book)
        try context.save()

        let result = try DuplicateDetection.findDuplicate(
            isbn: "UNKNOWN-uuid2",
            title: "DUNE messiah",
            author: "frank herbert",
            in: context
        )

        #expect(result != nil)
        #expect(result?.title == "Dune Messiah")
    }

    @Test func findDuplicate_normalization_whitespace() throws {
        let context = try makeContext()
        let book = Book(title: "Dune Messiah", author: "Frank Herbert", isbn: "UNKNOWN-uuid1")
        context.insert(book)
        try context.save()

        let result = try DuplicateDetection.findDuplicate(
            isbn: "UNKNOWN-uuid2",
            title: "  Dune   Messiah ",
            author: " Frank   Herbert ",
            in: context
        )

        #expect(result != nil)
        #expect(result?.title == "Dune Messiah")
    }

    @Test func findDuplicate_normalization_diacritics() throws {
        let context = try makeContext()
        let book = Book(title: "Émile Zola", author: "French Author", isbn: "UNKNOWN-uuid1")
        context.insert(book)
        try context.save()

        let result = try DuplicateDetection.findDuplicate(
            isbn: "UNKNOWN-uuid2",
            title: "Emile Zola",
            author: "French Author",
            in: context
        )

        #expect(result != nil)
        #expect(result?.title == "Émile Zola")
    }

    @Test func findDuplicate_fallbackMatch_emptyTitleOrAuthor() throws {
        let context = try makeContext()
        let book = Book(title: "Dune Messiah", author: "Frank Herbert", isbn: "UNKNOWN-uuid1")
        context.insert(book)
        try context.save()

        // Empty title should not match
        let resultEmptyTitle = try DuplicateDetection.findDuplicate(
            isbn: "UNKNOWN-uuid2",
            title: "",
            author: "Frank Herbert",
            in: context
        )
        #expect(resultEmptyTitle == nil)

        // Empty author should not match
        let resultEmptyAuthor = try DuplicateDetection.findDuplicate(
            isbn: "UNKNOWN-uuid3",
            title: "Dune Messiah",
            author: "",
            in: context
        )
        #expect(resultEmptyAuthor == nil)
    }

    // Note: The fetchFailed error path in DuplicateDetection requires a genuine
    // SwiftData fetch failure, which cannot be reliably triggered with an
    // in-memory ModelContext in unit tests. The error path is covered by
    // code inspection and the DuplicateDetectionError type having a
    // descriptive errorDescription.
}
