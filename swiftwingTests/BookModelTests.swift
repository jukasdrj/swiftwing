import Foundation
import Testing
@testable import swiftwing

/// Unit tests for Book SwiftData model
@Suite("BookModel")
struct BookModelTests {

    @Test func bookInitializationWithAllFields() {
        let book = Book(
            title: "Test Book",
            author: "Test Author",
            isbn: "1234567890",
            coverUrl: URL(string: "https://example.com/cover.jpg"),
            format: "Hardcover",
            publisher: "Test Publisher",
            publishedDate: Date(),
            pageCount: 250,
            spineConfidence: 0.95
        )

        #expect(book.title == "Test Book")
        #expect(book.author == "Test Author")
        #expect(book.isbn == "1234567890")
        #expect(book.coverUrl != nil)
        #expect(book.format == "Hardcover")
        #expect(book.pageCount == 250)
        #expect(book.spineConfidence == 0.95)
        #expect(book.readingStatus == nil)
        #expect(book.userRating == nil)
        #expect(book.notes == nil)
        #expect(book.needsReview == false)
    }

    @Test func bookInitializationWithMinimalFields() {
        let book = Book(
            title: "Minimal Book",
            author: "Author",
            isbn: "09876543210"
        )

        #expect(book.title == "Minimal Book")
        #expect(book.author == "Author")
        #expect(book.isbn == "09876543210")
        #expect(book.coverUrl == nil)
        #expect(book.format == nil)
        #expect(book.publisher == nil)
        #expect(book.publishedDate == nil)
        #expect(book.pageCount == nil)
        #expect(book.spineConfidence == nil)
        #expect(book.needsReview == false)
    }

    @Test(arguments: [
        (0.95, false, "High confidence"),
        (0.8, false, "Boundary high"),
        (0.79, true, "Just below threshold"),
        (0.7, true, "Low confidence"),
        (0.5, true, "Medium-low confidence"),
        (0.0, true, "Zero confidence"),
    ])
    func confidenceReviewThreshold(confidence: Double, expectsReview: Bool, label: String) {
        let book = Book(title: "Book", author: "Author", isbn: "1234567890", spineConfidence: confidence)
        #expect(book.needsReview == expectsReview, "\(label): confidence \(confidence) should \(expectsReview ? "" : "not ")need review")
    }

    @Test func nilConfidenceDefaultsToNoReview() {
        let book = Book(title: "Book", author: "Author", isbn: "1234567890", spineConfidence: nil)
        #expect(book.needsReview == false, "Nil confidence should default to 1.0 (no review)")
    }

    @Test(arguments: [ReadingStatus.toRead, .reading, .completed, .dnf])
    func readingStatusValues(status: ReadingStatus) {
        let book = Book(title: "Book", author: "Author", isbn: "1234567890", readingStatus: status)
        #expect(book.readingStatus == status)
    }

    @Test func readingStatusWithAllFields() {
        let book = Book(
            title: "Completed Book",
            author: "Author",
            isbn: "1234567890",
            readingStatus: .completed,
            dateRead: Date(),
            userRating: 5,
            notes: "Great book!"
        )
        #expect(book.readingStatus == .completed)
        #expect(book.dateRead != nil)
        #expect(book.userRating == 5)
        #expect(book.notes == "Great book!")
    }

    @Test func uniqueUUIDForEachBook() {
        let book1 = Book(title: "Book 1", author: "Author", isbn: "1111111111")
        let book2 = Book(title: "Book 2", author: "Author", isbn: "2222222222")
        #expect(book1.id != book2.id)
    }

    @Test func specialCharactersInTitle() {
        let book = Book(title: "Book with émojis! 📚✨", author: "Author", isbn: "1234567890")
        #expect(book.title == "Book with émojis! 📚✨")
    }
}
