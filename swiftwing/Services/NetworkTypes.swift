import Foundation

// MARK: - RFC 9457 Problem Details

/// RFC 9457 Problem Details for HTTP APIs
///
/// Standardized error response format used by Talaria API for structured error handling.
/// Maps directly to RFC 9457 specification for problem details in HTTP APIs.
///
/// **Fields:**
/// - `success`: Always false for error responses
/// - `type`: Problem type URI (e.g., "about:blank")
/// - `title`: Short human-readable summary (e.g., "Unprocessable Entity")
/// - `status`: HTTP status code (400, 429, 500, etc.)
/// - `detail`: Human-readable explanation of the problem
/// - `code`: Machine-readable error code for programmatic handling
/// - `retryable`: Whether the request can be retried
/// - `retryAfterMs`: Milliseconds to wait before retry (for rate limiting)
/// - `instance`: Unique identifier for this problem instance
/// - `metadata`: Additional context-specific data
///
/// **Talaria API Inconsistencies:**
/// - Some responses include `retryAfterMs` (non-standard, but useful for rate limiting)
/// - Field names use camelCase instead of snake_case (API inconsistency)
/// - Not all error codes document their meaning in OpenAPI spec
///
/// **Usage:**
/// ```swift
/// do {
///     try await talariaService.uploadScan(image)
/// } catch NetworkError.apiError(let problem) {
///     if problem.retryable {
///         let delayMs = problem.retryAfterMs ?? 60000
///         try await Task.sleep(nanoseconds: delayMs * 1_000_000)
///     }
/// }
/// ```
public struct ProblemDetails: Codable, Sendable {
    let success: Bool
    let type: String
    let title: String
    let status: Int
    let detail: String
    let code: String
    let retryable: Bool
    let retryAfterMs: Int?
    let instance: String?
    let metadata: [String: String]?
}

// MARK: - Network Errors

/// Errors that can occur during network operations
///
/// Comprehensive error handling for Talaria API integration with structured error details.
///
/// **Cases:**
/// - `noConnection`: Network is unreachable (URLError.networkConnectionLost)
/// - `timeout`: Request exceeded timeout interval (default 30s)
/// - `serverError(Int)`: HTTP 5xx error (500, 502, 503, 504)
/// - `invalidResponse`: Malformed JSON or unexpected response structure
/// - `rateLimited(retryAfter: TimeInterval?)`: HTTP 429 with optional retry delay
/// - `apiError(ProblemDetails)`: RFC 9457 structured error from Talaria API
///
/// **Talaria-Specific Handling:**
/// - Rate limiting returns both Retry-After header AND retryAfterMs in response body
/// - Server errors (5xx) should trigger exponential backoff with max 5 retries
/// - Invalid responses often indicate schema mismatch (check OpenAPI spec version)
/// - API errors include `retryable: true` flag in addition to HTTP status
///
/// **Pattern:**
/// ```swift
/// do {
///     return try await talariaService.uploadScan(image)
/// } catch NetworkError.rateLimited(let retryAfter) {
///     let delay = retryAfter ?? 60.0
///     print("Waiting \(delay)s before retry...")
/// } catch NetworkError.apiError(let problem) {
///     print("API Error: \(problem.code) - \(problem.detail)")
/// }
/// ```
public enum NetworkError: Error {
    case noConnection
    case timeout
    case serverError(Int)
    case invalidResponse
    case rateLimited(retryAfter: TimeInterval?)
    case apiError(ProblemDetails)

    public var localizedDescription: String {
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
        case .apiError(let problem):
            return problem.detail
        }
    }
}

// MARK: - Status Enums

/// Job processing status
///
/// Represents the overall state of a scan job throughout its lifecycle.
/// Transitions: initialized → processing → (completed | failed)
///
/// **Talaria API Note:** API currently returns status in mixed formats
/// - SSE events use ScanStage (detailed processing stages)
/// - Status endpoint returns JobStatus (overall job state)
/// - Not always synchronized - check both for complete picture
///
/// **Handling:**
/// - `initialized`: Job queued, not yet started
/// - `processing`: Job actively running
/// - `completed`: Job finished successfully (check individual book results)
/// - `failed`: Job failed completely (see error details in response)
/// - `canceled`: Job explicitly cancelled by user or system
public enum JobStatus: String, Codable, Sendable {
    case initialized
    case processing
    case completed
    case failed
    case canceled
}

/// Scan processing stage
///
/// Granular processing stages for a scan operation, sent via SSE stream.
/// More detailed than JobStatus - shows what Talaria is currently doing.
///
/// **Talaria API Note:** Stages may be skipped if they're not applicable
/// (e.g., if image has only 1 book, identifyingBooks stage completes instantly).
///
/// **Stages:**
/// - `analyzingImage`: Initial image preprocessing and OCR
/// - `identifyingBooks`: Spine text recognition and database lookup
/// - `enrichingMetadata`: Fetching covers, ratings, full details
/// - `complete`: All stages finished
///
/// **SSE Stream Pattern:**
/// ```
/// event: progress
/// data: {"stage": "analyzing_image", "progress": 25}
///
/// event: progress
/// data: {"stage": "identifying_books", "progress": 50}
///
/// event: progress
/// data: {"stage": "enriching_metadata", "progress": 75}
///
/// event: complete
/// ```
public enum ScanStage: String, Codable, Sendable {
    case analyzingImage = "analyzing_image"
    case identifyingBooks = "identifying_books"
    case enrichingMetadata = "enriching_metadata"
    case complete
}

/// Enrichment operation status
///
/// Status of individual enrichment operations (cover art, reviews, etc.)
/// for each identified book. Returned in result events.
///
/// **Talaria API Note:** Enrichment is partially optional. API continues
/// processing even if enrichment endpoints are down (see circuitOpen status).
///
/// **Statuses:**
/// - `pending`: Enrichment queued but not started
/// - `success`: Enrichment completed with data
/// - `notFound`: Book found but enrichment data unavailable
/// - `error`: Enrichment failed (see error details)
/// - `circuitOpen`: Enrichment endpoint down, skipped (not a failure)
/// - `reviewNeeded`: Book flagged for manual review (ambiguous spine)
///
/// **Handling:**
/// ```swift
/// switch enrichmentStatus {
/// case .success:
///     // Use enriched data (covers, ratings, etc.)
///     displayCover(result.coverUrl)
/// case .circuitOpen:
///     // Graceful degradation - show basic metadata without enrichment
///     displayBasicMetadata(title, author)
/// case .reviewNeeded:
///     // Flag for manual review - confidence is low
///     showManualReviewOverlay(book)
/// }
/// ```
public enum EnrichmentStatus: String, Codable, Sendable {
    case pending
    case success
    case notFound = "not_found"
    case error
    case circuitOpen = "circuit_open"
    case reviewNeeded = "review_needed"
}

// MARK: - Upload Response

/// Response from image upload to Talaria API
public struct UploadResponse: Codable, Sendable {
    let success: Bool
    let data: UploadResponseData
}

public struct UploadResponseData: Codable, Sendable {
    let jobId: String
    let sseUrl: URL
    let authToken: String?
    let statusUrl: URL?
}

// MARK: - Book Metadata

/// Book metadata returned from Talaria AI enrichment
public struct BookMetadata: Codable, Sendable {
    let title: String
    let author: String
    let isbn: String?
    let coverUrl: URL?
    let publisher: String?
    let publishedDate: String?
    let pageCount: Int?
    let format: String?
    let confidence: Double?
    let enrichmentStatus: EnrichmentStatus?
}

// MARK: - SSE Events

/// Enrichment degraded information
public struct EnrichmentDegradedInfo: Codable, Sendable {
    let jobId: String?
    let isbn: String?
    let title: String?
    let reason: String?
    let fallbackSource: String?
    let timestamp: String?
}

/// SSE error information with rich context
public struct SSEErrorInfo: Codable, Sendable {
    let message: String
    let code: String?
    let retryable: Bool?
    let jobId: String?
}

/// Server-Sent Event types from Talaria streaming API
public enum SSEEvent: Sendable {
    case progress(String)           // Real-time status: "Looking...", "Reading...", "Enriching..."
    case result(BookMetadata)       // Book metadata from AI (legacy - some API versions send in stream)
    case complete(resultsUrl: String?, books: [BookMetadata]?)  // Job finished successfully, fetch results from URL or use inline books
    case error(SSEErrorInfo)        // Job failed with error information
    case canceled                   // Job was canceled by user or system
    case segmented(SegmentedPreview)    // NEW: segmented image with detected regions
    case bookProgress(BookProgressInfo) // NEW: per-book processing progress
    case enrichmentDegraded(EnrichmentDegradedInfo) // Enrichment degraded event
    case ping                       // SSE keepalive ping
}

// MARK: - Progressive Results Types

/// Segmented image preview from backend after initial detection
public struct SegmentedPreview: Sendable, Codable {
    let imageData: Data       // JPEG data of annotated image with bounding boxes
    let totalBooks: Int        // Number of book spines detected
}

/// Per-book processing progress update
public struct BookProgressInfo: Sendable, Codable {
    let current: Int           // Which book is being processed (1-based)
    let total: Int             // Total books detected
    let stage: String?         // Optional stage description
}

// MARK: - SSE Error

/// Errors specific to SSE streaming
public enum SSEError: Error {
    case streamTimeout
    case invalidEventFormat
    case connectionFailed
    case maxRetriesExceeded

    public var localizedDescription: String {
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
