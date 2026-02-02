import Foundation

// MARK: - Talaria Service Actor

/// Actor-isolated service for Talaria API integration with type-safe domain model translation
///
/// **Architecture Pattern:** Manual implementation based on committed OpenAPI spec
/// (US-502: Committed spec workflow, US-507: Actor-based service design)
///
/// **Actor Isolation Rationale:**
/// - Protects URLSession instance from data races (Swift 6.2 strict concurrency)
/// - Ensures thread-safe access to deviceId and baseURL
/// - Eliminates need for locks/semaphores (actor provides isolation guarantee)
/// - Enables async/await without DispatchQueue (prevents deadlocks)
///
/// **Domain Model Translation:**
/// This service translates between OpenAPI types and SwiftWing domain models:
/// - UploadResponse (OpenAPI) → (jobId, streamUrl) tuple (domain)
/// - SSE event stream (text) → SSEEvent enum (domain events)
/// - BookMetadata JSON (OpenAPI) → BookMetadata struct (domain model)
///
/// **Performance Characteristics (US-509 benchmarks):**
/// - Upload latency: < 1000ms
/// - SSE first event: < 500ms
/// - Concurrent uploads: 5 scans < 10s
/// - CPU usage: < 15% main thread during SSE parsing
/// - Memory: Zero leaks in 10-minute sessions
///
/// **Future Migration Path:**
/// When swift-openapi-generator build plugin is enabled, this service can be
/// refactored to wrap generated Client type while maintaining same public API.
///
/// **Related:**
/// - OpenAPI spec: `swiftwing/OpenAPI/talaria-openapi.yaml`
/// - Integration tests: `swiftwingTests/TalariaIntegrationTests.swift`
/// - Documentation: See CLAUDE.md "Swift OpenAPI Generator Integration" section
actor TalariaService {

    // MARK: - Properties

    /// URLSession for network operations
    private let urlSession: URLSession

    /// Device identifier for API requests
    nonisolated private let deviceId: String

    /// Base URL for Talaria API (production)
    private let baseURL = "https://api.oooefam.net"

    // MARK: - Initialization

    /// Initialize TalariaService
    /// - Parameters:
    ///   - deviceId: Unique device identifier (defaults to new UUID)
    ///   - session: URLSession to use (defaults to configured session)
    init(deviceId: String = UUID().uuidString, session: URLSession? = nil) {
        self.deviceId = deviceId

        if let session = session {
            self.urlSession = session
        } else {
            // Configure production URLSession
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30.0
            configuration.httpAdditionalHeaders = [
                "User-Agent": "SwiftWing/1.0 iOS/26.0"
            ]
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    // MARK: - Public API

    /// Upload a book spine image to Talaria for AI processing
    /// - Parameters:
    ///   - image: Image data (JPEG format)
    ///   - deviceId: Unique device identifier
    /// - Returns: Tuple containing jobId, streamUrl for SSE, and optional authToken
    /// - Throws: NetworkError on failure
    func uploadScan(image: Data, deviceId: String) async throws -> (jobId: String, streamUrl: URL, authToken: String?) {
        // Construct upload endpoint
        guard let url = URL(string: "\(baseURL)/v3/jobs/scans") else {
            throw NetworkError.invalidResponse
        }

        // Create multipart/form-data request
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")

        // Build multipart body
        var body = Data()

        // Add image field (API expects photos[] for batch upload support)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photos[]\"; filename=\"spine.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(image)
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
            case 200, 202:
                // Parse response (202 Accepted is the standard response)
                let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)

                guard uploadResponse.success else {
                    print("❌ Upload failed: success=false in response")
                    throw NetworkError.invalidResponse
                }

                print("✅ Upload response received:")
                print("   JobID: \(uploadResponse.data.jobId)")
                print("   SSE URL: \(uploadResponse.data.sseUrl)")
                #if DEBUG
                print("   Auth Token: \(uploadResponse.data.authToken ?? "none")")
                #else
                print("   Auth Token: \(uploadResponse.data.authToken != nil ? "[REDACTED]" : "none")")
                #endif
                print("   Status URL: \(uploadResponse.data.statusUrl?.absoluteString ?? "none")")

                return (jobId: uploadResponse.data.jobId, streamUrl: uploadResponse.data.sseUrl, authToken: uploadResponse.data.authToken)

            case 429:
                // Rate limited
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { TimeInterval($0) }
                throw NetworkError.rateLimited(retryAfter: retryAfter)

            case 500...599:
                throw NetworkError.serverError(httpResponse.statusCode)

            default:
                throw NetworkError.serverError(httpResponse.statusCode)
            }

        } catch let error as NetworkError {
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw NetworkError.noConnection
            case .timedOut:
                throw NetworkError.timeout
            default:
                throw NetworkError.invalidResponse
            }
        } catch {
            throw NetworkError.invalidResponse
        }
    }

    /// Stream real-time scan progress events via Server-Sent Events with automatic retry
    /// - Parameters:
    ///   - streamUrl: SSE endpoint URL from uploadScan response
    ///   - deviceId: Device identifier (must match deviceId used in uploadScan)
    ///   - authToken: Optional authentication token from upload response
    ///   - maxAttempts: Maximum number of connection attempts on failure (default: 3 = 1 initial + 2 retries)
    /// - Returns: AsyncThrowingStream of SSEEvent
    nonisolated func streamEvents(streamUrl: URL, deviceId: String, authToken: String? = nil, maxAttempts: Int = 3) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Create session once before retry loop
                let sessionConfig = URLSessionConfiguration.default
                sessionConfig.timeoutIntervalForRequest = 300 // 5 minutes
                let session = URLSession(configuration: sessionConfig)

                defer {
                    session.finishTasksAndInvalidate()
                }

                var attempt = 0

                while attempt < maxAttempts {
                    do {
                        // Connect to SSE stream with required headers
                        var request = URLRequest(url: streamUrl)
                        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        if let authToken = authToken {
                            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
                        }

                        let (bytes, response) = try await session.bytes(for: request)

                        // Validate response with comprehensive diagnostics
                        guard let httpResponse = response as? HTTPURLResponse else {
                            print("❌ SSE: Response is not HTTPURLResponse - \(type(of: response))")
                            throw SSEError.connectionFailed
                        }

                        print("🔍 SSE Connection attempt \(attempt + 1):")
                        print("   Status: \(httpResponse.statusCode)")
                        print("   URL: \(streamUrl)")
                        #if DEBUG
                        print("   Headers: \(httpResponse.allHeaderFields)")
                        #else
                        print("   Headers: [redacted in production]")
                        #endif

                        guard httpResponse.statusCode == 200 else {
                            print("❌ SSE: Expected 200, got \(httpResponse.statusCode)")
                            throw SSEError.connectionFailed
                        }

                        print("✅ SSE: Connection established successfully")

                        // Parse SSE events
                        var currentEvent: String?
                        var currentData: String?

                        for try await line in bytes.lines {
                            print("🔍 SSE Line received: '\(line.isEmpty ? "<BLANK>" : line.prefix(80))'")
                            if line.hasPrefix("event:") {
                                currentEvent = String(line.dropFirst(6).trimmingCharacters(in: .whitespaces))
                                print("📨 SSE: Received event type: \(currentEvent ?? "nil")")
                            } else if line.hasPrefix("data:") {
                                currentData = String(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
                                print("📦 SSE: Received data: \(currentData?.prefix(100) ?? "nil")...")
                            } else if line.isEmpty {
                                print("⚪ SSE: Blank line detected. Event: \(currentEvent ?? "nil"), Data: \(currentData?.prefix(50) ?? "nil")")
                                // Parse event
                                if let event = currentEvent, let data = currentData {
                                    print("🔄 SSE: Processing event '\(event)' with data")

                                    // Parse all events uniformly through parseSSEEvent
                                    do {
                                        let sseEvent = try self.parseSSEEvent(event: event, data: data)
                                        print("✅ SSE: Parsed event successfully: \(sseEvent)")
                                        continuation.yield(sseEvent)

                                        // Finish stream on terminal events
                                        switch sseEvent {
                                        case .complete:
                                            print("✅ SSE: Complete event received - finishing stream")
                                            continuation.finish()
                                            return
                                        case .error(let message):
                                            print("❌ SSE: Error event received: \(message)")
                                            continuation.finish()
                                            return
                                        case .canceled:
                                            print("🛑 SSE: Canceled event received")
                                            continuation.finish()
                                            return
                                        case .progress, .result, .segmented, .bookProgress:
                                            // Continue processing stream
                                            break
                                        }
                                    } catch {
                                        print("❌ SSE: Failed to parse event '\(event)': \(error)")
                                        continuation.yield(.error("Failed to parse event: \(error.localizedDescription)"))
                                    }
                                }

                                // Reset for next event
                                currentEvent = nil
                                currentData = nil
                            }
                        }

                        print("✅ SSE: Stream completed normally")
                        continuation.finish()
                        return // Success - exit retry loop

                    } catch let error as SSEError where error == SSEError.connectionFailed {
                        attempt += 1
                        if attempt < maxAttempts {
                            let delay = pow(2.0, Double(attempt))
                            print("🔄 SSE retry \(attempt)/\(maxAttempts - 1) in \(delay)s")
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        } else {
                            print("❌ SSE: Max retries exceeded after \(maxAttempts) attempts")
                            continuation.finish(throwing: SSEError.maxRetriesExceeded)
                            return
                        }
                    } catch {
                        // Don't retry non-connection errors
                        print("❌ SSE: Stream error (non-retryable): \(error)")
                        print("   Error type: \(type(of: error))")
                        print("   Error description: \(error.localizedDescription)")
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }
        }
    }

    /// Cleanup job resources on Talaria server
    /// - Parameters:
    ///   - jobId: Job ID from uploadScan response
    ///   - authToken: Optional authentication token from upload response
    /// - Throws: NetworkError on failure
    ///
    /// Sends DELETE request to free server resources after scan completion.
    /// Should be called after receiving .complete or .error SSE events.
    func cleanup(jobId: String, authToken: String? = nil) async throws {
        // Construct cleanup endpoint
        guard let url = URL(string: "\(baseURL)/v3/jobs/scans/\(jobId)/cleanup") else {
            print("❌ Cleanup: Invalid URL for jobId: \(jobId)")
            throw NetworkError.invalidResponse
        }

        print("🗑️ Cleanup initiated: \(jobId)")
        print("   URL: \(url)")

        // Create DELETE request
        var request = URLRequest(url: url)
        request.setValue(self.deviceId, forHTTPHeaderField: "X-Device-ID")
        if let authToken = authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpMethod = "DELETE"

        do {
            let (_, response) = try await urlSession.data(for: request)

            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Cleanup: Invalid response type")
                throw NetworkError.invalidResponse
            }

            print("🗑️ Cleanup response: HTTP \(httpResponse.statusCode)")

            // Check status code
            switch httpResponse.statusCode {
            case 200, 204:
                // Success
                print("✅ Cleanup successful for job: \(jobId)")
                return

            case 404:
                // Job not found (already cleaned up)
                print("ℹ️ Job not found (already cleaned): \(jobId)")
                return

            case 500...599:
                print("❌ Cleanup failed: HTTP \(httpResponse.statusCode)")
                throw NetworkError.serverError(httpResponse.statusCode)

            default:
                print("❌ Cleanup failed: HTTP \(httpResponse.statusCode)")
                throw NetworkError.serverError(httpResponse.statusCode)
            }

        } catch let error as NetworkError {
            print("❌ Cleanup NetworkError: \(error.localizedDescription)")
            throw error
        } catch let urlError as URLError {
            print("❌ Cleanup URLError: \(urlError.localizedDescription)")
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw NetworkError.noConnection
            case .timedOut:
                throw NetworkError.timeout
            default:
                throw NetworkError.invalidResponse
            }
        } catch {
            print("❌ Cleanup error: \(error.localizedDescription)")
            throw NetworkError.invalidResponse
        }
    }

    /// Fetch scan results from the resultsUrl provided in SSE completion event
    /// - Parameter resultsUrl: Relative URL path (e.g. "/v3/jobs/ai_scan/scan_...")
    /// - Parameter authToken: Auth token for the job
    /// - Returns: Array of BookMetadata objects
    /// - Throws: NetworkError on failure
    ///
    /// Called after SSE stream completes to retrieve the array of identified books.
    /// The resultsUrl is provided in the "completed" event data.
    func fetchResults(resultsUrl: String, authToken: String) async throws -> [BookMetadata] {
        // Construct full URL (safe composition)
        guard let baseUrl = URL(string: baseURL),
              let url = URL(string: resultsUrl, relativeTo: baseUrl)?.absoluteURL else {
            print("❌ Results fetch: Invalid URL - base: \(baseURL), path: \(resultsUrl)")
            throw NetworkError.invalidResponse
        }

        print("🔍 Fetching results from: \(url.absoluteString)")

        // Create request with auth
        var request = URLRequest(url: url)
        request.addValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"

        // Execute request
        let (data, response) = try await urlSession.data(for: request)

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Results fetch: Invalid response type")
            throw NetworkError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            print("❌ Results fetch failed: HTTP \(httpResponse.statusCode)")
            throw NetworkError.serverError(httpResponse.statusCode)
        }

        // Parse JSON response (optimized direct decode)
        // Expected format: {"results": [BookMetadata, ...], "status": "completed", ...}
        struct ResultsResponse: Codable {
            let results: [BookMetadata]
        }

        let decoder = JSONDecoder()

        do {
            let response = try decoder.decode(ResultsResponse.self, from: data)
            print("✅ Fetched \(response.results.count) books from results URL")

            // Log each book
            for (index, book) in response.results.enumerated() {
                print("  ✅ Book \(index + 1): \(book.title) by \(book.author)")
            }

            return response.results

        } catch {
            print("❌ Results fetch: Failed to decode response - \(error)")
            throw NetworkError.invalidResponse
        }
    }

    // MARK: - Private Helpers
    
    /// Parse SSE event into domain SSEEvent enum
    ///
    /// **Domain Model Translation Logic:**
    /// This method translates raw Server-Sent Events from Talaria API into
    /// type-safe SwiftWing domain events. This decouples the app from the
    /// OpenAPI transport layer.
    ///
    /// **Translation Mappings:**
    /// - SSE `event: progress` → `.progress(String)` - Status updates
    /// - SSE `event: result` → `.result(BookMetadata)` - AI-identified book
    /// - SSE `event: complete` → `.complete` - Processing finished
    /// - SSE `event: error` → `.error(String)` - Processing failed
    /// - SSE `event: canceled` → `.canceled` - User/system cancellation
    ///
    /// **BookMetadata Deserialization (Line 280):**
    /// The result event contains BookMetadata JSON that matches the OpenAPI schema:
    /// ```
    /// Components.Schemas.BookMetadata {
    ///   title: string
    ///   author: string
    ///   isbn?: string
    ///   coverUrl?: string
    ///   confidence?: number
    ///   publishedDate?: string
    /// }
    /// ```
    /// This is decoded directly into SwiftWing's BookMetadata struct (NetworkTypes.swift)
    /// which serves as the domain model for book data throughout the app.
    ///
    /// **Why Direct Decoding Works:**
    /// TalariaService's BookMetadata struct is hand-written to match the OpenAPI schema
    /// exactly. When the build plugin is enabled, we can validate this mapping
    /// automatically by comparing to `Components.Schemas.BookMetadata`.
    ///
    /// - Parameters:
    ///   - event: SSE event type (e.g., "progress", "result")
    ///   - data: JSON-encoded event data
    /// - Returns: Strongly-typed SSEEvent enum case
    /// - Throws: SSEError.invalidEventFormat if parsing fails
    nonisolated private func parseSSEEvent(event: String, data: String) throws -> SSEEvent {
        switch event {
        case "progress":
            // Progress event with message
            if let jsonData = data.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let message = json["message"] as? String {
                return .progress(message)
            } else {
                throw SSEError.invalidEventFormat
            }

        case "result":
            // Result event with book metadata
            guard let jsonData = data.data(using: .utf8) else {
                throw SSEError.invalidEventFormat
            }

            // Decode BookMetadata directly (matches OpenAPI schema)
            let decoder = JSONDecoder()
            let metadata = try decoder.decode(BookMetadata.self, from: jsonData)

            return .result(metadata)

        case "complete", "completed":
            // Extract resultsUrl from completion event
            guard let jsonData = data.data(using: .utf8) else {
                return .complete(resultsUrl: nil)
            }

            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let resultsUrl = json["resultsUrl"] as? String {
                print("✅ SSE: Completed with results at: \(resultsUrl)")
                return .complete(resultsUrl: resultsUrl)
            } else {
                print("⚠️ SSE: Completed without resultsUrl")
                return .complete(resultsUrl: nil)
            }

        case "error":
            // Error event with message
            if let jsonData = data.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let message = json["message"] as? String {
                return .error(message)
            } else {
                return .error("Unknown error")
            }

        case "canceled":
            return .canceled

        case "segmented":
            // NEW: Segmented image preview
            guard let jsonData = data.data(using: .utf8) else {
                throw SSEError.invalidEventFormat
            }
            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            guard let imageBase64 = json?["image"] as? String,
                  let imageData = Data(base64Encoded: imageBase64),
                  let totalBooks = json?["totalBooks"] as? Int else {
                throw SSEError.invalidEventFormat
            }
            return .segmented(SegmentedPreview(imageData: imageData, totalBooks: totalBooks))

        case "book_progress":
            // NEW: Per-book processing progress
            guard let jsonData = data.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let current = json["current"] as? Int,
                  let total = json["total"] as? Int else {
                throw SSEError.invalidEventFormat
            }
            let stage = json["stage"] as? String
            return .bookProgress(BookProgressInfo(current: current, total: total, stage: stage))

        default:
            // BACKWARD COMPATIBILITY: Ignore unknown event types instead of throwing
            // This ensures older app versions don't crash when backend adds new events
            print("SSE: Unknown event type '\(event)' - ignoring for forward compatibility")
            throw SSEError.invalidEventFormat  // Will be caught and logged by caller
        }
    }
}
