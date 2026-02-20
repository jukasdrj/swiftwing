import XCTest
@testable import swiftwing

final class ReviewQueueManagerPerformanceTests: XCTestCase {

    // Benchmark: Measure standard filter performance (baseline)
    // This simulates the original implementation in ReviewQueueManager.showScanComplete
    func testStandardFilterPerformance() {
        let items = createLargeDataset(count: 100_000)

        measure {
            let high = items.filter { ($0.confidence ?? 1.0) >= 0.8 }.count
            let low = items.filter { ($0.confidence ?? 1.0) < 0.5 }.count
            _ = high + low // Prevent optimization
        }
    }

    // Benchmark: Measure lazy filter performance (optimized)
    // This simulates the proposed optimization using .lazy
    func testLazyFilterPerformance() {
        let items = createLargeDataset(count: 100_000)

        measure {
            let high = items.lazy.filter { ($0.confidence ?? 1.0) >= 0.8 }.count
            let low = items.lazy.filter { ($0.confidence ?? 1.0) < 0.5 }.count
            _ = high + low // Prevent optimization
        }
    }

    // Correctness: Ensure lazy filter produces exactly the same results as standard filter
    func testLazyFilterCorrectness() {
        let items = createLargeDataset(count: 1000)

        let highStandard = items.filter { ($0.confidence ?? 1.0) >= 0.8 }.count
        let lowStandard = items.filter { ($0.confidence ?? 1.0) < 0.5 }.count

        let highLazy = items.lazy.filter { ($0.confidence ?? 1.0) >= 0.8 }.count
        let lowLazy = items.lazy.filter { ($0.confidence ?? 1.0) < 0.5 }.count

        XCTAssertEqual(highStandard, highLazy, "High confidence count mismatch")
        XCTAssertEqual(lowStandard, lowLazy, "Low confidence count mismatch")
    }

    // Helper to create large dataset for benchmarking
    private func createLargeDataset(count: Int) -> [PendingBookResult] {
        var items: [PendingBookResult] = []
        items.reserveCapacity(count)

        for i in 0..<count {
            // Distribute confidence values to ensure both buckets get populated
            let confidence = Double.random(in: 0.0...1.0)
            let metadata = BookMetadata(
                title: "Book \(i)",
                author: "Author \(i)",
                confidence: confidence
            )
            let item = PendingBookResult(metadata: metadata, rawJSON: nil)
            items.append(item)
        }
        return items
    }
}
