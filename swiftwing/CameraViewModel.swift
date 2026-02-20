import os
import SwiftUI
import AVFoundation
import SwiftData

private let e2eLogger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "e2e-vm")

#if canImport(UIKit)
import UIKit
#endif

#if DEBUG
/// File-based debug logger for integration test diagnosis
private func integrationLog(_ msg: String) {
    guard ProcessInfo.processInfo.arguments.contains("INJECT_TEST_IMAGE") else { return }
    let logFile = URL(fileURLWithPath: "/tmp/swiftwing-integration-test.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: logFile.path) {
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    } else {
        try? data.write(to: logFile)
    }
}
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

    // MARK: - US-410: Stream Concurrency Manager
    let streamManager: StreamManager = StreamManager()

    // MARK: - Vision Framework State
    var isVisionEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isVisionEnabled") != false  // Default true if not set
    }
    var detectedText: [TextRegion] = []
    var detectedISBN: String? = nil
    var captureGuidance: CaptureGuidance = .noBookDetected
    var detectedObjects: [DetectedObject] = []

    // MARK: - Camera Interruption State
    var isInterrupted: Bool {
        cameraManager.isInterrupted
    }

    // MARK: - Haptic Feedback
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)

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

        // Show loading spinner only if setup takes > 200ms
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            if cameraManager.captureSession == nil {
                isLoading = true
            }
        }

        do {
            // Configure session (must be on main thread per AVFoundation docs)
            try cameraManager.setupSession()

            // Prepare haptic generator for faster response
            hapticGenerator.prepare()

            // Wire Vision processing callback
            cameraManager.onVisionResult = { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }

                    switch result {
                    case .textRegions(let regions):
                        self.detectedText = regions
                        self.detectedObjects = []
                        // Generate guidance based on detected text regions
                        self.captureGuidance = self.generateGuidance(from: regions)

                    case .barcode(let barcodeResult):
                        self.detectedObjects = []
                        if barcodeResult.isValidISBN {
                            self.detectedISBN = barcodeResult.isbn
                            self.captureGuidance = .spineDetected
                            // Haptic feedback when spine detected
                            self.hapticGenerator.impactOccurred()
                        }

                    case .objects(let objects):
                        self.detectedObjects = objects
                        // Generate guidance based on detected objects
                        self.captureGuidance = self.generateObjectGuidance(from: objects)

                    case .noContent:
                        // Throttled frames return .noContent - don't clear objects, keep last detection
                        // Objects will persist until next Vision result arrives
                        break
                    }

                    // TODO 6.1: Adaptive throttling based on activity
                    // Adjust VisionService processing rate based on guidance
                    let isActivelyScanning = (self.captureGuidance == .spineDetected)
                    self.cameraManager.setProcessingRate(active: isActivelyScanning)
                }
            }

            // Start session on background thread (non-blocking)
            cameraManager.startSession()

            // Update UI
            isLoading = false

            // Log total cold start time
            let totalDuration = CFAbsoluteTimeGetCurrent() - coldStartTime
            print("📹 Camera cold start: \(String(format: "%.3f", totalDuration))s (target: < 0.5s)")

            if totalDuration >= 0.5 {
                print("⚠️ WARNING: Camera cold start exceeded 0.5s target!")
            }

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            print("❌ Camera setup failed: \(error)")
        }
    }

    func stopCamera() {
        cameraManager.stopSession()
    }

    func toggleVision() {
        let newValue = !isVisionEnabled
        UserDefaults.standard.set(newValue, forKey: "isVisionEnabled")
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
            print("⚠️ Capture blocked: rate limited")
            return
        }

        // Show flash immediately (100ms animation)
        withAnimation(.easeOut(duration: 0.1)) {
            showFlash = true
        }

        // Hide flash after 100ms
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            withAnimation(.easeOut(duration: 0.1)) {
                showFlash = false
            }
        }

        // Fire and forget - process capture in parallel (non-blocking)
        let itemId = UUID()
        let task = Task {
            await processCapture(itemId: itemId)
        }
        Task { await scanCoordinator.trackJob(id: itemId, task: task) }
    }

    // MARK: - Processing Pipeline
    private func processCapture(itemId: UUID) async {
        do {
            // Capture photo from camera (must be on main actor)
            let imageData = try await cameraManager.capturePhoto()
            print("📸 Image captured (\(imageData.count) bytes)")

            // Process with injected modelContext
            guard let modelContext = modelContext else {
                print("❌ ModelContext not injected — cannot process capture")
                await showProcessingErrorOverlay("Internal error: storage unavailable. Please restart the app.")
                return
            }

            await processCaptureWithImageData(itemId: itemId, imageData: imageData, modelContext: modelContext)
        } catch {
            print("❌ Camera capture failed: \(error)")
            await showProcessingErrorOverlay(error.localizedDescription)
        }
    }

    func processCaptureWithImageData(itemId: UUID, imageData: Data, modelContext: ModelContext) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        var queueItem: ProcessingItem?
        var tempFileURL: URL?
        var jobId: String?
        var authToken: String?

        // Cleanup task tracker when done
        defer {
            Task { await scanCoordinator.removeJob(id: itemId) }
        }

        do {
            e2eLogger.info("📸 Processing image data (\(imageData.count) bytes)")
            print("📸 Processing image data (\(imageData.count) bytes)")

            // US-409: Check if offline - if so, queue for later upload
            e2eLogger.info("🌐 Network check: isConnected=\(self.networkMonitor.isConnected)")
            if !networkMonitor.isConnected {
                e2eLogger.warning("📴 Offline mode - queueing scan for later upload")
                print("📴 Offline mode - queueing scan for later upload")

                // Add to processing queue with offline state
                var item = ProcessingItem(imageData: imageData, state: .offline, progressMessage: "Queued (offline)")
                item.preScannedISBN = detectedISBN  // TODO 4.4: Pass Vision-detected ISBN
                withAnimation(.swissSpring) {
                    processingQueue.append(item)
                }

                // Queue scan in FileManager for persistent storage
                let queuedId = try await offlineQueueManager.queueScan(imageData: imageData)
                print("💾 Scan queued with ID: \(queuedId)")

                // Update offline queue count
                let count = try await offlineQueueManager.getQueuedScanCount()
                offlineQueuedCount = count

                // Keep item in queue indefinitely until uploaded
                return
            }

            // Add to processing queue immediately with thumbnail (preprocessing state)
            queueItem = addToQueue(imageData: imageData)

            guard let item = queueItem else { return }

            // Step 1: Preprocess image (contrast, brightness, denoising, rotation)
            updateQueueItem(id: item.id, state: .preprocessing, message: "Preprocessing...")
            let preprocessResult = await imagePreprocessor.preprocess(imageData)
            print("✨ Preprocessing: \(preprocessResult.processingTimeMs)ms, rotated: \(preprocessResult.wasRotated), brightness adj: \(preprocessResult.brightnessAdjustment)")

            // Step 2: Process (resize + compress) the preprocessed image
            let fileURL = try await imagePreprocessor.processImageForUpload(preprocessResult.processedData)
            tempFileURL = fileURL

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ Image processed in \(String(format: "%.3f", duration))s (target: < 0.5s)")

            if duration >= 0.5 {
                print("⚠️ WARNING: Image processing exceeded 0.5s target!")
            }

            // Read processed image data for upload
            let uploadData = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: fileURL)
            }.value

            // US-410: Performance optimization - limit concurrent SSE streams to 5
            await streamManager.acquireStreamSlot(scanId: itemId)

            // Ensure we release the stream slot when done (even on error)
            defer {
                Task {
                    await streamManager.releaseStreamSlot(scanId: itemId)
                }
            }

            // Update progress: uploading
            updateQueueItemProgress(id: item.id, message: "Uploading...")

            // Performance logging: start upload timer
            let uploadStart = CFAbsoluteTimeGetCurrent()

            // Upload via coordinator
            let uploadResult = try await scanCoordinator.uploadScan(imageData: uploadData, deviceId: self.deviceId)
            jobId = uploadResult.jobId
            authToken = uploadResult.authToken

            // Performance logging: upload completed
            let uploadDuration = (CFAbsoluteTimeGetCurrent() - uploadStart) * 1000 // Convert to ms
            print("📤 Upload took \(Int(uploadDuration))ms, jobId: \(uploadResult.jobId)")

            // Store temp file URL and job ID for cleanup (US-406)
            updateQueueItemCleanupInfo(id: item.id, tempFileURL: fileURL, jobId: uploadResult.jobId)

            // Switch to analyzing state
            updateQueueItem(id: item.id, state: .analyzing, message: "Analyzing...")

            // Capture item ID and thumbnail for callbacks
            let capturedItemId = item.id
            let capturedThumbnailData = item.thumbnailData
            let reviewCountBefore = reviewQueueManager.pendingReviewBooks.count

            // Build callbacks for the coordinator
            let callbacks = ScanJobCallbacks(
                onProgress: { [weak self] message in
                    self?.updateQueueItemProgress(id: capturedItemId, message: message)
                },
                onBookResult: { [weak self] metadata, rawJSON in
                    self?.reviewQueueManager.handleBookResult(metadata: metadata, rawJSON: rawJSON, thumbnailData: capturedThumbnailData, modelContext: modelContext)
                },
                onScanComplete: { [weak self] booksAdded, thumbnailData in
                    self?.reviewQueueManager.showScanComplete(booksAdded: booksAdded, thumbnailData: thumbnailData)
                },
                onError: { [weak self] message in
                    self?.updateQueueItemError(id: capturedItemId, errorMessage: message)
                    Task {
                        await self?.showProcessingErrorOverlay(message)
                    }
                    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                    impactFeedback.impactOccurred()
                },
                onRetryableError: { [weak self] message in
                    guard let self else { return }
                    self.updateQueueItemProgress(id: capturedItemId, message: "Retrying...")

                    // Auto-retry once after 2 second delay
                    if let originalImageData = item.originalImageData {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            withAnimation(.swissSpring) {
                                self.processingQueue.removeAll { $0.id == capturedItemId }
                            }

                            let retryItemId = UUID()
                            let retryTask = Task {
                                await self.processCaptureWithImageData(itemId: retryItemId, imageData: originalImageData, modelContext: modelContext)
                            }
                            await self.scanCoordinator.trackJob(id: retryItemId, task: retryTask)
                        }
                    } else {
                        self.updateQueueItemError(id: capturedItemId, errorMessage: message)
                        Task {
                            await self.showProcessingErrorOverlay(message)
                        }
                        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                        impactFeedback.impactOccurred()
                    }
                },
                onEnrichmentDegraded: { [weak self] reason in
                    Task {
                        await self?.showEnrichmentDegradedBanner(reason: reason)
                    }
                },
                onCanceled: { [weak self] in
                    self?.updateQueueItem(id: capturedItemId, state: .error, message: "Canceled")
                },
                onQueueProgress: { [weak self] message in
                    self?.updateQueueItemProgress(id: capturedItemId, message: message)
                },
                onBookMetadataReceived: { [weak self] metadata in
                    if let index = self?.processingQueue.firstIndex(where: { $0.id == capturedItemId }) {
                        self?.processingQueue[index].bookMetadata = metadata
                    }
                },
                onSegmented: { [weak self] preview in
                    self?.updateQueueItemSegmented(id: capturedItemId, preview: preview)
                },
                onBookProgress: { [weak self] current, total in
                    self?.updateQueueItemBookProgress(id: capturedItemId, current: current, total: total)
                },
                onResultsFetchFailed: { [weak self] url, fetchAuthToken, failedJobId in
                    self?.updateQueueItemError(id: capturedItemId, errorMessage: "Failed to fetch results. Check network and retry.")
                    if let index = self?.processingQueue.firstIndex(where: { $0.id == capturedItemId }) {
                        self?.processingQueue[index].retryContext = ResultsFetchRetryContext(
                            resultsUrl: url,
                            authToken: fetchAuthToken,
                            jobId: failedJobId
                        )
                    }
                    print("💡 Item kept in queue for manual retry")
                }
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

            // Cleanup resources (non-blocking)
            await scanCoordinator.cleanup(jobId: uploadResult.jobId, authToken: authToken)
            if let tempFileURL { await scanCoordinator.cleanupTempFile(tempFileURL) }

            // Auto-remove from queue after 5 seconds
            await removeQueueItemAfterDelay(id: capturedItemId, delay: 5.0)

        } catch {
            e2eLogger.error("❌ processCaptureWithImageData error: \(error.localizedDescription)")
            #if DEBUG
            integrationLog("ERROR: processCaptureWithImageData catch: \(error) - \(error.localizedDescription)")
            #endif
            // US-408: Check if this is a rate limit error
            if let networkError = error as? NetworkError,
               case .rateLimited(let retryAfter) = networkError {
                print("⏰ Rate limited: retry after \(retryAfter ?? 0)s")

                await rateLimitState.queueScan(imageData)

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

                return
            }

            // Other errors:
            print("❌ Image processing/upload failed: \(error.localizedDescription)")

            await showProcessingErrorOverlay(error.localizedDescription)

            if let item = queueItem {
                updateQueueItemError(id: item.id, errorMessage: error.localizedDescription)

                let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                impactFeedback.impactOccurred()

                if let jid = jobId {
                    await scanCoordinator.cleanup(jobId: jid, authToken: authToken)
                }
                if let tempFileURL { await scanCoordinator.cleanupTempFile(tempFileURL) }

                await removeQueueItemAfterDelay(id: item.id, delay: 5.0)
            }
        }
    }

    // MARK: - Queue Management
    private func addToQueue(imageData: Data) -> ProcessingItem {
        var item = ProcessingItem(imageData: imageData, state: .preprocessing)
        item.preScannedISBN = detectedISBN  // TODO 4.4: Pass Vision-detected ISBN
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
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        withAnimation(.swissSpring) {
            processingQueue.removeAll { $0.id == id }
        }
    }

    // MARK: - US-407: Retry Failed Item
    func retryFailedItem(_ item: ProcessingItem) {
        guard item.state == .error,
              let imageData = item.originalImageData else {
            print("⚠️ Cannot retry: item not in error state or no image data")
            return
        }

        print("🔄 Retrying failed item: \(item.id)")

        withAnimation(.swissSpring) {
            processingQueue.removeAll { $0.id == item.id }
        }

        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        guard let ctx = modelContext else {
            print("❌ ModelContext not injected — cannot retry failed item")
            return
        }

        let itemId = UUID()
        let task = Task {
            await processCaptureWithImageData(itemId: itemId, imageData: imageData, modelContext: ctx)
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
                        print("❌ ModelContext not injected — cannot process rate-limit queue")
                        break
                    }
                    for imageData in queuedScans {
                        let itemId = UUID()
                        let task = Task {
                            await processCaptureWithImageData(itemId: itemId, imageData: imageData, modelContext: ctx)
                        }
                        await scanCoordinator.trackJob(id: itemId, task: task)
                    }

                    break
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
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

        try? await Task.sleep(nanoseconds: 5_000_000_000)
        withAnimation(.swissSpring) {
            showProcessingError = false
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
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
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        withAnimation(.swissSpring) {
            showEnrichmentDegradedBanner = false
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
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
            try? await Task.sleep(nanoseconds: 1_000_000_000)
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
                print("📤 Found \(count) queued scans - uploading now")
                await uploadQueuedScans()
            } else if count > 0 {
                print("📴 Found \(count) queued scans - waiting for network")
            }
        } catch {
            print("⚠️ Failed to check queued scans: \(error)")
        }
    }

    func uploadQueuedScans() async {
        do {
            let queuedScans = try await offlineQueueManager.getAllQueuedScans()

            guard !queuedScans.isEmpty else {
                return
            }

            print("📤 Uploading \(queuedScans.count) queued scans")

            withAnimation(.swissSpring) {
                processingQueue.removeAll { $0.state == .offline }
            }

            guard let ctx = modelContext else {
                print("❌ ModelContext not injected — cannot upload queued scans")
                return
            }

            for (metadata, imageData) in queuedScans {
                let itemId = UUID()
                let task = Task {
                    await processCaptureWithImageData(itemId: itemId, imageData: imageData, modelContext: ctx)
                }
                await scanCoordinator.trackJob(id: itemId, task: task)

                await task.value

                try? await offlineQueueManager.removeQueuedScan(scanId: metadata.id)

                let count = try await offlineQueueManager.getQueuedScanCount()
                offlineQueuedCount = count
            }

            print("✅ All queued scans uploaded")
        } catch {
            print("❌ Failed to upload queued scans: \(error)")
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
            print("⚠️ No retry context available")
            return
        }

        print("🔄 Retrying results fetch for job: \(context.jobId)")

        // Reset state to analyzing
        updateQueueItem(id: item.id, state: .analyzing, message: "Retrying...")

        Task {
            do {
                let books = try await scanCoordinator.fetchResults(
                    resultsUrl: context.resultsUrl,
                    authToken: context.authToken
                )

                print("📚 Retry successful: Received \(books.count) books")

                guard let ctx = modelContext else {
                    print("❌ ModelContext not available")
                    return
                }

                // Process all books
                for book in books {
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
                print("❌ Retry failed: \(error)")
                updateQueueItemError(id: item.id, errorMessage: "Retry failed: \(error.localizedDescription)")
            }
        }
    }

    /// Generate guidance based on detected rectangle objects
    private func generateObjectGuidance(from objects: [DetectedObject]) -> CaptureGuidance {
        let highConfidenceObjects = objects.filter { $0.confidence > 0.85 }
        if !highConfidenceObjects.isEmpty {
            return .spineDetected
        } else if !objects.isEmpty {
            return .moveCloser
        } else {
            return .noBookDetected
        }
    }

    // MARK: - Vision Guidance Generation
    private func generateGuidance(from regions: [TextRegion]) -> CaptureGuidance {
        // Simple heuristic: if we have text regions with high confidence, spine is detected
        let highConfidenceRegions = regions.filter { $0.confidence > 0.7 }

        if highConfidenceRegions.count >= 3 {
            return .spineDetected
        } else if highConfidenceRegions.count > 0 {
            return .moveCloser
        } else {
            return .noBookDetected
        }
    }
}
