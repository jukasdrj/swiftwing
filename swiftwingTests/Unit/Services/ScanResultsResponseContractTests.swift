import XCTest
@testable import swiftwing

final class ScanResultsResponseContractTests: XCTestCase {
    let fixtureJSON = """
    {
      "success": true,
      "data": {
        "jobId": "550e8400-e29b-41d4-a716-446655440000",
        "status": "completed",
        "results": [
          {
            "title": "The Great Gatsby",
            "author": "F. Scott Fitzgerald",
            "isbn": "9780743273565",
            "confidence": 0.98,
            "format": "hardcover",
            "enrichmentStatus": "success",
            "enrichment": {
              "status": "success",
              "coverUrl": "https://example.com/covers/gatsby.jpg",
              "publisher": "Scribner",
              "publishedDate": "1925-04-10",
              "authors": ["F. Scott Fitzgerald"]
            }
          },
          {
            "title": "Unknown Title",
            "author": "Unknown Author",
            "isbn": "UNKNOWN-2024-001",
            "confidence": 0.45,
            "format": "paperback",
            "enrichmentStatus": "not_found",
            "enrichment": null
          }
        ]
      },
      "metadata": {
        "timestamp": "2026-01-18T12:00:00Z",
        "requestId": "req-abc-123"
      }
    }
    """

    func test_decodeScanResultsResponse_withEnrichmentStatus_success() throws {
        let data = fixtureJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(ScanResultsResponse.self, from: data)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data.results.count, 2)
    }

    func test_decodeScanResultsResponse_book1_enrichmentStatusSuccess() throws {
        let data = fixtureJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(ScanResultsResponse.self, from: data)
        XCTAssertEqual(response.data.results[0].enrichmentStatus, .success)
    }

    func test_decodeScanResultsResponse_book2_enrichmentStatusNotFound() throws {
        let data = fixtureJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(ScanResultsResponse.self, from: data)
        XCTAssertEqual(response.data.results[1].enrichmentStatus, .notFound)
    }

    func test_decodeScanResultsResponse_enrichmentStatusIsNonNil_contractSeam() throws {
        let data = fixtureJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(ScanResultsResponse.self, from: data)
        for book in response.data.results {
            XCTAssertNotNil(book.enrichmentStatus, "enrichmentStatus must be non-nil for contract compliance")
        }
    }

    func test_decodeScanResultsResponse_allBooksDecodedSuccessfully() throws {
        let data = fixtureJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(ScanResultsResponse.self, from: data)
        XCTAssertEqual(response.data.results[0].isbn, "9780743273565")
        XCTAssertEqual(response.data.results[1].isbn, "UNKNOWN-2024-001")
    }
}
