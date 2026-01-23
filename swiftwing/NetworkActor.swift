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

    // MARK: - Private Implementation

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
}
