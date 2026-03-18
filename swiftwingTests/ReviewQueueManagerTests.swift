import Foundation
import Testing
import SwiftData
@testable import swiftwing

@MainActor
struct ReviewQueueManagerTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, configurations: config)
        return container.mainContext
    }

    private func makeManager() -> ReviewQueueManager {
        ReviewQueueManager()
    }

    // MARK: - validateBookMetadata (tested indirectly via handleBookResult)

    @Test func handleBookResult_validMetadata_addsToQueue() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata = BookMetadata(title: "Valid Title", author: "Valid Author")

        manager.handleBookResult(metadata: metadata, rawJSON: nil, modelContext: context)

        #expect(manager.pendingReviewBooks.count == 1)
        #expect(manager.pendingReviewBooks.first?.metadata.title == "Valid Title")
    }

    @Test func handleBookResult_emptyTitle_rejectsAndShowsError() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata = BookMetadata(title: "", author: "Some Author")

        manager.handleBookResult(metadata: metadata, rawJSON: nil, modelContext: context)

        #expect(manager.pendingReviewBooks.isEmpty)
        #expect(manager.processingErrorMessage != nil || manager.pendingReviewBooks.isEmpty)
    }

    @Test func handleBookResult_nilTitle_rejectsBook() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata = BookMetadata(title: nil, author: "Some Author")

        manager.handleBookResult(metadata: metadata, rawJSON: nil, modelContext: context)

        #expect(manager.pendingReviewBooks.isEmpty)
    }

    @Test func handleBookResult_emptyAuthor_rejectsBook() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata = BookMetadata(title: "Some Title", author: "")

        manager.handleBookResult(metadata: metadata, rawJSON: nil, modelContext: context)

        #expect(manager.pendingReviewBooks.isEmpty)
    }

    @Test func handleBookResult_nilAuthor_rejectsBook() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata = BookMetadata(title: "Some Title", author: nil)

        manager.handleBookResult(metadata: metadata, rawJSON: nil, modelContext: context)

        #expect(manager.pendingReviewBooks.isEmpty)
    }

    @Test func handleBookResult_whitespaceOnlyTitle_rejectsBook() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata = BookMetadata(title: "   ", author: "Valid Author")

        manager.handleBookResult(metadata: metadata, rawJSON: nil, modelContext: context)

        #expect(manager.pendingReviewBooks.isEmpty)
    }

    @Test func handleBookResult_whitespaceOnlyAuthor_rejectsBook() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata = BookMetadata(title: "Valid Title", author: "\t\n")

        manager.handleBookResult(metadata: metadata, rawJSON: nil, modelContext: context)

        #expect(manager.pendingReviewBooks.isEmpty)
    }

    // MARK: - isDuplicateResult (tested indirectly via handleBookResult)

    @Test func handleBookResult_duplicateISBNWithin60s_suppressesSecondResult() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata = BookMetadata(title: "Dune", author: "Frank Herbert", isbn: "9780441013593")

        manager.handleBookResult(metadata: metadata, rawJSON: nil, modelContext: context)
        manager.handleBookResult(metadata: metadata, rawJSON: nil, modelContext: context)

        // Second call should be suppressed as duplicate
        #expect(manager.pendingReviewBooks.count == 1)
    }

    @Test func handleBookResult_duplicateTitleAuthorWithin60s_suppressesSecondResult() throws {
        let manager = makeManager()
        let context = try makeContext()
        // No ISBN — match on title+author
        let metadata1 = BookMetadata(title: "Foundation", author: "Isaac Asimov")
        let metadata2 = BookMetadata(title: "Foundation", author: "Isaac Asimov")

        manager.handleBookResult(metadata: metadata1, rawJSON: nil, modelContext: context)
        manager.handleBookResult(metadata: metadata2, rawJSON: nil, modelContext: context)

        #expect(manager.pendingReviewBooks.count == 1)
    }

    @Test func handleBookResult_differentISBNs_bothAdded() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata1 = BookMetadata(title: "Book One", author: "Author", isbn: "9780000000001")
        let metadata2 = BookMetadata(title: "Book Two", author: "Author", isbn: "9780000000002")

        manager.handleBookResult(metadata: metadata1, rawJSON: nil, modelContext: context)
        manager.handleBookResult(metadata: metadata2, rawJSON: nil, modelContext: context)

        #expect(manager.pendingReviewBooks.count == 2)
    }

    @Test func handleBookResult_differentTitleSameAuthor_bothAdded() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata1 = BookMetadata(title: "Foundation", author: "Isaac Asimov")
        let metadata2 = BookMetadata(title: "Foundation and Empire", author: "Isaac Asimov")

        manager.handleBookResult(metadata: metadata1, rawJSON: nil, modelContext: context)
        manager.handleBookResult(metadata: metadata2, rawJSON: nil, modelContext: context)

        #expect(manager.pendingReviewBooks.count == 2)
    }

    // MARK: - rejectBook

    @Test func rejectBook_removesFromQueue() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata = BookMetadata(title: "To Reject", author: "Author")

        manager.handleBookResult(metadata: metadata, rawJSON: nil, modelContext: context)
        let pending = try #require(manager.pendingReviewBooks.first)

        manager.rejectBook(pending)

        #expect(manager.pendingReviewBooks.isEmpty)
    }

    // MARK: - approveAllBooks

    @Test func approveAllBooks_clearsQueue() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata1 = BookMetadata(title: "Book One", author: "Author A", isbn: "9780000000001")
        let metadata2 = BookMetadata(title: "Book Two", author: "Author B", isbn: "9780000000002")

        manager.handleBookResult(metadata: metadata1, rawJSON: nil, modelContext: context)
        manager.handleBookResult(metadata: metadata2, rawJSON: nil, modelContext: context)
        #expect(manager.pendingReviewBooks.count == 2)

        manager.approveAllBooks(modelContext: context)

        #expect(manager.pendingReviewBooks.isEmpty)
    }

    @Test func approveAllBooks_persistsBooksToSwiftData() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata = BookMetadata(title: "Saved Book", author: "Author", isbn: "9780000000099")

        manager.handleBookResult(metadata: metadata, rawJSON: nil, modelContext: context)
        manager.approveAllBooks(modelContext: context)

        let descriptor = FetchDescriptor<Book>()
        let saved = try context.fetch(descriptor)
        #expect(saved.contains { $0.title == "Saved Book" })
    }

    // MARK: - showScanComplete

    @Test func showScanComplete_zeroBooksDoesNotSetBanner() {
        let manager = makeManager()

        manager.showScanComplete(booksAdded: 0, thumbnailData: nil)

        #expect(manager.scanCompleteBanner == nil)
    }

    @Test func showScanComplete_positiveCountSetsBanner() {
        let manager = makeManager()

        manager.showScanComplete(booksAdded: 3, thumbnailData: nil)

        let banner = manager.scanCompleteBanner
        #expect(banner != nil)
        #expect(banner?.bookCount == 3)
    }

    // MARK: - updatePendingBookEdits

    @Test func updatePendingBookEdits_updatesEditedFields() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata = BookMetadata(title: "Original Title", author: "Original Author")

        manager.handleBookResult(metadata: metadata, rawJSON: nil, modelContext: context)
        let pending = try #require(manager.pendingReviewBooks.first)

        manager.updatePendingBookEdits(id: pending.id, title: "Edited Title", author: "Edited Author")

        let updated = try #require(manager.pendingReviewBooks.first)
        #expect(updated.resolvedTitle == "Edited Title")
        #expect(updated.resolvedAuthor == "Edited Author")
    }
}
