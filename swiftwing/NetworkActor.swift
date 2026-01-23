import Foundation

// MARK: - Network Errors

/// Errors that can occur during network operations
enum NetworkError: Error {
    case noConnection
    case timeout
    case serverError(Int)
    case invalidResponse

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
    init(deviceId: String = UUID().uuidString, baseURL: String = "https://api.talaria.example.com") {
        self.deviceId = deviceId
        self.baseURL = baseURL

        // Configure URLSession with 30s timeout and custom User-Agent
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.httpAdditionalHeaders = [
            "User-Agent": "SwiftWing/1.0 iOS/26.0"
        ]

        self.urlSession = URLSession(configuration: configuration)
    }

    // MARK: - Public API

    /// Upload an image to Talaria for book spine identification
    /// - Parameter imageData: JPEG image data to upload
    /// - Returns: UploadResponse containing jobId and streamUrl for SSE
    /// - Throws: NetworkError on failure
    func uploadImage(_ imageData: Data) async throws -> UploadResponse {
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
            case 200...299:
                // Success - parse response
                do {
                    let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
                    return uploadResponse
                } catch {
                    throw NetworkError.invalidResponse
                }

            case 408:
                throw NetworkError.timeout

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
