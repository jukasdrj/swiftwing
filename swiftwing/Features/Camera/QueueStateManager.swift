import Foundation
import SwiftUI
import os

private let queueLogger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "queue-state")

/// Centralized manager for processing queue state.
/// Extracted from CameraViewModel for better separation of concerns and testability.
/// Provides SSOT (Single Source of Truth) for all queue-related state and UI bindings.
@MainActor
@Observable
final class QueueStateManager {
    // MARK: - Queue Items
    var processingQueue: [ProcessingItem] = []
    
    // MARK: - Rate Limit State
    var isRateLimited = false
    var rateLimitCountdown: Int = 0
    var queuedScansCount: Int = 0
    
    // MARK: - Offline Queue State
    var offlineQueuedCount: Int = 0
    
    // MARK: - Error State
    var processingErrorMessage: String?
    var showProcessingError = false
    var enrichmentDegradedMessage: String?
    var showEnrichmentDegradedBanner = false
    var showTruncationBanner = false
    
    // MARK: - Retry Context
    private var countdownTimer: Task<Void, Never>?
    
    // MARK: - Queue Operations
    
    /// Add a new item to the processing queue.
    func addItem(imageData: Data, preScannedISBN: String? = nil) -> ProcessingItem {
        var item = ProcessingItem(imageData: imageData, state: .preprocessing)
        item.preScannedISBN = preScannedISBN
        
        withAnimation(.swissSpring) {
            processingQueue.append(item)
        }
        
        queueLogger.debug("Added item to queue: \(item.id.uuidString.prefix(8))")
        return item
    }
    
    /// Update an item's processing state.
    func updateItemState(id: UUID, state: ProcessingItem.ProcessingState) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].state = state
            }
            queueLogger.debug("Updated item \(id.uuidString.prefix(8)) state to \(String(describing: state))")
        }
    }
    
    /// Update an item's progress message.
    func updateProgress(id: UUID, message: String?) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].progressMessage = message
            }
        }
    }
    
    /// Update both state and message.
    func updateItem(id: UUID, state: ProcessingItem.ProcessingState, message: String?) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].state = state
                processingQueue[index].progressMessage = message
            }
            queueLogger.debug("Updated item \(id.uuidString.prefix(8))")
        }
    }
    
    /// Mark an item as errored with message.
    func markError(id: UUID, message: String) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].state = .error
                processingQueue[index].progressMessage = message
            }
            queueLogger.error("Marked item \(id.uuidString.prefix(8)) as error: \(message)")
        }
    }
    
    /// Remove an item from the queue.
    func removeItem(id: UUID) {
        withAnimation(.swissSpring) {
            processingQueue.removeAll { $0.id == id }
        }
        queueLogger.debug("Removed item from queue")
    }
    
    /// Get an item by ID.
    func getItem(id: UUID) -> ProcessingItem? {
        return processingQueue.first { $0.id == id }
    }
    
    /// Clear all items from the queue.
    func clearQueue() {
        withAnimation(.swissSpring) {
            processingQueue.removeAll()
        }
        queueLogger.info("Queue cleared")
    }
    
    // MARK: - Rate Limit Management
    
    /// Start rate limit countdown.
    func startRateLimitCountdown(duration: TimeInterval) {
        isRateLimited = true
        rateLimitCountdown = Int(duration)
        
        countdownTimer?.cancel()
        countdownTimer = Task { @MainActor in
            while rateLimitCountdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                rateLimitCountdown -= 1
            }
            isRateLimited = false
            queueLogger.info("Rate limit expired")
        }
    }
    
    /// Clear rate limit state.
    func clearRateLimit() {
        isRateLimited = false
        rateLimitCountdown = 0
        countdownTimer?.cancel()
        countdownTimer = nil
        queueLogger.debug("Rate limit cleared")
    }
    
    /// Enqueue a scan for later retry.
    func queueScanForRetry() {
        queuedScansCount += 1
        queueLogger.debug("Queued scan for retry, total queued: \(self.queuedScansCount)")
    }
    
    /// Dequeue a scan.
    func dequeueScan() {
        if queuedScansCount > 0 {
            queuedScansCount -= 1
        }
    }
    
    // MARK: - Offline Queue Management
    
    /// Add scan to offline queue.
    func queueOfflineScan() {
        offlineQueuedCount += 1
        queueLogger.debug("Added scan to offline queue, total: \(self.offlineQueuedCount)")
    }
    
    /// Remove scan from offline queue.
    func dequeueOfflineScan() {
        if offlineQueuedCount > 0 {
            offlineQueuedCount -= 1
        }
    }
    
    // MARK: - Error Display
    
    /// Show processing error overlay.
    func showError(message: String) {
        processingErrorMessage = message
        showProcessingError = true
        queueLogger.error("Showing error: \(message)")
    }
    
    /// Hide error overlay.
    func hideError() {
        showProcessingError = false
        processingErrorMessage = nil
    }
    
    /// Show enrichment degradation banner.
    func showEnrichmentDegradation(reason: String?) {
        enrichmentDegradedMessage = reason ?? "Enrichment service temporarily unavailable"
        showEnrichmentDegradedBanner = true
        queueLogger.warning("Enrichment degraded: \(reason ?? "unknown")")
    }
    
    /// Hide enrichment degradation banner.
    func hideEnrichmentDegradation() {
        showEnrichmentDegradedBanner = false
        enrichmentDegradedMessage = nil
    }
    
    /// Show truncation warning.
    func showTruncation() {
        showTruncationBanner = true
        queueLogger.warning("Truncation suspected")
    }
    
    /// Hide truncation warning.
    func hideTruncation() {
        showTruncationBanner = false
    }
    
    // MARK: - Statistics
    
    /// Get number of items in queue.
    var queueCount: Int {
        processingQueue.count
    }
    
    /// Get number of failed items (for potential retry).
    var failedItemCount: Int {
        processingQueue.filter { $0.state == .error }.count
    }
    
    // MARK: - Cleanup
    
    deinit {
        // countdownTimer will be automatically cancelled when deallocated
    }
}
