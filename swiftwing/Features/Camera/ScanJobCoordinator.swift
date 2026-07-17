import Foundation
import os

#if canImport(UIKit)
import UIKit
#endif

private let e2eLogger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "scan-coordinator")

/// Callbacks from ScanJobCoordinator back to the UI layer (CameraViewModel).
/// All closures are @MainActor @Sendable since they update UI state.
struct ScanJobCallbacks: Sendable {
    /// Called when the job reports progress (poll path uses a simple status message)
    let onProgress: @MainActor @Sendable (_ message: String) -> Void

    /// Called when a book result arrives from the results endpoint
    let onBookResult: @MainActor @Sendable (_ metadata: BookMetadata, _ rawJSON: String?, _ preScannedISBN: String?, _ originalPhotoURL: URL?) -> Void

    /// Called when polling completes with books (booksAdded count, thumbnail)
    let onScanComplete: @MainActor @Sendable (_ booksAdded: Int, _ thumbnailData: Data?) -> Void

    /// Called on non-retryable error
    let onError: @MainActor @Sendable (_ message: String) -> Void

    /// Called on retryable error (provides original image data for retry)
    let onRetryableError: @MainActor @Sendable (_ message: String) -> Void

    /// Called when enrichment is degraded (non-fatal info)
    let onEnrichmentDegraded: @MainActor @Sendable (_ reason: String?) -> Void

    /// Called when job is canceled
    let onCanceled: @MainActor @Sendable () -> Void

    /// Called to update queue item progress message
    let onQueueProgress: @MainActor @Sendable (_ message: String?) -> Void

    /// Called to store metadata on the processing item
    let onBookMetadataReceived: @MainActor @Sendable (_ metadata: BookMetadata) -> Void

    /// Called with segmented preview data
    let onSegmented: @MainActor @Sendable (_ preview: SegmentedPreview) -> Void

    /// Called with per-book progress
    let onBookProgress: @MainActor @Sendable (_ current: Int, _ total: Int) -> Void

    /// Called when truncation is suspected in scan results
    let onTruncationSuspected: @MainActor @Sendable () -> Void
}

/// Result of a successful scan upload
struct ScanUploadResult: Sendable {
    let jobId: String
}

/// Coordinates the Upload → HTTP status poll → Results lifecycle for book scanning.
/// Extracted from CameraViewModel (Phase 1B refactoring) to isolate network I/O
/// from UI state management.
actor ScanJobCoordinator {
    private let talariaService: TalariaService
    // Cancel handles for in-flight scan tasks (tasks may have any success type)
    private var activeJobs: [UUID: @Sendable () -> Void] = [:]
    private var cleanupTasks: [Task<Void, Never>] = []

    init(talariaService: TalariaService) {
        self.talariaService = talariaService
    }

    // MARK: - Job Tracking

    func trackJob<Success: Sendable>(id: UUID, task: Task<Success, Never>) {
        activeJobs[id] = { task.cancel() }
    }

    func removeJob(id: UUID) {
        activeJobs.removeValue(forKey: id)
    }

    // MARK: - Upload

    /// Upload image to Talaria and return job info
    func uploadScan(imageData: Data, deviceId: String) async throws -> ScanUploadResult {
        e2eLogger.info("📤 Starting upload to Talaria...")
        #if DEBUG
        integrationLog("UPLOAD: Starting upload to Talaria...")
        #endif

        let (jobId, _) = try await talariaService.uploadScan(image: imageData, deviceId: deviceId)

        e2eLogger.info("📤 Upload success! jobId=\(jobId)")
        #if DEBUG
        integrationLog("UPLOAD: Success! jobId=\(jobId)")
        #endif

        return ScanUploadResult(jobId: jobId)
    }

    // MARK: - Status Polling

    /// Poll scan status from Talaria backend and dispatch results to callbacks.
    /// Returns the number of distinct books delivered from this job.
    func streamAndProcess(
        deviceId: String,
        jobId: String,
        thumbnailData: Data?,
        callbacks: ScanJobCallbacks
    ) async throws -> Int {
        e2eLogger.info("📡 Starting polling for jobId=\(jobId)...")
        #if DEBUG
        integrationLog("POLLING: Starting status polls for jobId=\(jobId)")
        #endif

        // Trigger progress callback to keep UI loader alive
        await callbacks.onProgress("Processing spine...")

        do {
            // Poll for completion and fetch results
            let books = try await talariaService.pollScanStatus(jobId: jobId)

            e2eLogger.info("📡 Polling complete! Received \(books.count) books.")
            #if DEBUG
            integrationLog("POLLING: Success! Received \(books.count) books")
            #endif

            if Task.isCancelled {
                e2eLogger.warning("Polling job cancelled")
                return 0
            }

            var deliveredBookKeys = Set<String>()
            var deliveredBooksCount = 0

            // Process books
            for book in books {
                if let bookKey = deduplicationKey(for: book) {
                    guard deliveredBookKeys.insert(bookKey).inserted else {
                        e2eLogger.info("Skipping duplicate book payload for \(book.resolvedTitle)")
                        continue
                    }
                }

                await callbacks.onBookMetadataReceived(book)

                let rawJSON: String?
                if let jsonData = try? JSONEncoder().encode(book),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    rawJSON = jsonString
                } else {
                    rawJSON = nil
                }

                await callbacks.onBookResult(book, rawJSON, nil, nil)
                deliveredBooksCount += 1
            }

            await callbacks.onScanComplete(deliveredBooksCount, thumbnailData)
            return deliveredBooksCount
        } catch is CancellationError {
            e2eLogger.warning("Polling job cancelled")
            await callbacks.onCanceled()
            return 0
        } catch {
            e2eLogger.error("Polling job failed: \(error.localizedDescription)")
            // NetworkError.scanFailed already carries the server's user-facing
            // failure message — don't stack a second "failed" prefix on it.
            if let networkError = error as? NetworkError, case .scanFailed = networkError {
                await callbacks.onError(error.localizedDescription)
            } else {
                await callbacks.onError("Scan processing failed: \(error.localizedDescription)")
            }
            return 0
        }
    }

    /// Internal (not private) so contract tests can pin dedup-key behavior
    /// (e.g. a server "unknown" ISBN must never produce "isbn:unknown").
    func deduplicationKey(for book: BookMetadata) -> String? {
        if let isbn = book.isbn?.trimmingCharacters(in: .whitespacesAndNewlines), !isbn.isEmpty {
            return "isbn:\(isbn)"
        }

        let title = book.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let author = book.author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, !author.isEmpty else {
            return nil
        }

        return "title-author:\(title.lowercased())|\(author.lowercased())"
    }

    // MARK: - Cleanup

    func cleanupTempFile(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            e2eLogger.info("Local temp file cleanup successful: \(url.lastPathComponent)")
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            e2eLogger.debug("Temp file already deleted: \(url.lastPathComponent)")
        } catch {
            e2eLogger.warning("Local temp file cleanup failed for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - Cancellation

    func cancelAllJobs(processingQueue: [ProcessingItem]) async {
        let jobCount = activeJobs.count
        guard jobCount > 0 else { return }

        e2eLogger.info("Cancelling \(jobCount) active poll jobs (navigation/backgrounding)")

        // Cancel all Swift Task instances
        for (_, cancel) in activeJobs {
            cancel()
        }
        activeJobs.removeAll()

        // Cancel any previously running cleanup tasks
        for task in cleanupTasks { task.cancel() }
        cleanupTasks.removeAll()
    }

    func cancelJob(id: UUID) {
        activeJobs[id]?()
        activeJobs.removeValue(forKey: id)
    }

    var activeJobCount: Int {
        activeJobs.count
    }
}
