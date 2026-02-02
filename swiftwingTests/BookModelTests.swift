import XCTest
@testable import swiftwing

/// Unit tests for Book SwiftData model
/// Tests data model validation, persistence, and business logic
final class BookModelTests: XCTestCase {

    // MARK: - Properties

    func testBookInitializationWithAllFields() {
        // Arrange
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

        // Assert
        XCTAssertEqual(book.title, "Test Book")
        XCTAssertEqual(book.author, "Test Author")
        XCTAssertEqual(book.isbn, "1234567890")
        XCTAssertNotNil(book.coverUrl)
        XCTAssertEqual(book.format, "Hardcover")
        XCTAssertEqual(book.pageCount, 250)
        XCTAssertEqual(book.spineConfidence, 0.95, accuracy: 0.001)
        XCTAssertEqual(book.readingStatus, nil)
        XCTAssertEqual(book.userRating, nil)
        XCTAssertEqual(book.notes, nil)
        XCTAssertEqual(book.needsReview, false)
    }

    func testBookInitializationWithMinimalFields() {
        // Arrange
        let book = Book(
            title: "Minimal Book",
            author: "Author",
            isbn: "09876543210"
        )

        // Assert
        XCTAssertEqual(book.title, "Minimal Book")
        XCTAssertEqual(book.author, "Author")
        XCTAssertEqual(book.isbn, "09876543210")
        XCTAssertNil(book.coverUrl)
        XCTAssertNil(book.format)
        XCTAssertNil(book.publisher)
        XCTAssertNil(book.publishedDate)
        XCTAssertNil(book.pageCount)
        XCTAssertNil(book.spineConfidence)
        XCTAssertFalse(book.needsReview)
    }

    // MARK: - ISBN Validation

    func testISBN10Validation() {
        // Valid ISBN-10
        let book = Book(
            title: "Book",
            author: "Author",
            isbn: "03064061522",  // Valid ISBN-10
            spineConfidence: 0.9
        )

        XCTAssertNotNil(book.isbn)
        XCTAssertFalse(book.needsReview, accuracy: 0.1)
    }

    func testISBN13Validation() {
        // Valid ISBN-13
        let book = Book(
            title: "Book",
            author: "Author",
            isbn: "9780306406157",  // Valid ISBN-13
            spineConfidence: 0.85
        )

        XCTAssertNotNil(book.isbn)
        XCTAssertFalse(book.needsReview, accuracy: 0.1)
    }

    func testLowConfidenceTriggersReviewNeeded() {
        // Arrange
        let book = Book(
            title: "Low Confidence Book",
            author: "Author",
            isbn: "1234567890",
            spineConfidence: 0.7  // Below 0.8 threshold
        )

        // Assert
        XCTAssertTrue(book.needsReview, "Low confidence should trigger review needed")
    }

    func testHighConfidenceNoReviewNeeded() {
        // Arrange
        let book = Book(
            title: "High Confidence Book",
            author: "Author",
            isbn: "1234567890",
            spineConfidence: 0.95  // Above 0.8 threshold
        )

        // Assert
        XCTAssertFalse(book.needsReview, "High confidence should not trigger review")
    }

    func testNilConfidenceDefaultsToReviewNeeded() {
        // Arrange
        let book = Book(
            title: "No Confidence Book",
            author: "Author",
            isbn: "1234567890",
            spineConfidence: nil  // Should default to 1.0, triggering review
        )

        // Assert
        XCTAssertTrue(book.needsReview, "Nil confidence should default to review needed")
    }

    // MARK: - Reading Status

    func testReadingStatusValues() {
        // Test all reading status values
        let statuses: [String] = ["to_read", "reading", "completed", "did_not_finish"]

        for status in statuses {
            let book = Book(
                title: "Book",
                author: "Author",
                isbn: "1234567890",
                readingStatus: status
            )

            XCTAssertEqual(book.readingStatus, status)
        }
    }

    func testReadingStatusWithAllFields() {
        // Arrange
        let book = Book(
            title: "Completed Book",
            author: "Author",
            isbn: "1234567890",
            readingStatus: "completed",
            dateRead: Date(),
            userRating: 5,
            notes: "Great book!"
        )

        // Assert
        XCTAssertEqual(book.readingStatus, "completed")
        XCTAssertNotNil(book.dateRead)
        XCTAssertEqual(book.userRating, 5)
        XCTAssertEqual(book.notes, "Great book!")
    }

    // MARK: - UUID Generation

    func testUniqueUUIDForEachBook() {
        // Arrange
        let book1 = Book(title: "Book 1", author: "Author", isbn: "1111111111")
        let book2 = Book(title: "Book 2", author: "Author", isbn: "2222222222")

        // Assert
        XCTAssertNotEqual(book1.id, book2.id, "Each book should have unique UUID")
    }

    // MARK: - Edge Cases

    func testEmptyTitleIsValid() {
        // Arrange - Empty title should be allowed
        let book = Book(
            title: "",
            author: "Author",
            isbn: "1234567890"
        )

        XCTAssertEqual(book.title, "")
        // Empty title doesn't mean invalid, just not useful
    }

    func testLongISBN() {
        // Arrange - Longer than standard ISBN (should still work)
        let longISBN = String(repeating: "1", count: 20)

        let book = Book(
            title: "Book",
            author: "Author",
            isbn: longISBN
        )

        XCTAssertEqual(book.isbn, longISBN)
    }

    func testSpecialCharactersInTitle() {
        // Arrange
        let book = Book(
            title: "Book with émojis! 📚✨",
            author: "Author",
            isbn: "1234567890"
        )

        XCTAssertEqual(book.title, "Book with émojis! 📚✨")
    }
}
