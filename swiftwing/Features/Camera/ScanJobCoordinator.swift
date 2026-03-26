import Foundation
import os

#if canImport(UIKit)
import UIKit
#endif

private let e2eLogger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "scan-coordinator")

/// Callbacks from ScanJobCoordinator back to the UI layer (CameraViewModel).
/// All closures are @MainActor @Sendable since they update UI state.
struct ScanJobCallbacks: Sendable {
    /// Called when SSE sends a progress message (e.g. "Analyzing...", "Looking...")
    let onProgress: @MainActor @Sendable (_ message: String) -> Void

    /// Called when a book result arrives (individual SSE result event)
    let onBookResult: @MainActor @Sendable (_ metadata: BookMetadata, _ rawJSON: String?, _ preScannedISBN: String?, _ originalPhotoURL: URL?) -> Void

    /// Called when SSE stream completes with books (booksAdded count, thumbnail, inline books processed)
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

    /// Called when results fetch fails (for retry context)
    let onResultsFetchFailed: @MainActor @Sendable (_ url: String, _ authToken: String, _ jobId: String) -> Void

    /// Called when truncation is suspected in scan results
    let onTruncationSuspected: @MainActor @Sendable () -> Void
}

/// Result of a successful scan upload
struct ScanUploadResult: Sendable {
    let jobId: String
    let streamUrl: URL
    let authToken: String?
}

/// Coordinates the Upload -> SSE Stream -> Results lifecycle for book scanning.
/// Extracted from CameraViewModel (Phase 1B refactoring) to isolate network I/O
/// from UI state management.
actor ScanJobCoordinator {
    private let talariaService: TalariaService
    private var activeJobs: [UUID: Task<Void, Never>] = [:]
    private var jobAuthTokens: [String: String] = [:]
    private var cleanupTasks: [Task<Void, Never>] = []

    init(talariaService: TalariaService) {
        self.talariaService = talariaService
    }

    // MARK: - Job Tracking

    func trackJob(id: UUID, task: Task<Void, Never>) {
        activeJobs[id] = task
    }

    func removeJob(id: UUID) {
        activeJobs.removeValue(forKey: id)
    }

    func storeAuthToken(jobId: String, token: String) {
        jobAuthTokens[jobId] = token
    }

    func getAuthToken(jobId: String) -> String? {
        jobAuthTokens[jobId]
    }

    func removeAuthToken(jobId: String) {
        jobAuthTokens.removeValue(forKey: jobId)
    }

    // MARK: - Upload

    /// Upload image to Talaria and return job info
    func uploadScan(imageData: Data, deviceId: String) async throws -> ScanUploadResult {
        e2eLogger.info("📤 Starting upload to Talaria...")
        #if DEBUG
        integrationLog("UPLOAD: Starting upload to Talaria...")
        #endif

        let (jobId, streamUrl, authToken) = try await talariaService.uploadScan(image: imageData, deviceId: deviceId)

        e2eLogger.info("📤 Upload success! jobId=\(jobId), streamUrl=\(streamUrl.absoluteString)")
        #if DEBUG
        integrationLog("UPLOAD: Success! jobId=\(jobId), streamUrl=\(streamUrl.absoluteString)")
        #endif

        // Store auth token for cleanup
        if let authToken = authToken {
            jobAuthTokens[jobId] = authToken
        }

        return ScanUploadResult(jobId: jobId, streamUrl: streamUrl, authToken: authToken)
    }

    // MARK: - SSE Streaming

    /// Stream SSE events and dispatch to callbacks.
    /// Returns the number of books added to the review queue from this stream.
    func streamAndProcess(
        streamUrl: URL,
        deviceId: String,
        authToken: String?,
        jobId: String,
        thumbnailData: Data?,
        reviewCountBefore: Int,
        callbacks: ScanJobCallbacks,
        getReviewCount: @MainActor @Sendable () -> Int
    ) async throws -> Int {
        let streamStart = CFAbsoluteTimeGetCurrent()

        let eventStream = talariaService.streamEvents(streamUrl: streamUrl, deviceId: deviceId, authToken: authToken)

        e2eLogger.info("📡 Starting SSE event loop...")
        #if DEBUG
        integrationLog("SSE: Starting event loop for streamUrl=\(streamUrl.absoluteString)")
        #endif

        for try await event in eventStream {
            // Check for task cancellation (app backgrounding)
            if Task.isCancelled {
                e2eLogger.warning("SSE stream cancelled (app backgrounding)")
                return 0
            }

            switch event {
            case .progress(let info):
                e2eLogger.info("SSE progress: \(info.message)")
                #if DEBUG
                integrationLog("SSE: progress event: \(info.message)")
                #endif
                await callbacks.onProgress(info.message)

            case .result(let bookMetadata):
                e2eLogger.info("Book result: \(bookMetadata.resolvedTitle) by \(bookMetadata.resolvedAuthor)")
                #if DEBUG
                integrationLog("SSE: result event: '\(bookMetadata.resolvedTitle)' by '\(bookMetadata.resolvedAuthor)'")
                #endif

                await callbacks.onBookMetadataReceived(bookMetadata)

                // Encode metadata to raw JSON string for debugging
                let rawJSON: String?
                if let jsonData = try? JSONEncoder().encode(bookMetadata),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    rawJSON = jsonString
                } else {
                    rawJSON = nil
                }

                await callbacks.onBookResult(bookMetadata, rawJSON, nil, nil)

            case .complete(let resultsUrl, let inlineBooks, let summary, let duration, let truncation):
                let streamDuration = CFAbsoluteTimeGetCurrent() - streamStart
                e2eLogger.info("SSE complete! duration=\(String(format: "%.1f", streamDuration))s, hasResultsUrl=\(resultsUrl != nil), inlineBooks=\(inlineBooks?.count ?? -1)")
                if let summary { e2eLogger.info("Scan summary: \(summary.totalDetected) detected, \(summary.totalUnique) unique") }
                if let duration, let totalMs = duration.totalMs { e2eLogger.info("Scan duration: \(totalMs)ms") }
                if let truncation, truncation.truncationSuspected {
                    e2eLogger.warning("Truncation suspected in scan results")
                    await callbacks.onTruncationSuspected()
                }
                #if DEBUG
                integrationLog("SSE: COMPLETE event! hasResultsUrl=\(resultsUrl != nil), inlineBooks=\(inlineBooks?.count ?? -1)")
                #endif

                var books: [BookMetadata] = []

                // First, check for inline books (modern API)
                if let inlineBooks = inlineBooks, !inlineBooks.isEmpty {
                    e2eLogger.info("Using inline books from completion event (\(inlineBooks.count) books)")
                    books = inlineBooks
                }
                // Fallback to fetching from resultsUrl (legacy API)
                else if let url = resultsUrl,
                        let storedAuthToken = jobAuthTokens[jobId] {
                    e2eLogger.info("Fetching book results from: \(url)")

                    do {
                        books = try await talariaService.fetchResults(
                            resultsUrl: url,
                            authToken: storedAuthToken
                        )
                        e2eLogger.info("Received \(books.count) books from results API")
                    } catch {
                        e2eLogger.error("Failed to fetch results from \(url): \(error.localizedDescription)")
                        await callbacks.onResultsFetchFailed(url, storedAuthToken, jobId)
                        return 0
                    }
                } else {
                    // Missing both inline books and resultsUrl
                    e2eLogger.warning("No results available in completion event")
                    #if DEBUG
                    integrationLog("SSE: COMPLETE but NO RESULTS - no inline books and no resultsUrl")
                    #endif

                    // Check if books were already delivered via individual SSE result events
                    let currentReviewCount = await getReviewCount()
                    let booksFromResultEvents = currentReviewCount - reviewCountBefore
                    if booksFromResultEvents > 0 {
                        e2eLogger.info("\(booksFromResultEvents) book(s) already delivered via result events, treating complete as success")
                        #if DEBUG
                        integrationLog("SSE: COMPLETE with books from result events (\(booksFromResultEvents) books), treating as success")
                        #endif
                        await callbacks.onScanComplete(booksFromResultEvents, thumbnailData)
                        removeAuthToken(jobId: jobId)
                        return booksFromResultEvents
                    } else {
                        #if DEBUG
                        integrationLog("SSE: COMPLETE with no books at all - treating as error")
                        #endif
                        await callbacks.onError("No results available")
                        removeAuthToken(jobId: jobId)
                        return 0
                    }
                }

                // Process all books via callbacks
                let countBefore = await getReviewCount()
                for book in books {
                    #if DEBUG
                    integrationLog("SSE: Processing book from complete: '\(book.resolvedTitle)' by '\(book.resolvedAuthor)'")
                    #endif
                    let rawJSON: String?
                    if let jsonData = try? JSONEncoder().encode(book),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        rawJSON = jsonString
                    } else {
                        rawJSON = nil
                    }
                    await callbacks.onBookResult(book, rawJSON, nil, nil)
                }

                let booksAdded = await getReviewCount() - countBefore
                await callbacks.onScanComplete(booksAdded, thumbnailData)
                removeAuthToken(jobId: jobId)
                return booksAdded

            case .error(let errorInfo):
                e2eLogger.error("SSE error (jobId: \(jobId)): \(errorInfo.message), retryable: \(errorInfo.retryable ?? false)")
                #if DEBUG
                integrationLog("SSE: ERROR event: \(errorInfo.message), retryable=\(errorInfo.retryable ?? false)")
                #endif

                if errorInfo.retryable == true {
                    e2eLogger.info("Error is retryable - signaling for retry")
                    await callbacks.onRetryableError(errorInfo.message)
                } else {
                    e2eLogger.error("Error is NOT retryable - showing permanent error")
                    await callbacks.onError(errorInfo.message)
                }
                removeAuthToken(jobId: jobId)
                return 0

            case .canceled:
                e2eLogger.warning("SSE job canceled (jobId: \(jobId))")
                await callbacks.onCanceled()
                removeAuthToken(jobId: jobId)
                return 0

            case .segmented(let preview):
                e2eLogger.debug("Segmented preview: \(preview.totalBooks) books detected (\(preview.imageData.count) bytes)")
                await callbacks.onSegmented(preview)

            case .bookProgress(let progress):
                e2eLogger.debug("Book progress: \(progress.current)/\(progress.total)")
                await callbacks.onBookProgress(progress.current, progress.total)

            case .ping:
                e2eLogger.debug("SSE ping received")

            case .enrichmentDegraded(let info):
                e2eLogger.warning("Enrichment degraded: \(info.reason ?? "unknown reason")")
                if let isbn = info.isbn {
                    e2eLogger.debug("Enrichment degraded ISBN: \(isbn)")
                }
                if let fallback = info.fallbackSource {
                    e2eLogger.debug("Enrichment fallback: \(fallback)")
                }
                await callbacks.onEnrichmentDegraded(info.reason)
            }
        }

        #if DEBUG
        integrationLog("SSE: for-await loop EXITED normally (no more events). Task.isCancelled=\(Task.isCancelled)")
        #endif

        return 0
    }

    // MARK: - Cleanup

    func cleanup(jobId: String, authToken: String? = nil) async {
        let token = authToken ?? jobAuthTokens[jobId]
        do {
            try await talariaService.cleanup(jobId: jobId, authToken: token)
            e2eLogger.info("Server cleanup successful for job: \(jobId)")
        } catch {
            e2eLogger.warning("Server cleanup failed for job \(jobId): \(error.localizedDescription)")
        }
    }

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

    /// Fetch results from a URL (used for retry)
    func fetchResults(resultsUrl: String, authToken: String) async throws -> [BookMetadata] {
        try await talariaService.fetchResults(resultsUrl: resultsUrl, authToken: authToken)
    }

    // MARK: - Cancellation

    func cancelAllJobs(processingQueue: [ProcessingItem]) async {
        let jobCount = activeJobs.count
        guard jobCount > 0 else { return }

        e2eLogger.info("Cancelling \(jobCount) active SSE streams (navigation/backgrounding)")

        // Cancel all Swift Task instances
        for (_, task) in activeJobs {
            task.cancel()
        }
        activeJobs.removeAll()

        // Collect all in-progress job IDs that need backend cleanup
        let activeJobIds = processingQueue
            .filter { $0.state == .uploading || $0.state == .analyzing }
            .compactMap { $0.jobId }

        // Cancel any previously running cleanup tasks
        for task in cleanupTasks { task.cancel() }
        cleanupTasks.removeAll()

        // Fire-and-forget cleanup calls to backend (tracked for future cancellation)
        for activeJobId in activeJobIds {
            let storedAuthToken = jobAuthTokens[activeJobId]
            let service = talariaService
            let cleanupTask = Task {
                do {
                    try await service.cleanup(jobId: activeJobId, authToken: storedAuthToken)
                    e2eLogger.info("Backend cleanup sent for disconnected job: \(activeJobId)")
                } catch {
                    e2eLogger.warning("Backend cleanup failed for \(activeJobId): \(error.localizedDescription)")
                }
            }
            cleanupTasks.append(cleanupTask)
        }

        // Clear all auth tokens
        jobAuthTokens.removeAll()
    }

    func cancelJob(id: UUID) {
        activeJobs[id]?.cancel()
        activeJobs.removeValue(forKey: id)
    }

    var activeJobCount: Int {
        activeJobs.count
    }
}
