@testable import swiftwing
import XCTest

final class PerformanceBenchmarkTests: XCTestCase {
    struct TestBook {
        let spineConfidence: Double?
    }

    /// Measure baseline performance using filter
    func testFilterPerformance() {
        let books = (0..<1_000_000).map { _ in TestBook(spineConfidence: Double.random(in: 0...1)) }

        measure {
            let count = books.filter { ($0.spineConfidence ?? 1.0) < 0.8 }.count
            _ = count
        }
    }

    /// Measure optimized performance using lazy filter
    func testLazyFilterPerformance() {
        let books = (0..<1_000_000).map { _ in TestBook(spineConfidence: Double.random(in: 0...1)) }

        measure {
            let count = books.lazy.filter { ($0.spineConfidence ?? 1.0) < 0.8 }.count
            _ = count
        }
    }
}
