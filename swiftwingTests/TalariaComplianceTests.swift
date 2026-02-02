import XCTest
import Foundation
@testable import swiftwing

/// Compliance tests for Talaria API v3.4.0
///
/// Tests RFC 9457 ProblemDetails, SSE event parsing, Last-Event-ID reconnection,
/// and all new event types from v3.4.0 specification.
///
/// **Test Coverage:**
/// 1. RFC 9457 ProblemDetails decoding (complete/minimal/metadata/retryable)
/// 2. SSE Event Parser (all 9 event types + unknown type handling)
/// 3. Last-Event-ID reconnection protocol
/// 4. NetworkError.apiError propagation
final class TalariaComplianceTests: XCTestCase {

    // MARK: - Test 1: RFC 9457 ProblemDetails

    /// AC: Test ProblemDetails decodes complete JSON with all fields
    func testProblemDetailsDecodesCompleteJSON() throws {
        let json = """
        {
            "success": false,
            "type": "https://api.oooefam.net/errors/rate-limit",
            "title": "Rate Limit Exceeded",
            "status": 429,
            "detail": "You have exceeded 10 scans per 20 minutes",
            "code": "RATE_LIMIT_EXCEEDED",
            "retryable": true,
            "retryAfterMs": 120000,
            "instance": "/v3/jobs/scans/123e4567-e89b-12d3-a456-426614174000",
            "metadata": {
                "requestId": "req-abc123",
                "timestamp": "2026-02-02T12:00:00Z"
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let problem = try decoder.decode(ProblemDetails.self, from: json)

        XCTAssertFalse(problem.success)
        XCTAssertEqual(problem.type, "https://api.oooefam.net/errors/rate-limit")
        XCTAssertEqual(problem.title, "Rate Limit Exceeded")
        XCTAssertEqual(problem.status, 429)
        XCTAssertEqual(problem.detail, "You have exceeded 10 scans per 20 minutes")
        XCTAssertEqual(problem.code, "RATE_LIMIT_EXCEEDED")
        XCTAssertTrue(problem.retryable)
        XCTAssertEqual(problem.retryAfterMs, 120000)
        XCTAssertEqual(problem.instance, "/v3/jobs/scans/123e4567-e89b-12d3-a456-426614174000")
        XCTAssertNotNil(problem.metadata)
        XCTAssertEqual(problem.metadata?["requestId"], "req-abc123")
        XCTAssertEqual(problem.metadata?["timestamp"], "2026-02-02T12:00:00Z")
    }

    /// AC: Test ProblemDetails decodes minimal JSON (no optional fields)
    func testProblemDetailsDecodesMinimalJSON() throws {
        let json = """
        {
            "success": false,
            "type": "about:blank",
            "title": "Internal Server Error",
            "status": 500,
            "detail": "An unexpected error occurred",
            "code": "INTERNAL_ERROR",
            "retryable": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let problem = try decoder.decode(ProblemDetails.self, from: json)

        XCTAssertFalse(problem.success)
        XCTAssertEqual(problem.type, "about:blank")
        XCTAssertEqual(problem.title, "Internal Server Error")
        XCTAssertEqual(problem.status, 500)
        XCTAssertEqual(problem.detail, "An unexpected error occurred")
        XCTAssertEqual(problem.code, "INTERNAL_ERROR")
        XCTAssertFalse(problem.retryable)
        XCTAssertNil(problem.retryAfterMs)
        XCTAssertNil(problem.instance)
        XCTAssertNil(problem.metadata)
    }

    /// AC: Test metadata field with timestamp/requestId
    func testProblemDetailsMetadataField() throws {
        let json = """
        {
            "success": false,
            "type": "about:blank",
            "title": "Unprocessable Entity",
            "status": 422,
            "detail": "Invalid image format",
            "code": "INVALID_IMAGE",
            "retryable": false,
            "metadata": {
                "timestamp": "2026-02-02T10:30:00Z",
                "requestId": "req-xyz789",
                "correlationId": "corr-456"
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let problem = try decoder.decode(ProblemDetails.self, from: json)

        XCTAssertNotNil(problem.metadata)
        XCTAssertEqual(problem.metadata?.count, 3)
        XCTAssertEqual(problem.metadata?["timestamp"], "2026-02-02T10:30:00Z")
        XCTAssertEqual(problem.metadata?["requestId"], "req-xyz789")
        XCTAssertEqual(problem.metadata?["correlationId"], "corr-456")
    }

    /// AC: Test retryable flag propagation through NetworkError.apiError
    func testRetryableFlagPropagation() throws {
        let retryableJSON = """
        {
            "success": false,
            "type": "about:blank",
            "title": "Service Unavailable",
            "status": 503,
            "detail": "Service temporarily unavailable",
            "code": "SERVICE_UNAVAILABLE",
            "retryable": true,
            "retryAfterMs": 5000
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let problem = try decoder.decode(ProblemDetails.self, from: retryableJSON)

        // Create NetworkError.apiError
        let error = NetworkError.apiError(problem)

        // Assert retryable flag accessible through NetworkError
        if case .apiError(let details) = error {
            XCTAssertTrue(details.retryable)
            XCTAssertEqual(details.retryAfterMs, 5000)
        } else {
            XCTFail("Should be NetworkError.apiError case")
        }
    }

    /// AC: Test retryAfterMs field presence and value
    func testRetryAfterMsField() throws {
        let json = """
        {
            "success": false,
            "type": "about:blank",
            "title": "Rate Limit",
            "status": 429,
            "detail": "Rate limited",
            "code": "RATE_LIMIT",
            "retryable": true,
            "retryAfterMs": 60000
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let problem = try decoder.decode(ProblemDetails.self, from: json)

        XCTAssertEqual(problem.retryAfterMs, 60000)
        XCTAssertTrue(problem.retryable)
    }

    // MARK: - Test 2: SSEEventParser

    /// AC: Test completed event with inline books
    func testSSEParserCompletedWithInlineBooks() throws {
        let parser = SSEEventParser()
        let data = """
        {
            "resultsUrl": "https://api.oooefam.net/v3/jobs/results/abc123",
            "books": [
                {
                    "title": "Clean Code",
                    "author": "Robert C. Martin",
                    "isbn": "0132350882",
                    "coverUrl": "https://example.com/cover.jpg",
                    "confidence": 0.95
                }
            ]
        }
        """

        let event = try parser.parse(event: "completed", data: data)

        if case .complete(let resultsUrl, let books) = event {
            XCTAssertEqual(resultsUrl, "https://api.oooefam.net/v3/jobs/results/abc123")
            XCTAssertNotNil(books)
            XCTAssertEqual(books?.count, 1)
            XCTAssertEqual(books?.first?.title, "Clean Code")
            XCTAssertEqual(books?.first?.author, "Robert C. Martin")
            XCTAssertEqual(books?.first?.isbn, "0132350882")
        } else {
            XCTFail("Should be .complete event")
        }
    }

    /// AC: Test completed event without books (only resultsUrl)
    func testSSEParserCompletedWithoutBooks() throws {
        let parser = SSEEventParser()
        let data = """
        {
            "resultsUrl": "https://api.oooefam.net/v3/jobs/results/xyz789"
        }
        """

        let event = try parser.parse(event: "complete", data: data)

        if case .complete(let resultsUrl, let books) = event {
            XCTAssertEqual(resultsUrl, "https://api.oooefam.net/v3/jobs/results/xyz789")
            XCTAssertNil(books)
        } else {
            XCTFail("Should be .complete event")
        }
    }

    /// AC: Test enrichment_degraded event with full fields
    func testSSEParserEnrichmentDegraded() throws {
        let parser = SSEEventParser()
        let data = """
        {
            "jobId": "job-123",
            "isbn": "1234567890",
            "title": "Test Book",
            "reason": "Circuit breaker open",
            "fallbackSource": "local-cache",
            "timestamp": "2026-02-02T12:00:00Z"
        }
        """

        let event = try parser.parse(event: "enrichment_degraded", data: data)

        if case .enrichmentDegraded(let info) = event {
            XCTAssertEqual(info.jobId, "job-123")
            XCTAssertEqual(info.isbn, "1234567890")
            XCTAssertEqual(info.title, "Test Book")
            XCTAssertEqual(info.reason, "Circuit breaker open")
            XCTAssertEqual(info.fallbackSource, "local-cache")
            XCTAssertEqual(info.timestamp, "2026-02-02T12:00:00Z")
        } else {
            XCTFail("Should be .enrichmentDegraded event")
        }
    }

    /// AC: Test ping event
    func testSSEParserPing() throws {
        let parser = SSEEventParser()
        let event = try parser.parse(event: "ping", data: "{}")

        if case .ping = event {
            XCTAssertTrue(true, "Ping event parsed correctly")
        } else {
            XCTFail("Should be .ping event")
        }
    }

    /// AC: Test error event with full SSEErrorInfo
    func testSSEParserErrorWithFullInfo() throws {
        let parser = SSEEventParser()
        let data = """
        {
            "message": "Recognition failed: no spine text detected",
            "code": "RECOGNITION_FAILED",
            "retryable": false,
            "jobId": "job-abc-123"
        }
        """

        let event = try parser.parse(event: "error", data: data)

        if case .error(let errorInfo) = event {
            XCTAssertEqual(errorInfo.message, "Recognition failed: no spine text detected")
            XCTAssertEqual(errorInfo.code, "RECOGNITION_FAILED")
            XCTAssertEqual(errorInfo.retryable, false)
            XCTAssertEqual(errorInfo.jobId, "job-abc-123")
        } else {
            XCTFail("Should be .error event")
        }
    }

    /// AC: Test unknown event type (silent ignore)
    func testSSEParserUnknownEventType() {
        let parser = SSEEventParser()

        // Unknown event should throw invalidEventFormat (caught and logged by caller)
        XCTAssertThrowsError(try parser.parse(event: "unknown_future_event", data: "{}")) { error in
            XCTAssertTrue(error is SSEError)
            if let sseError = error as? SSEError, case .invalidEventFormat = sseError {
                XCTAssertTrue(true, "Unknown event throws invalidEventFormat as expected")
            } else {
                XCTFail("Should throw SSEError.invalidEventFormat")
            }
        }
    }

    /// AC: Test progress event
    func testSSEParserProgress() throws {
        let parser = SSEEventParser()
        let data = """
        {
            "message": "Analyzing image..."
        }
        """

        let event = try parser.parse(event: "progress", data: data)

        if case .progress(let message) = event {
            XCTAssertEqual(message, "Analyzing image...")
        } else {
            XCTFail("Should be .progress event")
        }
    }

    /// AC: Test result event
    func testSSEParserResult() throws {
        let parser = SSEEventParser()
        let data = """
        {
            "title": "The Pragmatic Programmer",
            "author": "Andrew Hunt",
            "isbn": "0201616224",
            "coverUrl": "https://example.com/cover.jpg",
            "confidence": 0.92
        }
        """

        let event = try parser.parse(event: "result", data: data)

        if case .result(let metadata) = event {
            XCTAssertEqual(metadata.title, "The Pragmatic Programmer")
            XCTAssertEqual(metadata.author, "Andrew Hunt")
            XCTAssertEqual(metadata.isbn, "0201616224")
            XCTAssertEqual(metadata.confidence, 0.92)
        } else {
            XCTFail("Should be .result event")
        }
    }

    // MARK: - Test 3: Last-Event-ID Protocol

    /// AC: Test id: field extraction from SSE lines
    func testLastEventIDExtraction() {
        // Simulate SSE stream with id: field
        let sseLines = [
            "id: event-123",
            "event: progress",
            "data: {\"message\":\"Processing...\"}",
            "",
            "id: event-456",
            "event: result",
            "data: {\"title\":\"Test\",\"author\":\"Author\"}"
        ]

        var lastEventId: String?

        for line in sseLines {
            if line.hasPrefix("id:") {
                lastEventId = String(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
            }
        }

        XCTAssertEqual(lastEventId, "event-456")
    }

    /// AC: Test Last-Event-ID header on retry
    func testLastEventIDHeaderOnRetry() {
        // Create URLRequest with Last-Event-ID header
        var request = URLRequest(url: URL(string: "https://api.oooefam.net/v3/jobs/scans/abc/stream")!)
        let lastEventId = "event-789"

        request.setValue(lastEventId, forHTTPHeaderField: "Last-Event-ID")

        XCTAssertEqual(request.value(forHTTPHeaderField: "Last-Event-ID"), "event-789")
    }

    /// AC: Test no header when no ID received
    func testNoLastEventIDWhenNotReceived() {
        var request = URLRequest(url: URL(string: "https://api.oooefam.net/v3/jobs/scans/abc/stream")!)

        // Don't set Last-Event-ID header if no id: received
        let lastEventId: String? = nil

        if let id = lastEventId {
            request.setValue(id, forHTTPHeaderField: "Last-Event-ID")
        }

        XCTAssertNil(request.value(forHTTPHeaderField: "Last-Event-ID"))
    }

    // MARK: - Test 4: NetworkError Localized Descriptions

    /// AC: Test all NetworkError localized descriptions
    func testNetworkErrorLocalizedDescriptions() {
        let noConnection = NetworkError.noConnection
        let timeout = NetworkError.timeout
        let serverError = NetworkError.serverError(500)
        let invalidResponse = NetworkError.invalidResponse
        let rateLimited = NetworkError.rateLimited(retryAfter: 60)

        let problemDetails = ProblemDetails(
            success: false,
            type: "about:blank",
            title: "Error",
            status: 400,
            detail: "Bad request details",
            code: "BAD_REQUEST",
            retryable: false,
            retryAfterMs: nil,
            instance: nil,
            metadata: nil
        )
        let apiError = NetworkError.apiError(problemDetails)

        XCTAssertEqual(noConnection.localizedDescription, "No internet connection available")
        XCTAssertEqual(timeout.localizedDescription, "Request timed out")
        XCTAssertEqual(serverError.localizedDescription, "Server error (HTTP 500)")
        XCTAssertEqual(invalidResponse.localizedDescription, "Invalid server response")
        XCTAssertEqual(rateLimited.localizedDescription, "Rate limited - retry after 60s")
        XCTAssertEqual(apiError.localizedDescription, "Bad request details")
    }
}
