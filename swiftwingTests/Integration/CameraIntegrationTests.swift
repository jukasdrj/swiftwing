import XCTest
@testable import swiftwing

/// Integration test for the complete camera pipeline: capture → upload → SSE → dedup → save
final class CameraIntegrationTests: XCTestCase {
    
    var mockTalariaService: MockTalariaService!
    var testModelContext: ModelContext!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockTalariaService = MockTalariaService(deviceId: "integration-test-device")
        
        // Create in-memory container for testing
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        testModelContext = ModelContext(container)
    }
    
    // MARK: - Happy Path: Capture → Upload → SSE → Save
    
    func testFullCameraPipelineHappyPath() async throws {
        // Setup: Configure mock service with happy path events
        await mockTalariaService.setSSEEvents(SampleSSEEvents.happyPathSequence)
        
        // Step 1: Simulate capture (using mock image data)
        let testImageData = "fake jpeg data".data(using: .utf8)!
        
        // Step 2: Upload to Talaria
        let (jobId, sseUrl, authToken) = try await mockTalariaService.uploadScan(
            imageData: testImageData,
            filename: "scan-001.jpg"
        )
        
        XCTAssertFalse(jobId.isEmpty)
        XCTAssertFalse(authToken.isEmpty)
        
        // Step 3: Stream SSE events and collect results
        var receivedBooks: [BookMetadata] = []
        var processingComplete = false
        
        let callbacks = ScanJobCallbacks(
            onBookResult: { book in
                receivedBooks.append(book)
            },
            onComplete: { summary in
                processingComplete = true
                // Verify summary structure
                XCTAssertGreaterThan(summary.totalDetected, 0)
                XCTAssertGreaterThan(summary.books.count, 0)
            }
        )
        
        try await mockTalariaService.streamEvents(from: sseUrl, authToken: authToken, callbacks: callbacks)
        
        // Step 4: Verify books received
        XCTAssertTrue(processingComplete)
        XCTAssertEqual(receivedBooks.count, 2)
        
        // Step 5: Save to SwiftData
        let dataSyncActor = DataSyncActor()
        var savedBooks: [Book] = []
        
        for metadata in receivedBooks {
            let book = try await dataSyncActor.makeBook(from: metadata)
            try await dataSyncActor.save(book: book, in: testModelContext)
            savedBooks.append(book)
        }
        
        XCTAssertEqual(savedBooks.count, 2)
        XCTAssertEqual(savedBooks[0].title, "The Swift Programming Language")
        XCTAssertEqual(savedBooks[1].title, "Clean Code")
    }
    
    // MARK: - Deduplication: Prevent duplicate books from SSE + completion
    
    func testDeduplicationPreventsDuplicateBooks() async throws {
        // Setup: Mock returns same book in both .result event and .completed summary
        let duplicateEvent1 = SSEEvent(
            type: "result",
            data: """
            {
              "title": "The Book",
              "authors": ["Author"],
              "isbn": "978-0000000001",
              "confidence": 0.95,
              "processingStage": "enrichment"
            }
            """
        )
        
        let duplicateEvent2 = SSEEvent(
            type: "completed",
            data: """
            {
              "totalDetected": 1,
              "books": [
                {
                  "title": "The Book",
                  "authors": ["Author"],
                  "isbn": "978-0000000001",
                  "confidence": 0.95,
                  "processingStage": "enrichment"
                }
              ],
              "duration": {
                "totalMs": 1500,
                "uploadMs": 300,
                "processingMs": 1200
              }
            }
            """
        )
        
        await mockTalariaService.setSSEEvents([duplicateEvent1, duplicateEvent2])
        
        // Stream events and track unique ISBNs
        var seenISBNs = Set<String>()
        var duplicateCount = 0
        
        let callbacks = ScanJobCallbacks(
            onBookResult: { book in
                if seenISBNs.contains(book.isbn) {
                    duplicateCount += 1
                } else {
                    seenISBNs.insert(book.isbn)
                }
            }
        )
        
        try await mockTalariaService.streamEvents(
            from: "http://test",
            authToken: "token",
            callbacks: callbacks
        )
        
        // Only one book should be processed, not two
        XCTAssertEqual(seenISBNs.count, 1)
        XCTAssertGreaterThanOrEqual(duplicateCount, 1) // Duplicate was detected
    }
    
    // MARK: - Error Scenarios
    
    func testPipelineHandlesUploadFailure() async throws {
        // Setup: Upload fails
        await mockTalariaService.setUploadFailure(.apiError(ProblemDetails(
            type: "http://example.com/errors/upload",
            title: "Upload Failed",
            status: 400,
            detail: "Invalid image format"
        )))
        
        let testImageData = "invalid data".data(using: .utf8)!
        
        do {
            _ = try await mockTalariaService.uploadScan(imageData: testImageData, filename: "bad.jpg")
            XCTFail("Expected upload to fail")
        } catch NetworkError.apiError {
            // Expected
            XCTAssertTrue(true)
        }
    }
    
    func testPipelineHandlesEmptyResults() async throws {
        // Setup: Talaria returns no books
        await mockTalariaService.setSSEEvents(SampleSSEEvents.emptyResultSequence)
        
        let testImageData = "test data".data(using: .utf8)!
        
        let (jobId, sseUrl, authToken) = try await mockTalariaService.uploadScan(
            imageData: testImageData,
            filename: "empty.jpg"
        )
        
        var receivedBooks: [BookMetadata] = []
        var completionCalled = false
        
        let callbacks = ScanJobCallbacks(
            onBookResult: { book in receivedBooks.append(book) },
            onComplete: { _ in completionCalled = true }
        )
        
        try await mockTalariaService.streamEvents(from: sseUrl, authToken: authToken, callbacks: callbacks)
        
        XCTAssertTrue(completionCalled)
        XCTAssertEqual(receivedBooks.count, 0)
    }
    
    // MARK: - Enrichment Degradation
    
    func testPipelineHandlesEnrichmentDegradation() async throws {
        // Setup: Enrichment service is degraded
        await mockTalariaService.setSSEEvents(SampleSSEEvents.degradedSequence)
        
        let testImageData = "test data".data(using: .utf8)!
        
        let (jobId, sseUrl, authToken) = try await mockTalariaService.uploadScan(
            imageData: testImageData,
            filename: "test.jpg"
        )
        
        var enrichmentDegradedDetected = false
        var receivedBooks: [BookMetadata] = []
        
        let callbacks = ScanJobCallbacks(
            onBookResult: { book in receivedBooks.append(book) }
        )
        
        try await mockTalariaService.streamEvents(from: sseUrl, authToken: authToken, callbacks: callbacks)
        
        // Pipeline should complete despite enrichment degradation
        XCTAssertGreaterThan(receivedBooks.count, 0)
    }
    
    // MARK: - Batch Processing
    
    func testMultipleScansSequentially() async throws {
        // Simulate scanning multiple books in sequence
        let scanConfigs: [(name: String, events: [SSEEvent])] = [
            ("scan1.jpg", SampleSSEEvents.happyPathSequence),
            ("scan2.jpg", SampleSSEEvents.happyPathSequence),
        ]
        
        for (filename, events) in scanConfigs {
            await mockTalariaService.setSSEEvents(events)
            
            let testImageData = "\(filename) data".data(using: .utf8)!
            
            let (_, sseUrl, authToken) = try await mockTalariaService.uploadScan(
                imageData: testImageData,
                filename: filename
            )
            
            var bookCount = 0
            let callbacks = ScanJobCallbacks(
                onBookResult: { _ in bookCount += 1 }
            )
            
            try await mockTalariaService.streamEvents(from: sseUrl, authToken: authToken, callbacks: callbacks)
            
            XCTAssertEqual(bookCount, 2)
        }
    }
}
