import Foundation
import Testing
@testable import swiftwing

struct BookMetadataTests {

    // MARK: - author / authors field decoding

    @Test func decodesAuthorStringField() throws {
        let json = #"{"title": "Dune", "author": "Frank Herbert"}"#
        let data = try #require(json.data(using: .utf8))
        let metadata = try JSONDecoder().decode(BookMetadata.self, from: data)
        #expect(metadata.author == "Frank Herbert")
    }

    @Test func decodesAuthorsArrayFieldJoinedWithComma() throws {
        let json = #"{"title": "Good Omens", "authors": ["Terry Pratchett", "Neil Gaiman"]}"#
        let data = try #require(json.data(using: .utf8))
        let metadata = try JSONDecoder().decode(BookMetadata.self, from: data)
        #expect(metadata.author == "Terry Pratchett, Neil Gaiman")
    }

    @Test func prefersSingleAuthorOverAuthorsArray() throws {
        // When both fields are present, "author" string wins
        let json = #"{"title": "Test", "author": "Solo Author", "authors": ["Array Author"]}"#
        let data = try #require(json.data(using: .utf8))
        let metadata = try JSONDecoder().decode(BookMetadata.self, from: data)
        #expect(metadata.author == "Solo Author")
    }

    @Test func authorIsNilWhenBothFieldsMissing() throws {
        let json = #"{"title": "No Author Book"}"#
        let data = try #require(json.data(using: .utf8))
        let metadata = try JSONDecoder().decode(BookMetadata.self, from: data)
        #expect(metadata.author == nil)
        #expect(metadata.resolvedAuthor == "Unknown Author")
    }

    // MARK: - publicationYear int/string conversion

    @Test func decodesPublicationYearAsInt() throws {
        let json = #"{"title": "Test", "author": "Author", "publicationYear": 1984}"#
        let data = try #require(json.data(using: .utf8))
        let metadata = try JSONDecoder().decode(BookMetadata.self, from: data)
        #expect(metadata.publishedDate == "1984-01-01")
    }

    @Test func decodesPublicationYearAsString() throws {
        let json = #"{"title": "Test", "author": "Author", "publicationYear": "2001"}"#
        let data = try #require(json.data(using: .utf8))
        let metadata = try JSONDecoder().decode(BookMetadata.self, from: data)
        #expect(metadata.publishedDate == "2001-01-01")
    }

    @Test func decodesPublishedDateStringFallback() throws {
        let json = #"{"title": "Test", "author": "Author", "publishedDate": "1965-03-15"}"#
        let data = try #require(json.data(using: .utf8))
        let metadata = try JSONDecoder().decode(BookMetadata.self, from: data)
        #expect(metadata.publishedDate == "1965-03-15")
    }

    @Test func publishedDateIsNilWhenNoYearFields() throws {
        let json = #"{"title": "Test", "author": "Author"}"#
        let data = try #require(json.data(using: .utf8))
        let metadata = try JSONDecoder().decode(BookMetadata.self, from: data)
        #expect(metadata.publishedDate == nil)
    }

    // MARK: - Missing optional fields

    @Test func decodesMinimalPayloadWithOnlyTitle() throws {
        let json = #"{"title": "Minimal Book"}"#
        let data = try #require(json.data(using: .utf8))
        let metadata = try JSONDecoder().decode(BookMetadata.self, from: data)
        #expect(metadata.title == "Minimal Book")
        #expect(metadata.isbn == nil)
        #expect(metadata.coverUrl == nil)
        #expect(metadata.publisher == nil)
        #expect(metadata.pageCount == nil)
        #expect(metadata.confidence == nil)
        #expect(metadata.enrichmentStatus == nil)
    }

    @Test func resolvedTitleFallsBackToUnknownTitle() throws {
        let json = #"{}"#
        let data = try #require(json.data(using: .utf8))
        let metadata = try JSONDecoder().decode(BookMetadata.self, from: data)
        #expect(metadata.title == nil)
        #expect(metadata.resolvedTitle == "Unknown Title")
    }

    // MARK: - coverUrl handling

    @Test func decodesCoverUrlWhenValid() throws {
        let json = #"{"title": "Test", "coverUrl": "https://example.com/cover.jpg"}"#
        let data = try #require(json.data(using: .utf8))
        let metadata = try JSONDecoder().decode(BookMetadata.self, from: data)
        #expect(metadata.coverUrl == URL(string: "https://example.com/cover.jpg"))
    }

    @Test func coverUrlIsNilForMalformedURL() throws {
        // Malformed URL should not crash — resilient decoding returns nil
        let json = #"{"title": "Test", "coverUrl": "not a valid url %%"}"#
        let data = try #require(json.data(using: .utf8))
        let metadata = try JSONDecoder().decode(BookMetadata.self, from: data)
        #expect(metadata.coverUrl == nil)
    }

    @Test func coverUrlIsNilWhenFieldMissing() throws {
        let json = #"{"title": "Test"}"#
        let data = try #require(json.data(using: .utf8))
        let metadata = try JSONDecoder().decode(BookMetadata.self, from: data)
        #expect(metadata.coverUrl == nil)
    }

    // MARK: - Full payload round-trip

    @Test func decodesFullPayload() throws {
        let json = """
        {
            "title": "The Pragmatic Programmer",
            "author": "David Thomas",
            "isbn": "9780135957059",
            "coverUrl": "https://books.example.com/cover.jpg",
            "publisher": "Addison-Wesley",
            "publicationYear": 2019,
            "confidence": 0.95,
            "enrichmentStatus": "success"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let metadata = try JSONDecoder().decode(BookMetadata.self, from: data)
        #expect(metadata.title == "The Pragmatic Programmer")
        #expect(metadata.author == "David Thomas")
        #expect(metadata.isbn == "9780135957059")
        #expect(metadata.publisher == "Addison-Wesley")
        #expect(metadata.publishedDate == "2019-01-01")
        #expect(metadata.confidence == 0.95)
        #expect(metadata.enrichmentStatus == .success)
    }
}
