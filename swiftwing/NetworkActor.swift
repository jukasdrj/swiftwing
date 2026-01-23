import Foundation

// MARK: - Network Errors

/// Errors that can occur during network operations
enum NetworkError: Error {
    case noConnection
    case timeout
    case serverError(Int)
    case invalidResponse
    case rateLimited(retryAfter: TimeInterval?)

    var localizedDescription: String {
        switch self {
        case .noConnection:
            return "No internet connection available"
        case .timeout:
            return "Request timed out"
        case .serverError(let code):
            return "Server error (HTTP \(code))"
        case .invalidResponse:
            return "Invalid server response"
        case .rateLimited(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limited - retry after \(Int(retryAfter))s"
            } else {
                return "Rate limited - retry later"
            }
        }
    }
}

// MARK: - Upload Response

/// Response from image upload to Talaria API
struct UploadResponse: Codable, Sendable {
    let jobId: String
    let streamUrl: URL
}

// MARK: - Book Metadata

/// Book metadata returned from Talaria AI enrichment
struct BookMetadata: Codable, Sendable {
    let title: String
    let author: String
    let isbn: String?
    let coverUrl: URL?
    let publisher: String?
    let publishedDate: String?
    let pageCount: Int?
    let format: String?
    let confidence: Double?
}

// MARK: - SSE Events

/// Server-Sent Event types from Talaria streaming API
enum SSEEvent: Sendable {
    case progress(String)           // Real-time status: "Looking...", "Reading...", "Enriching..."
    case result(BookMetadata)       // Book metadata from AI
    case complete                   // Job finished successfully
    case error(String)              // Job failed with error message
}

// MARK: - SSE Error

/// Errors specific to SSE streaming
enum SSEError: Error {
    case streamTimeout
    case invalidEventFormat
    case connectionFailed
    case maxRetriesExceeded

    var localizedDescription: String {
        switch self {
        case .streamTimeout:
            return "SSE stream timed out (5 minute maximum)"
        case .invalidEventFormat:
            return "Invalid SSE event format"
        case .connectionFailed:
            return "Failed to establish SSE connection"
        case .maxRetriesExceeded:
            return "Maximum reconnection attempts exceeded"
        }
    }
}

// MARK: - Network Actor

/// Thread-safe actor for handling all network operations with Talaria API
actor NetworkActor {

    // MARK: - Properties

    /// URLSession configured for network operations
    private let urlSession: URLSession

    /// Device identifier for API requests (persisted from Epic 1)
    private let deviceId: String

    /// Base URL for Talaria API
    private let baseURL: String

    // MARK: - Initialization

    /// Initialize NetworkActor with configuration
    /// - Parameters:
    ///   - deviceId: Unique device identifier (will be from Keychain in production)
    ///   - baseURL: Talaria API base URL
    ///   - session: Custom URLSession (for testing only - uses default in production)
    init(deviceId: String = UUID().uuidString, baseURL: String = "https://api.talaria.example.com", session: URLSession? = nil) {
        self.deviceId = deviceId
        self.baseURL = baseURL

        if let session = session {
            // Use provided session (for testing with MockURLProtocol)
            self.urlSession = session
        } else {
            // Configure production URLSession with 30s timeout and custom User-Agent
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30.0
            configuration.httpAdditionalHeaders = [
                "User-Agent": "SwiftWing/1.0 iOS/26.0"
            ]
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    // MARK: - Public API

    /// Upload an image to Talaria for book spine identification
    /// - Parameter imageData: JPEG image data to upload
    /// - Returns: UploadResponse containing jobId and streamUrl for SSE
    /// - Throws: NetworkError on failure
    func uploadImage(_ imageData: Data) async throws -> UploadResponse {
        // Attempt upload with retry logic
        return try await performUploadWithRetry(imageData: imageData, maxRetries: 3)
    }

    /// Connect to SSE stream and receive real-time events from Talaria
    /// - Parameter streamUrl: URL of the SSE endpoint from UploadResponse
    /// - Returns: AsyncThrowingStream of SSEEvents (progress, result, complete, error)
    /// - Throws: SSEError on connection failure, timeout, or max retries exceeded
    ///
    /// Stream will automatically close on 'complete' or 'error' events.
    /// Implements 5-minute timeout per stream and exponential backoff reconnection.
    func streamEvents(from streamUrl: URL) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.performStreamWithRetry(streamUrl: streamUrl, continuation: continuation, maxRetries: 3, currentAttempt: 0)
            }
        }
    }

    // MARK: - Private Implementation (Upload)

    /// Perform upload with exponential backoff retry for server errors
    private func performUploadWithRetry(imageData: Data, maxRetries: Int, currentAttempt: Int = 0) async throws -> UploadResponse {
        do {
            return try await performUpload(imageData: imageData)
        } catch NetworkError.serverError(let statusCode) where statusCode >= 500 && currentAttempt < maxRetries {
            // Server error (5xx) - retry with exponential backoff
            let backoffSeconds = pow(2.0, Double(currentAttempt)) // 1s, 2s, 4s
            try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
            return try await performUploadWithRetry(imageData: imageData, maxRetries: maxRetries, currentAttempt: currentAttempt + 1)
        } catch NetworkError.rateLimited(let retryAfter) {
            // Rate limited (429) - respect retry-after header
            if let retryAfter = retryAfter {
                try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                return try await performUpload(imageData: imageData)
            } else {
                // No retry-after header, use default backoff
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2s default
                return try await performUpload(imageData: imageData)
            }
        }
    }

    /// Perform single upload attempt
    private func performUpload(imageData: Data) async throws -> UploadResponse {
        // Construct upload endpoint
        guard let url = URL(string: "\(baseURL)/v3/jobs/scans") else {
            throw NetworkError.invalidResponse
        }

        // Create multipart/form-data request
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()

        // Add deviceId field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"deviceId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(deviceId)\r\n".data(using: .utf8)!)

        // Add image field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"spine.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Perform upload
        do {
            let (data, response) = try await urlSession.data(for: request)

            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            // Check status code
            switch httpResponse.statusCode {
            case 202:
                // Accepted - parse response
                do {
                    let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
                    return uploadResponse
                } catch {
                    throw NetworkError.invalidResponse
                }

            case 408:
                throw NetworkError.timeout

            case 429:
                // Rate limited - extract retry-after header
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { TimeInterval($0) }
                throw NetworkError.rateLimited(retryAfter: retryAfter)

            case 500...599:
                // Server error - will be retried by caller
                throw NetworkError.serverError(httpResponse.statusCode)

            default:
                throw NetworkError.serverError(httpResponse.statusCode)
            }

        } catch let error as NetworkError {
            // Re-throw our custom errors
            throw error
        } catch let urlError as URLError {
            // Map URLError to NetworkError
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw NetworkError.noConnection
            case .timedOut:
                throw NetworkError.timeout
            default:
                throw NetworkError.invalidResponse
            }
        } catch {
            // Unknown error
            throw NetworkError.invalidResponse
        }
    }

    // MARK: - Private Implementation (SSE Streaming)

    /// Perform SSE stream with exponential backoff retry on connection failures
    private func performStreamWithRetry(
        streamUrl: URL,
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation,
        maxRetries: Int,
        currentAttempt: Int
    ) async {
        do {
            try await performStream(streamUrl: streamUrl, continuation: continuation)
        } catch SSEError.connectionFailed where currentAttempt < maxRetries {
            // Connection failed - retry with exponential backoff
            let backoffSeconds = pow(2.0, Double(currentAttempt)) // 1s, 2s, 4s
            try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
            await performStreamWithRetry(
                streamUrl: streamUrl,
                continuation: continuation,
                maxRetries: maxRetries,
                currentAttempt: currentAttempt + 1
            )
        } catch SSEError.connectionFailed {
            // Max retries exceeded
            continuation.finish(throwing: SSEError.maxRetriesExceeded)
        } catch {
            // Other errors (timeout, invalid format, etc.)
            continuation.finish(throwing: error)
        }
    }

    /// Perform single SSE stream attempt with 5-minute timeout
    private func performStream(
        streamUrl: URL,
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation
    ) async throws {
        // Create timeout task (5 minutes = 300 seconds)
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
        }

        // Create stream task
        let streamTask = Task {
            try await self.readSSEStream(streamUrl: streamUrl, continuation: continuation)
        }

        // Race between timeout and stream completion
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await timeoutTask.value }
                group.addTask { try await streamTask.value }

                // Wait for first task to complete
                try await group.next()

                // Cancel remaining tasks
                group.cancelAll()
            }
        } catch is CancellationError {
            // Stream completed normally (timeout task was cancelled)
            return
        } catch {
            // Timeout or stream error
            timeoutTask.cancel()
            streamTask.cancel()

            if !Task.isCancelled && timeoutTask.isCancelled {
                // Timeout task was cancelled = stream finished first
                throw error
            } else {
                // Timeout occurred
                throw SSEError.streamTimeout
            }
        }
    }

    /// Read and parse SSE stream from URL
    private func readSSEStream(
        streamUrl: URL,
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation
    ) async throws {
        // Attempt to connect to SSE endpoint
        let (bytes, response) = try await urlSession.bytes(from: streamUrl)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SSEError.connectionFailed
        }

        // Parse SSE events line by line
        var currentEvent: String?
        var currentData: String?

        for try await line in bytes.lines {
            // SSE format:
            // event: progress
            // data: {"message": "Looking..."}
            // (blank line = event delimiter)

            if line.hasPrefix("event:") {
                // Event type line
                currentEvent = String(line.dropFirst(6).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("data:") {
                // Data line
                currentData = String(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
            } else if line.isEmpty {
                // Blank line = event complete, parse and yield
                if let event = currentEvent, let data = currentData {
                    if let sseEvent = try? parseSSEEvent(event: event, data: data) {
                        continuation.yield(sseEvent)

                        // Close stream on terminal events
                        if case .complete = sseEvent {
                            continuation.finish()
                            return
                        } else if case .error = sseEvent {
                            continuation.finish()
                            return
                        }
                    }
                }

                // Reset for next event
                currentEvent = nil
                currentData = nil
            }
        }

        // Stream ended without explicit complete/error
        continuation.finish()
    }

    /// Parse SSE event and data into SSEEvent enum
    private func parseSSEEvent(event: String, data: String) throws -> SSEEvent {
        switch event {
        case "progress":
            // Progress event: data is a JSON object with "message" field
            if let jsonData = data.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let message = json["message"] as? String {
                return .progress(message)
            } else {
                throw SSEError.invalidEventFormat
            }

        case "result":
            // Result event: data is BookMetadata JSON
            guard let jsonData = data.data(using: .utf8) else {
                throw SSEError.invalidEventFormat
            }
            let metadata = try JSONDecoder().decode(BookMetadata.self, from: jsonData)
            return .result(metadata)

        case "complete":
            // Complete event: no data required
            return .complete

        case "error":
            // Error event: data is a JSON object with "message" field
            if let jsonData = data.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let message = json["message"] as? String {
                return .error(message)
            } else {
                return .error("Unknown error")
            }

        default:
            throw SSEError.invalidEventFormat
        }
    }
}
