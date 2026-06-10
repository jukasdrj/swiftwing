import os
import SwiftUI
import AVFoundation
import SwiftData
import Observation

private let e2eLogger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "e2e-vm")

#if canImport(UIKit)
import UIKit
#endif

/// ViewModel for CameraView with @Observable for reactive state management
/// Extracted from CameraView.swift (Phase 2A refactoring)
/// Manages all camera state, processing queue, and business logic
@MainActor
@Observable
final class CameraViewModel {
    // MARK: - Core State
    var cameraManager = CameraManager()
    var isLoading = true
    var errorMessage: String?
    var coldStartTime: CFAbsoluteTime = 0
    var showFlash = false
    var focusPoint: CGPoint?
    var showFocusIndicator = false

    // MARK: - Review Queue Manager (extracted Phase 1A)
    let reviewQueueManager = ReviewQueueManager()

    // MARK: - Tab Navigation
    var requestedTab: Int?

    // MARK: - Scan Job Coordinator (extracted Phase 1B)
    let scanCoordinator: ScanJobCoordinator

    // MARK: - Queue State Manager (extracted Phase 2B)
    let queueStateManager: QueueStateManager
    
    // MARK: - Forwarding properties for backward compatibility with views
    var processingQueue: [ProcessingItem] { queueStateManager.processingQueue }
    var isRateLimited: Bool {
        get { queueStateManager.isRateLimited }
        set { queueStateManager.isRateLimited = newValue }
    }
    var rateLimitCountdown: Int {
        get { queueStateManager.rateLimitCountdown }
        set { queueStateManager.rateLimitCountdown = newValue }
    }
    var queuedScansCount: Int {
        get { queueStateManager.queuedScansCount }
        set { queueStateManager.queuedScansCount = newValue }
    }
    var offlineQueuedCount: Int {
        get { queueStateManager.offlineQueuedCount }
        set { queueStateManager.offlineQueuedCount = newValue }
    }
    var processingErrorMessage: String? {
        get { queueStateManager.processingErrorMessage }
        set { queueStateManager.processingErrorMessage = newValue }
    }
    var showProcessingError: Bool {
        get { queueStateManager.showProcessingError }
        set { queueStateManager.showProcessingError = newValue }
    }
    var enrichmentDegradedMessage: String? {
        get { queueStateManager.enrichmentDegradedMessage }
        set { queueStateManager.enrichmentDegradedMessage = newValue }
    }
    var showEnrichmentDegradedBanner: Bool {
        get { queueStateManager.showEnrichmentDegradedBanner }
        set { queueStateManager.showEnrichmentDegradedBanner = newValue }
    }
    var showTruncationBanner: Bool {
        get { queueStateManager.showTruncationBanner }
        set { queueStateManager.showTruncationBanner = newValue }
    }

    // MARK: - US-408: Rate Limit State
    let rateLimitState: RateLimitState = RateLimitState()
    private var rateLimitCountdownTask: Task<Void, Never>?

    // MARK: - US-409: Offline Queue State
    var networkMonitor: NetworkMonitor = NetworkMonitor()
    let offlineQueueManager: OfflineQueueManager = OfflineQueueManager()
    private var isUploadingOfflineScans = false

    // MARK: - Capture Throttle
    private var activeCaptureCount = 0
    private let maxConcurrentCaptures = 5

    // MARK: - US-410: Stream Concurrency Manager
    let streamManager: StreamManager = StreamManager()

    // MARK: - Camera Interruption State
    var isInterrupted: Bool {
        cameraManager.isInterrupted
    }

    // MARK: - Haptic Feedback (delegated to CameraHapticsManager)
    private let haptics = CameraHapticsManager()

    // MARK: - Image Preprocessing
    private let imagePreprocessor = ImagePreprocessor()

    // MARK: - ModelContext (injected by view)
    var modelContext: ModelContext?

    // MARK: - Device Identity
    private let deviceId: String

    // MARK: - Talaria Service (single shared instance)
    private let talariaService: TalariaService

    // MARK: - Initialization
    init(deviceId: String = DeviceIdentifier.current, talariaService: TalariaService? = nil) {
        self.deviceId = deviceId
        let service = talariaService ?? TalariaService(deviceId: deviceId)
        self.talariaService = service
        self.scanCoordinator = ScanJobCoordinator(talariaService: service)
        self.queueStateManager = QueueStateManager()
    }

    // MARK: - Camera Setup
    func setupCamera() async {
        coldStartTime = CFAbsoluteTimeGetCurrent()

        // Show loading spinner only if setup takes > 200ms.
        // Store the handle so we can cancel it if setup finishes first.
        let loadingTask = Task {
            try? await Task.sleep(for: .milliseconds(200)) // 200ms
            if cameraManager.captureSession == nil {
                isLoading = true
            }
        }

        do {
            // Configure session (must be on main thread per AVFoundation docs)
            try cameraManager.setupSession()

            // Prepare haptic generators for faster response
            haptics.prepare()

            // Start session on background thread (non-blocking)
            cameraManager.startSession()

            // Cancel the deferred loading task — setup finished before it could fire
            loadingTask.cancel()

            // Update UI
            isLoading = false

            // Log total cold start time
            let totalDuration = CFAbsoluteTimeGetCurrent() - coldStartTime
            e2eLogger.info("Camera cold start: \(String(format: "%.3f", totalDuration))s (target: < 0.5s)")

            if totalDuration >= 0.5 {
                e2eLogger.warning("Camera cold start exceeded 0.5s target!")
            }

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            e2eLogger.error("Camera setup failed: \(error.localizedDescription)")
        }
    }

    func stopCamera() {
        cameraManager.stopSession()
    }

    /// Configure rotation coordinator after preview layer is available
    /// Called from CameraPreviewView once preview layer exists
    func configureRotationCoordinator(previewLayer: AVCaptureVideoPreviewLayer) {
        cameraManager.configureRotation(previewLayer: previewLayer)
    }

    // MARK: - Image Capture
    func captureImage() {
        // US-408: Safety check - should not be called when rate limited (button is disabled)
        guard !queueStateManager.isRateLimited else {
            e2eLogger.warning("Capture blocked: rate limited")
            return
        }

        guard activeCaptureCount < maxConcurrentCaptures else {
            let limit = maxConcurrentCaptures
            e2eLogger.warning("Max concurrent captures reached (\(limit))")
            return
        }
        activeCaptureCount += 1

        // Show flash immediately (100ms animation)
        withAnimation(.easeOut(duration: 0.1)) {
            showFlash = true
        }

        // Hide flash after 100ms
        Task {
            try? await Task.sleep(for: .milliseconds(100)) // 100ms
            withAnimation(.easeOut(duration: 0.1)) {
                showFlash = false
            }
        }

        // Fire and forget - process capture in parallel (non-blocking)
        let itemId = UUID()
        let task = Task {
            await processCapture(itemId: itemId)
            self.activeCaptureCount -= 1
        }
        Task { await scanCoordinator.trackJob(id: itemId, task: task) }
    }

    // MARK: - Processing Pipeline
    private func processCapture(itemId: UUID) async {
        do {
            // Capture photo from camera (must be on main actor)
            let imageData = try await cameraManager.capturePhoto()
            e2eLogger.info("Image captured (\(imageData.count) bytes)")

            // Process with injected modelContext
            guard let modelContext = modelContext else {
                e2eLogger.error("ModelContext not injected — cannot process capture")
                await showProcessingErrorOverlay("Internal error: storage unavailable. Please restart the app.")
                return
            }

            await processCaptureWithImageData(itemId: itemId, imageData: imageData, modelContext: modelContext)
        } catch {
            e2eLogger.error("Camera capture failed: \(error.localizedDescription)")
            await showProcessingErrorOverlay(error.localizedDescription)
        }
    }

    /// - Returns: true when the scan was uploaded successfully or safely handed
    ///   off (re-queued offline); false when processing failed and any persisted
    ///   copy of the scan should be retained for retry
    @discardableResult
    func processCaptureWithImageData(itemId: UUID, imageData: Data, modelContext: ModelContext, preScannedISBN: String? = nil) async -> Bool {
        let startTime = CFAbsoluteTimeGetCurrent()
        var queueItem: ProcessingItem?
        var tempFileURL: URL?
        var jobId: String?
        var authToken: String?
        // Use caller-supplied pre-scanned ISBN if provided (e.g. from offline queue retry)
        let capturedISBN = preScannedISBN

        // Cleanup task tracker when done
        defer {
            Task { await scanCoordinator.removeJob(id: itemId) }
        }

        do {
            e2eLogger.info("Processing image data (\(imageData.count) bytes)")

            // US-409: Check if offline - if so, queue for later upload
            e2eLogger.info("Network check: isConnected=\(self.networkMonitor.isConnected)")
            if !networkMonitor.isConnected {
                e2eLogger.warning("Offline mode - queueing scan for later upload")

                // Add to processing queue with offline state
                let item = queueStateManager.addItem(imageData: imageData, preScannedISBN: capturedISBN)
                queueStateManager.updateItem(id: item.id, state: .offline, message: "Queued (offline)")

                // Queue scan in FileManager for persistent storage
                let queuedId = try await offlineQueueManager.queueScan(imageData: imageData, preScannedISBN: capturedISBN)
                e2eLogger.info("Scan queued with ID: \(queuedId)")

                // Update offline queue count
                let count = try await offlineQueueManager.getQueuedScanCount()
                queueStateManager.offlineQueuedCount = count

                // Keep item in queue indefinitely until uploaded
                return true
            }

            // Add to processing queue immediately with thumbnail (preprocessing state)
            let item = queueStateManager.addItem(imageData: imageData, preScannedISBN: capturedISBN)
            queueItem = item

            // Steps 1 & 2: Preprocess + process image for upload
            let (uploadData, fileURL) = try await preprocessAndPrepareUpload(
                itemId: itemId, item: item, imageData: imageData, startTime: startTime
            )
            tempFileURL = fileURL

            // Step 3: Upload to Talaria
            let uploadResult = try await uploadToTalaria(
                itemId: itemId, item: item, uploadData: uploadData, fileURL: fileURL
            )
            jobId = uploadResult.jobId
            authToken = uploadResult.authToken

            // Switch to analyzing state
            queueStateManager.updateItem(id: item.id, state: .analyzing, message: "Analyzing...")

            // Capture item ID and thumbnail for callbacks
            let capturedItemId = item.id
            let capturedThumbnailData = item.thumbnailData

            // Build callbacks for the coordinator (thread photo URL for bounding box overlay)
            let callbacks = buildScanCallbacks(
                itemId: capturedItemId, item: item, capturedISBN: capturedISBN, modelContext: modelContext, originalPhotoURL: tempFileURL
            )

            // Stream SSE events via coordinator
            let _ = try await scanCoordinator.streamAndProcess(
                streamUrl: uploadResult.streamUrl,
                deviceId: self.deviceId,
                authToken: authToken,
                jobId: uploadResult.jobId,
                thumbnailData: capturedThumbnailData,
                callbacks: callbacks
            )

            // Check if task was cancelled during streaming
            if Task.isCancelled {
                if let tempFileURL { await scanCoordinator.cleanupTempFile(tempFileURL) }
                return false
            }

            // Success path - mark as done (unless callbacks already handled error/retry)
            if let index = queueStateManager.processingQueue.firstIndex(where: { $0.id == capturedItemId }),
               queueStateManager.processingQueue[index].state == .analyzing {
                queueStateManager.updateItem(id: capturedItemId, state: .done, message: nil)
            }

            // Auto-remove from queue after 5 seconds
            await removeQueueItemAfterDelay(id: capturedItemId, delay: 5.0)
            return true

        } catch is CancellationError {
            // Task was cancelled (e.g. user navigated away) — not a user-visible error
            e2eLogger.debug("processCaptureWithImageData: task cancelled")
            return false
        } catch {
            e2eLogger.error("❌ processCaptureWithImageData error: \(error.localizedDescription)")
            #if DEBUG
            integrationLog("ERROR: processCaptureWithImageData catch: \(error) - \(error.localizedDescription)")
            #endif
            if let networkError = error as? NetworkError,
               case .rateLimited(let retryAfter) = networkError {
                await handleRateLimitError(retryAfter: retryAfter, imageData: imageData, capturedISBN: capturedISBN, queueItem: queueItem, tempFileURL: tempFileURL)
            } else {
                await handleProcessingError(error: error, queueItem: queueItem, jobId: jobId, authToken: authToken, tempFileURL: tempFileURL)
            }
            return false
        }
    }

    // MARK: - Error Handling Helpers

    private func handleRateLimitError(
        retryAfter: TimeInterval?,
        imageData: Data,
        capturedISBN: String?,
        queueItem: ProcessingItem?,
        tempFileURL: URL?
    ) async {
        e2eLogger.warning("Rate limited: retry after \(retryAfter ?? 0)s")

        await rateLimitState.queueScan(imageData, preScannedISBN: capturedISBN)

        let retryDuration = retryAfter ?? 60.0
        await rateLimitState.setRateLimited(retryAfter: retryDuration)

        await startRateLimitCountdown()

        if let item = queueItem {
            queueStateManager.removeItem(id: item.id)
        }

        if let tempFileURL = tempFileURL {
            try? FileManager.default.removeItem(at: tempFileURL)
        }
    }

    private func handleProcessingError(
        error: Error,
        queueItem: ProcessingItem?,
        jobId: String?,
        authToken: String?,
        tempFileURL: URL?
    ) async {
        e2eLogger.error("Image processing/upload failed: \(error.localizedDescription)")

        await showProcessingErrorOverlay(error.localizedDescription)

        if let item = queueItem {
            queueStateManager.markError(id: item.id, message: error.localizedDescription)

            haptics.errorOccurred()

            if let tempFileURL { await scanCoordinator.cleanupTempFile(tempFileURL) }

            await removeQueueItemAfterDelay(id: item.id, delay: 5.0)
        }
    }

    // MARK: - Processing Pipeline Helpers

    /// Preprocess raw image data and compress it for upload.
    /// Returns the processed image data and temp file URL.
    private func preprocessAndPrepareUpload(itemId: UUID, item: ProcessingItem, imageData: Data, startTime: CFAbsoluteTime) async throws -> (Data, URL) {
        // Step 1: Preprocess image (contrast, brightness, denoising, rotation)
        queueStateManager.updateItem(id: item.id, state: .preprocessing, message: "Preprocessing...")
        let preprocessResult = await imagePreprocessor.preprocess(imageData)
        e2eLogger.debug("Preprocessing: \(preprocessResult.processingTimeMs)ms, rotated: \(preprocessResult.wasRotated), brightness adj: \(preprocessResult.brightnessAdjustment)")

        // Step 2: Process (resize + compress) the preprocessed image
        let fileURL = try await imagePreprocessor.processImageForUpload(preprocessResult.processedData)

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        e2eLogger.info("Image processed in \(String(format: "%.3f", duration))s (target: < 0.5s)")

        if duration >= 0.5 {
            e2eLogger.warning("Image processing exceeded 0.5s target!")
        }

        let uploadData = try Data(contentsOf: fileURL)
        return (uploadData, fileURL)
    }

    /// Acquire a stream slot, upload image data to Talaria, and record cleanup info.
    /// Returns the upload result containing jobId, authToken, and streamUrl.
    private func uploadToTalaria(itemId: UUID, item: ProcessingItem, uploadData: Data, fileURL: URL) async throws -> ScanUploadResult {
        // US-410: Performance optimization - limit concurrent SSE streams to 5
        await streamManager.acquireStreamSlot(scanId: itemId)
        guard await streamManager.hasActiveSlot(scanId: itemId) else {
            throw CancellationError()
        }

        // Note: slot release is explicit at each exit point below (success and error).
        // A fire-and-forget Task in defer is not guaranteed to execute before the caller
        // resumes, so we release directly with await instead.
        do {
            queueStateManager.updateProgress(id: item.id, message: "Uploading...")

            let uploadStart = CFAbsoluteTimeGetCurrent()
            let uploadResult = try await scanCoordinator.uploadScan(imageData: uploadData, deviceId: self.deviceId)
            let uploadDuration = (CFAbsoluteTimeGetCurrent() - uploadStart) * 1000 // Convert to ms
            e2eLogger.info("Upload took \(Int(uploadDuration))ms, jobId: \(uploadResult.jobId)")

            // Store temp file URL and job ID for cleanup (US-406)
            updateQueueItemCleanupInfo(id: item.id, tempFileURL: fileURL, jobId: uploadResult.jobId)

            await streamManager.releaseStreamSlot(scanId: itemId)
            return uploadResult
        } catch {
            await streamManager.releaseStreamSlot(scanId: itemId)
            throw error
        }
    }

    /// Build the full set of SSE streaming callbacks for a scan job.
    private func buildScanCallbacks(itemId: UUID, item: ProcessingItem, capturedISBN: String?, modelContext: ModelContext, originalPhotoURL: URL? = nil) -> ScanJobCallbacks {
        let capturedThumbnailData = item.thumbnailData

        return ScanJobCallbacks(
            onProgress: { [weak self] message in
                self?.queueStateManager.updateProgress(id: itemId, message: message)
            },
            onBookResult: { [weak self] metadata, rawJSON, _, _ in
                self?.reviewQueueManager.handleBookResult(metadata: metadata, rawJSON: rawJSON, thumbnailData: capturedThumbnailData, preScannedISBN: capturedISBN, originalPhotoURL: originalPhotoURL, modelContext: modelContext)
            },
            onScanComplete: { [weak self] booksAdded, thumbnailData in
                self?.reviewQueueManager.showScanComplete(booksAdded: booksAdded, thumbnailData: thumbnailData)
            },
            onError: { [weak self] message in
                self?.queueStateManager.markError(id: itemId, message: message)
                Task {
                    await self?.showProcessingErrorOverlay(message)
                }
                self?.haptics.errorOccurred()
            },
            onRetryableError: { [weak self] message in
                guard let self else { return }
                self.queueStateManager.updateProgress(id: itemId, message: "Retrying...")

                // Auto-retry once after 2 second delay
                if let originalImageData = item.originalImageData {
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        self.queueStateManager.removeItem(id: itemId)

                        let retryItemId = UUID()
                        let retryTask = Task {
                            await self.processCaptureWithImageData(itemId: retryItemId, imageData: originalImageData, modelContext: modelContext, preScannedISBN: capturedISBN)
                        }
                        await self.scanCoordinator.trackJob(id: retryItemId, task: retryTask)
                    }
                } else {
                    self.queueStateManager.markError(id: itemId, message: message)
                    Task {
                        await self.showProcessingErrorOverlay(message)
                    }
                    self.haptics.errorOccurred()
                }
            },
            onEnrichmentDegraded: { [weak self] reason in
                Task {
                    await self?.showEnrichmentDegradedBanner(reason: reason)
                }
            },
            onCanceled: { [weak self] in
                self?.queueStateManager.updateItem(id: itemId, state: .error, message: "Canceled")
            },
            onQueueProgress: { [weak self] message in
                self?.queueStateManager.updateProgress(id: itemId, message: message)
            },
            onBookMetadataReceived: { [weak self] metadata in
                if let index = self?.queueStateManager.processingQueue.firstIndex(where: { $0.id == itemId }) {
                    self?.queueStateManager.processingQueue[index].bookMetadata = metadata
                }
            },
            onSegmented: { [weak self] preview in
                self?.updateQueueItemSegmented(id: itemId, preview: preview)
            },
            onBookProgress: { [weak self] current, total in
                self?.updateQueueItemBookProgress(id: itemId, current: current, total: total)
            },
            onResultsFetchFailed: { [weak self] url, fetchAuthToken, failedJobId in
                self?.queueStateManager.markError(id: itemId, message: "Failed to fetch results. Check network and retry.")
                if let index = self?.queueStateManager.processingQueue.firstIndex(where: { $0.id == itemId }) {
                    self?.queueStateManager.processingQueue[index].retryContext = ResultsFetchRetryContext(
                        resultsUrl: url,
                        authToken: fetchAuthToken,
                        jobId: failedJobId
                    )
                }
                e2eLogger.info("Item kept in queue for manual retry")
            },
            onTruncationSuspected: { [weak self] in
                guard let self else { return }
                e2eLogger.warning("Scan results may be truncated (large bookshelf)")
                self.queueStateManager.showTruncation()
            }
        )
    }

    // MARK: - Queue Management
    
    private func updateQueueItemSegmented(id: UUID, preview: SegmentedPreview) {
        if let index = queueStateManager.processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                queueStateManager.processingQueue[index].segmentedPreview = preview.imageData
                queueStateManager.processingQueue[index].detectedBookCount = preview.totalBooks
            }
        }
    }

    private func updateQueueItemBookProgress(id: UUID, current: Int, total: Int) {
        if let index = queueStateManager.processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                queueStateManager.processingQueue[index].currentBookIndex = current
                queueStateManager.processingQueue[index].progressMessage = "Processing book \(current)/\(total)"
            }
        }
    }

    private func updateQueueItemCleanupInfo(id: UUID, tempFileURL: URL, jobId: String) {
        if let index = queueStateManager.processingQueue.firstIndex(where: { $0.id == id }) {
            queueStateManager.processingQueue[index].tempFileURL = tempFileURL
            queueStateManager.processingQueue[index].jobId = jobId
        }
    }

    private func removeQueueItemAfterDelay(id: UUID, delay: TimeInterval) async {
        try? await Task.sleep(for: .seconds(delay))
        queueStateManager.removeItem(id: id)
    }

    // MARK: - US-407: Retry Failed Item
    func retryFailedItem(_ item: ProcessingItem) {
        guard item.state == .error,
              let imageData = item.originalImageData else {
            e2eLogger.warning("Cannot retry: item not in error state or no image data")
            return
        }

        e2eLogger.info("Retrying failed item: \(item.id)")

        queueStateManager.removeItem(id: item.id)

        haptics.retryTriggered()

        guard let ctx = modelContext else {
            e2eLogger.error("ModelContext not injected — cannot retry failed item")
            return
        }

        let itemId = UUID()
        let task = Task {
            await processCaptureWithImageData(itemId: itemId, imageData: imageData, modelContext: ctx, preScannedISBN: item.preScannedISBN)
        }
        Task { await scanCoordinator.trackJob(id: itemId, task: task) }
    }

    // MARK: - US-408: Rate Limit Management
    func startRateLimitCountdown() async {
        rateLimitCountdownTask?.cancel()

        let duration = TimeInterval(await rateLimitState.getRemainingSeconds())
        guard duration > 0 else {
            await rateLimitState.clearRateLimit()
            queueStateManager.clearRateLimit()
            return
        }

        queueStateManager.startRateLimitCountdown(duration: duration)

        rateLimitCountdownTask = Task { [weak self] in
            await self?.monitorRateLimitExpiration()
        }
    }

    // MARK: - US-406: Stream Cancellation
    func cancelAllStreamingTasks() {
        let queueSnapshot = queueStateManager.processingQueue
        Task {
            await scanCoordinator.cancelAllJobs(processingQueue: queueSnapshot)
        }

        // Remove in-progress items from queue with animation
        queueStateManager.processingQueue.removeAll {
            $0.state == .uploading || $0.state == .analyzing
        }
    }

    // MARK: - Error Display
    private func showProcessingErrorOverlay(_ message: String) async {
        queueStateManager.showError(message: message)

        try? await Task.sleep(for: .seconds(5))
        queueStateManager.hideError()
    }

    private func showEnrichmentDegradedBanner(reason: String?) async {
        queueStateManager.showEnrichmentDegradation(reason: reason)

        // Auto-dismiss after 5 seconds
        try? await Task.sleep(for: .seconds(5))
        queueStateManager.hideEnrichmentDegradation()
    }

    private func monitorRateLimitExpiration() async {
        do {
            while await rateLimitState.getRemainingSeconds() > 0 {
                try await Task.sleep(for: .seconds(1))
            }

            await rateLimitState.clearRateLimit()
            queueStateManager.clearRateLimit()

            let queuedScans = await rateLimitState.dequeueAllScans()
            guard !queuedScans.isEmpty else {
                return
            }

            guard let ctx = modelContext else {
                e2eLogger.error("ModelContext not injected — cannot process rate-limit queue")
                return
            }

            for scan in queuedScans {
                let itemId = UUID()
                let task = Task {
                    await processCaptureWithImageData(itemId: itemId, imageData: scan.imageData, modelContext: ctx, preScannedISBN: scan.preScannedISBN)
                }
                await scanCoordinator.trackJob(id: itemId, task: task)
            }
        } catch is CancellationError {
            e2eLogger.debug("Rate limit countdown task canceled")
        } catch {
            e2eLogger.error("Rate limit countdown task failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Focus Handling
    func handleFocusTap(_ devicePoint: CGPoint) {
        cameraManager.setFocusPoint(devicePoint)

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }
        let screenSize = windowScene.screen.bounds.size
        let screenPoint = CGPoint(
            x: devicePoint.x * screenSize.width,
            y: devicePoint.y * screenSize.height
        )

        focusPoint = screenPoint
        withAnimation(.easeOut(duration: 0.2)) {
            showFocusIndicator = true
        }

        Task {
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeOut(duration: 0.3)) {
                showFocusIndicator = false
            }
        }
    }

    func checkAndUploadQueuedScans() async {
        do {
            let count = try await offlineQueueManager.getQueuedScanCount()
            queueStateManager.offlineQueuedCount = count

            if count > 0 && networkMonitor.isConnected {
                e2eLogger.info("Found \(count) queued scans - uploading now")
                await uploadQueuedScans()
            } else if count > 0 {
                e2eLogger.info("Found \(count) queued scans - waiting for network")
            }
        } catch {
            e2eLogger.warning("Failed to check queued scans: \(error.localizedDescription)")
        }
    }

    func uploadQueuedScans() async {
        guard !isUploadingOfflineScans else {
            e2eLogger.info("Offline upload already in progress - skipping duplicate trigger")
            return
        }

        isUploadingOfflineScans = true
        defer { isUploadingOfflineScans = false }

        do {
            var hasScans = false

            guard let ctx = modelContext else {
                e2eLogger.error("ModelContext not injected — cannot upload queued scans")
                return
            }

            queueStateManager.processingQueue.removeAll { $0.state == .offline }

            // Stream queued scans one at a time from oldest to newest
            for try await (metadata, imageData) in offlineQueueManager.streamQueuedScans() {
                hasScans = true
                let itemId = UUID()
                let task = Task {
                    await processCaptureWithImageData(itemId: itemId, imageData: imageData, modelContext: ctx, preScannedISBN: metadata.preScannedISBN)
                }
                await scanCoordinator.trackJob(id: itemId, task: task)

                // Wait for this scan to complete before processing the next one
                let uploaded = await task.value

                // Remove from queue only after successful processing — a failed
                // upload keeps the scan on disk for the next retry pass
                if uploaded {
                    do {
                        try await self.offlineQueueManager.removeQueuedScan(scanId: metadata.id)
                    } catch {
                        e2eLogger.warning("Failed to remove queued scan \(metadata.id): \(error.localizedDescription)")
                    }
                } else {
                    e2eLogger.warning("Queued scan \(metadata.id) failed to upload - keeping in offline queue")
                }
            }

            if !hasScans {
                return
            }

            let finalCount = try await offlineQueueManager.getQueuedScanCount()
            queueStateManager.offlineQueuedCount = finalCount

            e2eLogger.info("All queued scans uploaded")
        } catch {
            e2eLogger.error("Failed to upload queued scans: \(error.localizedDescription)")
        }
    }

    func handleNetworkChange(oldValue: Bool, newValue: Bool) {
        if !oldValue && newValue {
            Task {
                await uploadQueuedScans()
            }
        }
    }

    // MARK: - Fix #2: Retry Failed Results Fetch
    func retryResultsFetch(item: ProcessingItem) {
        guard let context = item.retryContext else {
            e2eLogger.warning("No retry context available")
            return
        }

        e2eLogger.info("Retrying results fetch for job: \(context.jobId)")

        // Reset state to analyzing
        queueStateManager.updateItem(id: item.id, state: .analyzing, message: "Retrying...")

        Task {
            do {
                let books = try await scanCoordinator.fetchResults(
                    resultsUrl: context.resultsUrl,
                    authToken: context.authToken
                )

                e2eLogger.info("Retry successful: Received \(books.count) books")

                guard let ctx = modelContext else {
                    e2eLogger.error("ModelContext not available")
                    return
                }

                // Process all books
                for book in books {
                    // Skip if already in library (e.g., auto-approved during original scan)
                    let isbn = book.isbn ?? ""
                    if !isbn.isEmpty && !isbn.hasPrefix("UNKNOWN-") {
                        if let _ = try? DuplicateDetection.findDuplicate(isbn: isbn, in: ctx) {
                            e2eLogger.info("Retry dedup: skipping '\(book.resolvedTitle)' — already in library")
                            continue
                        }
                    }

                    let rawJSON: String?
                    if let jsonData = try? JSONEncoder().encode(book),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        rawJSON = jsonString
                    } else {
                        rawJSON = nil
                    }

                    reviewQueueManager.handleBookResult(metadata: book, rawJSON: rawJSON, thumbnailData: item.thumbnailData, modelContext: ctx)
                }

                // Success - mark as done
                queueStateManager.updateItem(id: item.id, state: .done, message: nil)
                await removeQueueItemAfterDelay(id: item.id, delay: 5.0)

            } catch {
                e2eLogger.error("Retry failed: \(error.localizedDescription)")
                queueStateManager.markError(id: item.id, message: "Retry failed: \(error.localizedDescription)")
            }
        }
    }

}
