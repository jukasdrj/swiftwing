import Testing
import SwiftData
@testable import swiftwing

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
}
