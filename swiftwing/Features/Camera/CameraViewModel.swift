import os
import SwiftUI
import AVFoundation
import SwiftData

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
    var processingQueue: [ProcessingItem] = []
    var focusPoint: CGPoint?
    var showFocusIndicator = false
    var processingErrorMessage: String?
    var showProcessingError = false
    var enrichmentDegradedMessage: String?
    var showEnrichmentDegradedBanner = false
    var showTruncationBanner = false

    // MARK: - Review Queue Manager (extracted Phase 1A)
    let reviewQueueManager = ReviewQueueManager()

    // MARK: - Tab Navigation
    var requestedTab: Int?

    // MARK: - Scan Job Coordinator (extracted Phase 1B)
    let scanCoordinator: ScanJobCoordinator

    // MARK: - US-408: Rate Limit State
    let rateLimitState: RateLimitState = RateLimitState()
    var isRateLimited = false
    var rateLimitCountdown: Int = 0
    var queuedScansCount: Int = 0
    var countdownTimer: Task<Void, Never>?

    // MARK: - US-409: Offline Queue State
    var networkMonitor: NetworkMonitor = NetworkMonitor()
    let offlineQueueManager: OfflineQueueManager = OfflineQueueManager()
    var offlineQueuedCount: Int = 0

    // MARK: - Capture Throttle
    private var activeCaptureCount = 0
    private let maxConcurrentCaptures = 5

    // MARK: - US-410: Stream Concurrency Manager
    let streamManager: StreamManager = StreamManager()

    // MARK: - Vision Framework State (delegated to CameraVisionCoordinator)
    let visionCoordinator = CameraVisionCoordinator()

    var isVisionEnabled: Bool { visionCoordinator.isVisionEnabled }
    var detectedText: [TextRegion] { visionCoordinator.detectedText }
    var detectedISBN: String? { visionCoordinator.detectedISBN }
    var captureGuidance: CaptureGuidance { visionCoordinator.captureGuidance }
    var detectedObjects: [DetectedObject] { visionCoordinator.detectedObjects }

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

            // Wire Vision processing callback
            cameraManager.onVisionResult = { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }

                    let spineDetected = self.visionCoordinator.handle(result: result)
                    if spineDetected {
                        self.haptics.spineDetected()
                    }

                    // TODO 6.1: Adaptive throttling based on activity
                    // Adjust VisionService processing rate based on guidance
                    self.cameraManager.setProcessingRate(active: self.visionCoordinator.isActivelyScanning)
                }
            }

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

    func toggleVision() {
        visionCoordinator.setVisionEnabled(!isVisionEnabled)
        // Note: Vision is now always enabled in iOS 26, this is just for UI state
    }

    /// Configure rotation coordinator after preview layer is available
    /// Called from CameraPreviewView once preview layer exists
    func configureRotationCoordinator(previewLayer: AVCaptureVideoPreviewLayer) {
        cameraManager.configureRotation(previewLayer: previewLayer)
    }

    // MARK: - Image Capture
    func captureImage() {
        // US-408: Safety check - should not be called when rate limited (button is disabled)
        guard !isRateLimited else {
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

    func processCaptureWithImageData(itemId: UUID, imageData: Data, modelContext: ModelContext, preScannedISBN: String? = nil) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        var queueItem: ProcessingItem?
        var tempFileURL: URL?
        var jobId: String?
        var authToken: String?
        // Snapshot the Vision-detected ISBN at capture time (caller may pass explicit value, or we read current)
        let capturedISBN = preScannedISBN ?? detectedISBN

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
                var item = ProcessingItem(imageData: imageData, state: .offline, progressMessage: "Queued (offline)")
                item.preScannedISBN = capturedISBN
                withAnimation(.swissSpring) {
                    processingQueue.append(item)
                }

                // Queue scan in FileManager for persistent storage
                let queuedId = try await offlineQueueManager.queueScan(imageData: imageData, preScannedISBN: capturedISBN)
                e2eLogger.info("Scan queued with ID: \(queuedId)")

                // Update offline queue count
                let count = try await offlineQueueManager.getQueuedScanCount()
                offlineQueuedCount = count

                // Keep item in queue indefinitely until uploaded
                return
            }

            // Add to processing queue immediately with thumbnail (preprocessing state)
            queueItem = addToQueue(imageData: imageData, preScannedISBN: capturedISBN)

            guard let item = queueItem else { return }

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
            updateQueueItem(id: item.id, state: .analyzing, message: "Analyzing...")

            // Capture item ID and thumbnail for callbacks
            let capturedItemId = item.id
            let capturedThumbnailData = item.thumbnailData
            let reviewCountBefore = reviewQueueManager.pendingReviewBooks.count

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
                reviewCountBefore: reviewCountBefore,
                callbacks: callbacks,
                getReviewCount: { [weak self] in
                    self?.reviewQueueManager.pendingReviewBooks.count ?? 0
                }
            )

            // Check if task was cancelled during streaming
            if Task.isCancelled {
                await scanCoordinator.cleanup(jobId: uploadResult.jobId, authToken: authToken)
                if let tempFileURL { await scanCoordinator.cleanupTempFile(tempFileURL) }
                return
            }

            // Success path - mark as done (unless callbacks already handled error/retry)
            if let index = processingQueue.firstIndex(where: { $0.id == capturedItemId }),
               processingQueue[index].state == .analyzing {
                updateQueueItem(id: capturedItemId, state: .done, message: nil)
            }

            // Cleanup server resources (non-blocking); temp file deferred until review action
            await scanCoordinator.cleanup(jobId: uploadResult.jobId, authToken: authToken)

            // Auto-remove from queue after 5 seconds
            await removeQueueItemAfterDelay(id: capturedItemId, delay: 5.0)

        } catch is CancellationError {
            // Task was cancelled (e.g. user navigated away) — not a user-visible error
            e2eLogger.debug("processCaptureWithImageData: task cancelled")
            return
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
            withAnimation(.swissSpring) {
                processingQueue.removeAll { $0.id == item.id }
            }
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
            updateQueueItemError(id: item.id, errorMessage: error.localizedDescription)

            haptics.errorOccurred()

            if let jid = jobId {
                await scanCoordinator.cleanup(jobId: jid, authToken: authToken)
            }
            if let tempFileURL { await scanCoordinator.cleanupTempFile(tempFileURL) }

            await removeQueueItemAfterDelay(id: item.id, delay: 5.0)
        }
    }

    // MARK: - Processing Pipeline Helpers

    /// Preprocess raw image data and compress it for upload.
    /// Returns the processed image data and temp file URL.
    private func preprocessAndPrepareUpload(itemId: UUID, item: ProcessingItem, imageData: Data, startTime: CFAbsoluteTime) async throws -> (Data, URL) {
        // Step 1: Preprocess image (contrast, brightness, denoising, rotation)
        updateQueueItem(id: item.id, state: .preprocessing, message: "Preprocessing...")
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

        // Note: slot release is explicit at each exit point below (success and error).
        // A fire-and-forget Task in defer is not guaranteed to execute before the caller
        // resumes, so we release directly with await instead.
        do {
            updateQueueItemProgress(id: item.id, message: "Uploading...")

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
                self?.updateQueueItemProgress(id: itemId, message: message)
            },
            onBookResult: { [weak self] metadata, rawJSON, _, _ in
                self?.reviewQueueManager.handleBookResult(metadata: metadata, rawJSON: rawJSON, thumbnailData: capturedThumbnailData, preScannedISBN: capturedISBN, originalPhotoURL: originalPhotoURL, modelContext: modelContext)
            },
            onScanComplete: { [weak self] booksAdded, thumbnailData in
                self?.reviewQueueManager.showScanComplete(booksAdded: booksAdded, thumbnailData: thumbnailData)
            },
            onError: { [weak self] message in
                self?.updateQueueItemError(id: itemId, errorMessage: message)
                Task {
                    await self?.showProcessingErrorOverlay(message)
                }
                self?.haptics.errorOccurred()
            },
            onRetryableError: { [weak self] message in
                guard let self else { return }
                self.updateQueueItemProgress(id: itemId, message: "Retrying...")

                // Auto-retry once after 2 second delay
                if let originalImageData = item.originalImageData {
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.swissSpring) {
                            self.processingQueue.removeAll { $0.id == itemId }
                        }

                        let retryItemId = UUID()
                        let retryTask = Task {
                            await self.processCaptureWithImageData(itemId: retryItemId, imageData: originalImageData, modelContext: modelContext, preScannedISBN: capturedISBN)
                        }
                        await self.scanCoordinator.trackJob(id: retryItemId, task: retryTask)
                    }
                } else {
                    self.updateQueueItemError(id: itemId, errorMessage: message)
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
                self?.updateQueueItem(id: itemId, state: .error, message: "Canceled")
            },
            onQueueProgress: { [weak self] message in
                self?.updateQueueItemProgress(id: itemId, message: message)
            },
            onBookMetadataReceived: { [weak self] metadata in
                if let index = self?.processingQueue.firstIndex(where: { $0.id == itemId }) {
                    self?.processingQueue[index].bookMetadata = metadata
                }
            },
            onSegmented: { [weak self] preview in
                self?.updateQueueItemSegmented(id: itemId, preview: preview)
            },
            onBookProgress: { [weak self] current, total in
                self?.updateQueueItemBookProgress(id: itemId, current: current, total: total)
            },
            onResultsFetchFailed: { [weak self] url, fetchAuthToken, failedJobId in
                self?.updateQueueItemError(id: itemId, errorMessage: "Failed to fetch results. Check network and retry.")
                if let index = self?.processingQueue.firstIndex(where: { $0.id == itemId }) {
                    self?.processingQueue[index].retryContext = ResultsFetchRetryContext(
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
                self.showTruncationBanner = true
            }
        )
    }

    // MARK: - Queue Management
    private func addToQueue(imageData: Data, preScannedISBN: String? = nil) -> ProcessingItem {
        var item = ProcessingItem(imageData: imageData, state: .preprocessing)
        item.preScannedISBN = preScannedISBN
        withAnimation(.swissSpring) {
            processingQueue.append(item)
        }
        return item
    }

    private func updateQueueItemState(id: UUID, state: ProcessingItem.ProcessingState) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].state = state
            }
        }
    }

    private func updateQueueItemProgress(id: UUID, message: String?) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].progressMessage = message
            }
        }
    }

    private func updateQueueItem(id: UUID, state: ProcessingItem.ProcessingState, message: String?) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].state = state
                processingQueue[index].progressMessage = message

                // Release memory when transitioning to .done
                if state == .done {
                    processingQueue[index].segmentedPreview = nil
                }
            }
        }
    }

    private func updateQueueItemError(id: UUID, errorMessage: String) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].state = .error
                processingQueue[index].errorMessage = errorMessage
            }
        }
    }

    private func updateQueueItemSegmented(id: UUID, preview: SegmentedPreview) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].segmentedPreview = preview.imageData
                processingQueue[index].detectedBookCount = preview.totalBooks
            }
        }
    }

    private func updateQueueItemBookProgress(id: UUID, current: Int, total: Int) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].currentBookIndex = current
                processingQueue[index].progressMessage = "Processing book \(current)/\(total)"
            }
        }
    }

    private func updateQueueItemCleanupInfo(id: UUID, tempFileURL: URL, jobId: String) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            processingQueue[index].tempFileURL = tempFileURL
            processingQueue[index].jobId = jobId
        }
    }

    private func removeQueueItemAfterDelay(id: UUID, delay: TimeInterval) async {
        try? await Task.sleep(for: .seconds(delay))
        withAnimation(.swissSpring) {
            processingQueue.removeAll { $0.id == id }
        }
    }

    // MARK: - US-407: Retry Failed Item
    func retryFailedItem(_ item: ProcessingItem) {
        guard item.state == .error,
              let imageData = item.originalImageData else {
            e2eLogger.warning("Cannot retry: item not in error state or no image data")
            return
        }

        e2eLogger.info("Retrying failed item: \(item.id)")

        withAnimation(.swissSpring) {
            processingQueue.removeAll { $0.id == item.id }
        }

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
        countdownTimer?.cancel()

        rateLimitCountdown = await rateLimitState.getRemainingSeconds()
        isRateLimited = true

        countdownTimer = Task { @MainActor in
            while await rateLimitState.isRateLimited {
                rateLimitCountdown = await rateLimitState.getRemainingSeconds()
                queuedScansCount = await rateLimitState.queuedScanCount

                if rateLimitCountdown <= 0 {
                    await rateLimitState.clearRateLimit()
                    isRateLimited = false

                    let queuedScans = await rateLimitState.dequeueAllScans()
                    guard let ctx = modelContext else {
                        e2eLogger.error("ModelContext not injected — cannot process rate-limit queue")
                        break
                    }
                    for scan in queuedScans {
                        let itemId = UUID()
                        let task = Task {
                            await processCaptureWithImageData(itemId: itemId, imageData: scan.imageData, modelContext: ctx, preScannedISBN: scan.preScannedISBN)
                        }
                        await scanCoordinator.trackJob(id: itemId, task: task)
                    }

                    break
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - US-406: Stream Cancellation
    func cancelAllStreamingTasks() {
        let queueSnapshot = processingQueue
        Task {
            await scanCoordinator.cancelAllJobs(processingQueue: queueSnapshot)
        }

        // Remove in-progress items from queue with animation
        withAnimation(.swissSpring) {
            processingQueue.removeAll {
                $0.state == .uploading || $0.state == .analyzing
            }
        }
    }

    // MARK: - Error Display
    private func showProcessingErrorOverlay(_ message: String) async {
        processingErrorMessage = message
        withAnimation(.swissSpring) {
            showProcessingError = true
        }

        try? await Task.sleep(for: .seconds(5))
        withAnimation(.swissSpring) {
            showProcessingError = false
        }

        try? await Task.sleep(for: .milliseconds(200))
        processingErrorMessage = nil
    }

    private func showEnrichmentDegradedBanner(reason: String?) async {
        enrichmentDegradedMessage = "Some book details may be limited (enrichment service degraded)"
        if let reason = reason {
            enrichmentDegradedMessage = (enrichmentDegradedMessage ?? "") + ": \(reason)"
        }

        withAnimation(.swissSpring) {
            showEnrichmentDegradedBanner = true
        }

        // Auto-dismiss after 5 seconds
        try? await Task.sleep(for: .seconds(5))
        withAnimation(.swissSpring) {
            showEnrichmentDegradedBanner = false
        }

        try? await Task.sleep(for: .milliseconds(200))
        enrichmentDegradedMessage = nil
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

    // MARK: - US-409: Offline Queue Management
    func checkAndUploadQueuedScans() async {
        do {
            let count = try await offlineQueueManager.getQueuedScanCount()
            offlineQueuedCount = count

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
        do {
            let queuedScans = try await offlineQueueManager.getAllQueuedScans()

            guard !queuedScans.isEmpty else {
                return
            }

            e2eLogger.info("Uploading \(queuedScans.count) queued scans")

            withAnimation(.swissSpring) {
                processingQueue.removeAll { $0.state == .offline }
            }

            guard let ctx = modelContext else {
                e2eLogger.error("ModelContext not injected — cannot upload queued scans")
                return
            }

            await withTaskGroup(of: Result<Void, Error>.self) { group in
                for (metadata, imageData) in queuedScans {
                    let itemId = UUID()
                    let task = Task {
                        await processCaptureWithImageData(itemId: itemId, imageData: imageData, modelContext: ctx, preScannedISBN: metadata.preScannedISBN)
                    }
                    await scanCoordinator.trackJob(id: itemId, task: task)

                    group.addTask {
                        await task.value
                        do {
                            try await self.offlineQueueManager.removeQueuedScan(scanId: metadata.id)
                            return .success(())
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                // Collect partial failures — individual upload errors don't abort the group
                var failureCount = 0
                for await result in group {
                    if case .failure(let error) = result {
                        failureCount += 1
                        e2eLogger.warning("Offline upload removal failed: \(error.localizedDescription)")
                    }
                }
                if failureCount > 0 {
                    e2eLogger.warning("Some offline scan removals failed: \(failureCount) error(s)")
                }
            }

            let finalCount = try await offlineQueueManager.getQueuedScanCount()
            offlineQueuedCount = finalCount

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
        updateQueueItem(id: item.id, state: .analyzing, message: "Retrying...")

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
                updateQueueItem(id: item.id, state: .done, message: nil)
                await removeQueueItemAfterDelay(id: item.id, delay: 5.0)

            } catch {
                e2eLogger.error("Retry failed: \(error.localizedDescription)")
                updateQueueItemError(id: item.id, errorMessage: "Retry failed: \(error.localizedDescription)")
            }
        }
    }

}
