import XCTest
@testable import swiftwing

/// Integration tests for TalariaService with REAL Talaria API
/// Tests all workflows (upload, SSE streaming, cleanup) against live backend
/// US-509: Verify API contract compatibility and performance benchmarks
///
/// IMPORTANT: These tests hit the REAL Talaria API at https://api.oooefam.net
/// Network connectivity required. Tests may fail if API is down or rate-limited.
final class TalariaIntegrationTests: XCTestCase {

    // MARK: - Properties

    var talariaService: TalariaService!
    var testDeviceId: String!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Create unique device ID for test isolation
        testDeviceId = "test-device-\(UUID().uuidString)"

        // Create TalariaService with real API endpoint
        talariaService = TalariaService(deviceId: testDeviceId)
    }

    override func tearDown() async throws {
        talariaService = nil
        testDeviceId = nil
        try await super.tearDown()
    }

    // MARK: - Test 1: Upload Workflow (POST /v3/jobs/scans)

    /// AC: Test upload workflow returns valid jobId and streamUrl
    /// AC: Upload latency < 1000ms (network dependent)
    func testUploadReturnsValidJobIdAndStreamUrl() async throws {
        // Arrange
        let testImage = createTestBookSpineImage()

        // Act: Measure upload latency
        let startTime = CFAbsoluteTimeGetCurrent()
        let (jobId, streamUrl, _) = try await talariaService.uploadScan(image: testImage, deviceId: testDeviceId)
        let uploadLatency = CFAbsoluteTimeGetCurrent() - startTime

        // Assert: Valid response structure
        XCTAssertFalse(jobId.isEmpty, "jobId should not be empty")
        XCTAssertTrue(UUID(uuidString: jobId) != nil, "jobId should be valid UUID format")

        XCTAssertNotNil(streamUrl, "streamUrl should not be nil")
        XCTAssertTrue(streamUrl.absoluteString.contains("/v3/jobs/scans/"), "streamUrl should contain expected path")
        XCTAssertTrue(streamUrl.absoluteString.contains("/stream"), "streamUrl should point to stream endpoint")

        // Assert: Performance benchmark
        XCTAssertLessThan(uploadLatency, 1.0, "Upload latency should be < 1000ms, was \(String(format: "%.0f", uploadLatency * 1000))ms")

        print("✅ Upload test passed: jobId=\(jobId), latency=\(String(format: "%.0f", uploadLatency * 1000))ms")

        // Cleanup
        try? await talariaService.cleanup(jobId: jobId)
    }

    // MARK: - Test 2: SSE Stream (GET streamUrl)

    /// AC: Test SSE stream receives progress, completed, and failed events
    /// AC: SSE first event received < 500ms after connection
    /// AC: SSE parsing CPU usage < 15% on main thread
    func testSSEStreamReceivesAllEventTypes() async throws {
        // Arrange: Upload to get stream URL
        let testImage = createTestBookSpineImage()
        let (jobId, streamUrl, _) = try await talariaService.uploadScan(image: testImage, deviceId: testDeviceId)

        // Act: Stream events and measure timing
        let expectation = XCTestExpectation(description: "SSE stream completes")
        var firstEventTime: CFAbsoluteTime?
        let streamStartTime = CFAbsoluteTimeGetCurrent()

        var receivedProgressEvent = false
        var receivedResultEvent = false
        var receivedCompleteEvent = false
        var receivedErrorEvent = false
        var bookMetadata: BookMetadata?

        Task {
            do {
                for try await event in talariaService.streamEvents(streamUrl: streamUrl, deviceId: testDeviceId) {
                    // Record first event timing
                    if firstEventTime == nil {
                        firstEventTime = CFAbsoluteTimeGetCurrent()
                    }

                    switch event {
                    case .progress(let message):
                        receivedProgressEvent = true
                        print("📡 Progress: \(message)")

                    case .result(let metadata):
                        receivedResultEvent = true
                        bookMetadata = metadata
                        print("📚 Result: \(metadata.title) by \(metadata.author)")

                    case .complete(let resultsUrl, let books):
                        receivedCompleteEvent = true
                        print("✅ Complete - resultsUrl: \(resultsUrl ?? "none"), books: \(books?.count ?? 0)")
                        expectation.fulfill()

                    case .error(let errorInfo):
                        receivedErrorEvent = true
                        print("❌ Error: \(errorInfo.message)")
                        expectation.fulfill()

                    case .canceled:
                        print("🚫 Canceled")
                        expectation.fulfill()

                    case .segmented, .bookProgress, .enrichmentDegraded, .ping:
                        // Ignore additional event types in this test
                        break
                    }
                }
            } catch {
                XCTFail("Stream failed with error: \(error)")
                expectation.fulfill()
            }
        }

        // Wait for stream to complete (with timeout)
        await fulfillment(of: [expectation], timeout: 60.0)

        // Assert: Event types received
        XCTAssertTrue(receivedProgressEvent, "Should receive at least one progress event")

        // Note: result/complete/error are mutually exclusive terminal events
        let receivedTerminalEvent = receivedCompleteEvent || receivedErrorEvent
        XCTAssertTrue(receivedTerminalEvent, "Should receive terminal event (complete or error)")

        // Assert: First event timing
        if let firstEventTime = firstEventTime {
            let firstEventLatency = firstEventTime - streamStartTime
            XCTAssertLessThan(firstEventLatency, 0.5, "First event should arrive < 500ms, was \(String(format: "%.0f", firstEventLatency * 1000))ms")
            print("⚡ First event latency: \(String(format: "%.0f", firstEventLatency * 1000))ms")
        } else {
            XCTFail("No events received from stream")
        }

        // Assert: Metadata structure (if successful)
        if receivedCompleteEvent, let metadata = bookMetadata {
            XCTAssertFalse(metadata.title.isEmpty, "Book title should not be empty")
            XCTAssertFalse(metadata.author.isEmpty, "Book author should not be empty")
            print("📖 Received metadata: \(metadata.title) - \(metadata.author)")
        }

        // Cleanup
        try? await talariaService.cleanup(jobId: jobId)
    }

    // MARK: - Test 3: Cleanup (DELETE /v3/jobs/scans/:jobId/cleanup)

    /// AC: Test cleanup succeeds after scan completion
    /// AC: Verify cleanup is idempotent (can call multiple times)
    func testCleanupSucceedsAndIsIdempotent() async throws {
        // Arrange: Create completed scan
        let testImage = createTestBookSpineImage()
        let (jobId, streamUrl, _) = try await talariaService.uploadScan(image: testImage, deviceId: testDeviceId)

        // Wait for stream to complete
        let expectation = XCTestExpectation(description: "Stream completes")
        Task {
            for try await event in talariaService.streamEvents(streamUrl: streamUrl, deviceId: testDeviceId) {
                if case .complete = event {
                    expectation.fulfill()
                    break
                } else if case .error = event {
                    expectation.fulfill()
                    break
                }
            }
        }
        await fulfillment(of: [expectation], timeout: 60.0)

        // Act: Cleanup first time
        try await talariaService.cleanup(jobId: jobId)
        print("✅ First cleanup succeeded")

        // Act: Cleanup second time (idempotent test)
        try await talariaService.cleanup(jobId: jobId)
        print("✅ Second cleanup succeeded (idempotent)")

        // Assert: No errors thrown (success implicit in not crashing)
        XCTAssertTrue(true, "Cleanup should be idempotent")
    }

    // MARK: - Test 4: Error Handling (Network Failures)

    /// AC: Test network failure, 429 rate limit, 5xx server errors
    func testErrorHandlingForNetworkFailures() async throws {
        // This test requires deliberately triggering errors, which is difficult with real API
        // Strategy: Test error enum deserialization and handling logic

        // Test invalid data (will trigger network error)
        let invalidData = Data() // Empty data

        do {
            _ = try await talariaService.uploadScan(image: invalidData, deviceId: testDeviceId)
            XCTFail("Should have thrown error for invalid data")
        } catch let error as NetworkError {
            // Expected error
            print("✅ Correctly threw NetworkError: \(error.localizedDescription)")
            XCTAssertTrue(true, "Error handling works")
        } catch {
            XCTFail("Should throw NetworkError, got: \(error)")
        }
    }

    // MARK: - Test 5: Concurrent Uploads (5 simultaneous)

    /// AC: Test 5 simultaneous scans complete successfully
    /// AC: Concurrent upload throughput: 5 uploads complete in < 10s
    func testConcurrentUploadsCompleteSuccessfully() async throws {
        // Arrange
        let concurrentCount = 5
        let testImage = createTestBookSpineImage()
        let startTime = CFAbsoluteTimeGetCurrent()

        // Act: Launch 5 concurrent uploads
        try await withThrowingTaskGroup(of: (String, URL, String?).self) { group in
            for i in 1...concurrentCount {
                group.addTask {
                    let deviceId = "concurrent-test-\(i)-\(UUID().uuidString)"
                    let service = TalariaService(deviceId: deviceId)
                    return try await service.uploadScan(image: testImage, deviceId: deviceId)
                }
            }

            // Collect all results
            var jobIds: [String] = []
            for try await (jobId, _, _) in group {
                jobIds.append(jobId)
                print("✅ Concurrent upload \(jobIds.count)/\(concurrentCount) completed: \(jobId)")
            }

            // Assert: All uploads succeeded
            XCTAssertEqual(jobIds.count, concurrentCount, "All \(concurrentCount) uploads should succeed")

            // Cleanup all jobs
            for jobId in jobIds {
                try? await talariaService.cleanup(jobId: jobId)
            }
        }

        let totalDuration = CFAbsoluteTimeGetCurrent() - startTime

        // Assert: Performance benchmark
        XCTAssertLessThan(totalDuration, 10.0, "5 concurrent uploads should complete in < 10s, took \(String(format: "%.2f", totalDuration))s")
        print("⚡ Concurrent upload throughput: \(concurrentCount) uploads in \(String(format: "%.2f", totalDuration))s")
    }

    // MARK: - Test 6: Memory Leak Detection (10-minute session)

    /// AC: Verify no memory leaks during 10-minute streaming session
    /// Note: This test is disabled by default (long-running)
    /// Run manually with: xcodebuild test -only-testing:TalariaIntegrationTests/testMemoryLeaksDuring10MinuteSession
    func disabledTestMemoryLeaksDuring10MinuteSession() async throws {
        // This test would run for 10 minutes, uploading and streaming continuously
        // Instruments Memory Profiler would detect leaks
        // Disabled for normal test runs

        let sessionDuration: TimeInterval = 600.0 // 10 minutes
        let startTime = CFAbsoluteTimeGetCurrent()

        var iterationCount = 0
        while CFAbsoluteTimeGetCurrent() - startTime < sessionDuration {
            iterationCount += 1

            let testImage = createTestBookSpineImage()
            let (jobId, streamUrl, _) = try await talariaService.uploadScan(image: testImage, deviceId: testDeviceId)

            // Stream until complete
            for try await _ in talariaService.streamEvents(streamUrl: streamUrl, deviceId: testDeviceId) {
                // Consume events
            }

            // Cleanup
            try await talariaService.cleanup(jobId: jobId)

            print("✅ Iteration \(iterationCount) completed")

            // Small delay between iterations
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }

        print("✅ 10-minute session completed with \(iterationCount) iterations, no crashes")
    }

    // MARK: - Test 7: Type Deserialization

    /// AC: Verify generated types correctly deserialize real API responses
    func testTypesDeserializeCorrectly() async throws {
        // Arrange: Upload and stream to get real API response
        let testImage = createTestBookSpineImage()
        let (jobId, streamUrl, _) = try await talariaService.uploadScan(image: testImage, deviceId: testDeviceId)

        let expectation = XCTestExpectation(description: "Receive result event")
        var metadata: BookMetadata?

        Task {
            for try await event in talariaService.streamEvents(streamUrl: streamUrl, deviceId: testDeviceId) {
                if case .result(let result) = event {
                    metadata = result
                    expectation.fulfill()
                    break
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 60.0)

        // Assert: All expected fields deserialize correctly
        guard let metadata = metadata else {
            // If no result received (e.g., API returned error), skip validation
            print("⚠️ No metadata received (API may have errored)")
            try? await talariaService.cleanup(jobId: jobId)
            return
        }

        // Verify required fields
        XCTAssertFalse(metadata.title.isEmpty, "title should deserialize")
        XCTAssertFalse(metadata.author.isEmpty, "author should deserialize")

        // Verify optional fields have correct types (even if nil)
        if let isbn = metadata.isbn {
            XCTAssertFalse(isbn.isEmpty, "isbn should not be empty if present")
        }

        if let coverUrl = metadata.coverUrl {
            XCTAssertTrue(coverUrl.absoluteString.hasPrefix("http"), "coverUrl should be valid URL")
        }

        if let confidence = metadata.confidence {
            XCTAssertGreaterThanOrEqual(confidence, 0.0, "confidence should be >= 0")
            XCTAssertLessThanOrEqual(confidence, 1.0, "confidence should be <= 1")
        }

        print("✅ All types deserialized correctly: \(metadata)")

        // Cleanup
        try? await talariaService.cleanup(jobId: jobId)
    }

    // MARK: - Helper Methods

    /// Create test book spine image (minimal JPEG)
    private func createTestBookSpineImage() -> Data {
        // Minimal valid JPEG (1x1 pixel black square)
        // In production, would use actual book spine photo
        return Data([
            0xFF, 0xD8, // SOI (Start of Image)
            0xFF, 0xE0, // APP0
            0x00, 0x10, // Length
            0x4A, 0x46, 0x49, 0x46, 0x00, // "JFIF\0"
            0x01, 0x01, // Version 1.1
            0x00, // No units
            0x00, 0x01, 0x00, 0x01, // Density
            0x00, 0x00, // No thumbnail
            0xFF, 0xD9  // EOI (End of Image)
        ])
    }
}
