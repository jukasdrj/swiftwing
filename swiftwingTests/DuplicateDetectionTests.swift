import Testing
import SwiftData
@testable import swiftwing

@Suite("DuplicateDetection")
@MainActor
struct DuplicateDetectionTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, configurations: config)
        return container.mainContext
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

    @Test func findDuplicate_fetchErrorPath_throwsDuplicateDetectionError() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Book.self, configurations: config)
        let context = container.mainContext

        // Create a closed context to trigger a fetch error
        try! context.save()
        context.delete(context)  // This invalidates the context

        // Attempting to fetch with an invalid context should throw DuplicateDetectionError.fetchFailed
        #expect(throws: DuplicateDetection.DuplicateDetectionError.fetchFailed) {
            _ = try DuplicateDetection.findDuplicate(isbn: "9780000000001", in: context)
        }
    }
}
