import XCTest
@testable import swiftwing

/// Unit tests for NetworkActor multipart upload with retry logic
final class NetworkActorTests: XCTestCase {

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        // Reset mock handler before each test
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.requestCount = 0
    }

    // MARK: - Success Tests

    /// Test successful upload with 202 Accepted response
    func testUploadImageSuccess() async throws {
        // Arrange: Create test JPEG
        let testImageData = createTestJPEGData()
        let mockJSON = """
        {
            "jobId": "test-job-123",
            "streamUrl": "https://api.talaria.example.com/v3/stream/test-job-123"
        }
        """

        // Configure mock to return 202 with valid JSON
        MockURLProtocol.requestHandler = { request in
            // Verify request structure
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.starts(with: "multipart/form-data") ?? false)
            XCTAssertNotNil(request.httpBody)

            // Return success response
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 202,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, mockJSON.data(using: .utf8)!)
        }

        // Act: Upload image
        let actor = createTestActor()
        let result = try await actor.uploadImage(testImageData)

        // Assert: Response parsed correctly
        XCTAssertEqual(result.jobId, "test-job-123")
        XCTAssertEqual(result.streamUrl.absoluteString, "https://api.talaria.example.com/v3/stream/test-job-123")
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    /// Test real JPEG from temporary directory
    func testUploadRealJPEGFromTempDirectory() async throws {
        // Arrange: Create real JPEG in temp directory
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-spine.jpg")
        let testJPEG = createTestJPEGData()
        try testJPEG.write(to: tempURL)

        // Configure mock
        MockURLProtocol.requestHandler = { request in
            let mockJSON = """
            {"jobId": "real-jpeg-test", "streamUrl": "https://api.talaria.example.com/v3/stream/real"}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!
            return (response, mockJSON.data(using: .utf8)!)
        }

        // Act: Read and upload
        let imageData = try Data(contentsOf: tempURL)
        let actor = createTestActor()
        let result = try await actor.uploadImage(imageData)

        // Assert
        XCTAssertEqual(result.jobId, "real-jpeg-test")

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Error Handling Tests

    /// Test network timeout error
    func testUploadImageTimeout() async throws {
        // Arrange: Mock timeout
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        // Act & Assert
        let actor = createTestActor()
        do {
            _ = try await actor.uploadImage(createTestJPEGData())
            XCTFail("Expected NetworkError.timeout")
        } catch NetworkError.timeout {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Test no connection error
    func testUploadImageNoConnection() async throws {
        // Arrange: Mock no connection
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        // Act & Assert
        let actor = createTestActor()
        do {
            _ = try await actor.uploadImage(createTestJPEGData())
            XCTFail("Expected NetworkError.noConnection")
        } catch NetworkError.noConnection {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Test invalid response parsing
    func testUploadImageInvalidResponse() async throws {
        // Arrange: Mock malformed JSON
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!
            return (response, "{ invalid json }".data(using: .utf8)!)
        }

        // Act & Assert
        let actor = createTestActor()
        do {
            _ = try await actor.uploadImage(createTestJPEGData())
            XCTFail("Expected NetworkError.invalidResponse")
        } catch NetworkError.invalidResponse {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Retry Logic Tests

    /// Test 429 rate limit with Retry-After header
    func testUploadImage429WithRetryAfter() async throws {
        // Arrange: Mock rate limit then success
        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if callCount == 1 {
                // First call: rate limited
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "1"]
                )!
                return (response, Data())
            } else {
                // Second call: success
                let mockJSON = """
                {"jobId": "retry-success", "streamUrl": "https://api.talaria.example.com/v3/stream/retry"}
                """
                let response = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!
                return (response, mockJSON.data(using: .utf8)!)
            }
        }

        // Act: Upload should retry
        let actor = createTestActor()
        let result = try await actor.uploadImage(createTestJPEGData())

        // Assert: Succeeded after retry
        XCTAssertEqual(result.jobId, "retry-success")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    /// Test 429 rate limit without Retry-After header
    func testUploadImage429WithoutRetryAfter() async throws {
        // Arrange: Rate limit without header, then success
        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if callCount == 1 {
                let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            } else {
                let mockJSON = """
                {"jobId": "default-backoff", "streamUrl": "https://api.talaria.example.com/v3/stream/backoff"}
                """
                let response = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!
                return (response, mockJSON.data(using: .utf8)!)
            }
        }

        // Act
        let actor = createTestActor()
        let result = try await actor.uploadImage(createTestJPEGData())

        // Assert
        XCTAssertEqual(result.jobId, "default-backoff")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    /// Test 5xx server error with exponential backoff (3 retries)
    func testUploadImage5xxWithRetry() async throws {
        // Arrange: Fail twice with 500, succeed on third
        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if callCount <= 2 {
                // First two calls: server error
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            } else {
                // Third call: success
                let mockJSON = """
                {"jobId": "backoff-success", "streamUrl": "https://api.talaria.example.com/v3/stream/backoff"}
                """
                let response = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!
                return (response, mockJSON.data(using: .utf8)!)
            }
        }

        // Act: Should retry twice and succeed
        let actor = createTestActor()
        let result = try await actor.uploadImage(createTestJPEGData())

        // Assert
        XCTAssertEqual(result.jobId, "backoff-success")
        XCTAssertEqual(MockURLProtocol.requestCount, 3)
    }

    /// Test 5xx exhausts retries and throws
    func testUploadImage5xxExhaustsRetries() async throws {
        // Arrange: Always return 503
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        // Act & Assert: Should fail after max retries
        let actor = createTestActor()
        do {
            _ = try await actor.uploadImage(createTestJPEGData())
            XCTFail("Expected NetworkError.serverError(503)")
        } catch NetworkError.serverError(let code) {
            XCTAssertEqual(code, 503)
            // Max retries = 3, so total calls = 4 (initial + 3 retries)
            XCTAssertEqual(MockURLProtocol.requestCount, 4)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - SSE Streaming Tests

    /// Test successful SSE stream with progress, result, and complete events
    func testStreamEventsSuccess() async throws {
        // Arrange: Create mock SSE stream
        let sseData = """
        event: progress
        data: {"message": "Looking..."}

        event: progress
        data: {"message": "Reading spine..."}

        event: result
        data: {"title": "Test Book", "author": "Test Author", "isbn": "1234567890", "coverUrl": "https://example.com/cover.jpg", "confidence": 0.95}

        event: complete
        data: {}

        """.data(using: .utf8)!

        // Configure mock to return SSE stream
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
            return (response, sseData)
        }

        // Act: Stream events
        let actor = createTestActor()
        let streamUrl = URL(string: "https://api.talaria.example.com/v3/stream/test-job-123")!
        var events: [SSEEvent] = []

        for try await event in actor.streamEvents(from: streamUrl) {
            events.append(event)
        }

        // Assert: Received all events in order
        XCTAssertEqual(events.count, 4)

        // Verify progress events
        if case .progress(let message1) = events[0] {
            XCTAssertEqual(message1, "Looking...")
        } else {
            XCTFail("Expected progress event")
        }

        if case .progress(let message2) = events[1] {
            XCTAssertEqual(message2, "Reading spine...")
        } else {
            XCTFail("Expected progress event")
        }

        // Verify result event
        if case .result(let metadata) = events[2] {
            XCTAssertEqual(metadata.title, "Test Book")
            XCTAssertEqual(metadata.author, "Test Author")
            XCTAssertEqual(metadata.isbn, "1234567890")
            XCTAssertEqual(metadata.confidence, 0.95)
        } else {
            XCTFail("Expected result event")
        }

        // Verify complete event
        if case .complete = events[3] {
            // Success
        } else {
            XCTFail("Expected complete event")
        }
    }

    /// Test SSE stream with error event
    func testStreamEventsError() async throws {
        // Arrange: Mock SSE with error
        let sseData = """
        event: progress
        data: {"message": "Processing..."}

        event: error
        data: {"message": "Failed to identify book spine"}

        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, sseData)
        }

        // Act
        let actor = createTestActor()
        let streamUrl = URL(string: "https://api.talaria.example.com/v3/stream/error-job")!
        var events: [SSEEvent] = []

        for try await event in actor.streamEvents(from: streamUrl) {
            events.append(event)
        }

        // Assert: Stream closed after error
        XCTAssertEqual(events.count, 2)
        if case .error(let message) = events[1] {
            XCTAssertEqual(message, "Failed to identify book spine")
        } else {
            XCTFail("Expected error event")
        }
    }

    /// Test SSE connection failure with retry
    func testStreamEventsConnectionFailureRetry() async throws {
        // Arrange: Fail first, succeed second
        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if callCount == 1 {
                // First call: connection failed
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            } else {
                // Second call: success
                let sseData = """
                event: progress
                data: {"message": "Connected after retry"}

                event: complete
                data: {}

                """.data(using: .utf8)!
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, sseData)
            }
        }

        // Act: Should retry and succeed
        let actor = createTestActor()
        let streamUrl = URL(string: "https://api.talaria.example.com/v3/stream/retry")!
        var events: [SSEEvent] = []

        for try await event in actor.streamEvents(from: streamUrl) {
            events.append(event)
        }

        // Assert: Succeeded after retry
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(events.count, 2)
    }

    /// Test SSE connection failure exhausts retries
    func testStreamEventsConnectionFailureExhausted() async throws {
        // Arrange: Always fail
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        // Act & Assert: Should throw after max retries
        let actor = createTestActor()
        let streamUrl = URL(string: "https://api.talaria.example.com/v3/stream/fail")!

        do {
            for try await _ in actor.streamEvents(from: streamUrl) {
                XCTFail("Should not receive events")
            }
            XCTFail("Expected SSEError.maxRetriesExceeded")
        } catch SSEError.maxRetriesExceeded {
            // Expected: max retries = 3, so total calls = 4
            XCTAssertEqual(MockURLProtocol.requestCount, 4)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Test SSE parsing with invalid event format
    func testStreamEventsInvalidFormat() async throws {
        // Arrange: Mock malformed SSE
        let sseData = """
        event: progress
        data: not a json object

        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, sseData)
        }

        // Act: Should skip invalid events
        let actor = createTestActor()
        let streamUrl = URL(string: "https://api.talaria.example.com/v3/stream/invalid")!
        var events: [SSEEvent] = []

        for try await event in actor.streamEvents(from: streamUrl) {
            events.append(event)
        }

        // Assert: No events yielded (invalid format ignored)
        XCTAssertEqual(events.count, 0)
    }

    // MARK: - Helper Methods

    /// Create NetworkActor configured with MockURLProtocol
    private func createTestActor() -> NetworkActor {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        // Inject custom session for testing with MockURLProtocol
        return NetworkActor(deviceId: "test-device-id", baseURL: "https://api.talaria.example.com", session: session)
    }

    /// Create minimal valid JPEG data
    private func createTestJPEGData() -> Data {
        // JPEG magic bytes + minimal structure
        var jpeg = Data([
            0xFF, 0xD8, // SOI (Start of Image)
            0xFF, 0xE0, // APP0 marker
            0x00, 0x10, // Length (16 bytes)
            0x4A, 0x46, 0x49, 0x46, 0x00, // JFIF identifier
            0x01, 0x01, // Version
            0x00, // Density units
            0x00, 0x01, 0x00, 0x01, // Density
            0x00, 0x00, // Thumbnail
            0xFF, 0xD9  // EOI (End of Image)
        ])
        return jpeg
    }
}

// MARK: - Mock URLProtocol

/// Mock URLProtocol for intercepting network requests in tests
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requestCount: Int = 0

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        MockURLProtocol.requestCount += 1

        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Request handler not set")
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

            // For SSE streams (text/event-stream), send data in chunks to simulate streaming
            if let contentType = response.value(forHTTPHeaderField: "Content-Type"),
               contentType.contains("text/event-stream") {
                // Split by newlines and send each line separately to simulate streaming
                let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []
                for line in lines {
                    if let lineData = (line + "\n").data(using: .utf8) {
                        client?.urlProtocol(self, didLoad: lineData)
                    }
                }
            } else {
                // Regular response: send all data at once
                client?.urlProtocol(self, didLoad: data)
            }

            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No-op
    }
}
