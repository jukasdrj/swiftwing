import Foundation

/// Thread-safe actor for managing API rate limit state
/// Handles 429 Too Many Requests responses with countdown and queued scans
actor RateLimitState {

    // MARK: - Properties

    /// Whether currently rate limited
    private(set) var isRateLimited: Bool = false

    /// Date when rate limit will expire (nil if not rate limited)
    private(set) var retryAfterDate: Date?

    /// Queued image scans during rate limit (preserved to retry after cooldown)
    private var queuedScans: [(Data, String?)] = []

    // MARK: - Public API

    /// Set rate limit state with retry-after duration
    /// - Parameter retryAfter: Seconds until rate limit expires
    func setRateLimited(retryAfter: TimeInterval) {
        isRateLimited = true
        retryAfterDate = Date().addingTimeInterval(retryAfter)
        print("⏰ Rate limit set: retry after \(Int(retryAfter))s (until \(retryAfterDate!))")
    }

    /// Clear rate limit state (called when cooldown expires)
    func clearRateLimit() {
        isRateLimited = false
        retryAfterDate = nil
        print("✅ Rate limit cleared")
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

    /// Queue an image scan during rate limit
    /// - Parameters:
    ///   - imageData: JPEG image data to queue
    ///   - isbn: Vision-detected ISBN at time of capture
    func queueScan(_ imageData: Data, isbn: String? = nil) {
        queuedScans.append((imageData, isbn))
        print("📥 Queued scan (\(queuedScans.count) total in queue)")
    }

    /// Get all queued scans and clear the queue
    /// - Returns: Array of queued image data and their ISBNs
    func dequeueAllScans() -> [(Data, String?)] {
        let scans = queuedScans
        queuedScans.removeAll()
        print("📤 Dequeued \(scans.count) scans")
        return scans
    }

    /// Get count of queued scans
    var queuedScanCount: Int {
        queuedScans.count
    }
}
