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
    /// - Returns: Tuple containing jobId, optional streamUrl, status, and optional auth token
    /// - Throws: NetworkError on failure
    ///
    /// **API Contract:** Returns fields from JobResponseSchema (status, streamUrl, token).
    /// The status field indicates job state (queued, processing, completed, failed, canceled).
    /// streamUrl is optional (server transition tolerance); use polling path if nil.
    func uploadScan(image: Data, deviceId: String) async throws -> (jobId: String, streamUrl: URL?, status: JobStatus, token: String?) {
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
                    e2eLogger.error("Upload failed: success=false in response")
                    throw NetworkError.invalidResponse
                }

                e2eLogger.info("Upload response received: JobID=\(uploadResponse.data.jobId, privacy: .public) Status=\(String(describing: uploadResponse.data.status), privacy: .public) StreamURL=\(String(describing: uploadResponse.data.streamUrl), privacy: .public)")

                return (jobId: uploadResponse.data.jobId, streamUrl: uploadResponse.data.streamUrl, status: uploadResponse.data.status, token: uploadResponse.data.token)

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

    /// Fetch scan results from a job-provided results URL
    /// - Parameter resultsUrl: Relative URL path (e.g. "/v3/jobs/ai_scan/scan_...")
    /// - Parameter authToken: Auth token for the job
    /// - Returns: Array of BookMetadata objects
    /// - Throws: NetworkError on failure
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
            e2eLogger.error("Results fetch: Invalid URL - base: \(self.baseURL, privacy: .public), path: \(resultsUrlWithFormat, privacy: .public)")
            throw NetworkError.invalidResponse
        }

        e2eLogger.debug("Fetching results from: \(url.absoluteString, privacy: .public)")

        // Create request with auth and device ID
        var request = URLRequest(url: url)
        request.addValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.addValue(self.deviceId, forHTTPHeaderField: "X-Device-ID")
        request.httpMethod = "GET"

        // Execute request
        let (data, response) = try await urlSession.data(for: request)

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            e2eLogger.error("Results fetch: Invalid response type")
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
                e2eLogger.error("Results fetch failed: HTTP \(httpResponse.statusCode, privacy: .public)")
                throw NetworkError.serverError(httpResponse.statusCode)
            }

        default:
            e2eLogger.error("Results fetch failed: HTTP \(httpResponse.statusCode, privacy: .public)")
            throw NetworkError.serverError(httpResponse.statusCode)
        }

        // Parse JSON response
        // Talaria returns books under "results" key:
        //   {"success": true, "data": {"results": [BookMetadata, ...]}}
        let decoder = JSONDecoder()

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any] else {
                e2eLogger.error("Results fetch: Missing top-level data object")
                throw NetworkError.invalidResponse
            }

            let booksArray: [[String: Any]]
            if let results = dataObj["results"] as? [[String: Any]] {
                booksArray = results
            } else {
                e2eLogger.error("Results fetch: No 'results' key in data")
                throw NetworkError.invalidResponse
            }

            let booksData = try JSONSerialization.data(withJSONObject: booksArray)
            let books = try decoder.decode([BookMetadata].self, from: booksData)
            e2eLogger.info("Fetched \(books.count, privacy: .public) books from results URL")

            for (index, book) in books.enumerated() {
                e2eLogger.debug("Book \(index + 1, privacy: .public): \(book.resolvedTitle, privacy: .public) by \(book.resolvedAuthor, privacy: .public)")
            }

            return books

        } catch let error as NetworkError {
            throw error
        } catch {
            e2eLogger.error("Results fetch: Failed to decode response - \(error, privacy: .public)")
            throw NetworkError.invalidResponse
        }
    }

    /// Exponential backoff with 4s cap: 1s, 1s, 2s, 2s, 4s, 4s, ...
    private nonisolated func backoffDelay(for attempt: Int) -> TimeInterval {
        min(pow(2.0, Double((attempt - 1) / 2)), 4.0)
    }

    /// Poll job status until completion or failure, then fetch the results
    func pollScanStatus(jobId: String, interval: TimeInterval = 1.0) async throws -> [BookMetadata] {
        guard let url = URL(string: "\(baseURL)/v3/jobs/scans/\(jobId)") else {
            throw NetworkError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(self.deviceId, forHTTPHeaderField: "X-Device-ID")
        request.httpMethod = "GET"

        var pollAttempt = 0
        // ~5 minutes at the 4s backoff cap — bounds battery/network cost if a
        // job gets stuck server-side in queued/processing
        let maxPollAttempts = 75

        while pollAttempt < maxPollAttempts {
            // Check if the current task has been cancelled (e.g. app backgrounded or screen dismissed)
            if Task.isCancelled {
                throw CancellationError()
            }

            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                let statusResponse = try JSONDecoder().decode(JobStatusResponse.self, from: data)

                if statusResponse.data.status == .completed {
                    // Job is completed, fetch full results
                    return try await fetchPollingResults(jobId: jobId)
                } else if statusResponse.data.status == .failed {
                    throw NetworkError.serverError(500)
                } else if statusResponse.data.status == .canceled {
                    throw CancellationError()
                }
            case 404:
                throw NetworkError.serverError(404)
            default:
                throw NetworkError.serverError(httpResponse.statusCode)
            }

            // Sleep with adaptive backoff before checking again
            pollAttempt += 1
            let delay = backoffDelay(for: pollAttempt)
            e2eLogger.debug("Poll attempt \(pollAttempt, privacy: .public) - waiting \(delay, privacy: .public)s before next check")
            try await Task.sleep(for: .seconds(delay))
        }

        e2eLogger.error("Polling timed out after \(maxPollAttempts, privacy: .public) attempts for job \(jobId, privacy: .public)")
        throw NetworkError.timeout
    }

    /// Fetch results for completed job in stateless polling mode
    private func fetchPollingResults(jobId: String) async throws -> [BookMetadata] {
        guard let url = URL(string: "\(baseURL)/v3/jobs/scans/\(jobId)/results?format=lite") else {
            throw NetworkError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(self.deviceId, forHTTPHeaderField: "X-Device-ID")
        request.httpMethod = "GET"

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NetworkError.invalidResponse
        }

        let resultsResponse = try JSONDecoder().decode(ScanResultsResponse.self, from: data)
        return resultsResponse.data.results
    }

    // MARK: - Private Helpers
    // (Dead code removed - parseSSEEvent extracted to SSEEventParser)
}
