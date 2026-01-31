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
    /// - Returns: Tuple containing jobId and streamUrl for SSE
    /// - Throws: NetworkError on failure
    func uploadScan(image: Data, deviceId: String) async throws -> (jobId: String, streamUrl: URL) {
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

                return (jobId: uploadResponse.data.jobId, streamUrl: uploadResponse.data.sseUrl)

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
    ///   - maxAttempts: Maximum number of connection attempts on failure (default: 3 = 1 initial + 2 retries)
    /// - Returns: AsyncThrowingStream of SSEEvent
    nonisolated func streamEvents(streamUrl: URL, maxAttempts: Int = 3) -> AsyncThrowingStream<SSEEvent, Error> {
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
                        // Connect to SSE stream with device ID header
                        var request = URLRequest(url: streamUrl)
                        request.setValue(self.deviceId, forHTTPHeaderField: "X-Device-ID")

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
                            if line.hasPrefix("event:") {
                                currentEvent = String(line.dropFirst(6).trimmingCharacters(in: .whitespaces))
                                print("📨 SSE: Received event type: \(currentEvent ?? "nil")")
                            } else if line.hasPrefix("data:") {
                                currentData = String(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
                                print("📦 SSE: Received data: \(currentData?.prefix(100) ?? "nil")...")
                            } else if line.isEmpty {
                                // Parse event
                                if let event = currentEvent, let data = currentData {
                                    print("🔄 SSE: Processing event '\(event)' with data")

                                    if event == "complete" {
                                        // V3 Architecture: Fetch results from URL provided in complete event
                                        // 1. Decode complete event to get resultsUrl
                                        // 2. Fetch results
                                        // 3. Emit .result for each book
                                        // 4. Emit .complete

                                        do {
                                            guard let resultsUrl = try self.extractResultsUrl(from: data) else {
                                                print("❌ SSE: No results URL in complete event")
                                                throw SSEError.invalidEventFormat
                                            }
                                            print("✅ SSE: Extracted results URL: \(resultsUrl)")

                                            // Fetch and emit results
                                            let books = try await self.fetchResults(from: resultsUrl)
                                            print("📚 SSE: Fetched \(books.count) books from results endpoint")

                                            for book in books {
                                                print("📚 Yielding .result event for: \(book.title)")
                                                continuation.yield(.result(book))
                                            }
                                        } catch {
                                            print("❌ SSE: Failed to process complete event: \(error)")
                                            continuation.yield(.error("Failed to fetch results: \(error.localizedDescription)"))
                                            continuation.finish()
                                            return  // Don't yield .complete on error
                                        }

                                        continuation.yield(.complete)
                                        continuation.finish()
                                        return
                                    } else {
                                        // Handle other events (progress, error)
                                        do {
                                            let sseEvent = try self.parseSSEEvent(event: event, data: data)
                                            print("✅ SSE: Parsed event successfully: \(sseEvent)")
                                            continuation.yield(sseEvent)

                                            if case .error(let message) = sseEvent {
                                                print("❌ SSE: Error event received: \(message)")
                                                continuation.finish()
                                                return
                                            } else if case .canceled = sseEvent {
                                                print("🛑 SSE: Canceled event received")
                                                continuation.finish()
                                                return
                                            }
                                        } catch {
                                            print("❌ SSE: Failed to parse event '\(event)': \(error)")
                                        }
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
    /// - Parameter jobId: Job ID from uploadScan response
    /// - Throws: NetworkError on failure
    ///
    /// Sends DELETE request to free server resources after scan completion.
    /// Should be called after receiving .complete or .error SSE events.
    func cleanup(jobId: String) async throws {
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
    
    // MARK: - Private Helpers
    
    /// Extract resultsUrl from complete event JSON
    nonisolated private func extractResultsUrl(from jsonString: String) throws -> URL? {
        print("🔍 Extracting resultsUrl from complete event data")
        guard let data = jsonString.data(using: .utf8) else {
            print("❌ Failed to convert JSON string to Data")
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ Failed to parse JSON: \(jsonString.prefix(200))...")
            return nil
        }
        guard let path = json["resultsUrl"] as? String else {
            print("❌ No resultsUrl field in JSON. Available keys: \(json.keys)")
            return nil
        }
        let fullUrl = URL(string: "\(baseURL)\(path)")
        print("✅ Extracted resultsUrl: \(fullUrl?.absoluteString ?? "nil")")
        return fullUrl
    }
    
    /// Fetch full job results from the API
    private func fetchResults(from url: URL) async throws -> [BookMetadata] {
        print("🌐 Fetching results from: \(url)")
        var request = URLRequest(url: url)
        request.setValue(self.deviceId, forHTTPHeaderField: "X-Device-ID")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Response is not HTTPURLResponse")
            throw NetworkError.invalidResponse
        }

        print("📡 Results fetch HTTP \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            print("❌ Expected 200, got \(httpResponse.statusCode)")
            #if DEBUG
            if let responseBody = String(data: data, encoding: .utf8) {
                print("   Response body: \(responseBody.prefix(500))")
            }
            #endif
            throw NetworkError.invalidResponse
        }

        // Decode JobResultsResponse (V3 API)
        // Structure: { success: true, data: { results: [BookMetadata], ... } }
        struct JobResultsResponse: Codable {
            let success: Bool
            let data: JobResultsData
        }

        struct JobResultsData: Codable {
            let results: [BookMetadata]
        }

        let resultsResponse = try JSONDecoder().decode(JobResultsResponse.self, from: data)
        print("✅ Decoded \(resultsResponse.data.results.count) books from results endpoint")
        return resultsResponse.data.results
    }

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

        case "complete":
            return .complete

        case "error":
            // Error event with message
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
