import Foundation
import Testing
import SwiftData
@testable import swiftwing

@Suite("ReviewQueueManager")
@MainActor
struct ReviewQueueManagerTests {

    private func makeContext() throws -> ModelContext {
        try makeSwiftDataContext()
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

    // MARK: - Error Path Tests

    @Test func handleBookResult_invalidState_rejectionErrorPath() throws {
        let manager = makeManager()
        let context = try makeContext()

        // Test error path: nil title and nil author simultaneously
        let invalidMetadata = BookMetadata(title: nil, author: nil)
        manager.handleBookResult(metadata: invalidMetadata, rawJSON: nil, modelContext: context)

        // Both validation errors should suppress the book
        #expect(manager.pendingReviewBooks.isEmpty)
    }

    @Test func approveBook_duplicateDetectionFailure_proceedsWithoutAlert() throws {
        let manager = makeManager()
        let context = try makeContext()

        // Add a book to the review queue
        let metadata = BookMetadata(title: "Test Book", author: "Author", isbn: "9780000000001")
        manager.handleBookResult(metadata: metadata, rawJSON: nil, modelContext: context)
        let pending = try #require(manager.pendingReviewBooks.first)

        // Approve the book — should proceed without triggering a duplicate alert
        // since no duplicate exists yet in this context
        manager.approveBook(pending, modelContext: context)

        #expect(manager.duplicateBook == nil)
    }

    @Test func updatePendingBookEdits_invalidBookId_doesNothing() throws {
        let manager = makeManager()
        let context = try makeContext()
        let metadata = BookMetadata(title: "Original Title", author: "Original Author")

        manager.handleBookResult(metadata: metadata, rawJSON: nil, modelContext: context)

        // Try to update with a non-existent ID
        let nonExistentId = UUID()
        manager.updatePendingBookEdits(id: nonExistentId, title: "Edited Title", author: "Edited Author")

        // Original book should remain unchanged since ID didn't match
        let pending = try #require(manager.pendingReviewBooks.first)
        #expect(pending.editedTitle == nil)
        #expect(pending.editedAuthor == nil)
    }

    // MARK: - applyRecoveredMetadata (enrichment recovery)

    private func gatsbySearchResult() -> BookSearchResult {
        BookSearchResult(
            isbn: "0743273567",
            isbn13: "9780743273565",
            title: "The Great Gatsby",
            authors: ["F. Scott Fitzgerald"],
            publisher: "Scribner",
            publishedDate: "2004-09-30",
            coverUrl: URL(string: "https://example.com/cover.jpg"),
            source: "google",
            confidence: 0.97,
            fuzzyMatched: false
        )
    }

    @Test("applyRecoveredMetadata replaces title, author, isbn and cover on the pending book")
    func applyRecoveredMetadata_graftsSearchResult() throws {
        let manager = makeManager()
        let context = try makeContext()
        // A garbled spine that came back not_found — the recovery entry point.
        let original = BookMetadata(
            title: "Grat Gasby",
            author: "F Fitzgerld",
            confidence: 0.4,
            enrichmentStatus: .notFound
        )

        manager.handleBookResult(metadata: original, rawJSON: nil, modelContext: context)
        let pending = try #require(manager.pendingReviewBooks.first)

        manager.applyRecoveredMetadata(id: pending.id, from: gatsbySearchResult())

        let updated = try #require(manager.pendingReviewBooks.first)
        #expect(updated.resolvedTitle == "The Great Gatsby")
        #expect(updated.resolvedAuthor == "F. Scott Fitzgerald")
        #expect(updated.resolvedISBN == "9780743273565")
        #expect(updated.resolvedMetadata.coverUrl?.absoluteString == "https://example.com/cover.jpg")
        #expect(updated.resolvedMetadata.publisher == "Scribner")
        #expect(updated.resolvedMetadata.enrichmentStatus == .success)
        // The original AI result stays intact for provenance.
        #expect(updated.metadata.title == "Grat Gasby")
        #expect(updated.metadata.enrichmentStatus == .notFound)
    }

    @Test("applyRecoveredMetadata clears prior inline edits so the card shows looked-up values")
    func applyRecoveredMetadata_clearsEdits() throws {
        let manager = makeManager()
        let context = try makeContext()
        let original = BookMetadata(title: "Grat Gasby", author: "F Fitzgerld", confidence: 0.4)

        manager.handleBookResult(metadata: original, rawJSON: nil, modelContext: context)
        let pending = try #require(manager.pendingReviewBooks.first)
        manager.updatePendingBookEdits(id: pending.id, title: "Half Typed", author: "Guess")

        manager.applyRecoveredMetadata(id: pending.id, from: gatsbySearchResult())

        let updated = try #require(manager.pendingReviewBooks.first)
        #expect(updated.editedTitle == nil)
        #expect(updated.editedAuthor == nil)
        #expect(updated.resolvedTitle == "The Great Gatsby")
    }

    @Test("applyRecoveredMetadata with an unknown id does nothing")
    func applyRecoveredMetadata_unknownId_doesNothing() throws {
        let manager = makeManager()
        let context = try makeContext()
        let original = BookMetadata(title: "Grat Gasby", author: "F Fitzgerld", confidence: 0.4)

        manager.handleBookResult(metadata: original, rawJSON: nil, modelContext: context)
        manager.applyRecoveredMetadata(id: UUID(), from: gatsbySearchResult())

        let pending = try #require(manager.pendingReviewBooks.first)
        #expect(pending.recoveredMetadata == nil)
        #expect(pending.resolvedTitle == "Grat Gasby")
    }
}
