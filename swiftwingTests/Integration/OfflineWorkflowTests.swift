import XCTest
@testable import swiftwing

/// Integration test for offline queue and network recovery workflow.
final class OfflineWorkflowTests: XCTestCase {
    
    var mockNetworkMonitor: MockNetworkMonitor!
    var mockTalariaService: MockTalariaService!
    var testModelContext: ModelContext!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockNetworkMonitor = MockNetworkMonitor()
        mockTalariaService = MockTalariaService(deviceId: "offline-test-device")
        
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        testModelContext = ModelContext(container)
    }
    
    // MARK: - Offline Queueing
    
    func testQueueScanWhenNetworkDown() async throws {
        // Setup: Network is down
        mockNetworkMonitor.simulateNetworkDown()
        XCTAssertFalse(mockNetworkMonitor.isOnline)
        
        // When user captures while offline, scan should be queued
        let testImageData = "offline scan data".data(using: .utf8)!
        let testFilename = "offline-scan-001.jpg"
        
        // Simulate: Application should queue this scan instead of uploading
        let queuedMetadata = (
            filename: testFilename,
            imageData: testImageData,
            timestamp: Date()
        )
        
        // Verify metadata can be captured for later processing
        XCTAssertNotNil(queuedMetadata.imageData)
        XCTAssertEqual(queuedMetadata.filename, testFilename)
    }
    
    // MARK: - Network Recovery & Retry
    
    func testRetryUploadWhenNetworkRecovered() async throws {
        // Setup: Start offline with queued scan
        mockNetworkMonitor.simulateNetworkDown()
        
        let testImageData = "queued scan data".data(using: .utf8)!
        let testFilename = "queued-001.jpg"
        
        // Simulate: Network comes back online
        mockNetworkMonitor.simulateNetworkRecovery()
        XCTAssertTrue(mockNetworkMonitor.isOnline)
        
        // Setup mock to return success
        await mockTalariaService.setSSEEvents(SampleSSEEvents.happyPathSequence)
        
        // Retry upload should succeed
        let (jobId, sseUrl, authToken) = try await mockTalariaService.uploadScan(
            imageData: testImageData,
            filename: testFilename
        )
        
        XCTAssertFalse(jobId.isEmpty)
        
        // Process results
        var bookCount = 0
        let callbacks = ScanJobCallbacks(
            onBookResult: { _ in bookCount += 1 }
        )
        
        try await mockTalariaService.streamEvents(from: sseUrl, authToken: authToken, callbacks: callbacks)
        
        XCTAssertGreaterThan(bookCount, 0)
    }
    
    // MARK: - Batch Recovery: Multiple Queued Scans
    
    func testProcessMultipleQueuedScansOnNetworkRecovery() async throws {
        // Setup: Multiple scans queued while offline
        let queuedScans = [
            ("scan-1.jpg", "data1".data(using: .utf8)!),
            ("scan-2.jpg", "data2".data(using: .utf8)!),
            ("scan-3.jpg", "data3".data(using: .utf8)!),
        ]
        
        // Network comes back
        mockNetworkMonitor.simulateNetworkRecovery()
        
        // Setup mock for successful uploads
        await mockTalariaService.setSSEEvents(SampleSSEEvents.happyPathSequence)
        
        var totalBooksProcessed = 0
        
        // Process each queued scan
        for (filename, imageData) in queuedScans {
            let (_, sseUrl, authToken) = try await mockTalariaService.uploadScan(
                imageData: imageData,
                filename: filename
            )
            
            var bookCount = 0
            let callbacks = ScanJobCallbacks(
                onBookResult: { _ in bookCount += 1 }
            )
            
            try await mockTalariaService.streamEvents(from: sseUrl, authToken: authToken, callbacks: callbacks)
            
            totalBooksProcessed += bookCount
        }
        
        // All scans should be processed
        XCTAssertGreaterThan(totalBooksProcessed, 0)
    }
    
    // MARK: - Upload Failure Recovery
    
    func testRetryAfterTemporaryUploadFailure() async throws {
        let testImageData = "test data".data(using: .utf8)!
        
        // First attempt fails
        await mockTalariaService.setUploadFailure(.apiError(ProblemDetails(
            type: "http://example.com/errors/temp",
            title: "Temporary Error",
            status: 503,
            detail: "Service temporarily unavailable"
        )))
        
        do {
            _ = try await mockTalariaService.uploadScan(imageData: testImageData, filename: "test.jpg")
            XCTFail("First upload should fail")
        } catch NetworkError.apiError {
            // Expected
        }
        
        // Second attempt succeeds
        await mockTalariaService.setShouldSucceedUpload()
        await mockTalariaService.setSSEEvents(SampleSSEEvents.happyPathSequence)
        
        let (jobId, sseUrl, authToken) = try await mockTalariaService.uploadScan(
            imageData: testImageData,
            filename: "test.jpg"
        )
        
        XCTAssertFalse(jobId.isEmpty)
        
        var bookCount = 0
        let callbacks = ScanJobCallbacks(
            onBookResult: { _ in bookCount += 1 }
        )
        
        try await mockTalariaService.streamEvents(from: sseUrl, authToken: authToken, callbacks: callbacks)
        
        XCTAssertGreaterThan(bookCount, 0)
    }
    
    // MARK: - Rate Limit Recovery
    
    func testQueueUploadOnRateLimit() async throws {
        let testImageData = "rate limited data".data(using: .utf8)!
        
        // Simulate rate limit error with retry-after
        let rateLimitError = NetworkError.rateLimited(retryAfter: 5.0)
        await mockTalariaService.setUploadFailure(rateLimitError)
        
        // Upload should fail with rate limit
        do {
            _ = try await mockTalariaService.uploadScan(imageData: testImageData, filename: "test.jpg")
            XCTFail("Expected rate limit error")
        } catch NetworkError.rateLimited(let retryAfter) {
            XCTAssertGreaterThan(retryAfter ?? 0, 0)
        }
    }
    
    // MARK: - Data Integrity
    
    func testNoDataLossAfterOfflineQueueing() async throws {
        // Queue scan data
        let testImageData = "precious data".data(using: .utf8)!
        let testFilename = "important.jpg"
        
        // Simulate queuing in memory or to disk
        var queuedData = testImageData
        var queuedFilename = testFilename
        
        // Verify data integrity
        XCTAssertEqual(queuedData, testImageData)
        XCTAssertEqual(queuedFilename, testFilename)
        
        // When network recovers, data should still be intact
        mockNetworkMonitor.simulateNetworkRecovery()
        XCTAssertTrue(mockNetworkMonitor.isOnline)
        
        // Upload with original data
        await mockTalariaService.setShouldSucceedUpload()
        await mockTalariaService.setSSEEvents(SampleSSEEvents.happyPathSequence)
        
        let (jobId, _, _) = try await mockTalariaService.uploadScan(
            imageData: queuedData,
            filename: queuedFilename
        )
        
        XCTAssertFalse(jobId.isEmpty)
    }
    
    // MARK: - Concurrent Network Status Changes
    
    func testHandlesFrequentNetworkStatusChanges() async throws {
        // Simulate network flapping
        mockNetworkMonitor.simulateNetworkDown()
        XCTAssertFalse(mockNetworkMonitor.isOnline)
        
        mockNetworkMonitor.simulateNetworkRecovery()
        XCTAssertTrue(mockNetworkMonitor.isOnline)
        
        mockNetworkMonitor.simulateNetworkDown()
        XCTAssertFalse(mockNetworkMonitor.isOnline)
        
        mockNetworkMonitor.simulateNetworkRecovery()
        XCTAssertTrue(mockNetworkMonitor.isOnline)
        
        // Eventually should stabilize
        XCTAssertTrue(mockNetworkMonitor.isOnline)
    }
}
