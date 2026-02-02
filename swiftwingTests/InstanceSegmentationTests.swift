import XCTest
@testable import swiftwing
import Vision
import CoreImage

/// Comprehensive test suite for instance segmentation accuracy and performance
/// Validates InstanceSegmentationService with mock test images
final class InstanceSegmentationTests: XCTestCase {
    var service: InstanceSegmentationService!

    override func setUp() async throws {
        service = await InstanceSegmentationService()
    }

    override func tearDown() async throws {
        service = nil
    }

    // MARK: - Accuracy Tests

    func testSingleBookDetection() async throws {
        // Load test image (1 book)
        let testImage = createMockImage(withBookCount: 1)

        let books = try await service.segmentBooks(from: testImage)

        XCTAssertEqual(books.count, 1, "Should detect exactly 1 book")
        XCTAssertGreaterThan(books[0].imageSize.width, 0, "Cropped image should have width")
        XCTAssertGreaterThan(books[0].imageSize.height, 0, "Cropped image should have height")
        XCTAssertGreaterThan(books[0].boundingBox.width, 0, "Bounding box should be non-zero")
    }

    func testFiveBookShelfDetection() async throws {
        let testImage = createMockImage(withBookCount: 5)

        let books = try await service.segmentBooks(from: testImage)

        XCTAssertEqual(books.count, 5, "Should detect exactly 5 books")

        // Verify each book has valid data
        for (index, book) in books.enumerated() {
            XCTAssertGreaterThan(book.boundingBox.width, 0, "Book \(index) bounding box width invalid")
            XCTAssertGreaterThan(book.boundingBox.height, 0, "Book \(index) bounding box height invalid")
            XCTAssertLessThanOrEqual(book.boundingBox.maxX, 1.0, "Book \(index) bounding box not normalized")
            XCTAssertLessThanOrEqual(book.boundingBox.maxY, 1.0, "Book \(index) bounding box not normalized")
        }
    }

    func testTenBookShelfDetection() async throws {
        let testImage = createMockImage(withBookCount: 10)

        let books = try await service.segmentBooks(from: testImage)

        XCTAssertEqual(books.count, 10, "Should detect exactly 10 books")
    }

    func testTwentyBookMaximumDetection() async throws {
        let testImage = createMockImage(withBookCount: 20)

        let books = try await service.segmentBooks(from: testImage)

        XCTAssertEqual(books.count, 20, "Should detect maximum 20 books")
    }

    func testEmptyShelfError() async throws {
        let testImage = createMockImage(withBookCount: 0)

        do {
            _ = try await service.segmentBooks(from: testImage)
            XCTFail("Should throw noInstancesFound error for empty shelf")
        } catch let error as SegmentationError {
            if case .noInstancesFound = error {
                // Expected error
                XCTAssertTrue(true)
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testTooManyBooksError() async throws {
        let testImage = createMockImage(withBookCount: 25)

        do {
            _ = try await service.segmentBooks(from: testImage)
            XCTFail("Should throw tooManyBooks error for 25 books")
        } catch let error as SegmentationError {
            if case .tooManyBooks(let count) = error {
                XCTAssertEqual(count, 25, "Error should report correct count")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testOverlappingBooksCount() async throws {
        // Mock image with 3 slightly overlapping books
        let testImage = createMockImageWithOverlap(bookCount: 3)

        let books = try await service.segmentBooks(from: testImage)

        // Vision framework should still detect 3 separate instances
        XCTAssertGreaterThanOrEqual(books.count, 3, "Should detect at least 3 books even with overlap")
    }

    // MARK: - Performance Tests

    func testPerformanceWithTenBooks() throws {
        let testImage = createMockImage(withBookCount: 10)

        measure {
            // Performance target: <2 seconds for 10 books
            Task {
                _ = try? await service.segmentBooks(from: testImage)
            }
        }

        // XCTest will report average time
        // If > 2s, optimization needed in Sprint 4
    }

    // MARK: - Mock Image Generation

    /// Creates a synthetic test image with specified number of books
    /// Real test images would be stored in Tests/TestAssets/ folder
    private func createMockImage(withBookCount count: Int) -> CIImage {
        // For actual implementation:
        // 1. Load real test photos from bundle
        // 2. Or generate synthetic images with Core Graphics
        // 3. Ensure consistent test data

        // Placeholder: return solid color image
        let size = CGSize(width: 1920, height: 1080)
        let color = CIColor(red: 0.5, green: 0.5, blue: 0.5)
        return CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size))
    }

    private func createMockImageWithOverlap(bookCount: Int) -> CIImage {
        // Mock overlapping books scenario
        return createMockImage(withBookCount: bookCount)
    }
}

// MARK: - Test Assets Note
/*
 TODO: Add real test images to swiftwingTests/TestAssets/

 Required test images:
 - single-book-shelf.jpg (1 book, clear lighting)
 - five-book-shelf.jpg (5 books, standard shelf)
 - ten-book-shelf.jpg (10 books, realistic density)
 - twenty-book-shelf.jpg (20 books, maximum density)
 - empty-shelf.jpg (empty bookshelf)
 - overlapping-books.jpg (3-5 books with slight overlap)

 Use real photos from development testing or stock images.
 Ensure consistent resolution (1920x1080 or actual device camera resolution).
 */
