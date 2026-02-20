import Foundation
import os

private let e2eLogger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "e2e-talaria")

#if DEBUG
/// File-based debug logger for SSE stream diagnosis
private func sseLog(_ msg: String) {
    guard ProcessInfo.processInfo.arguments.contains("INJECT_TEST_IMAGE") else { return }
    let logFile = URL(fileURLWithPath: "/tmp/swiftwing-integration-test.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] SSE_STREAM: \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: logFile.path) {
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    } else {
        try? data.write(to: logFile)
    }
}
#endif

// Import NetworkTypes for domain models
// Provides: NetworkError, BookMetadata, SSEEvent, UploadResponse, etc.

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

            case 400, 413, 429, 500...599:
                // Attempt RFC 9457 ProblemDetails parsing
                if let problemDetails = try? JSONDecoder().decode(ProblemDetails.self, from: data) {
                    // For 429, extract retryAfterMs from ProblemDetails
                    if httpResponse.statusCode == 429 {
                        let retryAfter = problemDetails.retryAfterMs.map { TimeInterval($0) / 1000.0 }
                        throw NetworkError.rateLimited(retryAfter: retryAfter)
                    }
                    throw NetworkError.apiError(problemDetails)
                } else {
                    // Fallback to generic server error
                    if httpResponse.statusCode == 429 {
                        let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                            .flatMap { TimeInterval($0) }
                        throw NetworkError.rateLimited(retryAfter: retryAfter)
                    }
                    throw NetworkError.serverError(httpResponse.statusCode)
                }

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
                var lastEventId: String?

                while attempt < maxAttempts {
                    do {
                        // Connect to SSE stream with required headers
                        var request = URLRequest(url: streamUrl)
                        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        if let authToken = authToken {
                            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
                        }
                        // On reconnection, send Last-Event-ID for resume capability
                        if let lastEventId = lastEventId {
                            request.setValue(lastEventId, forHTTPHeaderField: "Last-Event-ID")
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

                        e2eLogger.info("✅ SSE: Connection established, status 200")
                        print("✅ SSE: Connection established successfully")
                        #if DEBUG
                        sseLog("Connection established, status=200, content-type=\(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "nil")")
                        #endif

                        // Parse SSE events
                        // WORKAROUND: bytes.lines silently fails to yield data over HTTP/3 (QUIC)
                        // on iOS 26. Read raw bytes and split on newlines manually instead.
                        var currentEvent: String?
                        var currentData: String?
                        var currentId: String?
                        var lineBuffer = Data()
                        var byteCount = 0

                        #if DEBUG
                        sseLog("Starting byte iterator loop... Task.isCancelled=\(Task.isCancelled)")
                        #endif
                        for try await byte in bytes {
                            byteCount += 1
                            #if DEBUG
                            if byteCount == 1 {
                                sseLog("First byte received!")
                            }
                            #endif
                            if byte == UInt8(ascii: "\n") {
                                let line: String
                                // Strip trailing \r if present (SSE uses \r\n)
                                if lineBuffer.last == UInt8(ascii: "\r") {
                                    line = String(data: lineBuffer.dropLast(), encoding: .utf8) ?? ""
                                } else {
                                    line = String(data: lineBuffer, encoding: .utf8) ?? ""
                                }
                                lineBuffer.removeAll(keepingCapacity: true)

                            #if DEBUG
                            sseLog("LINE[\(byteCount)]: '\(line.isEmpty ? "<BLANK>" : String(line.prefix(120)))'")
                            #endif
                            print("🔍 SSE Line received: '\(line.isEmpty ? "<BLANK>" : String(line.prefix(80)))'")
                            if line.hasPrefix("event:") {
                                currentEvent = String(line.dropFirst(6).trimmingCharacters(in: .whitespaces))
                                print("📨 SSE: Received event type: \(currentEvent ?? "nil")")
                            } else if line.hasPrefix("data:") {
                                currentData = String(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
                                print("📦 SSE: Received data: \(currentData?.prefix(100) ?? "nil")...")
                            } else if line.hasPrefix("id:") {
                                currentId = String(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
                                print("🆔 SSE: Received event ID: \(currentId ?? "nil")")
                            } else if line.isEmpty {
                                print("⚪ SSE: Blank line detected. Event: \(currentEvent ?? "nil"), Data: \(currentData?.prefix(50) ?? "nil")")
                                // Parse event
                                if let event = currentEvent, let data = currentData {
                                    print("🔄 SSE: Processing event '\(event)' with data")

                                    // Parse all events uniformly through SSEEventParser
                                    do {
                                        let parser = SSEEventParser()
                                        let sseEvent = try parser.parse(event: event, data: data)
                                        e2eLogger.info("✅ SSE parsed: \(String(describing: sseEvent))")
                                        print("✅ SSE: Parsed event successfully: \(sseEvent)")
                                        #if DEBUG
                                        sseLog("YIELDING event to continuation: \(event)")
                                        #endif
                                        continuation.yield(sseEvent)

                                        // Store last event ID for reconnection
                                        if let id = currentId {
                                            lastEventId = id
                                        }

                                        // Finish stream on terminal events
                                        switch sseEvent {
                                        case .complete:
                                            print("✅ SSE: Complete event received - finishing stream")
                                            continuation.finish()
                                            return
                                        case .error(let errorInfo):
                                            print("❌ SSE: Error event received: \(errorInfo.message)")
                                            continuation.finish()
                                            return
                                        case .canceled:
                                            print("🛑 SSE: Canceled event received")
                                            continuation.finish()
                                            return
                                        case .progress, .result, .segmented, .bookProgress, .ping, .enrichmentDegraded:
                                            // Continue processing stream
                                            break
                                        }
                                    } catch SSEError.unknownEvent(let name) {
                                        // Silently skip unknown events — forward compatibility.
                                        // New server event types must not crash older app builds.
                                        print("ℹ️ SSE: Skipping unknown event type '\(name)'")
                                    } catch {
                                        // Log parse failure but don't kill the stream —
                                        // a single malformed event shouldn't abort the whole scan.
                                        // The complete event with resultsUrl is the primary delivery mechanism.
                                        print("⚠️ SSE: Failed to parse event '\(event)': \(error) — skipping")
                                        print("   Raw data: \(data.prefix(200))")
                                    }
                                }

                                // Reset for next event
                                currentEvent = nil
                                currentData = nil
                                currentId = nil
                            }
                            } else {
                                // Accumulate non-newline bytes into line buffer
                                lineBuffer.append(byte)
                            }
                        }

                        #if DEBUG
                        sseLog("Byte loop exited normally after \(byteCount) bytes, Task.isCancelled=\(Task.isCancelled)")
                        #endif
                        print("✅ SSE: Stream completed normally")
                        continuation.finish()
                        return // Success - exit retry loop

                    } catch let error as SSEError where error == SSEError.connectionFailed {
                        #if DEBUG
                        sseLog("CATCH connectionFailed: attempt=\(attempt+1)/\(maxAttempts)")
                        #endif
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
                        #if DEBUG
                        sseLog("CATCH generic error: \(error) - type=\(type(of: error)) - cancelled=\(Task.isCancelled)")
                        #endif
                        // Don't retry non-connection errors
                        e2eLogger.error("❌ SSE stream error: \(error.localizedDescription)")
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
            let (data, response) = try await urlSession.data(for: request)

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

            case 401:
                // Auth token expired or invalid — job likely already cleaned up server-side
                print("ℹ️ Cleanup auth expired (401) for job: \(jobId) — treating as success")
                return

            case 404:
                // Job not found (already cleaned up)
                print("ℹ️ Job not found (already cleaned): \(jobId)")
                return

            case 400, 413, 429, 500...599:
                // Attempt RFC 9457 ProblemDetails parsing
                if let problemDetails = try? JSONDecoder().decode(ProblemDetails.self, from: data) {
                    throw NetworkError.apiError(problemDetails)
                } else {
                    print("❌ Cleanup failed: HTTP \(httpResponse.statusCode)")
                    throw NetworkError.serverError(httpResponse.statusCode)
                }

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
        // Construct full URL with ?format=lite query parameter
        var resultsUrlWithFormat = resultsUrl
        if !resultsUrl.contains("?format=lite") {
            resultsUrlWithFormat = resultsUrl.contains("?")
                ? "\(resultsUrl)&format=lite"
                : "\(resultsUrl)?format=lite"
        }

        guard let baseUrl = URL(string: baseURL),
              let url = URL(string: resultsUrlWithFormat, relativeTo: baseUrl)?.absoluteURL else {
            print("❌ Results fetch: Invalid URL - base: \(baseURL), path: \(resultsUrlWithFormat)")
            throw NetworkError.invalidResponse
        }

        print("🔍 Fetching results from: \(url.absoluteString)")

        // Create request with auth and device ID
        var request = URLRequest(url: url)
        request.addValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.addValue(self.deviceId, forHTTPHeaderField: "X-Device-ID")
        request.httpMethod = "GET"

        // Execute request
        let (data, response) = try await urlSession.data(for: request)

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Results fetch: Invalid response type")
            throw NetworkError.invalidResponse
        }

        // Check HTTP status
        switch httpResponse.statusCode {
        case 200:
            // Success - continue to parse
            break

        case 400, 413, 429, 500...599:
            // Attempt RFC 9457 ProblemDetails parsing
            if let problemDetails = try? JSONDecoder().decode(ProblemDetails.self, from: data) {
                throw NetworkError.apiError(problemDetails)
            } else {
                print("❌ Results fetch failed: HTTP \(httpResponse.statusCode)")
                throw NetworkError.serverError(httpResponse.statusCode)
            }

        default:
            print("❌ Results fetch failed: HTTP \(httpResponse.statusCode)")
            throw NetworkError.serverError(httpResponse.statusCode)
        }

        // Parse JSON response
        // Talaria may return books under "results" or "books" key:
        //   Format A: {"success": true, "data": {"results": [BookMetadata, ...]}}
        //   Format B: {"success": true, "data": {"books": [BookMetadata, ...]}}
        let decoder = JSONDecoder()

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any] else {
                print("❌ Results fetch: Missing top-level data object")
                throw NetworkError.invalidResponse
            }

            // Try "results" key first, then "books" (OpenAPI spec uses "books")
            let booksArray: [[String: Any]]
            if let results = dataObj["results"] as? [[String: Any]] {
                booksArray = results
            } else if let books = dataObj["books"] as? [[String: Any]] {
                booksArray = books
            } else {
                print("❌ Results fetch: No 'results' or 'books' key in data")
                throw NetworkError.invalidResponse
            }

            let booksData = try JSONSerialization.data(withJSONObject: booksArray)
            let books = try decoder.decode([BookMetadata].self, from: booksData)
            print("✅ Fetched \(books.count) books from results URL")

            for (index, book) in books.enumerated() {
                print("  ✅ Book \(index + 1): \(book.resolvedTitle) by \(book.resolvedAuthor)")
            }

            return books

        } catch let error as NetworkError {
            throw error
        } catch {
            print("❌ Results fetch: Failed to decode response - \(error)")
            throw NetworkError.invalidResponse
        }
    }

    // MARK: - Private Helpers
    // (Dead code removed - parseSSEEvent extracted to SSEEventParser)
}
