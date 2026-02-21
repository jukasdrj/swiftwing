import Foundation
import os

private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "rate-limit")

/// Thread-safe actor for managing API rate limit state
/// Handles 429 Too Many Requests responses with countdown and queued scans
actor RateLimitState {

    // MARK: - Properties

    /// Whether currently rate limited
    private(set) var isRateLimited: Bool = false

    /// Date when rate limit will expire (nil if not rate limited)
    private(set) var retryAfterDate: Date?

    /// Queued image scans during rate limit (stored as temp file URLs to avoid memory pressure)
    private var queuedScans: [(imageUrl: URL, preScannedISBN: String?)] = []

    // MARK: - Public API

    /// Set rate limit state with retry-after duration
    /// - Parameter retryAfter: Seconds until rate limit expires
    func setRateLimited(retryAfter: TimeInterval) {
        isRateLimited = true
        retryAfterDate = Date().addingTimeInterval(retryAfter)
        logger.info("Rate limit set: retry after \(Int(retryAfter))s")
    }

    /// Clear rate limit state (called when cooldown expires)
    func clearRateLimit() {
        isRateLimited = false
        retryAfterDate = nil
        logger.info("Rate limit cleared")
    }

    /// Get remaining seconds until rate limit expires
    /// - Returns: Seconds remaining (0 if expired or not rate limited)
    func getRemainingSeconds() -> Int {
        guard let retryAfterDate = retryAfterDate else {
            return 0
        }

        let remaining = retryAfterDate.timeIntervalSinceNow
        return max(0, Int(ceil(remaining)))
    }

    /// Queue an image scan during rate limit by writing to a temp file
    /// - Parameters:
    ///   - imageData: JPEG image data to queue
    ///   - preScannedISBN: Vision-detected ISBN from barcode scanner
    func queueScan(_ imageData: Data, preScannedISBN: String? = nil) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        do {
            try imageData.write(to: tempURL)
            queuedScans.append((imageUrl: tempURL, preScannedISBN: preScannedISBN))
            logger.info("Queued scan to temp file (\(self.queuedScans.count) total in queue)")
        } catch {
            logger.error("Failed to write queued scan to temp file: \(error.localizedDescription)")
        }
    }

    /// Get all queued scans and clear the queue
    /// Reads image data from temp files and removes them after loading
    /// - Returns: Array of queued (imageData, preScannedISBN) tuples
    func dequeueAllScans() -> [(imageData: Data, preScannedISBN: String?)] {
        let scans = queuedScans
        queuedScans.removeAll()
        var results: [(imageData: Data, preScannedISBN: String?)] = []
        for scan in scans {
            do {
                let data = try Data(contentsOf: scan.imageUrl)
                results.append((imageData: data, preScannedISBN: scan.preScannedISBN))
            } catch {
                logger.warning("Failed to read queued scan from temp file: \(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: scan.imageUrl)
        }
        logger.info("Dequeued \(results.count) scans")
        return results
    }

    /// Get count of queued scans
    var queuedScanCount: Int {
        queuedScans.count
    }
}
