import Foundation

// MARK: - Stream Manager Configuration

/// Configuration for StreamManager concurrency limits
struct StreamManagerConfig {
    /// Maximum number of concurrent SSE streams allowed
    /// Default: 5 (balances throughput with resource usage)
    let maxConcurrentStreams: Int

    static let `default` = StreamManagerConfig(maxConcurrentStreams: 5)
}

// MARK: - Stream Manager

/// Actor that manages concurrent SSE stream limits and queuing for bulk scanning
///
/// US-410: Ensures bulk scanning remains performant by limiting max concurrent
/// SSE streams to 5 (configurable) and queuing additional scans.
///
/// Performance targets:
/// - Memory usage < 100 MB with 10 active streams
/// - UI maintains 60 FPS during bulk scanning
/// - Handles 20+ rapid scans in < 30 seconds
///
/// Usage:
/// ```swift
/// let streamManager = StreamManager()
/// await streamManager.acquireStreamSlot(scanId: uuid)
/// defer { Task { await streamManager.releaseStreamSlot(scanId: uuid) } }
/// // ... perform upload and streaming ...
/// ```
actor StreamManager {

    // MARK: - Properties

    /// Maximum allowed concurrent SSE streams
    private let maxConcurrentStreams: Int

    /// Current number of active SSE streams
    private var activeStreams: Int = 0

    /// Queue of pending scan IDs waiting for stream slots (FIFO)
    private var pendingScans: [UUID] = []

    /// Continuations for pending scans waiting to be resumed
    private var waitingContinuations: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Performance metrics for active scans
    private var activeMetrics: [UUID: ScanMetrics] = [:]

    // MARK: - Initialization

    /// Initialize StreamManager with configuration
    /// - Parameter config: Configuration specifying max concurrent streams
    init(config: StreamManagerConfig = .default) {
        self.maxConcurrentStreams = config.maxConcurrentStreams
    }

    // MARK: - Public API

    /// Acquire a stream slot for scanning
    ///
    /// If fewer than `maxConcurrentStreams` are active, returns immediately.
    /// Otherwise, suspends until a stream slot becomes available.
    ///
    /// - Parameter scanId: Unique identifier for this scan (for tracking)
    func acquireStreamSlot(scanId: UUID) async {
        // Check if we have capacity
        if activeStreams < maxConcurrentStreams {
            grantStreamSlot(scanId: scanId)
        } else {
            // Queue and wait for slot
            await withCheckedContinuation { continuation in
                pendingScans.append(scanId)
                waitingContinuations[scanId] = continuation

                print("[StreamManager] Scan \(scanId.uuidString.prefix(8)): Queued (Active: \(activeStreams)/\(maxConcurrentStreams), Queue: \(pendingScans.count))")
            }
        }
    }

    /// Release a stream slot after scanning completes
    ///
    /// Call this in a defer block to ensure it runs even on errors.
    ///
    /// - Parameter scanId: Unique identifier for the completed scan
    func releaseStreamSlot(scanId: UUID) {
        // Decrement active stream count
        activeStreams -= 1

        // Calculate and log performance metrics
        if let metrics = activeMetrics[scanId] {
            let duration = CFAbsoluteTimeGetCurrent() - metrics.startTime
            let durationMs = Int(duration * 1000)

            print("[StreamManager] Scan \(scanId.uuidString.prefix(8)): Completed in \(durationMs)ms (Active: \(activeStreams)/\(maxConcurrentStreams), Queue: \(pendingScans.count))")

            // Remove metrics
            activeMetrics.removeValue(forKey: scanId)
        }

        // Grant slot to next pending scan if any
        if !pendingScans.isEmpty {
            let nextScanId = pendingScans.removeFirst()
            if let continuation = waitingContinuations.removeValue(forKey: nextScanId) {
                print("[StreamManager] Scan \(nextScanId.uuidString.prefix(8)): Dequeued (Active: \(activeStreams)/\(maxConcurrentStreams), Queue: \(pendingScans.count))")

                // Grant slot and resume waiting task
                grantStreamSlot(scanId: nextScanId)
                continuation.resume()
            }
        }
    }

    /// Get current number of active SSE streams
    /// - Returns: Number of streams currently executing
    func getActiveStreamCount() -> Int {
        return activeStreams
    }

    /// Get current queue depth
    /// - Returns: Number of scans waiting in queue
    func getQueueDepth() -> Int {
        return pendingScans.count
    }

    // MARK: - Private Implementation

    /// Grant a stream slot to a scan (increments active count, starts metrics)
    private func grantStreamSlot(scanId: UUID) {
        activeStreams += 1

        // Initialize performance metrics
        let metrics = ScanMetrics(scanId: scanId, startTime: CFAbsoluteTimeGetCurrent())
        activeMetrics[scanId] = metrics

        print("[StreamManager] Scan \(scanId.uuidString.prefix(8)): Started (Active: \(activeStreams)/\(maxConcurrentStreams), Queue: \(pendingScans.count))")
    }
}

// MARK: - Performance Metrics

/// Performance metrics for a single scan operation
private struct ScanMetrics {
    let scanId: UUID
    let startTime: CFAbsoluteTime
}
