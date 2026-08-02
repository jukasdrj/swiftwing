import Foundation
import Testing
@testable import swiftwing

@Suite(.serialized) struct BookSearchTests {

    private func makeService() -> TalariaService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SequencedURLProtocol.self]
        return TalariaService(
            deviceId: "550e8400-e29b-41d4-a716-446655440000",
            session: URLSession(configuration: config)
        )
    }

    private func successBody() -> Data {
        """
        {"success":true,"data":{"isbn":"9780743273565","isbn13":"9780743273565",
        "title":"The Great Gatsby","authors":["F. Scott Fitzgerald"],
        "publisher":"Scribner","publishedDate":"2004-09-30",
        "coverUrl":"https://example.com/cover.jpg","source":"google",
        "confidence":0.97,"fuzzyMatched":false},
        "metadata":{"timestamp":"2026-08-02T00:00:00Z"}}
        """.data(using: .utf8)!
    }

    @Test("decodes a 200 search result into BookSearchResult")
    func decodesSuccess() async throws {
        SequencedURLProtocol.script([(200, successBody())])
        let result = try await makeService().searchBook(isbn: "9780743273565", title: nil, author: nil)

        #expect(result.title == "The Great Gatsby")
        #expect(result.authors == ["F. Scott Fitzgerald"])
        #expect(result.isbn13 == "9780743273565")
        #expect(result.confidence == 0.97)
        #expect(result.fuzzyMatched == false)
        #expect(result.coverUrl?.absoluteString == "https://example.com/cover.jpg")
    }

    @Test("404 surfaces as apiError with status 404, not a decode failure")
    func notFoundSurfacesAsApiError() async throws {
        let problem = """
        {"success":false,"type":"https://api.oooefam.net/errors/not-found",
        "title":"Not Found","status":404,"detail":"No matching book found"}
        """.data(using: .utf8)!
        SequencedURLProtocol.script([(404, problem)])

        await #expect(throws: NetworkError.self) {
            _ = try await makeService().searchBook(isbn: nil, title: "Nonexistent", author: nil)
        }
    }

    @Test("throws before hitting the network when all params are nil")
    func requiresAtLeastOneParameter() async throws {
        SequencedURLProtocol.script([(200, successBody())])

        await #expect(throws: NetworkError.self) {
            _ = try await makeService().searchBook(isbn: nil, title: nil, author: nil)
        }
        #expect(SequencedURLProtocol.recordedRequestCount() == 0)
    }
}
