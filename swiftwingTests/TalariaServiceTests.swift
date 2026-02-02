import XCTest
import Foundation
@testable import swiftwing

/// Unit tests for TalariaService with mocked network
/// Tests service logic without hitting real API
final class TalariaServiceTests: XCTestCase {

    // MARK: - Properties

    var mockSession: MockURLSession!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        mockSession = MockURLSession()
        mockSession.uploadDelay = 0.01  // 10ms latency
        mockSession.streamDelay = 0.01
    }

    override func tearDown() async throws {
        mockSession = nil
        try await super.tearDown()
    }

    // MARK: - Test 1: Upload Returns Valid Response

    func testUploadReturnsJobIdAndStreamUrl() async throws {
        // Arrange
        let testImage = createTestImageData()
        let service = TalariaService(session: mockSession, deviceId: "test-device")

        // Mock successful upload response
        let uploadResponse = """
            {
                "success": true,
                "data": {
                    "jobId": "test-job-123",
                    "sseUrl": "https://api.oooefam.net/v3/jobs/scans/test-job-123/stream",
                    "statusUrl": "https://api.oooefam.net/v3/jobs/scans/test-job-123/status",
                    "authToken": "test-token-123"
                }
            }
            """.data(using: .utf8)!

        mockSession.mockUploadResponse(data: uploadResponse, for: "https://api.oooefam.net/v3/jobs/scans")

        // Act
        let (jobId, streamUrl, authToken) = try await service.uploadScan(image: testImage, deviceId: "test-device")

        // Assert
        XCTAssertEqual(jobId, "test-job-123")
        XCTAssertEqual(streamUrl.absoluteString, "https://api.oooefam.net/v3/jobs/scans/test-job-123/stream")
        XCTAssertEqual(authToken, "test-token-123")
    }

    // MARK: - Test 2: Upload Error Handling

    func testUploadThrowsOnNetworkError() async throws {
        // Arrange
        let testImage = createTestImageData()
        let service = TalariaService(session: mockSession, deviceId: "test-device")
        let networkError = NSError(domain: "test", code: -1, userInfo: nil)

        mockSession.mockUploadError(networkError, for: "https://api.oooefam.net/v3/jobs/scans")

        // Act & Assert
        await XCTAssertThrowsError(service.uploadScan(image: testImage, deviceId: "test-device")) { error in
            XCTAssertTrue(error.localizedDescription.contains("network"))
        }
    }

    // MARK: - Test 3: SSE Streaming - All Event Types

    func testSSEStreamReturnsAllEventTypes() async throws {
        // Arrange
        let testImage = createTestImageData()
        let service = TalariaService(session: mockSession, deviceId: "test-device")

        // Mock upload response first
        let uploadResponse = """
            {
                "success": true,
                "data": {
                    "jobId": "test-job-events",
                    "sseUrl": "https://api.oooefam.net/v3/jobs/scans/test-job-events/stream"
                }
            }
            """.data(using: .utf8)!

        mockSession.mockUploadResponse(data: uploadResponse, for: "https://api.oooefam.net/v3/jobs/scans")

        // Mock stream events
        let streamUrl = "https://api.oooefam.net/v3/jobs/scans/test-job-events/stream"
        let mockEvents: [NetworkTypes.SSEEvent] = [
            .progress("Looking for book spine..."),
            .progress("Reading spine text..."),
            .progress("Analyzing ISBN..."),
            .result(NetworkTypes.BookMetadata(
                title: "Test Book",
                author: "Test Author",
                isbn: "1234567890",
                coverUrl: URL(string: "https://example.com/cover.jpg")!,
                publisher: "Test Publisher",
                publishedDate: "2024-01-01",
                pageCount: 250,
                format: "Hardcover",
                confidence: 0.95,
                enrichmentStatus: nil
            )),
            .complete(resultsUrl: nil, books: nil)
        ]
        mockSession.mockStreamEvents(mockEvents, for: streamUrl)

        // Act
        let (jobId, _, _) = try await service.uploadScan(image: testImage, deviceId: "test-device")

        var receivedEvents: [NetworkTypes.SSEEvent] = []
        for try await event in service.streamEvents(from: URL(string: streamUrl)!, deviceId: "test-device") {
            receivedEvents.append(event)
        }

        // Assert
        XCTAssertEqual(receivedEvents.count, 5)
        XCTAssertTrue(receivedEvents.contains { if case .progress = $0 { return true }; return false })
        XCTAssertTrue(receivedEvents.contains { if case .result = $0 { return true }; return false })
        XCTAssertTrue(receivedEvents.contains { if case .complete = $0 { return true }; return false })
    }

    // MARK: - Test 4: SSE Error Event

    func testSSEStreamHandlesErrorEvent() async throws {
        // Arrange
        let testImage = createTestImageData()
        let service = TalariaService(session: mockSession, deviceId: "test-device")

        let uploadResponse = """
            {
                "success": true,
                "data": {
                    "jobId": "test-job-error",
                    "sseUrl": "https://api.oooefam.net/v3/jobs/scans/test-job-error/stream"
                }
            }
            """.data(using: .utf8)!

        mockSession.mockUploadResponse(data: uploadResponse, for: "https://api.oooefam.net/v3/jobs/scans")

        let streamUrl = "https://api.oooefam.net/v3/jobs/scans/test-job-error/stream"
        let mockEvents: [NetworkTypes.SSEEvent] = [
            .progress("Starting..."),
            .error(SSEErrorInfo(
                message: "Recognition failed: could not detect spine",
                code: "RECOGNITION_FAILED",
                retryable: false,
                jobId: "test-job-error"
            ))
        ]
        mockSession.mockStreamEvents(mockEvents, for: streamUrl)

        // Act
        let (jobId, _, _) = try await service.uploadScan(image: testImage, deviceId: "test-device")

        var receivedError = false
        for try await event in service.streamEvents(from: URL(string: streamUrl)!, deviceId: "test-device") {
            if case .error = event {
                receivedError = true
                break
            }
        }

        // Assert
        XCTAssertTrue(receivedError, "Should receive error event")
    }

    // MARK: - Test 5: Cleanup Idempotency

    func testCleanupIsIdempotent() async throws {
        // Arrange
        let testImage = createTestImageData()
        let service = TalariaService(session: mockSession, deviceId: "test-device")

        let uploadResponse = """
            {
                "success": true,
                "data": {
                    "jobId": "test-job-cleanup",
                    "sseUrl": "https://api.oooefam.net/v3/jobs/scans/test-job-cleanup/stream"
                }
            }
            """.data(using: .utf8)!

        mockSession.mockUploadResponse(data: uploadResponse, for: "https://api.oooefam.net/v3/jobs/scans")

        let streamUrl = "https://api.oooefam.net/v3/jobs/scans/test-job-cleanup/stream"
        mockSession.mockStreamEvents([.complete(resultsUrl: nil, books: nil)], for: streamUrl)

        // Act
        let (jobId, _, _) = try await service.uploadScan(image: testImage, deviceId: "test-device")

        var events: [NetworkTypes.SSEEvent] = []
        for try await event in service.streamEvents(from: URL(string: streamUrl)!, deviceId: "test-device") {
            events.append(event)
        }

        XCTAssertEqual(events.count, 1, "Should receive exactly 1 event")

        // Cleanup first time
        try await service.cleanup(jobId: jobId)

        // Cleanup second time (idempotent - should not throw)
        try await service.cleanup(jobId: jobId)

        // Assert
        XCTAssertTrue(true, "Second cleanup should succeed")
    }

    // MARK: - Test 6: Rate Limit State

    func testRateLimitStateInitialValues() {
        // Arrange & Act
        let state = RateLimitState()

        // Assert
        XCTAssertFalse(state.isRateLimited, "Should not be rate limited initially")
        XCTAssertNil(state.retryAfterDate, "Retry date should be nil initially")
        XCTAssertEqual(state.remainingTime, 0, "Remaining time should be 0 initially")
    }

    func testRateLimitStateCalculatesRemainingTime() {
        // Arrange
        let state = RateLimitState()
        let futureDate = Date().addingTimeInterval(120)

        // Act
        state.setRateLimited(until: futureDate)

        // Assert
        XCTAssertTrue(state.isRateLimited)
        XCTAssertEqual(state.retryAfterDate, futureDate)
        XCTAssertGreaterThan(state.remainingTime, 100, "Should have positive remaining time")
        XCTAssertLessThan(state.remainingTime, 130, "Should be less than 130 seconds")
    }

    // MARK: - Test 7: Concurrent Uploads

    func testConcurrentUploadsHandleMultipleJobs() async throws {
        // Arrange
        let testImage = createTestImageData()
        let service = TalariaService(session: mockSession, deviceId: "test-device")
        let expectation = XCTestExpectation(description: "3 concurrent uploads complete")

        // Act - Launch 3 concurrent uploads
        async let results = try await withThrowingTaskGroup(of: (String, URL).self) { group in
            for i in 1...3 {
                group.addTask {
                    return try await service.uploadScan(image: testImage, deviceId: "test-device-\(i)")
                }
            }
        }

        // Assert
        XCTAssertEqual(results.0, results.1, "Job IDs should match")
        XCTAssertEqual(results.0, results.2, "Stream URLs should match")
        XCTAssertEqual(results.count, 3, "Should have 3 results")
    }

    // MARK: - Test 8: Network Error Deserialization

    func testNetworkErrorLocalizedDescriptions() {
        // Test all error cases
        let noConnection = NetworkError.noConnection
        let timeout = NetworkError.timeout
        let serverError = NetworkError.serverError(500)
        let invalid = NetworkError.invalidResponse
        let rateLimited = NetworkError.rateLimited(retryAfter: 60)

        XCTAssertEqual(noConnection.localizedDescription, "No internet connection available")
        XCTAssertEqual(timeout.localizedDescription, "Request timed out")
        XCTAssertEqual(serverError.localizedDescription, "Server error (HTTP 500)")
        XCTAssertEqual(invalid.localizedDescription, "Invalid server response")
        XCTAssertEqual(rateLimited.localizedDescription, "Rate limited - retry after 60s")
    }

    // MARK: - Test 9: BookMetadata Structure

    func testBookMetadataDeserializesCorrectly() async throws {
        // Arrange
        let testImage = createTestImageData()
        let service = TalariaService(session: mockSession, deviceId: "test-device")

        let uploadResponse = """
            {
                "success": true,
                "data": {
                    "jobId": "test-job-metadata",
                    "sseUrl": "https://api.oooefam.net/v3/jobs/scans/test-job-metadata/stream"
                }
            }
            """.data(using: .utf8)!

        mockSession.mockUploadResponse(data: uploadResponse, for: "https://api.oooefam.net/v3/jobs/scans")

        let streamUrl = "https://api.oooefam.net/v3/jobs/scans/test-job-metadata/stream"
        let mockEvents: [NetworkTypes.SSEEvent] = [
            .result(NetworkTypes.BookMetadata(
                title: "Clean Code",
                author: "Robert C. Martin",
                isbn: "0201633612",
                coverUrl: URL(string: "https://example.com/clean.jpg")!,
                publisher: "Addison-Wesley",
                publishedDate: "2008-08-01",
                pageCount: 464,
                format: "Hardcover",
                confidence: 0.92,
                enrichmentStatus: nil
            ))
        ]
        mockSession.mockStreamEvents(mockEvents, for: streamUrl)

        // Act
        let (jobId, _, _) = try await service.uploadScan(image: testImage, deviceId: "test-device")

        var metadata: NetworkTypes.BookMetadata?
        for try await event in service.streamEvents(from: URL(string: streamUrl)!, deviceId: "test-device") {
            if case .result(let result) = event {
                metadata = result
                break
            }
        }

        // Assert
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.title, "Clean Code")
        XCTAssertEqual(metadata?.author, "Robert C. Martin")
        XCTAssertEqual(metadata?.isbn, "0201633612")
        XCTAssertEqual(metadata?.pageCount, 464)
        XCTAssertEqual(metadata?.confidence, 0.92, accuracy: 0.001)
    }

    // MARK: - Helper Methods

    private func createTestImageData() -> Data {
        // Minimal valid JPEG (1x1 black square)
        return Data([
            0xFF, 0xD8, // SOI
            0xFF, 0xE0, // APP0
            0x00, 0x10, // Length
            0x4A, 0x46, 0x49, 0x46, // "JFIF\0"
            0x01, 0x01, // Version 1.1
            0x00, 0x00, // No units
            0x00, 0x01, // Density
            0x01, 0x01, // No thumbnail
            0x00, 0x00, // EOI
        ])
    }
}
