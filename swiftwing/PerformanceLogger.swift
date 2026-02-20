import Foundation
import os

private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "performance")

// MARK: - Performance Logger
/// US-321: Performance measurement and logging for library rendering
/// Tracks rendering times, scroll FPS, and cache efficiency
struct PerformanceLogger {

    // MARK: - Measurement Categories
    enum Category: String {
        case libraryRendering = "Library Rendering"
        case scrollPerformance = "Scroll Performance"
        case imageLoading = "Image Loading"
        case dataFetch = "Data Fetch"
        case cacheEfficiency = "Cache Efficiency"
    }

    // MARK: - Performance Measurement

    /// Measure and log execution time of a code block
    /// - Parameters:
    ///   - category: Performance category
    ///   - operation: Description of operation being measured
    ///   - block: Code block to measure
    /// - Returns: Result of the block execution
    static func measure<T>(
        category: Category,
        operation: String,
        block: () throws -> T
    ) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        log(category: category, operation: operation, duration: duration)

        return result
    }

    /// Measure and log execution time of an async code block
    /// - Parameters:
    ///   - category: Performance category
    ///   - operation: Description of operation being measured
    ///   - block: Async code block to measure
    /// - Returns: Result of the block execution
    static func measureAsync<T>(
        category: Category,
        operation: String,
        block: () async throws -> T
    ) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        log(category: category, operation: operation, duration: duration)

        return result
    }

    // MARK: - Logging

    /// Log performance measurement
    /// - Parameters:
    ///   - category: Performance category
    ///   - operation: Description of operation
    ///   - duration: Time taken in seconds
    private static func log(category: Category, operation: String, duration: TimeInterval) {
        let milliseconds = duration * 1000
        let emoji = getEmoji(for: duration, category: category)

        logger.info("[\(category.rawValue, privacy: .public)] \(operation, privacy: .public): \(String(format: "%.2f", milliseconds), privacy: .public)ms")

        // Warn if operation is slow
        if shouldWarn(duration: duration, category: category) {
            logger.warning("Performance warning: Operation took longer than expected")
        }
    }

    /// Log library rendering statistics
    /// - Parameters:
    ///   - bookCount: Number of books rendered
    ///   - duration: Time taken to render
    static func logLibraryRendering(bookCount: Int, duration: TimeInterval) {
        let milliseconds = duration * 1000
        let avgPerBook = bookCount > 0 ? milliseconds / Double(bookCount) : 0

        logger.info("Library rendered \(bookCount, privacy: .public) books in \(String(format: "%.2f", milliseconds), privacy: .public)ms")
        logger.info("Average: \(String(format: "%.3f", avgPerBook), privacy: .public)ms per book")

        // Check against target (60 FPS = 16.67ms per frame)
        if milliseconds > 100 {
            logger.warning("Initial render exceeded 100ms target")
        } else {
            logger.info("Performance target met (< 100ms)")
        }
    }

    /// Log scroll performance (FPS estimation)
    /// - Parameters:
    ///   - frameTime: Time per frame in seconds
    ///   - scrollDistance: Distance scrolled (for context)
    static func logScrollPerformance(frameTime: TimeInterval, scrollDistance: CGFloat = 0) {
        let fps = 1.0 / frameTime
        let emoji = fps >= 55 ? "✅" : (fps >= 30 ? "⚠️" : "❌")

        logger.info("Scroll FPS: \(String(format: "%.1f", fps), privacy: .public)")

        if scrollDistance > 0 {
            logger.debug("Scroll distance: \(String(format: "%.0f", scrollDistance), privacy: .public)px")
        }

        if fps < 55 {
            logger.warning("Below 60 FPS target")
        }
    }

    /// Log image cache statistics
    /// - Parameters:
    ///   - memoryUsed: Memory cache usage in bytes
    ///   - diskUsed: Disk cache usage in bytes
    ///   - hitRate: Cache hit rate (0.0 - 1.0)
    static func logCacheStatistics(
        memoryUsed: Int,
        diskUsed: Int,
        hitRate: Double? = nil
    ) {
        logger.info("Image Cache Statistics: Memory \(memoryUsed / 1024 / 1024, privacy: .public)MB / 50MB, Disk \(diskUsed / 1024 / 1024, privacy: .public)MB / 200MB")

        if let hitRate = hitRate {
            if hitRate > 0.8 {
                logger.info("Cache hit rate: \(String(format: "%.1f", hitRate * 100), privacy: .public)%")
            } else if hitRate > 0.5 {
                logger.warning("Cache hit rate low: \(String(format: "%.1f", hitRate * 100), privacy: .public)%")
            } else {
                logger.error("Cache hit rate very low: \(String(format: "%.1f", hitRate * 100), privacy: .public)%")
            }
        }
    }

    // MARK: - Helpers

    /// Get appropriate emoji for performance measurement
    private static func getEmoji(for duration: TimeInterval, category: Category) -> String {
        let milliseconds = duration * 1000

        switch category {
        case .libraryRendering:
            return milliseconds < 100 ? "✅" : (milliseconds < 500 ? "⚠️" : "❌")
        case .scrollPerformance:
            return milliseconds < 16.67 ? "✅" : (milliseconds < 33 ? "⚠️" : "❌")  // 60 FPS target
        case .imageLoading:
            return milliseconds < 500 ? "✅" : (milliseconds < 1000 ? "⚠️" : "❌")
        case .dataFetch:
            return milliseconds < 100 ? "✅" : (milliseconds < 500 ? "⚠️" : "❌")
        case .cacheEfficiency:
            return "📊"
        }
    }

    /// Check if duration should trigger a warning
    private static func shouldWarn(duration: TimeInterval, category: Category) -> Bool {
        let milliseconds = duration * 1000

        switch category {
        case .libraryRendering:
            return milliseconds > 500
        case .scrollPerformance:
            return milliseconds > 33  // Below 30 FPS
        case .imageLoading:
            return milliseconds > 1000
        case .dataFetch:
            return milliseconds > 500
        case .cacheEfficiency:
            return false
        }
    }

    // MARK: - Timer Utility

    /// Simple timer for manual measurements
    struct Timer {
        private let startTime: CFAbsoluteTime
        let category: Category
        let operation: String

        init(category: Category, operation: String) {
            self.startTime = CFAbsoluteTimeGetCurrent()
            self.category = category
            self.operation = operation
        }

        func stop() {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            PerformanceLogger.log(category: category, operation: operation, duration: duration)
        }

        var elapsed: TimeInterval {
            CFAbsoluteTimeGetCurrent() - startTime
        }
    }

    /// Start a manual timer
    static func startTimer(category: Category, operation: String) -> Timer {
        Timer(category: category, operation: operation)
    }
}

// MARK: - Performance Monitoring Extensions

extension PerformanceLogger {

    /// Monitor view rendering performance
    /// Usage: Add to view's onAppear or body
    static func monitorViewRender(viewName: String) {
        let timer = startTimer(category: .libraryRendering, operation: "Render \(viewName)")

        // Auto-stop after next runloop cycle using MainActor
        Task { @MainActor in
            timer.stop()
        }
    }

    /// Monitor scroll gesture performance
    /// Call this repeatedly during scrolling to track FPS
    static func monitorScrollFrame(previousTime: CFAbsoluteTime) -> CFAbsoluteTime {
        let currentTime = CFAbsoluteTimeGetCurrent()
        let frameTime = currentTime - previousTime

        // Only log if frame took longer than 16ms (below 60 FPS)
        if frameTime > 0.016 {
            logScrollPerformance(frameTime: frameTime)
        }

        return currentTime
    }
}
