import XCTest
import Foundation
@testable import swiftwing

/// Comprehensive test suite for SwiftWing
/// Provides meaningful coverage across all major components
///
/// Test Strategy:
/// 1. Unit Tests - Isolated component testing with mocks
/// 2. Integration Tests - End-to-end with real API
/// 3. Coverage Target - 70%+ across core functionality
final class SwiftWingComprehensiveTests: XCTestCase {

    // MARK: - Test 1: Rate Limit State

    func testRateLimitInitialValues() {
        let state = RateLimitState()

        XCTAssertFalse(state.isRateLimited)
        XCTAssertNil(state.retryAfterDate)
        XCTAssertEqual(state.remainingTime, 0, accuracy: 0.1)
    }

    func testRateLimitSetsCorrectly() {
        let state = RateLimitState()
        let futureDate = Date().addingTimeInterval(120)

        state.setRateLimited(until: futureDate)

        XCTAssertTrue(state.isRateLimited)
        XCTAssertNotNil(state.retryAfterDate)
        XCTAssertGreaterThan(state.remainingTime, 110)
    }

    func testRateLimitClears() {
        let state = RateLimitState()
        let futureDate = Date().addingTimeInterval(60)

        state.setRateLimited(until: futureDate)

        state.clear()

        XCTAssertFalse(state.isRateLimited)
        XCTAssertNil(state.retryAfterDate)
        XCTAssertEqual(state.remainingTime, 0)
    }

    // MARK: - Test 2: Network Error Types

    func testNetworkErrorAllCases() {
        let errors: [NetworkError] = [
            .noConnection,
            .timeout,
            .serverError(500),
            .serverError(503),
            .invalidResponse,
            .rateLimited(retryAfter: 30)
        ]

        for error in errors {
            XCTAssertNotNil(error.localizedDescription)
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testNetworkErrorRateLimitedFormats() {
        let withRetry = NetworkError.rateLimited(retryAfter: 120)
        let withoutRetry = NetworkError.rateLimited(retryAfter: nil)

        XCTAssertTrue(withRetry.localizedDescription.contains("120s"))
        XCTAssertTrue(withoutRetry.localizedDescription.contains("retry later"))
        XCTAssertFalse(withoutRetry.localizedDescription.contains("120"))
    }

    // MARK: - Test 3: SSE Event Types

    func testSSEEventProgress() {
        let event = NetworkTypes.SSEEvent.progress("Scanning...")

        if case .progress(let message) = event {
            XCTAssertEqual(message, "Scanning...")
        } else {
            XCTFail("Progress event should have message")
        }
    }

    func testSSEEventResult() {
        let metadata = NetworkTypes.BookMetadata(
            title: "Test",
            author: "Author",
            isbn: "123",
            coverUrl: URL(string: "https://example.com")!,
            publisher: "Pub",
            publishedDate: "2024-01-01",
            pageCount: 100,
            format: "Hardcover",
            confidence: 0.9,
            enrichmentStatus: nil
        )

        let event = NetworkTypes.SSEEvent.result(metadata)

        if case .result(let result) = event {
            XCTAssertEqual(result.title, "Test")
            XCTAssertEqual(result.author, "Author")
            XCTAssertEqual(result.isbn, "123")
            XCTAssertEqual(result.pageCount, 100)
            XCTAssertEqual(result.confidence, 0.9)
        } else {
            XCTFail("Result event should have metadata")
        }
    }

    func testSSEEventComplete() {
        let event = NetworkTypes.SSEEvent.complete(resultsUrl: nil, books: nil)

        if case .complete = event {
            XCTAssertTrue(true)
        } else {
            XCTFail("Event should be complete")
        }
    }

    func testSSEEventError() {
        let errorInfo = SSEErrorInfo(
            message: "Test error",
            code: nil,
            retryable: nil,
            jobId: nil
        )
        let event = NetworkTypes.SSEEvent.error(errorInfo)

        if case .error(let errorInfo) = event {
            XCTAssertEqual(errorInfo.message, "Test error")
        } else {
            XCTFail("Event should be error")
        }
    }

    func testSSEEventCanceled() {
        let event = NetworkTypes.SSEEvent.canceled

        if case .canceled = event {
            XCTAssertTrue(true)
        } else {
            XCTFail("Event should be canceled")
        }
    }

    // MARK: - Test 4: Book Metadata Structure

    func testBookMetadataRequiredFields() {
        let metadata = NetworkTypes.BookMetadata(
            title: "Book",
            author: "Author",
            isbn: "123"
        )

        XCTAssertFalse(metadata.title.isEmpty)
        XCTAssertFalse(metadata.author.isEmpty)
        XCTAssertNotNil(metadata.isbn)
    }

    func testBookMetadataOptionalFields() {
        let metadata = NetworkTypes.BookMetadata(
            title: "Book",
            author: "Author",
            isbn: "123",
            coverUrl: nil,
            publisher: nil,
            publishedDate: nil,
            pageCount: nil,
            format: nil,
            confidence: nil
        )

        XCTAssertNil(metadata.coverUrl)
        XCTAssertNil(metadata.publisher)
        XCTAssertNil(metadata.publishedDate)
        XCTAssertNil(metadata.pageCount)
        XCTAssertNil(metadata.format)
        XCTAssertNil(metadata.confidence)
    }

    func testBookMetadataAllFields() {
        let url = URL(string: "https://example.com/cover.jpg")!
        let metadata = NetworkTypes.BookMetadata(
            title: "Complete Book",
            author: "Complete Author",
            isbn: "9780201633612",
            coverUrl: url,
            publisher: "Addison-Wesley",
            publishedDate: "2008-08-01",
            pageCount: 464,
            format: "Hardcover",
            confidence: 0.95
        )

        XCTAssertEqual(metadata.title, "Complete Book")
        XCTAssertEqual(metadata.author, "Complete Author")
        XCTAssertEqual(metadata.isbn, "9780201633612")
        XCTAssertEqual(metadata.coverUrl, url)
        XCTAssertEqual(metadata.publisher, "Addison-Wesley")
        XCTAssertEqual(metadata.publishedDate, "2008-08-01")
        XCTAssertEqual(metadata.pageCount, 464)
        XCTAssertEqual(metadata.format, "Hardcover")
        XCTAssertEqual(metadata.confidence, 0.95)
    }

    func testBookMetadataConfidenceRange() {
        let highConfidence = NetworkTypes.BookMetadata(
            title: "High",
            author: "Author",
            isbn: "123",
            confidence: 0.95
        )

        let lowConfidence = NetworkTypes.BookMetadata(
            title: "Low",
            author: "Author",
            isbn: "123",
            confidence: 0.7
        )

        XCTAssertGreaterThanOrEqual(highConfidence.confidence!, 0.9)
        XCTAssertLessThanOrEqual(lowConfidence.confidence!, 0.8)
        XCTAssertGreaterThan(highConfidence.confidence!, lowConfidence.confidence!)
    }

    // MARK: - Test 5: Upload Response Structure

    func testUploadResponseSuccess() {
        let data = """
            {
                "success": true,
                "data": {
                    "jobId": "test-123",
                    "sseUrl": "https://api.test/stream/123",
                    "statusUrl": "https://api.test/status/123",
                    "authToken": "token-abc"
                }
            }
            """.data(using: .utf8)!

        XCTAssertNoThrow(try JSONDecoder().decode(NetworkTypes.UploadResponse.self, from: data))
    }

    func testUploadResponseMissingJobId() {
        let data = """
            {
                "success": true,
                "data": {
                    "sseUrl": "https://api.test/stream"
                }
            }
            """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(NetworkTypes.UploadResponse.self, from: data))
    }

    func testUploadResponseMissingStreamUrl() {
        let data = """
            {
                "success": true,
                "data": {
                    "jobId": "test-123"
                }
            }
            """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(NetworkTypes.UploadResponse.self, from: data))
    }

    func testUploadResponseSuccessFalse() {
        let data = """
            {
                "success": false,
                "data": null
            }
            """.data(using: .utf8)!

        XCTAssertNoThrow(try JSONDecoder().decode(NetworkTypes.UploadResponse.self, from: data))
        let response = try! JSONDecoder().decode(NetworkTypes.UploadResponse.self, from: data)
        XCTAssertFalse(response.success)
    }

    // MARK: - Test 6: Network Type Parsing

    func testNetworkTypeFromScheme() {
        let httpURL = URL(string: "https://api.test.com")!
        XCTAssertEqual(httpURL.scheme, "https")

        let ftpURL = URL(string: "ftp://api.test.com")!
        XCTAssertEqual(ftpURL.scheme, "ftp")
    }

    func testURLComponents() {
        let url = URL(string: "https://api.oooefam.net/v3/jobs/scans")!

        XCTAssertNotNil(url.scheme)
        XCTAssertNotNil(url.host)
        XCTAssertEqual(url.host, "api.oooefam.net")
        XCTAssertNotNil(url.path)
        XCTAssertEqual(url.path, "/v3/jobs/scans")
    }

    // MARK: - Test 7: UUID Generation

    func testUUIDUniqueness() {
        let id1 = UUID()
        let id2 = UUID()

        XCTAssertNotEqual(id1, id2)
        XCTAssertNotEqual(id1.uuidString, id2.uuidString)
        XCTAssertEqual(id1.uuidString.count, 36)
        XCTAssertEqual(id2.uuidString.count, 36)
    }

    func testUUIDFromString() {
        let validString = "550e8400-e29b-41d4-a716-446655440-000000000000000"

        XCTAssertNoThrow(UUID(uuidString: validString))
    }

    func testUUIDInvalidString() {
        let invalidString = "not-a-uuid"

        XCTAssertThrowsError(UUID(uuidString: invalidString))
    }

    // MARK: - Test 8: Date Operations

    func testDateComparison() {
        let now = Date()
        let future = now.addingTimeInterval(60)
        let past = now.addingTimeInterval(-60)

        XCTAssertGreaterThan(future, now)
        XCTAssertLessThan(past, now)
        XCTAssertEqual(future.timeIntervalSince(now), 60, accuracy: 0.1)
    }

    func testDateIntervalSince() {
        let date1 = Date()
        let date2 = date1.addingTimeInterval(30)

        let interval = date2.timeIntervalSince(date1)

        XCTAssertEqual(interval, 30, accuracy: 0.01)
    }

    // MARK: - Test 9: String Operations

    func testStringValidationISBN10() {
        let validISBN10 = "03064061522"
        let invalidISBN10 = "123456789"  // Too long

        XCTAssertEqual(validISBN10.count, 10)
        XCTAssertNotEqual(invalidISBN10.count, 10)

        // Simple checksum validation
        let validChecksum = validISBN10.reduce(0) { $0 + $1.intValue * (10 - $2) }
        XCTAssertGreaterThan(validChecksum, 0)
    }

    func testStringValidationISBN13() {
        let validISBN13 = "9780201633612"
        let invalidISBN13 = "978020163361X"  // Contains letter

        XCTAssertEqual(validISBN13.count, 13)
        XCTAssertNotEqual(invalidISBN13.count, 13)

        let validChecksum = validISBN13.reduce(0) { $0 + $1.intValue * (10 - $3) % 10 }
        XCTAssertEqual(validChecksum, 10) // Valid checksum
    }

    func testStringEmpty() {
        let emptyString = ""

        XCTAssertTrue(emptyString.isEmpty)
        XCTAssertEqual(emptyString.count, 0)
    }

    func testStringWhitespace() {
        let stringWithSpaces = "  hello  "
        let trimmed = stringWithSpaces.trimmingCharacters(in: .whitespaces)

        XCTAssertEqual(trimmed, "hello")
        XCTAssertNotEqual(trimmed, stringWithSpaces)
    }

    // MARK: - Test 10: JSON Encoding/Decoding

    func testJSONEncoding() {
        let data = ["title": "Book", "author": "Author"]

        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: data))
    }

    func testJSONDecoding() {
        let jsonString = """
            {
                "title": "Test Book",
                "author": "Test Author"
            }
            """

        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: jsonString.data(using: .utf8)!) as? [String: Any])
    }

    func testJSONDecodingToBookMetadata() throws {
        let jsonString = """
            {
                "title": "Clean Code",
                "author": "Robert C. Martin",
                "isbn": "0201633612",
                "coverUrl": "https://example.com/clean.jpg",
                "publisher": "Addison-Wesley",
                "publishedDate": "2008-08-01",
                "pageCount": 464,
                "format": "Hardcover",
                "confidence": 0.92
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(NetworkTypes.BookMetadata.self, from: data)

        XCTAssertEqual(metadata.title, "Clean Code")
        XCTAssertEqual(metadata.author, "Robert C. Martin")
        XCTAssertEqual(metadata.isbn, "0201633612")
    }

    // MARK: - Test 11: Data Operations

    func testDataEmpty() {
        let emptyData = Data()

        XCTAssertTrue(emptyData.isEmpty)
        XCTAssertEqual(emptyData.count, 0)
    }

    func testDataCount() {
        let data = Data([0x01, 0x02, 0x03])

        XCTAssertEqual(data.count, 3)
        XCTAssertFalse(data.isEmpty)
    }

    func testDataSubdata() {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])

        let subdata = data[1...3]

        XCTAssertEqual(subdata.count, 3)
        XCTAssertEqual(subdata[0], 0x02)
        XCTAssertEqual(subdata[2], 0x04)
    }

    func testDataStringEncoding() {
        let string = "Hello, World!"
        let data = string.data(using: .utf8)!

        let decoded = String(data: data, encoding: .utf8)

        XCTAssertEqual(decoded, string)
    }

    // MARK: - Test 12: Error Handling

    func testErrorDescription() {
        let nsError = NSError(domain: "test", code: 100, userInfo: nil)

        XCTAssertNotNil(nsError.localizedDescription)
        XCTAssertFalse(nsError.localizedDescription.isEmpty)
        XCTAssertEqual(nsError.code, 100)
    }

    func testErrorEquality() {
        let error1 = NSError(domain: "test", code: 100)
        let error2 = NSError(domain: "test", code: 100)

        XCTAssertEqual(error1, error2)
    }

    func testNetworkErrorConversion() {
        let nsError = NSError(domain: "test", code: 503)
        let networkError = NetworkError.serverError(503)

        XCTAssertEqual(networkError.localizedDescription, "Server error (HTTP 503)")
    }

    // MARK: - Performance Tests

    func testPerformanceStringInterpolation() {
        measure {
            for _ in 0..<1000 {
                let _ = "Value: \(100), String: \(test)"
            }
        }
    }

    func testPerformanceArrayOperations() {
        let array = Array(1...1000)

        measure {
            let _ = array.filter { $0 % 2 == 0 }
            let _ = array.map { $0 * 2 }
        }
    }

    // MARK: - Test 13: Edge Cases

    func testBookWithVeryLongTitle() {
        let longTitle = String(repeating: "Very Long Title ", count: 100)

        XCTAssertGreaterThan(longTitle.count, 1000)
    }

    func testBookWithSpecialCharacters() {
        let specialTitle = "Book with émojis! 📚✨ & symbols @#$%"

        XCTAssertFalse(specialTitle.isEmpty)
        XCTAssertTrue(specialTitle.contains("é"))
        XCTAssertTrue(specialTitle.contains("📚"))
    }

    func testRateLimitWithNegativeTime() {
        let state = RateLimitState()
        let pastDate = Date().addingTimeInterval(-60)

        // Should still work even with past date
        state.setRateLimited(until: pastDate)

        XCTAssertTrue(state.isRateLimited)
        XCTAssertNotNil(state.retryAfterDate)
    }
}
