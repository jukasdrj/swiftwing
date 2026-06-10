import Foundation
import os

private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "network")

// MARK: - RFC 9457 Problem Details

/// Handles mixed-type JSON values from Talaria's metadata dict.
/// Talaria defines metadata as Record<string, unknown> — values can be strings, numbers, or booleans.
public enum AnyCodableValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if container.decodeNil() { self = .null }
        else { self = .null }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
}

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
///     if problem.retryable ?? false {
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
    let detail: String?
    let code: String?
    let retryable: Bool?
    let retryAfterMs: Int?
    let instance: String?
    let metadata: [String: AnyCodableValue]?
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
///     print("API Error: \(problem.code ?? "UNKNOWN") - \(problem.detail ?? "unknown error")")
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
            return problem.detail ?? "Unknown API error"
        }
    }
}

// MARK: - Status Enums

/// Job processing status
///
/// Represents the overall state of a scan job throughout its lifecycle.
/// Transitions: queued → processing → (completed | failed)
///
/// **Talaria API Note:** API currently returns status in mixed formats
/// - SSE events use ScanStage (detailed processing stages)
/// - Status endpoint returns JobStatus (overall job state)
/// - Not always synchronized - check both for complete picture
///
/// **Handling:**
/// - `queued`: Job accepted but not yet started
/// - `processing`: Job actively running
/// - `completed`: Job finished successfully (check individual book results)
/// - `failed`: Job failed completely (see error details in response)
/// - `canceled`: Job explicitly cancelled by user or system
public enum JobStatus: String, Codable, Sendable {
    case queued
    case processing
    case completed
    case failed
    case canceled
}

extension JobStatus {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "initialized":
            self = .queued
        default:
            guard let status = JobStatus(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Cannot initialize JobStatus from invalid String value \(rawValue)"
                )
            }
            self = status
        }
    }
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
public enum EnrichmentStatus: String, Sendable {
    case pending
    case success
    case notFound = "not_found"
    case error
    case circuitOpen = "circuit_open"
    case reviewNeeded = "review_needed"
    // NOTE: Removed cases "complete", "partial", "degraded", "failed" (never sent by Talaria).
    // Any persisted Book records with these values will map to .pending via the custom init fallback.
    // No SwiftData migration required — enrichmentStatus is stored as String in the Book model.
}

extension EnrichmentStatus: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        // Accept any known value, default to .pending for unknown
        self = EnrichmentStatus(rawValue: rawValue) ?? .pending
    }
}

// MARK: - Upload Response

/// Response from image upload to Talaria API
///
/// **API Contract Boundary:**
/// UploadResponseData directly mirrors the Talaria `JobResponseSchema` returned by POST /v3/jobs/scans.
/// This is the external API contract (not the internal canonical model).
///
/// **Field Mapping (Talaria → Swiftwing):**
/// - jobId (string UUID) → jobId (String)
/// - status (JobStatus enum) → status (JobStatus)
/// - streamUrl (string URL) → streamUrl (URL)
/// - token (string) → token (String) — for future auth-header use
///
/// **Note:** Talaria firehose upload (POST /v3/jobs/scans/firehose) returns additional
/// fields (uploadUrl, chunkSize, photoCount) not mapped here. Add when firehose is implemented.
public struct UploadResponse: Codable, Sendable {
    let success: Bool
    let data: UploadResponseData
}

/// Job initialization response data from Talaria API.
///
/// **CRITICAL: API Contract vs. Internal Models**
/// This struct represents the **external API contract** returned by Talaria.
/// The canonical internal model uses plural fields (e.g., `authors[]`).
/// Swiftwing's domain models (BookMetadata) may differ slightly for
/// forward-compatibility and convenience (e.g., joining authors into single string).
///
/// **Field Semantics:**
/// - `jobId`: Unique job identifier for this scan (UUID format)
/// - `status`: Current job state (queued, processing, completed, failed, canceled)
/// - `streamUrl`: Server-Sent Events endpoint for real-time progress updates
/// - `token`: Optional auth token for SSE stream (future use for auth-header setup)
public struct UploadResponseData: Codable, Sendable {
    let jobId: String
    let status: JobStatus
    let streamUrl: URL
    let token: String?
}

// MARK: - Book Metadata

/// Bounding box for detected book spine on shelf image
public struct BoundingBox: Codable, Sendable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// Book metadata decoded from Talaria SSE events and results endpoint.
///
/// **CRITICAL: API Contract Boundary**
/// This struct represents book data returned by the Talaria API (the external contract).
/// The internal canonical data model uses plural `authors[]`; this API struct uses singular `author`.
///
/// **API vs. Internal Models:**
/// - **External (API):** Talaria returns `author: String` (singular)
/// - **Internal (Canonical):** Canonical BookSchema uses `authors: String[]` (plural)
/// - **Swiftwing Strategy:** Accept both formats for forward-compatibility (see decoder below)
///
/// **Field Mapping (Talaria API → Swiftwing Domain):**
/// - `title: String?` — Book title or null if review_needed
/// - `author: String?` — Author name(s) as single string OR `authors: String[]` if plural
/// - `isbn: String?` — 10 or 13 digit ISBN
/// - `coverUrl: URL?` — Cover image URL (from Google Books or enrichment)
/// - `publisher: String?` — Publisher name
/// - `publishedDate: String?` — ISO date (converted from publicationYear: Int)
/// - `enrichmentStatus: EnrichmentStatus?` — success/review_needed/circuit_open/etc.
/// - `confidence: Double?` — AI confidence score (0.0-1.0)
/// - `boundingBox: BoundingBox?` — Pixel coordinates on shelf image
///
/// **SSE vs. Results Endpoint:**
/// - **SSE `result` events:** Includes title, author, isbn, coverUrl, enrichmentStatus, confidence, boundingBox
/// - **Results endpoint:** Same fields plus optional pageCount, format, publishedDate
/// - Not all fields are guaranteed; use resolvedTitle/resolvedAuthor for UI display
///
/// **Field Semantics:**
/// - `title` and `author` may be null when enrichmentStatus is "review_needed" (ambiguous spine)
/// - Use `resolvedTitle` and `resolvedAuthor` getters for display (fallback to "Unknown Title"/"Unknown Author")
/// - `publishedDate` is constructed from Talaria's `publicationYear` (Int) or passed as String
///
/// **Talaria API Inconsistencies:**
/// - Sends `publicationYear` as Int (converted to YYYY-01-01 string)
/// - May send both `author` (string) and `authors` (array) — decoder handles both
/// - Some responses include redundant fields that are ignored
public struct BookMetadata: Sendable, Equatable {
    let title: String?
    let author: String?
    let isbn: String?
    let coverUrl: URL?
    let publisher: String?
    let publishedDate: String?
    let pageCount: Int?
    let format: String?
    let confidence: Double?
    let boundingBox: BoundingBox?
    let enrichmentStatus: EnrichmentStatus?

    /// Title with fallback for display purposes
    var resolvedTitle: String { title ?? "Unknown Title" }
    /// Author with fallback for display purposes
    var resolvedAuthor: String { author ?? "Unknown Author" }

    public init(
        title: String? = nil,
        author: String? = nil,
        isbn: String? = nil,
        coverUrl: URL? = nil,
        publisher: String? = nil,
        publishedDate: String? = nil,
        pageCount: Int? = nil,
        format: String? = nil,
        confidence: Double? = nil,
        boundingBox: BoundingBox? = nil,
        enrichmentStatus: EnrichmentStatus? = nil
    ) {
        self.title = title
        self.author = author
        self.isbn = isbn
        self.coverUrl = coverUrl
        self.publisher = publisher
        self.publishedDate = publishedDate
        self.pageCount = pageCount
        self.format = format
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.enrichmentStatus = enrichmentStatus
    }
}

extension BookMetadata: Codable {
    private enum CodingKeys: String, CodingKey {
        case title, author, authors, isbn, coverUrl, publisher
        case publishedDate, publicationYear
        case pageCount, format, confidence, boundingBox, enrichmentStatus
    }

    /// Custom decoder for BookMetadata to handle API contract variations
    ///
    /// **Forward-Compatibility Strategy:**
    /// This decoder accepts both singular `author` (current API contract)
    /// and plural `authors[]` (future canonical model) for graceful migration.
    ///
    /// **Author Field Handling:**
    /// 1. Try to decode `author: String` (current API contract)
    /// 2. If not found, try to decode `authors: [String]` and join with ", "
    /// 3. If neither found, set to nil (handled by resolvedAuthor fallback)
    ///
    /// **Date Field Handling:**
    /// Talaria sends `publicationYear` as Int; convert to ISO date string YYYY-01-01.
    /// Fallback to `publishedDate` if available. This ensures backward compatibility
    /// if Talaria changes the field name in the future.
    ///
    /// **Resilient Decoding:**
    /// Uses `try?` for optional fields to prevent single field corruption
    /// from failing the entire book decode. This is critical for SSE parsing
    /// where one malformed book shouldn't kill the entire stream.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        
        // Forward-compatible: accept both singular author and plural authors[]
        let authorString = try container.decodeIfPresent(String.self, forKey: .author)
        if let a = authorString {
            author = a
        } else if let authorsArray = try? container.decodeIfPresent([String].self, forKey: .authors) {
            author = authorsArray.joined(separator: ", ")
        } else {
            author = nil
        }
        
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        format = try container.decodeIfPresent(String.self, forKey: .format)

        // Resilient decoding: use try? for fields where Talaria may send unexpected types.
        // This prevents a single malformed field from killing the entire book decode.
        if let coverUrlString = try? container.decodeIfPresent(String.self, forKey: .coverUrl),
           let candidateURL = URL(string: coverUrlString),
           let scheme = candidateURL.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           candidateURL.host != nil {
            coverUrl = candidateURL
        } else {
            coverUrl = nil
        }
        pageCount = try? container.decodeIfPresent(Int.self, forKey: .pageCount)
        confidence = try? container.decodeIfPresent(Double.self, forKey: .confidence)
        boundingBox = try? container.decodeIfPresent(BoundingBox.self, forKey: .boundingBox)
        enrichmentStatus = try? container.decodeIfPresent(EnrichmentStatus.self, forKey: .enrichmentStatus)

        // Talaria sends publicationYear (Int). Try that first, then publishedDate (String) fallback.
        if let year = try? container.decodeIfPresent(Int.self, forKey: .publicationYear) {
            publishedDate = "\(year)-01-01"
        } else if let yearStr = try? container.decodeIfPresent(String.self, forKey: .publicationYear) {
            publishedDate = "\(yearStr)-01-01"
        } else if let date = try? container.decodeIfPresent(String.self, forKey: .publishedDate) {
            publishedDate = date
        } else {
            publishedDate = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(isbn, forKey: .isbn)
        try container.encodeIfPresent(coverUrl, forKey: .coverUrl)
        try container.encodeIfPresent(publisher, forKey: .publisher)
        try container.encodeIfPresent(publishedDate, forKey: .publishedDate)
        try container.encodeIfPresent(pageCount, forKey: .pageCount)
        try container.encodeIfPresent(format, forKey: .format)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(boundingBox, forKey: .boundingBox)
        try container.encodeIfPresent(enrichmentStatus, forKey: .enrichmentStatus)
    }
}

// MARK: - SSE Events

/// Rich progress information from SSE progress events
public struct ProgressInfo: Sendable, Equatable {
    let message: String
    let progress: Double?        // 0.0 - 1.0
    let processedCount: Int?
    let totalCount: Int?
}

/// Summary statistics from a completed scan
public struct ScanSummary: Sendable, Equatable {
    let totalDetected: Int
    let totalUnique: Int
    let approved: Int
    let needsReview: Int
    /// From nested summary.review_needed (optional — older API versions may not send)
    let reviewNeeded: Int?
    /// From nested summary.degraded_count (optional — older API versions may not send)
    let degradedCount: Int?
}

/// Truncation metadata from scan results (large bookshelves may be truncated)
public struct TruncationMetadata: Sendable, Equatable {
    let truncationSuspected: Bool
    let outputTruncated: Bool
}

/// Timing breakdown for a completed scan
public struct ScanDuration: Codable, Sendable, Equatable {
    let totalMs: Int?
    let uploadMs: Int?
    let geminiMs: Int?
    let enrichmentMs: Int?
    let cleanupMs: Int?
}

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
    case progress(ProgressInfo)     // Real-time status with optional progress fraction and counts
    case result(BookMetadata)       // Book metadata from AI (legacy - some API versions send in stream)
    case complete(resultsUrl: String?, books: [BookMetadata]?, summary: ScanSummary?, duration: ScanDuration?, truncation: TruncationMetadata?)  // Job finished successfully
    case error(SSEErrorInfo)        // Job failed with error information
    case canceled                   // Job was canceled by user or system
    case segmented(SegmentedPreview)    // Segmented image with detected regions
    case bookProgress(BookProgressInfo) // Per-book processing progress
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
public enum SSEError: Error, Equatable {
    case streamTimeout
    case invalidEventFormat
    case connectionFailed
    case unauthorized
    case maxRetriesExceeded
    case unknownEvent(String)   // Forward-compatibility: unknown event type from server

    public var localizedDescription: String {
        switch self {
        case .streamTimeout:
            return "SSE stream timed out (5 minute maximum)"
        case .invalidEventFormat:
            return "Invalid SSE event format"
        case .connectionFailed:
            return "Failed to establish SSE connection"
        case .unauthorized:
            return "SSE stream authorization expired"
        case .maxRetriesExceeded:
            return "Maximum reconnection attempts exceeded"
        case .unknownEvent(let name):
            return "Unknown SSE event type: \(name)"
        }
    }
}

// MARK: - HTTP Polling Models

public struct JobStatusResponse: Codable, Sendable {
    public let success: Bool
    public let data: JobStatusData
}

public struct JobStatusData: Codable, Sendable {
    public let jobId: String
    public let status: JobStatus
    public let progress: Double
}

public struct ScanResultsResponse: Codable, Sendable {
    public let success: Bool
    public let data: ScanResultsData
}

public struct ScanResultsData: Codable, Sendable {
    public let jobId: String
    public let status: JobStatus
    public let results: [BookMetadata]
}

