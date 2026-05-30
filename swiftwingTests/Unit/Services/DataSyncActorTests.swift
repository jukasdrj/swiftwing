import SwiftData
import Testing
@testable import swiftwing

@Suite("DataSyncActor")
@MainActor
struct DataSyncActorTests {
    private func makeContext() throws -> ModelContext {
        try makeSwiftDataContext()
    }

    private func makePendingBook(
        title: String?,
        author: String?,
        isbn: String?,
        preScannedISBN: String? = nil,
        confidence: Double? = 0.95,
        publishedDate: String? = nil,
        rawJSON: String? = nil
    ) -> PendingBookResult {
        let metadata = BookMetadata(
            title: title,
            author: author,
            isbn: isbn,
            publishedDate: publishedDate,
            confidence: confidence,
            enrichmentStatus: .success
        )

        return PendingBookResult(
            metadata: metadata,
            rawJSON: rawJSON,
            preScannedISBN: preScannedISBN
        )
    }

    @Test
    func saveInsertsResolvedBook() throws {
        let context = try makeContext()
        let pending = makePendingBook(
            title: "Effective Swift",
            author: "Mattt Thompson",
            isbn: "9781491927288",
            publishedDate: "2016-01-01",
            rawJSON: #"{"title":"Effective Swift"}"#
        )

        let saved = try DataSyncActor.shared.save(book: pending, in: context)

        #expect(saved)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)

        let book = try #require(books.first)
        #expect(book.title == "Effective Swift")
        #expect(book.author == "Mattt Thompson")
        #expect(book.isbn == "9781491927288")
        #expect(book.rawJSON == #"{"title":"Effective Swift"}"#)
        #expect(book.spineConfidence == 0.95)
        #expect(book.enrichmentStatus == EnrichmentStatus.success.rawValue)
        #expect(book.publishedDate != nil)
    }

    @Test
    func saveSkipsDuplicateISBN() throws {
        let context = try makeContext()
        let existing = makePendingBook(
            title: "First Copy",
            author: "Author",
            isbn: "9780000000001"
        )
        let duplicate = makePendingBook(
            title: "Second Copy",
            author: "Different Author",
            isbn: "9780000000001"
        )

        let firstSaved = try DataSyncActor.shared.save(book: existing, in: context)
        let secondSaved = try DataSyncActor.shared.save(book: duplicate, in: context)

        #expect(firstSaved)
        #expect(secondSaved == false)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)
        #expect(books.first?.title == "First Copy")
    }

    @Test
    func saveAllPersistsOnlyUniqueBooks() throws {
        let context = try makeContext()
        let booksToSave = [
            makePendingBook(title: "Book 1", author: "Author 1", isbn: "9780000000010"),
            makePendingBook(title: "Book 2", author: "Author 2", isbn: "9780000000020"),
            makePendingBook(title: "Duplicate", author: "Author 3", isbn: "9780000000010"),
        ]

        let savedCount = try DataSyncActor.shared.saveAll(books: booksToSave, in: context)

        #expect(savedCount == 2)

        let savedBooks = try context.fetch(FetchDescriptor<Book>())
        #expect(savedBooks.count == 2)
        #expect(savedBooks.map(\.isbn).sorted() == ["9780000000010", "9780000000020"])
    }

    @Test
    func saveUsesFallbackISBNWhenMetadataISBNMissing() throws {
        let context = try makeContext()
        let pending = makePendingBook(
            title: nil,
            author: nil,
            isbn: nil,
            preScannedISBN: "9780306406157"
        )

        let saved = try DataSyncActor.shared.save(book: pending, in: context)

        #expect(saved)

        let book = try #require(try context.fetch(FetchDescriptor<Book>()).first)
        #expect(book.title == "Unknown Title")
        #expect(book.author == "Unknown Author")
        #expect(book.isbn == "9780306406157")
    }
}
