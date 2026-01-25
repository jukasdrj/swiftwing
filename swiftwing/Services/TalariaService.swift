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
                    throw NetworkError.invalidResponse
                }
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

    /// Stream real-time scan progress events via Server-Sent Events
    /// - Parameter streamUrl: SSE endpoint URL from uploadScan response
    /// - Returns: AsyncThrowingStream of SSEEvent
    ///
    /// Events emitted:
    /// - .progress(String) - Status updates ("Looking...", "Reading...", etc.)
    /// - .result(BookMetadata) - Book metadata from AI
    /// - .complete - Processing finished successfully
    /// - .error(String) - Processing failed
    /// - .canceled - Processing was canceled by user or system
    nonisolated func streamEvents(streamUrl: URL) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Connect to SSE stream with device ID header
                    var request = URLRequest(url: streamUrl)
                    request.setValue(self.deviceId, forHTTPHeaderField: "X-Device-ID")
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    // Validate response
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        throw SSEError.connectionFailed
                    }

                    // Parse SSE events
                    var currentEvent: String?
                    var currentData: String?

                    for try await line in bytes.lines {
                        // SSE format:
                        // event: <type>
                        // data: <json>
                        // (blank line = event complete)

                        if line.hasPrefix("event:") {
                            currentEvent = String(line.dropFirst(6).trimmingCharacters(in: .whitespaces))
                        } else if line.hasPrefix("data:") {
                            currentData = String(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
                        } else if line.isEmpty {
                            // Parse complete event
                            if let event = currentEvent, let data = currentData {
                                if let sseEvent = try? self.parseSSEEvent(event: event, data: data) {
                                    continuation.yield(sseEvent)

                                    // Close stream on terminal events
                                    if case .complete = sseEvent {
                                        continuation.finish()
                                        return
                                    } else if case .error = sseEvent {
                                        continuation.finish()
                                        return
                                    } else if case .canceled = sseEvent {
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

                    // Stream ended
                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
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
            throw NetworkError.invalidResponse
        }

        // Create DELETE request
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        do {
            let (_, response) = try await urlSession.data(for: request)

            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            // Check status code
            switch httpResponse.statusCode {
            case 200, 204:
                // Success
                return

            case 404:
                // Job not found (already cleaned up)
                return

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
