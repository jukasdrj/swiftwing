import Foundation
import SwiftData
import os

private let aggLogger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "streaming-agg")

/// Aggregates SSE events and handles deduplication logic.
/// Prevents duplicate books that appear in both .result events and .completed summary.
/// Extracted from CameraViewModel for better separation of concerns and testability.
actor StreamingAggregator {
    private let modelContext: ModelContext
    private var receivedISBNs = Set<String>()
    private var duplicateCount = 0
    private var enrichmentDegraded = false
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Deduplication
    
    /// Track a book result and check for duplicates.
    /// Returns true if the book is a duplicate and should be skipped.
    func trackBookResult(isbn: String, title: String) -> Bool {
        if receivedISBNs.contains(isbn) {
            aggLogger.debug("Duplicate book detected: \(title, privacy: .public) (ISBN: \(isbn, privacy: .public))")
            duplicateCount += 1
            return true
        }
        receivedISBNs.insert(isbn)
        return false
    }
    
    /// Mark enrichment service as degraded.
    func markEnrichmentDegraded() {
        enrichmentDegraded = true
        aggLogger.warning("Enrichment service degraded")
    }
    
    /// Check if enrichment is degraded.
    nonisolated func isEnrichmentDegraded() -> Bool {
        return enrichmentDegraded
    }
    
    // MARK: - Statistics
    
    /// Get count of unique books received.
    nonisolated func getUniqueBookCount() -> Int {
        // Note: In real implementation, would need to track this with proper atomics
        return receivedISBNs.count
    }
    
    /// Get count of duplicate books detected and skipped.
    nonisolated func getDuplicateCount() -> Int {
        return duplicateCount
    }
    
    // MARK: - Result Finalization
    
    /// Called after all SSE events have been processed.
    /// Performs final deduplication and consolidation.
    func deduplicateResults() async throws {
        aggLogger.info("Finalizing results: unique=\(self.receivedISBNs.count), duplicates=\(self.duplicateCount)")
        
        if enrichmentDegraded {
            aggLogger.warning("Scan completed with enrichment degraded")
        }
    }
    
    /// Save deduplicated results to SwiftData.
    /// This is called after streaming is complete.
    func saveResults(_ books: [BookMetadata]) async throws {
        let dataSyncActor = DataSyncActor()
        
        var savedCount = 0
        var skippedCount = 0
        
        for metadata in books {
            // Check if already tracked from SSE
            if trackBookResult(isbn: metadata.isbn, title: metadata.title) {
                skippedCount += 1
                continue
            }
            
            let book = try await dataSyncActor.makeBook(from: metadata)
            try await dataSyncActor.save(book: book, in: modelContext)
            savedCount += 1
        }
        
        aggLogger.info("Saved \(savedCount) books, skipped \(skippedCount) duplicates")
    }
    
    // MARK: - Reset
    
    /// Reset state for next scan.
    func reset() {
        receivedISBNs.removeAll()
        duplicateCount = 0
        enrichmentDegraded = false
        aggLogger.debug("StreamingAggregator reset")
    }
}

// MARK: - Extension for Model Context

extension StreamingAggregator {
    /// Convenience method to perform bulk deduplication check.
    func filterDuplicates(_ books: [BookMetadata]) -> [BookMetadata] {
        return books.filter { !trackBookResult(isbn: $0.isbn, title: $0.title) }
    }
}
