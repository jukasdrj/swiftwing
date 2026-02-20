import XCTest
@testable import swiftwing

final class FormatStatsBenchmarkTests: XCTestCase {

    struct TestBook {
        let format: String?
    }

    // Measure baseline performance using Dictionary(grouping:by:)
    func testFormatStatsBaseline() {
        let formats = ["Hardcover", "Paperback", "Ebook", "Audiobook", nil]
        // Create a large dataset to make the performance difference measurable
        let books = (0..<100_000).map { _ in TestBook(format: formats.randomElement()!) }

        measure {
            // This is the implementation being replaced
            let formatCounts = Dictionary(grouping: books.compactMap { $0.format }, by: { $0 })
                .mapValues { $0.count }
            _ = formatCounts
        }
    }

    // Measure optimized performance using reduce(into:)
    func testFormatStatsOptimized() {
        let formats = ["Hardcover", "Paperback", "Ebook", "Audiobook", nil]
        let books = (0..<100_000).map { _ in TestBook(format: formats.randomElement()!) }

        measure {
            // This is the new optimized implementation
            let formatCounts = books.reduce(into: [String: Int]()) { counts, book in
                if let format = book.format {
                    counts[format, default: 0] += 1
                }
            }
            _ = formatCounts
        }
    }
}
