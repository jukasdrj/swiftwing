import Foundation

// MARK: - Talaria Service Actor

/// Actor-isolated service for Talaria API integration
/// Wraps network operations with actor isolation and domain model translation
/// Future: Will integrate generated OpenAPI client from swift-openapi-generator
actor TalariaService {

    // MARK: - Properties

    /// URLSession for network operations
    private nonisolated(unsafe) let urlSession: URLSession

    /// Device identifier for API requests
    private let deviceId: String

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
            case 200:
                // Parse response
                let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
                return (jobId: uploadResponse.jobId, streamUrl: uploadResponse.streamUrl)

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
    func streamEvents(streamUrl: URL) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Connect to SSE stream
                    let (bytes, response) = try await URLSession.shared.bytes(from: streamUrl)

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
    private func parseSSEEvent(event: String, data: String) throws -> SSEEvent {
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
