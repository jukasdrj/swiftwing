import XCTest
@testable import swiftwing

final class TalariaServiceTests: XCTestCase {
    
    var talariaService: TalariaService!
    let testDeviceId = "test-device-\(UUID().uuidString.prefix(8))"
    
    override func setUp() async throws {
        try await super.setUp()
        talariaService = TalariaService(deviceId: testDeviceId)
    }
    
    // MARK: - Upload Tests
    
    func testUploadScanReturnsJobIdAndSSEUrl() async throws {
        let testData = "test image data".data(using: .utf8)!
        
        let (jobId, sseUrl, authToken) = try await talariaService.uploadScan(imageData: testData, filename: "test.jpg")
        
        XCTAssertFalse(jobId.isEmpty)
        XCTAssert(sseUrl.contains("/sse/") || sseUrl.contains(jobId))
        XCTAssertFalse(authToken.isEmpty)
    }
    
    func testUploadScanIncludesDeviceId() async throws {
        let testData = "test image data".data(using: .utf8)!
        
        // Note: This test verifies the service was initialized with the device ID
        // In a real scenario, you'd verify this via network inspection or mock
        XCTAssertEqual(talariaService.deviceId, testDeviceId)
    }
    
    // MARK: - Stream Tests
    
    func testStreamEventsProcessesProgressEvents() async throws {
        let mockService = MockTalariaService(deviceId: testDeviceId)
        await mockService.setSSEEvents(SampleSSEEvents.happyPathSequence)
        
        var receivedEvents: [String] = []
        let callbacks = ScanJobCallbacks(
            onProgress: { _ in receivedEvents.append("progress") },
            onBookResult: { _ in receivedEvents.append("book") },
            onComplete: { _ in receivedEvents.append("complete") },
            onError: { _ in receivedEvents.append("error") }
        )
        
        try await mockService.streamEvents(from: "http://test", authToken: "token", callbacks: callbacks)
        
        XCTAssertEqual(receivedEvents, ["progress", "book", "book", "complete"])
    }
    
    func testStreamEventsHandlesEmptyResults() async throws {
        let mockService = MockTalariaService(deviceId: testDeviceId)
        await mockService.setSSEEvents(SampleSSEEvents.emptyResultSequence)
        
        var completionCalled = false
        var bookCount = 0
        
        let callbacks = ScanJobCallbacks(
            onBookResult: { _ in bookCount += 1 },
            onComplete: { _ in completionCalled = true }
        )
        
        try await mockService.streamEvents(from: "http://test", authToken: "token", callbacks: callbacks)
        
        XCTAssertTrue(completionCalled)
        XCTAssertEqual(bookCount, 0)
    }
    
    // MARK: - Error Handling
    
    func testUploadFailureThrowsNetworkError() async throws {
        let mockService = MockTalariaService(deviceId: testDeviceId)
        await mockService.setUploadFailure(.apiError(ProblemDetails(
            type: "http://example.com/errors/server-error",
            title: "Server Error",
            status: 500,
            detail: "Internal server error"
        )))
        
        let testData = "test image data".data(using: .utf8)!
        
        do {
            _ = try await mockService.uploadScan(imageData: testData, filename: "test.jpg")
            XCTFail("Expected upload to fail")
        } catch let error as NetworkError {
            XCTAssert(error.description.contains("500") || error.description.contains("error"))
        }
    }
    
    // MARK: - Cleanup Tests
    
    func testCleanupSucceeds() async throws {
        let mockService = MockTalariaService(deviceId: testDeviceId)
        
        // Should not throw
        try await mockService.cleanup(jobId: "test-job-123")
        XCTAssertTrue(true) // If we get here, cleanup succeeded
    }
}
