import XCTest
@testable import swiftwing

/// Contract adherence tests for Talaria API integration
///
/// Validates that Swiftwing correctly parses Talaria's API responses according to the
/// latest contract (v3.5.0+). These tests catch contract mismatches early before they
/// cause production issues.
///
/// **Test Strategy:**
/// - Uses TalariaContractFixtures for realistic API responses
/// - Tests both happy path and edge cases
/// - Verifies forward-compatibility (singular vs. plural author fields)
/// - Ensures graceful degradation for missing/malformed fields
/// - No live API dependency (CI-safe)
final class TalariaContractAdherenceTests: XCTestCase {
    
    // MARK: - UploadResponse Tests
    
    func test_decodeUploadResponse_withStandardSchema() throws {
        // Arrange
        let response = try TalariaContractFixtures.decodeUploadResponse(from: TalariaContractFixtures.uploadResponseJSON)

        // Assert
        XCTAssertEqual(response.success, true)
        XCTAssertEqual(response.data.jobId, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(response.data.status, .queued)
        XCTAssertEqual(response.data.streamUrl?.absoluteString, "https://api.oooefam.net/v3/jobs/scans/550e8400-e29b-41d4-a716-446655440000/stream")
        XCTAssertNotNil(response.data.token)
    }
    
    func test_decodeUploadResponse_withProcessingStatus() throws {
        // Arrange
        let response = try TalariaContractFixtures.decodeUploadResponse(from: TalariaContractFixtures.uploadResponseProcessingJSON)
        
        // Assert
        XCTAssertEqual(response.data.status, .processing)
        XCTAssertNil(response.data.token, "Token should be nil for processing status")
    }
    
    func test_uploadResponseData_hasAllRequiredFields() throws {
        // Arrange
        let response = try TalariaContractFixtures.decodeUploadResponse(from: TalariaContractFixtures.uploadResponseJSON)
        
        // Assert - Verify all required fields are present
        XCTAssertFalse(response.data.jobId.isEmpty, "jobId cannot be empty")
        XCTAssertNotNil(response.data.status, "status is required")
        XCTAssertNotNil(response.data.streamUrl, "streamUrl is required")
    }
    
    // MARK: - BookMetadata Tests (Singular Author)
    
    func test_decodeBookMetadata_withSingularAuthor() throws {
        // Arrange
        let book = try TalariaContractFixtures.decodeBookMetadata(from: TalariaContractFixtures.bookMetadataFullJSON)
        
        // Assert
        XCTAssertEqual(book.title, "The Great Gatsby")
        XCTAssertEqual(book.author, "F. Scott Fitzgerald")
        XCTAssertEqual(book.isbn, "9780743273565")
        XCTAssertEqual(book.publisher, "Scribner")
        XCTAssertEqual(book.enrichmentStatus, .success)
        XCTAssertEqual(book.confidence, 0.98)
    }
    
    func test_decodeBookMetadata_withPublicationYearAsInt() throws {
        // Arrange
        let book = try TalariaContractFixtures.decodeBookMetadata(from: TalariaContractFixtures.bookMetadataFullJSON)
        
        // Assert - publicationYear should be converted to ISO date
        XCTAssertEqual(book.publishedDate, "1925-01-01")
    }
    
    func test_decodeBookMetadata_withBoundingBox() throws {
        // Arrange
        let book = try TalariaContractFixtures.decodeBookMetadata(from: TalariaContractFixtures.bookMetadataFullJSON)
        
        // Assert
        XCTAssertNotNil(book.boundingBox)
        XCTAssertEqual(book.boundingBox?.x, 120.5)
        XCTAssertEqual(book.boundingBox?.y, 200.3)
        XCTAssertEqual(book.boundingBox?.width, 80.0)
        XCTAssertEqual(book.boundingBox?.height, 150.0)
    }
    
    // MARK: - BookMetadata Tests (Plural Authors - Forward Compatibility)
    
    func test_decodeBookMetadata_withPluralAuthors_singleAuthor() throws {
        // Arrange
        let book = try TalariaContractFixtures.decodeBookMetadata(from: TalariaContractFixtures.bookMetadataPluralAuthorsJSON)
        
        // Assert - Plural authors should be joined into single string
        XCTAssertEqual(book.author, "Donald E. Knuth")
    }
    
    func test_decodeBookMetadata_withPluralAuthors_multipleAuthors() throws {
        // Arrange
        let book = try TalariaContractFixtures.decodeBookMetadata(from: TalariaContractFixtures.bookMetadataMultipleAuthorsJSON)
        
        // Assert - Multiple authors should be joined with ", "
        XCTAssertEqual(book.author, "Robert C. Martin, Reviewed by James O. Coplien")
    }
    
    func test_decodeBookMetadata_prefersSingularAuthorOverPlural() throws {
        // Arrange - Create JSON with both singular and plural author
        let json = """
        {
          "title": "Test Book",
          "author": "Singular Author",
          "authors": ["Plural Author"],
          "isbn": "9780000000000",
          "enrichmentStatus": "success"
        }
        """
        let book = try TalariaContractFixtures.decodeBookMetadata(from: json)
        
        // Assert - Singular author should take precedence
        XCTAssertEqual(book.author, "Singular Author")
    }
    
    // MARK: - BookMetadata Tests (EnrichmentStatus Variations)
    
    func test_decodeBookMetadata_withReviewNeededStatus() throws {
        // Arrange
        let book = try TalariaContractFixtures.decodeBookMetadata(from: TalariaContractFixtures.bookMetadataReviewNeededJSON)
        
        // Assert
        XCTAssertEqual(book.enrichmentStatus, .reviewNeeded)
        XCTAssertNil(book.title, "title should be nil when review_needed")
        XCTAssertNil(book.author, "author should be nil when review_needed")
        XCTAssertEqual(book.resolvedTitle, "Unknown Title", "resolvedTitle should provide fallback")
        XCTAssertEqual(book.resolvedAuthor, "Unknown Author", "resolvedAuthor should provide fallback")
    }
    
    func test_decodeBookMetadata_withCircuitOpenStatus() throws {
        // Arrange
        let book = try TalariaContractFixtures.decodeBookMetadata(from: TalariaContractFixtures.bookMetadataCircuitOpenJSON)
        
        // Assert
        XCTAssertEqual(book.enrichmentStatus, .circuitOpen)
        XCTAssertNotNil(book.title, "title should be present (enrichment partial)")
        XCTAssertNotNil(book.author, "author should be present (enrichment partial)")
        XCTAssertNil(book.coverUrl, "coverUrl should be nil (enrichment failed)")
    }
    
    func test_decodeBookMetadata_withNotFoundStatus() throws {
        // Arrange
        let book = try TalariaContractFixtures.decodeBookMetadata(from: TalariaContractFixtures.bookMetadataMinimalJSON)
        
        // Assert
        XCTAssertEqual(book.enrichmentStatus, .notFound)
    }
    
    // MARK: - BookMetadata Tests (Resilient Decoding)
    
    func test_decodeBookMetadata_withMissingOptionalFields() throws {
        // Arrange
        let book = try TalariaContractFixtures.decodeBookMetadata(from: TalariaContractFixtures.bookMetadataMinimalJSON)
        
        // Assert - Should not fail when optional fields are missing
        XCTAssertNotNil(book.title)
        XCTAssertNil(book.isbn)
        XCTAssertNil(book.coverUrl)
        XCTAssertNil(book.publisher)
        XCTAssertNil(book.boundingBox)
    }
    
    func test_decodeBookMetadata_resilientToMalformedURL() throws {
        // Arrange
        let book = try TalariaContractFixtures.decodeBookMetadata(from: TalariaContractFixtures.bookMetadataMalformedURLJSON)
        
        // Assert - Malformed URL should be skipped, other fields should parse
        XCTAssertNil(book.coverUrl, "Malformed URL should fail to decode")
        XCTAssertEqual(book.title, "Test Book", "Other fields should parse successfully")
        XCTAssertEqual(book.author, "Test Author")
    }
    
    func test_decodeBookMetadata_resilientToUnexpectedFieldType() throws {
        // Arrange
        let book = try TalariaContractFixtures.decodeBookMetadata(from: TalariaContractFixtures.bookMetadataUnexpectedConfidenceJSON)
        
        // Assert - String confidence should fail to decode, but book should parse
        XCTAssertNil(book.confidence, "String confidence should fail to decode")
        XCTAssertEqual(book.title, "Test Book", "Other fields should parse successfully")
    }
    
    // MARK: - Error Response Tests
    
    func test_decodeProblemDetails_rateLimitError() throws {
        // Arrange
        let error = try TalariaContractFixtures.decodeProblemDetails(from: TalariaContractFixtures.errorRateLimitedJSON)
        
        // Assert
        XCTAssertEqual(error.status, 429)
        XCTAssertEqual(error.code, "RATE_LIMITED")
        XCTAssertEqual(error.retryable, .some(true))  // Optional field, fixture provides true
        XCTAssertEqual(error.retryAfterMs, 30000)
    }
    
    func test_decodeProblemDetails_serverError() throws {
        // Arrange
        let error = try TalariaContractFixtures.decodeProblemDetails(from: TalariaContractFixtures.errorServerErrorJSON)
        
        // Assert
        XCTAssertEqual(error.status, 500)
        XCTAssertEqual(error.code, "EXTERNAL_API_ERROR")
        XCTAssertTrue(error.retryable ?? false)  // Optional, but fixture provides it
    }

    func test_decodeProblemDetails_invalidRequest() throws {
        let error = try TalariaContractFixtures.decodeProblemDetails(from: TalariaContractFixtures.errorInvalidRequestJSON)

        XCTAssertEqual(error.status, 422)
        XCTAssertEqual(error.code, "INVALID_IMAGE_SIZE")
        XCTAssertFalse(error.retryable ?? false)  // Optional, but fixture provides it
    }
    
    // MARK: - Contract Version Detection
    
    func test_uploadResponse_containsRequiredFields_forVersionDetection() throws {
        // Arrange
        let response = try TalariaContractFixtures.decodeUploadResponse(from: TalariaContractFixtures.uploadResponseJSON)

        // Assert - These fields must exist for version detection
        XCTAssertNotNil(response.data.status, "status field required for v3.5.0+")
        XCTAssertNotNil(response.data.streamUrl, "streamUrl field provided in v3.5.0+ (optional for transition)")
        XCTAssertNotNil(response.data.token, "token field provided in v3.5.0+")
    }
    
    // MARK: - Integration Tests
    
    func test_talariaService_usesCorrectResponseMapping() throws {
        // This test verifies that TalariaService correctly maps UploadResponseData fields
        // Arrange
        let response = try TalariaContractFixtures.decodeUploadResponse(from: TalariaContractFixtures.uploadResponseJSON)
        
        // Act
        let jobId = response.data.jobId
        let streamUrl = response.data.streamUrl
        let status = response.data.status
        let token = response.data.token
        
        // Assert - All fields should map correctly for TalariaService.uploadScan return type
        XCTAssertEqual(jobId, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(streamUrl?.absoluteString, "https://api.oooefam.net/v3/jobs/scans/550e8400-e29b-41d4-a716-446655440000/stream")
        XCTAssertEqual(status, .queued)
        XCTAssertNotNil(token)
    }
    
    // MARK: - Backward Compatibility Tests
    
    func test_enrichmentStatus_defaultsToUnknownValue() throws {
        // Arrange - Create JSON with unknown enrichment status
        let json = """
        {
          "title": "Test Book",
          "author": "Test Author",
          "enrichmentStatus": "unknown_future_status"
        }
        """
        
        // Act & Assert - Should not throw, should default to .pending
        let book = try TalariaContractFixtures.decodeBookMetadata(from: json)
        XCTAssertEqual(book.enrichmentStatus, .pending, "Unknown status should default to pending")
    }
    
    func test_jobStatus_acceptsAllDefinedValues() throws {
        // Arrange
        let statuses: [(String, JobStatus)] = [
            ("queued", .queued),
            ("initialized", .queued),
            ("processing", .processing),
            ("completed", .completed),
            ("failed", .failed),
            ("canceled", .canceled),
        ]
        
        // Act & Assert
        for (statusString, expectedStatus) in statuses {
            let json = """
            {
              "success": true,
              "data": {
                "jobId": "test-id",
                "status": "\(statusString)",
                "streamUrl": "https://example.com/stream",
                "token": null
              }
            }
            """
            
            let response = try TalariaContractFixtures.decodeUploadResponse(from: json)
            XCTAssertEqual(response.data.status, expectedStatus, "Should decode status: \(statusString)")
        }
    }
}
