import Foundation

/// API contract validation fixtures matching the latest Talaria schema (v3.5.0+)
/// These fixtures are used to validate Swiftwing's parsing against the Talaria API contract.
///
/// **Purpose:**
/// - Verify that Swiftwing correctly parses Talaria's API responses
/// - Test forward-compatibility (accepting both singular `author` and plural `authors[]`)
/// - Ensure graceful degradation when fields are missing or malformed
/// - Catch contract mismatches early (CI-safe, no live API dependency)
///
/// **Maintenance:**
/// Update these fixtures when Talaria's schema changes. Use the actual API responses
/// from production (via curl or API client) as the source of truth.
enum TalariaContractFixtures {
    
    // MARK: - Upload Response Fixtures
    
    /// Standard upload response (POST /v3/jobs/scans)
    /// Matches the new JobResponseSchema from Talaria v3.5.0+
    static let uploadResponseJSON = """
    {
      "success": true,
      "data": {
        "jobId": "550e8400-e29b-41d4-a716-446655440000",
        "status": "initialized",
        "streamUrl": "https://api.oooefam.net/v3/jobs/scans/550e8400-e29b-41d4-a716-446655440000/stream",
        "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
      }
    }
    """
    
    /// Upload response with processing status (less common)
    static let uploadResponseProcessingJSON = """
    {
      "success": true,
      "data": {
        "jobId": "660e8400-e29b-41d4-a716-446655440001",
        "status": "processing",
        "streamUrl": "https://api.oooefam.net/v3/jobs/scans/660e8400-e29b-41d4-a716-446655440001/stream",
        "token": null
      }
    }
    """
    
    // MARK: - SSE Event Fixtures (BookMetadata)
    
    /// SSE result event with all fields present (ideal case)
    static let bookMetadataFullJSON = """
    {
      "title": "The Great Gatsby",
      "author": "F. Scott Fitzgerald",
      "isbn": "9780743273565",
      "coverUrl": "https://books.google.com/books/content?id=...",
      "publisher": "Scribner",
      "publicationYear": 1925,
      "enrichmentStatus": "success",
      "confidence": 0.98,
      "boundingBox": {
        "x": 120.5,
        "y": 200.3,
        "width": 80.0,
        "height": 150.0
      }
    }
    """
    
    /// SSE result event with plural authors (future format)
    static let bookMetadataPluralAuthorsJSON = """
    {
      "title": "The Art of Computer Programming",
      "authors": ["Donald E. Knuth"],
      "isbn": "9780201896831",
      "coverUrl": "https://books.google.com/books/content?id=...",
      "publisher": "Addison-Wesley",
      "publicationYear": 1968,
      "enrichmentStatus": "success",
      "confidence": 0.95,
      "boundingBox": {
        "x": 100.0,
        "y": 150.0,
        "width": 85.0,
        "height": 140.0
      }
    }
    """
    
    /// SSE result event with multiple authors (future format)
    static let bookMetadataMultipleAuthorsJSON = """
    {
      "title": "Clean Code",
      "authors": ["Robert C. Martin", "Reviewed by James O. Coplien"],
      "isbn": "9780136083238",
      "coverUrl": null,
      "publisher": "Prentice Hall",
      "publicationYear": 2008,
      "enrichmentStatus": "success",
      "confidence": 0.92,
      "boundingBox": {
        "x": 110.0,
        "y": 180.0,
        "width": 75.0,
        "height": 135.0
      }
    }
    """
    
    /// SSE result event with missing title and author (review_needed)
    static let bookMetadataReviewNeededJSON = """
    {
      "title": null,
      "author": null,
      "isbn": null,
      "coverUrl": null,
      "publisher": null,
      "publicationYear": null,
      "enrichmentStatus": "review_needed",
      "confidence": 0.45,
      "boundingBox": {
        "x": 150.0,
        "y": 220.0,
        "width": 70.0,
        "height": 130.0
      }
    }
    """
    
    /// SSE result event with enrichment circuit open (graceful degradation)
    static let bookMetadataCircuitOpenJSON = """
    {
      "title": "Swift Concurrency",
      "author": "Chris Lattner",
      "isbn": "9781492030270",
      "coverUrl": null,
      "publisher": null,
      "publicationYear": null,
      "enrichmentStatus": "circuit_open",
      "confidence": 0.88,
      "boundingBox": {
        "x": 130.0,
        "y": 200.0,
        "width": 80.0,
        "height": 145.0
      }
    }
    """
    
    /// SSE result event with minimal fields (edge case)
    static let bookMetadataMinimalJSON = """
    {
      "title": "Unknown Book",
      "author": null,
      "isbn": null,
      "coverUrl": null,
      "enrichmentStatus": "not_found",
      "confidence": 0.5,
      "boundingBox": null
    }
    """
    
    /// SSE result event with malformed URL (resilient decoding test)
    static let bookMetadataMalformedURLJSON = """
    {
      "title": "Test Book",
      "author": "Test Author",
      "isbn": "9780000000000",
      "coverUrl": "not-a-valid-url",
      "publisher": "Test Publisher",
      "publicationYear": 2024,
      "enrichmentStatus": "success",
      "confidence": 0.85
    }
    """
    
    /// SSE result event with unexpected type for confidence (resilient decoding)
    static let bookMetadataUnexpectedConfidenceJSON = """
    {
      "title": "Test Book",
      "author": "Test Author",
      "isbn": "9780000000000",
      "confidence": "0.85",
      "enrichmentStatus": "success",
      "publicationYear": 2024
    }
    """
    
    // MARK: - Error Response Fixtures
    
    /// RFC 9457 error response (rate limiting)
    static let errorRateLimitedJSON = """
    {
      "success": false,
      "type": "about:blank",
      "title": "Too Many Requests",
      "status": 429,
      "detail": "Rate limit exceeded. Maximum 5 scans per minute.",
      "code": "RATE_LIMITED",
      "retryable": true,
      "retryAfterMs": 30000
    }
    """
    
    /// RFC 9457 error response (invalid request)
    static let errorInvalidRequestJSON = """
    {
      "success": false,
      "type": "about:blank",
      "title": "Unprocessable Entity",
      "status": 422,
      "detail": "Image size exceeds maximum of 10MB",
      "code": "INVALID_IMAGE_SIZE",
      "retryable": false,
      "metadata": {
        "maxSizeBytes": 10485760,
        "receivedSizeBytes": 15000000
      }
    }
    """
    
    /// RFC 9457 error response (server error)
    static let errorServerErrorJSON = """
    {
      "success": false,
      "type": "about:blank",
      "title": "Internal Server Error",
      "status": 500,
      "detail": "Gemini API temporarily unavailable",
      "code": "EXTERNAL_API_ERROR",
      "retryable": true,
      "retryAfterMs": 60000
    }
    """
    
    // MARK: - Helper Methods
    
    /// Parse JSON fixture and return Data
    static func data(from json: String) -> Data? {
        return json.data(using: .utf8)
    }
    
    /// Decode fixture to UploadResponse
    static func decodeUploadResponse(from json: String) throws -> UploadResponse {
        guard let data = data(from: json) else {
            throw NSError(domain: "TalariaContractFixtures", code: -1, userInfo: nil)
        }
        return try JSONDecoder().decode(UploadResponse.self, from: data)
    }
    
    /// Decode fixture to BookMetadata
    static func decodeBookMetadata(from json: String) throws -> BookMetadata {
        guard let data = data(from: json) else {
            throw NSError(domain: "TalariaContractFixtures", code: -1, userInfo: nil)
        }
        return try JSONDecoder().decode(BookMetadata.self, from: data)
    }
    
    /// Decode fixture to ProblemDetails
    static func decodeProblemDetails(from json: String) throws -> ProblemDetails {
        guard let data = data(from: json) else {
            throw NSError(domain: "TalariaContractFixtures", code: -1, userInfo: nil)
        }
        return try JSONDecoder().decode(ProblemDetails.self, from: data)
    }
}
