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
    let success: Bool
    let data: UploadResponseData
}

struct UploadResponseData: Codable, Sendable {
    let jobId: String
    let sseUrl: URL
    let authToken: String?
    let statusUrl: URL?
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
    case canceled                   // Job was canceled by user or system
    case segmented(SegmentedPreview)    // NEW: segmented image with detected regions
    case bookProgress(BookProgressInfo) // NEW: per-book processing progress
}

// MARK: - Progressive Results Types

/// Segmented image preview from backend after initial detection
struct SegmentedPreview: Sendable, Codable {
    let imageData: Data       // JPEG data of annotated image with bounding boxes
    let totalBooks: Int        // Number of book spines detected
}

/// Per-book processing progress update
struct BookProgressInfo: Sendable, Codable {
    let current: Int           // Which book is being processed (1-based)
    let total: Int             // Total books detected
    let stage: String?         // Optional stage description
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
