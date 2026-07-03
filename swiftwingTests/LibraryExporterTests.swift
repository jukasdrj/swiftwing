import Foundation
import Testing
@testable import swiftwing

/// Unit tests for LibraryExporter's Hardcover.app CSV import format (US-318)
@Suite("LibraryExporter")
struct LibraryExporterTests {

    // MARK: - Helpers

    /// Noon local time avoids DST/day-boundary flakiness in yyyy-MM-dd formatting.
    /// Pinned to Gregorian so a non-Gregorian system calendar can't skew years.
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    /// Publish dates are stored as UTC-midnight instants (see formatPublishDate).
    private func utcMidnight(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(secondsFromGMT: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: components)!
    }

    private func makeBook(
        title: String = "Test Book",
        author: String = "Test Author",
        isbn: String = "9780441478125",
        format: String? = nil,
        publisher: String? = nil,
        publishedDate: Date? = nil,
        pageCount: Int? = nil,
        addedDate: Date = Date(),
        readingStatus: ReadingStatus? = nil,
        dateRead: Date? = nil,
        userRating: Int? = nil,
        notes: String? = nil
    ) -> Book {
        Book(
            title: title,
            author: author,
            isbn: isbn,
            format: format,
            publisher: publisher,
            publishedDate: publishedDate,
            pageCount: pageCount,
            addedDate: addedDate,
            readingStatus: readingStatus,
            dateRead: dateRead,
            userRating: userRating,
            notes: notes
        )
    }

    // MARK: - Header

    @Test func headerRowMatchesHardcoverFormatExactly() {
        let expected = "Title,Author,Series,Status,Privacy,Hardcover Book ID,Hardcover Edition ID,ISBN 10,ISBN 13,ASIN,Media,Country Code,Language Code,Binding,Pages,Duration in Seconds,Publish Date,Publisher,Genres,Moods,Tags,Content Warnings,Lists,Date Added,Date Started,Date Finished,Rating,Review,Review Contains Spoilers,Sponsored Review,Review Date,Review URL,Review Media URL,Private Notes,Owned,Compilation,Review Slate"
        let csv = LibraryExporter.generateCSV(from: [])
        let header = csv.components(separatedBy: "\n").first
        #expect(header == expected)
    }

    @Test func headerHas37Columns() {
        let csv = LibraryExporter.generateCSV(from: [])
        let header = csv.components(separatedBy: "\n").first ?? ""
        #expect(header.components(separatedBy: ",").count == 37)
    }

    // MARK: - Full row

    @Test func fullyPopulatedBookProducesExpectedRow() {
        let book = makeBook(
            title: "The Left Hand of Darkness",
            author: "Ursula K. Le Guin",
            isbn: "9780441478125",
            format: "Hardcover",
            publisher: "Ace Books",
            publishedDate: utcMidnight(1969, 6, 1),
            pageCount: 304,
            addedDate: date(2026, 1, 15),
            readingStatus: .completed,
            dateRead: date(2026, 2, 20),
            userRating: 5,
            notes: "A classic."
        )

        let csv = LibraryExporter.generateCSV(from: [book])
        let lines = csv.components(separatedBy: "\n")
        #expect(lines.count >= 2)

        let expectedRow = "The Left Hand of Darkness,Ursula K. Le Guin,,Read,,,,,9780441478125,,Book,,,Hardcover,304,,1969-06-01,Ace Books,,,,,,2026-01-15,,2026-02-20,5,,,,,,,A classic.,Yes,,"
        #expect(lines[1] == expectedRow)
    }

    @Test func rowFieldCountMatchesHeader() {
        let book = makeBook()
        let row = LibraryExporter.hardcoverRow(for: book)
        let headerCount = LibraryExporter.hardcoverHeader.components(separatedBy: ",").count
        #expect(row.count == headerCount)
    }

    @Test func minimalBookLeavesOptionalColumnsEmpty() {
        let book = makeBook(isbn: "9780441478125", addedDate: date(2026, 3, 1))
        let row = LibraryExporter.hardcoverRow(for: book)
        #expect(row[2] == "")            // Series
        #expect(row[14] == "")           // Pages
        #expect(row[16] == "")           // Publish Date
        #expect(row[17] == "")           // Publisher
        #expect(row[25] == "")           // Date Finished
        #expect(row[26] == "")           // Rating
        #expect(row[33] == "")           // Private Notes
    }

    // MARK: - ISBN classification

    @Test func thirteenDigitISBNMapsToISBN13() {
        let result = LibraryExporter.classifyISBN("9780441478125")
        #expect(result.isbn10 == "")
        #expect(result.isbn13 == "9780441478125")
    }

    @Test func tenDigitISBNMapsToISBN10() {
        let result = LibraryExporter.classifyISBN("0441478123")
        #expect(result.isbn10 == "0441478123")
        #expect(result.isbn13 == "")
    }

    @Test func tenDigitISBNWithXCheckDigitMapsToISBN10() {
        let result = LibraryExporter.classifyISBN("080442957X")
        #expect(result.isbn10 == "080442957X")
        #expect(result.isbn13 == "")
    }

    @Test func lowercaseXCheckDigitAccepted() {
        let result = LibraryExporter.classifyISBN("080442957x")
        #expect(result.isbn10 == "080442957X")
        #expect(result.isbn13 == "")
    }

    @Test func dashedISBN13IsStrippedAndClassified() {
        let result = LibraryExporter.classifyISBN("978-0-441-47812-5")
        #expect(result.isbn10 == "")
        #expect(result.isbn13 == "9780441478125")
    }

    @Test func dashedISBN10IsStrippedAndClassified() {
        let result = LibraryExporter.classifyISBN("0-441-47812-3")
        #expect(result.isbn10 == "0441478123")
        #expect(result.isbn13 == "")
    }

    @Test func spacedISBNIsStrippedAndClassified() {
        let result = LibraryExporter.classifyISBN("978 0441 478125")
        #expect(result.isbn13 == "9780441478125")
    }

    @Test func unknownPrefixedISBNMapsToBothBlank() {
        let result = LibraryExporter.classifyISBN("UNKNOWN-1A2B3C4D")
        #expect(result.isbn10 == "")
        #expect(result.isbn13 == "")
    }

    @Test(arguments: ["12345", "", "notanisbn!", "12345678901234", "044147812Y"])
    func unrecognizedISBNMapsToBothBlank(raw: String) {
        let result = LibraryExporter.classifyISBN(raw)
        #expect(result.isbn10 == "")
        #expect(result.isbn13 == "")
    }

    // MARK: - Status mapping

    // Parameterized over raw values for stable @Test argument labels.
    @Test(arguments: [
        ("completed", "Read"),
        ("reading", "Currently Reading"),
        ("to_read", "Want to Read"),
        ("did_not_finish", "Did Not Finish"),
    ])
    func readingStatusMapsToHardcoverStatus(rawStatus: String, expected: String) {
        let status = ReadingStatus(rawValue: rawStatus)
        #expect(status != nil)
        #expect(LibraryExporter.statusField(for: status) == expected)
    }

    @Test func nilStatusMapsToRead() {
        #expect(LibraryExporter.statusField(for: nil) == "Read")
    }

    // MARK: - Media mapping

    @Test(arguments: [
        ("Ebook", "Ebook"),
        ("eBook", "Ebook"),
        ("E-Book (Kindle)", "Ebook"),
        ("Audiobook", "Audiobook"),
        ("Audio CD", "Audiobook"),
        ("Hardcover", "Book"),
        ("Paperback", "Book"),
    ])
    func formatMapsToMedia(format: String, expected: String) {
        #expect(LibraryExporter.mediaField(for: format) == expected)
    }

    @Test func nilFormatMapsToBookMedia() {
        #expect(LibraryExporter.mediaField(for: nil) == "Book")
    }

    // MARK: - CSV escaping

    @Test func commaInTitleIsQuoted() {
        let book = makeBook(title: "Hello, World")
        let row = LibraryExporter.hardcoverRow(for: book)
        #expect(row[0] == "\"Hello, World\"")
    }

    @Test func quoteInTitleIsDoubledAndQuoted() {
        let book = makeBook(title: "Say \"Hi\"")
        let row = LibraryExporter.hardcoverRow(for: book)
        #expect(row[0] == "\"Say \"\"Hi\"\"\"")
    }

    @Test func newlineInNotesIsQuoted() {
        let book = makeBook(notes: "line one\nline two")
        let row = LibraryExporter.hardcoverRow(for: book)
        #expect(row[33] == "\"line one\nline two\"")
    }

    @Test func plainFieldsAreNotQuoted() {
        let book = makeBook(title: "Plain Title", author: "Plain Author")
        let row = LibraryExporter.hardcoverRow(for: book)
        #expect(row[0] == "Plain Title")
        #expect(row[1] == "Plain Author")
    }

    // MARK: - Owned

    @Test func everyRowIsMarkedOwned() {
        let books = [
            makeBook(title: "One", isbn: "1111111111"),
            makeBook(title: "Two", isbn: "2222222222", readingStatus: .reading),
            makeBook(title: "Three", isbn: "UNKNOWN-3333"),
        ]
        for book in books {
            let row = LibraryExporter.hardcoverRow(for: book)
            #expect(row[34] == "Yes")
        }
    }
}
