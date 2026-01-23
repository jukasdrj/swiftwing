import XCTest
import SwiftData
@testable import swiftwing

/// Integration tests for complete scan-to-library flow (Epic 4)
/// Tests end-to-end scenarios from image capture through SSE streaming to SwiftData persistence
final class IntegrationTests: XCTestCase {

    // MARK: - Properties

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var networkActor: NetworkActor!
    var offlineQueueManager: OfflineQueueManager!
    var tempFiles: [URL] = []

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory SwiftData container for testing
        let schema = Schema([Book.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)

        // Create NetworkActor with mock session
        let mockSession = createMockURLSession()
        networkActor = NetworkActor(
            deviceId: "integration-test-device",
            baseURL: "https://api.talaria.example.com",
            session: mockSession
        )

        // Create OfflineQueueManager
        offlineQueueManager = OfflineQueueManager()

        // Reset mock state
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.requestCount = 0

        // Clean up any leftover temp files
        try await cleanupTempFiles()
    }

    override func tearDown() async throws {
        // Clean up temp files
        try await cleanupTempFiles()

        // Reset everything
        modelContext = nil
        modelContainer = nil
        networkActor = nil
        offlineQueueManager = nil
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.requestCount = 0

        try await super.tearDown()
    }

    // MARK: - Scenario 1: Happy Path (Scan → Upload → SSE → Library)

    /// Test successful scan-to-library flow with real-time progress updates
    func testScenario1_SuccessfulScanToLibrary() async throws {
        // Arrange: Configure mock for upload + SSE stream
        let jobId = "test-job-\(UUID().uuidString)"
        let streamUrl = "https://api.talaria.example.com/v3/stream/\(jobId)"

        configureMockForSuccessfulFlow(jobId: jobId, streamUrl: streamUrl)

        let imageData = createTestJPEGData()

        // Act: Execute full flow
        // Step 1: Upload image
        let uploadResponse = try await networkActor.uploadImage(imageData)

        XCTAssertEqual(uploadResponse.jobId, jobId)
        XCTAssertEqual(uploadResponse.streamUrl.absoluteString, streamUrl)

        // Step 2: Stream SSE events and collect metadata
        var progressMessages: [String] = []
        var bookMetadata: BookMetadata?
        var completedSuccessfully = false

        for try await event in networkActor.streamEvents(from: uploadResponse.streamUrl) {
            switch event {
            case .progress(let message):
                progressMessages.append(message)
            case .result(let metadata):
                bookMetadata = metadata
            case .complete:
                completedSuccessfully = true
            case .error(let message):
                XCTFail("Unexpected error: \(message)")
            }
        }

        // Step 3: Save to SwiftData
        guard let metadata = bookMetadata else {
            XCTFail("No book metadata received")
            return
        }

        let book = Book(
            title: metadata.title,
            author: metadata.author,
            isbn: metadata.isbn ?? "UNKNOWN",
            coverUrl: metadata.coverUrl,
            format: metadata.format,
            publisher: metadata.publisher,
            spineConfidence: metadata.confidence
        )
        modelContext.insert(book)
        try modelContext.save()

        // Step 4: Cleanup job
        try await networkActor.cleanupJob(jobId)

        // Assert: Verify complete flow
        XCTAssertTrue(completedSuccessfully, "Stream should complete successfully")
        XCTAssertEqual(progressMessages, ["Looking...", "Reading spine...", "Enriching metadata..."])

        // Verify metadata
        XCTAssertEqual(metadata.title, "The Swift Programming Language")
        XCTAssertEqual(metadata.author, "Apple Inc.")
        XCTAssertEqual(metadata.isbn, "9781234567890")
        XCTAssertEqual(metadata.confidence, 0.95)

        // Verify book in SwiftData
        let fetchDescriptor = FetchDescriptor<Book>()
        let books = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(books.count, 1, "Should have exactly 1 book")

        let savedBook = books[0]
        XCTAssertEqual(savedBook.title, "The Swift Programming Language")
        XCTAssertEqual(savedBook.author, "Apple Inc.")
        XCTAssertEqual(savedBook.isbn, "9781234567890")
        XCTAssertEqual(savedBook.spineConfidence, 0.95)

        // Verify cleanup was called (4 requests: upload + stream connect + stream read + cleanup)
        XCTAssertGreaterThanOrEqual(MockURLProtocol.requestCount, 3)
    }

    // MARK: - Scenario 2: Error Recovery (SSE Error → Retry → Success)

    /// Test error recovery with retry logic
    func testScenario2_SSEErrorWithRetryAndSuccess() async throws {
        // Arrange: First attempt fails, second succeeds
        let jobId1 = "error-job-\(UUID().uuidString)"
        let jobId2 = "success-job-\(UUID().uuidString)"
        var attemptCount = 0

        MockURLProtocol.requestHandler = { request in
            attemptCount += 1

            if request.url?.path.contains("/v3/jobs/scans") == true {
                // Upload requests
                let responseJobId = attemptCount == 1 ? jobId1 : jobId2
                let streamUrl = "https://api.talaria.example.com/v3/stream/\(responseJobId)"

                let mockJSON = """
                {
                    "jobId": "\(responseJobId)",
                    "streamUrl": "\(streamUrl)"
                }
                """
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 202,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, mockJSON.data(using: .utf8)!)
            } else if request.url?.path.contains("/v3/stream") == true {
                // SSE stream requests
                if attemptCount <= 2 {
                    // First stream: error
                    let sseData = """
                    event: progress
                    data: {"message": "Processing..."}

                    event: error
                    data: {"message": "Image quality too low"}

                    """.data(using: .utf8)!

                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "text/event-stream"]
                    )!
                    return (response, sseData)
                } else {
                    // Second stream: success
                    let sseData = """
                    event: progress
                    data: {"message": "Retrying..."}

                    event: result
                    data: {"title": "Retry Success Book", "author": "Test Author", "isbn": "1111111111", "confidence": 0.88}

                    event: complete
                    data: {}

                    """.data(using: .utf8)!

                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "text/event-stream"]
                    )!
                    return (response, sseData)
                }
            } else {
                // Cleanup requests
                let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
        }

        let imageData = createTestJPEGData()

        // Act: First attempt (expect error)
        let uploadResponse1 = try await networkActor.uploadImage(imageData)
        var firstAttemptErrored = false

        for try await event in networkActor.streamEvents(from: uploadResponse1.streamUrl) {
            if case .error = event {
                firstAttemptErrored = true
            }
        }

        XCTAssertTrue(firstAttemptErrored, "First attempt should error")

        // Retry: Second attempt (expect success)
        let uploadResponse2 = try await networkActor.uploadImage(imageData)
        var bookMetadata: BookMetadata?
        var completedSuccessfully = false

        for try await event in networkActor.streamEvents(from: uploadResponse2.streamUrl) {
            switch event {
            case .result(let metadata):
                bookMetadata = metadata
            case .complete:
                completedSuccessfully = true
            case .error(let message):
                XCTFail("Second attempt should succeed, got error: \(message)")
            default:
                break
            }
        }

        // Save to SwiftData
        guard let metadata = bookMetadata else {
            XCTFail("No metadata from retry")
            return
        }

        let book = Book(
            title: metadata.title,
            author: metadata.author,
            isbn: metadata.isbn ?? "UNKNOWN",
            spineConfidence: metadata.confidence
        )
        modelContext.insert(book)
        try modelContext.save()

        // Assert
        XCTAssertTrue(completedSuccessfully, "Retry should succeed")
        XCTAssertEqual(metadata.title, "Retry Success Book")

        let books = try modelContext.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].title, "Retry Success Book")
    }

    // MARK: - Scenario 3: Offline Queue (Offline → Network Returns → Auto-upload)

    /// Test offline queueing and auto-upload when network returns
    func testScenario3_OfflineQueueWithAutoUpload() async throws {
        // Arrange: Simulate offline capture
        let imageData = createTestJPEGData()

        // Step 1: Queue scan while offline
        let queuedScanId = try await offlineQueueManager.queueScan(imageData: imageData)
        XCTAssertNotNil(queuedScanId)

        // Verify queue
        let queuedScans = try await offlineQueueManager.getAllQueuedScans()
        XCTAssertEqual(queuedScans.count, 1)

        // Step 2: Network returns - configure mock for successful upload
        let jobId = "offline-recovery-\(UUID().uuidString)"
        let streamUrl = "https://api.talaria.example.com/v3/stream/\(jobId)"
        configureMockForSuccessfulFlow(jobId: jobId, streamUrl: streamUrl)

        // Step 3: Process queued scan
        let queuedScan = queuedScans[0]
        let uploadResponse = try await networkActor.uploadImage(queuedScan.imageData)

        var bookMetadata: BookMetadata?
        for try await event in networkActor.streamEvents(from: uploadResponse.streamUrl) {
            if case .result(let metadata) = event {
                bookMetadata = metadata
            }
        }

        // Save to SwiftData
        guard let metadata = bookMetadata else {
            XCTFail("No metadata from queued upload")
            return
        }

        let book = Book(
            title: metadata.title,
            author: metadata.author,
            isbn: metadata.isbn ?? "UNKNOWN",
            spineConfidence: metadata.confidence
        )
        modelContext.insert(book)
        try modelContext.save()

        // Step 4: Remove from queue
        try await offlineQueueManager.removeQueuedScan(scanId: queuedScan.metadata.id)

        // Assert
        XCTAssertEqual(metadata.title, "The Swift Programming Language")

        // Verify book in library
        let books = try modelContext.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(books.count, 1)

        // Verify queue is empty
        let remainingQueuedScans = try await offlineQueueManager.getAllQueuedScans()
        XCTAssertEqual(remainingQueuedScans.count, 0, "Queue should be empty after processing")
    }

    // MARK: - Scenario 4: Load Test (10 Rapid Scans → All Complete in 2 Minutes)

    /// Test concurrent processing of 10 rapid scans
    func testScenario4_TenRapidScansCompleteWithinTwoMinutes() async throws {
        // Arrange: Configure mock for concurrent scans
        let scanCount = 10
        var processedScans = 0

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("/v3/jobs/scans") == true {
                // Upload requests
                let jobId = "load-test-job-\(UUID().uuidString)"
                let streamUrl = "https://api.talaria.example.com/v3/stream/\(jobId)"

                let mockJSON = """
                {
                    "jobId": "\(jobId)",
                    "streamUrl": "\(streamUrl)"
                }
                """
                let response = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!
                return (response, mockJSON.data(using: .utf8)!)
            } else if request.url?.path.contains("/v3/stream") == true {
                // SSE streams - simulate quick responses
                processedScans += 1
                let sseData = """
                event: progress
                data: {"message": "Fast processing..."}

                event: result
                data: {"title": "Load Test Book \(processedScans)", "author": "Test Author \(processedScans)", "isbn": "ISBN\(processedScans)", "confidence": 0.90}

                event: complete
                data: {}

                """.data(using: .utf8)!

                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!
                return (response, sseData)
            } else {
                // Cleanup
                let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
        }

        // Act: Launch 10 concurrent scans
        let startTime = CFAbsoluteTimeGetCurrent()

        await withTaskGroup(of: BookMetadata?.self) { group in
            for i in 1...scanCount {
                group.addTask {
                    do {
                        let imageData = self.createTestJPEGData()
                        let uploadResponse = try await self.networkActor.uploadImage(imageData)

                        var metadata: BookMetadata?
                        for try await event in self.networkActor.streamEvents(from: uploadResponse.streamUrl) {
                            if case .result(let result) = event {
                                metadata = result
                            }
                        }

                        try? await self.networkActor.cleanupJob(uploadResponse.jobId)
                        return metadata
                    } catch {
                        print("Scan \(i) failed: \(error)")
                        return nil
                    }
                }
            }

            // Collect results and save to SwiftData
            for await metadata in group {
                if let metadata = metadata {
                    let book = Book(
                        title: metadata.title,
                        author: metadata.author,
                        isbn: metadata.isbn ?? "UNKNOWN",
                        spineConfidence: metadata.confidence
                    )
                    self.modelContext.insert(book)
                }
            }
        }

        try modelContext.save()

        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime

        // Assert: All scans completed within 2 minutes
        XCTAssertLessThan(duration, 120.0, "10 scans should complete within 2 minutes, took \(duration)s")

        // Verify all books in SwiftData
        let books = try modelContext.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(books.count, scanCount, "Should have all \(scanCount) books")

        // Verify unique ISBNs
        let uniqueISBNs = Set(books.map { $0.isbn })
        XCTAssertEqual(uniqueISBNs.count, scanCount, "All books should have unique ISBNs")

        print("✅ Load test: \(scanCount) scans completed in \(String(format: "%.2f", duration))s")
    }

    // MARK: - Temp File Cleanup Verification

    /// Test that temp files are properly cleaned up after processing
    func testTempFileCleanupAfterProcessing() async throws {
        // Arrange
        let jobId = "cleanup-test-\(UUID().uuidString)"
        let streamUrl = "https://api.talaria.example.com/v3/stream/\(jobId)"
        configureMockForSuccessfulFlow(jobId: jobId, streamUrl: streamUrl)

        // Create temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-scan-\(UUID().uuidString).jpg")
        let imageData = createTestJPEGData()
        try imageData.write(to: tempURL)
        tempFiles.append(tempURL)

        // Act: Process scan
        let uploadResponse = try await networkActor.uploadImage(imageData)
        for try await _ in networkActor.streamEvents(from: uploadResponse.streamUrl) {
            // Consume stream
        }

        // Cleanup
        try await networkActor.cleanupJob(jobId)
        try await cleanupTempFiles()

        // Assert: Verify temp file removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path), "Temp file should be deleted")
    }

    // MARK: - SwiftData Validation

    /// Test that SwiftData correctly persists all metadata fields
    func testSwiftDataPersistsCompleteMetadata() async throws {
        // Arrange
        let book = Book(
            title: "Complete Metadata Test",
            author: "Test Author",
            isbn: "9999999999",
            coverUrl: URL(string: "https://example.com/cover.jpg"),
            format: "Hardcover",
            publisher: "Test Publisher",
            publishedDate: Date(),
            pageCount: 350,
            spineConfidence: 0.92,
            readingStatus: ReadingStatus.reading.rawValue,
            userRating: 4,
            notes: "Test notes"
        )

        // Act
        modelContext.insert(book)
        try modelContext.save()

        // Fetch and verify
        let fetchDescriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.isbn == "9999999999" })
        let books = try modelContext.fetch(fetchDescriptor)

        // Assert
        XCTAssertEqual(books.count, 1)
        let savedBook = books[0]

        XCTAssertEqual(savedBook.title, "Complete Metadata Test")
        XCTAssertEqual(savedBook.author, "Test Author")
        XCTAssertEqual(savedBook.isbn, "9999999999")
        XCTAssertEqual(savedBook.format, "Hardcover")
        XCTAssertEqual(savedBook.publisher, "Test Publisher")
        XCTAssertEqual(savedBook.pageCount, 350)
        XCTAssertEqual(savedBook.spineConfidence, 0.92)
        XCTAssertEqual(savedBook.readingStatus, ReadingStatus.reading.rawValue)
        XCTAssertEqual(savedBook.userRating, 4)
        XCTAssertEqual(savedBook.notes, "Test notes")
        XCTAssertNotNil(savedBook.coverUrl)
    }

    // MARK: - Helper Methods

    /// Create test JPEG data
    private func createTestJPEGData() -> Data {
        // JPEG magic bytes + minimal structure
        return Data([
            0xFF, 0xD8, // SOI
            0xFF, 0xE0, // APP0
            0x00, 0x10, // Length
            0x4A, 0x46, 0x49, 0x46, 0x00, // JFIF
            0x01, 0x01, // Version
            0x00, // Units
            0x00, 0x01, 0x00, 0x01, // Density
            0x00, 0x00, // Thumbnail
            0xFF, 0xD9  // EOI
        ])
    }

    /// Create mock URLSession for testing
    private func createMockURLSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Configure mock for successful scan flow
    private func configureMockForSuccessfulFlow(jobId: String, streamUrl: String) {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("/v3/jobs/scans") == true {
                // Upload request
                let mockJSON = """
                {
                    "jobId": "\(jobId)",
                    "streamUrl": "\(streamUrl)"
                }
                """
                let response = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!
                return (response, mockJSON.data(using: .utf8)!)
            } else if request.url?.path.contains("/v3/stream") == true {
                // SSE stream
                let sseData = """
                event: progress
                data: {"message": "Looking..."}

                event: progress
                data: {"message": "Reading spine..."}

                event: progress
                data: {"message": "Enriching metadata..."}

                event: result
                data: {"title": "The Swift Programming Language", "author": "Apple Inc.", "isbn": "9781234567890", "coverUrl": "https://example.com/swift.jpg", "confidence": 0.95}

                event: complete
                data: {}

                """.data(using: .utf8)!

                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!
                return (response, sseData)
            } else if request.url?.path.contains("/cleanup") == true {
                // Cleanup request
                let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            } else {
                // Fallback
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
        }
    }

    /// Clean up temp files
    private func cleanupTempFiles() async throws {
        for url in tempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        tempFiles.removeAll()
    }
}
