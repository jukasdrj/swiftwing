import Foundation

// MARK: - Library Export Utilities (US-318)
// Emits Hardcover.app's custom CSV import format. Hardcover rejects files whose
// header row doesn't contain every expected column with exact case-sensitive names,
// so the header below must not be reordered or renamed.
struct LibraryExporter {
    static let hardcoverHeader = "Title,Author,Series,Status,Privacy,Hardcover Book ID,Hardcover Edition ID,ISBN 10,ISBN 13,ASIN,Media,Country Code,Language Code,Binding,Pages,Duration in Seconds,Publish Date,Publisher,Genres,Moods,Tags,Content Warnings,Lists,Date Added,Date Started,Date Finished,Rating,Review,Review Contains Spoilers,Sponsored Review,Review Date,Review URL,Review Media URL,Private Notes,Owned,Compilation,Review Slate"

    static func generateCSV(from books: [Book]) -> String {
        var csv = hardcoverHeader + "\n"
        for book in books {
            csv += hardcoverRow(for: book).joined(separator: ",") + "\n"
        }
        return csv
    }

    /// Builds one row's fields in `hardcoverHeader` column order.
    static func hardcoverRow(for book: Book) -> [String] {
        let (isbn10, isbn13) = classifyISBN(book.isbn)
        return [
            escapeCSVField(book.title),                 // Title
            escapeCSVField(book.author),                // Author
            "",                                         // Series
            statusField(for: book.readingStatus),       // Status
            "",                                         // Privacy
            "",                                         // Hardcover Book ID
            "",                                         // Hardcover Edition ID
            isbn10,                                     // ISBN 10
            isbn13,                                     // ISBN 13
            "",                                         // ASIN
            mediaField(for: book.format),               // Media
            "",                                         // Country Code
            "",                                         // Language Code
            escapeCSVField(book.format ?? ""),          // Binding
            book.pageCount.map(String.init) ?? "",      // Pages
            "",                                         // Duration in Seconds
            book.publishedDate.map(formatPublishDate) ?? "", // Publish Date
            escapeCSVField(book.publisher ?? ""),       // Publisher
            "",                                         // Genres
            "",                                         // Moods
            "",                                         // Tags
            "",                                         // Content Warnings
            "",                                         // Lists
            formatDate(book.addedDate),                 // Date Added
            "",                                         // Date Started
            book.dateRead.map(formatDate) ?? "",        // Date Finished
            book.userRating.map(String.init) ?? "",     // Rating
            "",                                         // Review
            "",                                         // Review Contains Spoilers
            "",                                         // Sponsored Review
            "",                                         // Review Date
            "",                                         // Review URL
            "",                                         // Review Media URL
            escapeCSVField(book.notes ?? ""),           // Private Notes
            "Yes",                                      // Owned
            "",                                         // Compilation
            ""                                          // Review Slate
        ]
    }

    /// Classifies a stored ISBN into Hardcover's `ISBN 10` / `ISBN 13` columns.
    /// Placeholder ISBNs (`UNKNOWN-` prefix) and anything unrecognized map to
    /// two blank fields.
    static func classifyISBN(_ raw: String) -> (isbn10: String, isbn13: String) {
        guard !raw.hasPrefix("UNKNOWN-") else { return ("", "") }
        let cleaned = raw
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        func isASCIIDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
        if cleaned.count == 13, cleaned.allSatisfy(isASCIIDigit) {
            return ("", cleaned)
        }
        if cleaned.count == 10, let check = cleaned.last,
           cleaned.dropLast().allSatisfy(isASCIIDigit),
           isASCIIDigit(check) || check == "X" || check == "x" {
            return (cleaned.uppercased(), "")
        }
        return ("", "")
    }

    /// Maps the free-form `format` field to Hardcover's Media enum (Book / Ebook / Audiobook).
    static func mediaField(for format: String?) -> String {
        let normalized = (format ?? "").lowercased()
        if normalized.contains("ebook") || normalized.contains("e-book") { return "Ebook" }
        if normalized.contains("audio") { return "Audiobook" }
        return "Book"
    }

    /// Maps ReadingStatus to Hardcover's Status column. Books with no status
    /// import as "Read" — the whole shelf is treated as read (user decision).
    static func statusField(for status: ReadingStatus?) -> String {
        switch status {
        case .completed: return "Read"
        case .reading: return "Currently Reading"
        case .toRead: return "Want to Read"
        case .dnf: return "Did Not Finish"
        case nil: return "Read"
        }
    }

    static func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escapedField = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escapedField)\""
        }
        return field
    }

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Publish dates arrive as UTC-midnight instants (Talaria's publicationYear
    /// becomes "<year>-01-01" parsed at GMT by DataSyncActor) — format them at
    /// GMT too, or every western-timezone export shifts to Dec 31 of the prior
    /// year. Local timestamps (Date Added / Date Finished) keep local formatting.
    static func formatPublishDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func generateFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        return "SwiftWing_Library_\(dateString).csv"
    }

    static func saveToTemporaryFile(csv: String, filename: String) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(filename)
        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
