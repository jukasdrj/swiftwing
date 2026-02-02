import SwiftUI
import AVFoundation
import SwiftData

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

    // MARK: - US-405: Duplicate Detection State
    var duplicateBook: Book?
    var showDuplicateAlert = false
    var pendingBookMetadata: BookMetadata?
    var pendingRawJSON: String?

    // MARK: - Review Queue State
    var pendingReviewBooks: [PendingBookResult] = []
    var pendingBookBeingApproved: PendingBookResult?

    // MARK: - US-406: Active Streaming Tasks
    var activeStreamingTasks: [UUID: Task<Void, Never>] = [:]

    // NEW: Job ID to auth token mapping for cleanup calls
    private var jobAuthTokens: [String: String] = [:]

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
    var isVisionEnabled: Bool = true
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

    // MARK: - Initialization
    init() {}

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
                        print("🎯 CameraViewModel: Received \(objects.count) objects from Vision")
                        for (index, object) in objects.enumerated() {
                            print("   Object \(index+1): confidence=\(String(format: "%.2f", object.confidence)), uuid=\(object.observationUUID)")
                        }
                        self.detectedObjects = objects
                        // Generate guidance based on detected objects
                        self.captureGuidance = self.generateObjectGuidance(from: objects)

                    case .noContent:
                        self.detectedText = []
                        self.detectedObjects = []
                        self.captureGuidance = .noBookDetected
                    }

                    // TODO 6.1: Adaptive throttling based on activity
                    // Adjust VisionService processing rate based on guidance
                    let isActivelyScanning = (self.captureGuidance == .spineDetected)
                    self.cameraManager.frameProcessor.visionService.setProcessingRate(active: isActivelyScanning)
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
        isVisionEnabled.toggle()
        cameraManager.setVisionEnabled(isVisionEnabled)
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
        activeStreamingTasks[itemId] = task
    }

    // MARK: - Processing Pipeline
    private func processCapture(itemId: UUID) async {
        do {
            // Capture photo from camera (must be on main actor)
            let imageData = try await cameraManager.capturePhoto()
            print("📸 Image captured (\(imageData.count) bytes)")

            // Process with injected modelContext
            guard let modelContext = modelContext else {
                fatalError("ModelContext not injected into ViewModel")
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
        let talariaService = TalariaService()

        // Cleanup task tracker when done
        defer {
            activeStreamingTasks.removeValue(forKey: itemId)
        }

        do {
            print("📸 Processing image data (\(imageData.count) bytes)")

            // US-409: Check if offline - if so, queue for later upload
            if !networkMonitor.isConnected {
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
            let fileURL = try await Self.processImage(preprocessResult.processedData)
            tempFileURL = fileURL

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ Image processed in \(String(format: "%.3f", duration))s (target: < 0.5s)")

            if duration >= 0.5 {
                print("⚠️ WARNING: Image processing exceeded 0.5s target!")
            }

            // Read processed image data for upload
            let uploadData = try Data(contentsOf: fileURL)

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

            // Generate consistent device ID for this scan operation
            let scanDeviceId = UUID().uuidString

            let (uploadedJobId, streamUrl, uploadedAuthToken) = try await talariaService.uploadScan(image: uploadData, deviceId: scanDeviceId)
            jobId = uploadedJobId
            authToken = uploadedAuthToken

            // NEW: Store auth token for disconnect cleanup
            if let uploadedAuthToken = uploadedAuthToken {
                jobAuthTokens[uploadedJobId] = uploadedAuthToken
            }

            // Performance logging: upload completed
            let uploadDuration = (CFAbsoluteTimeGetCurrent() - uploadStart) * 1000 // Convert to ms
            print("📤 Upload took \(Int(uploadDuration))ms, jobId: \(uploadedJobId)")

            // Store temp file URL and job ID for cleanup (US-406)
            updateQueueItemCleanupInfo(id: item.id, tempFileURL: fileURL, jobId: uploadedJobId)

            // Switch to analyzing state
            updateQueueItem(id: item.id, state: .analyzing, message: "Analyzing...")

            // Performance logging: start SSE stream timer
            let streamStart = CFAbsoluteTimeGetCurrent()

            // Stream SSE events from Talaria (use same deviceId as upload)
            let eventStream = talariaService.streamEvents(streamUrl: streamUrl, deviceId: scanDeviceId, authToken: authToken)

            for try await event in eventStream {
                // Check for task cancellation (app backgrounding)
                if Task.isCancelled {
                    print("🛑 SSE stream cancelled (app backgrounding)")
                    await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService, authToken: authToken)
                    return
                }

                switch event {
                case .progress(let message):
                    print("📡 SSE progress: \(message)")
                    updateQueueItemProgress(id: item.id, message: message)

                case .result(let bookMetadata):
                    print("📚 Book identified: \(bookMetadata.title) by \(bookMetadata.author)")

                    // Encode metadata to raw JSON string for debugging
                    let rawJSON: String?
                    if let jsonData = try? JSONEncoder().encode(bookMetadata),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        rawJSON = jsonString
                    } else {
                        rawJSON = nil
                    }

                    handleBookResult(metadata: bookMetadata, rawJSON: rawJSON, modelContext: modelContext)

                case .complete(let resultsUrl):
                    let streamDuration = CFAbsoluteTimeGetCurrent() - streamStart
                    print("✅ SSE stream lasted \(String(format: "%.1f", streamDuration))s")

                    // Fetch actual book results from URL
                    if let url = resultsUrl,
                       let jid = jobId,
                       let authToken = jobAuthTokens[jid] {
                        print("📥 Fetching book results from: \(url)")

                        do {
                            let books = try await talariaService.fetchResults(
                                resultsUrl: url,
                                authToken: authToken
                            )

                            print("📚 Received \(books.count) books from results API")

                            // Process each book
                            for book in books {
                                // Encode to raw JSON for debugging
                                let rawJSON: String?
                                if let jsonData = try? JSONEncoder().encode(book),
                                   let jsonString = String(data: jsonData, encoding: .utf8) {
                                    rawJSON = jsonString
                                } else {
                                    rawJSON = nil
                                }

                                handleBookResult(metadata: book, rawJSON: rawJSON, modelContext: modelContext)
                            }

                            // Success - mark as done
                            updateQueueItem(id: item.id, state: .done, message: nil)

                        } catch {
                            print("❌ Failed to fetch results: \(error)")
                            // Set error state so user knows something went wrong
                            updateQueueItemError(id: item.id, errorMessage: "Failed to retrieve results")
                        }
                    } else {
                        // Missing resultsUrl - treat as error (shouldn't happen in normal flow)
                        print("⚠️ No resultsUrl in completion event - marking as error")
                        updateQueueItemError(id: item.id, errorMessage: "No results available")
                    }

                    // Cleanup resources (non-blocking)
                    await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService, authToken: authToken)

                    // Remove auth token (job is done)
                    if let jid = jobId {
                        jobAuthTokens.removeValue(forKey: jid)
                    }

                    // Auto-remove from queue after 5 seconds
                    await removeQueueItemAfterDelay(id: item.id, delay: 5.0)

                case .error(let errorMessage):
                    print("❌ SSE error (jobId: \(jobId ?? "unknown")): \(errorMessage)")

                    updateQueueItemError(id: item.id, errorMessage: errorMessage)
                    await showProcessingErrorOverlay(errorMessage)

                    // Trigger error haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                    impactFeedback.impactOccurred()

                    await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService, authToken: authToken)

                    // Remove auth token (job is done)
                    if let jid = jobId {
                        jobAuthTokens.removeValue(forKey: jid)
                    }

                case .canceled:
                    print("⚠️ SSE job canceled (jobId: \(jobId ?? "unknown"))")

                    updateQueueItem(id: item.id, state: .error, message: "Canceled")

                    await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService, authToken: authToken)

                    // Remove auth token (job is done)
                    if let jid = jobId {
                        jobAuthTokens.removeValue(forKey: jid)
                    }

                    await removeQueueItemAfterDelay(id: item.id, delay: 3.0)

                // NEW: Progressive results event handling
                case .segmented(let preview):
                    print("📸 Segmented preview: \(preview.totalBooks) books detected (\(preview.imageData.count) bytes)")
                    updateQueueItemSegmented(id: item.id, preview: preview)

                case .bookProgress(let progress):
                    print("📊 Book progress: \(progress.current)/\(progress.total)")
                    updateQueueItemBookProgress(id: item.id, current: progress.current, total: progress.total)
                }
            }

        } catch {
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

                await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService, authToken: authToken)

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
            fatalError("ModelContext not injected into ViewModel")
        }

        let itemId = UUID()
        let task = Task {
            await processCaptureWithImageData(itemId: itemId, imageData: imageData, modelContext: ctx)
        }
        activeStreamingTasks[itemId] = task
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
                        fatalError("ModelContext not injected into ViewModel")
                    }
                    for imageData in queuedScans {
                        let itemId = UUID()
                        let task = Task {
                            await processCaptureWithImageData(itemId: itemId, imageData: imageData, modelContext: ctx)
                        }
                        activeStreamingTasks[itemId] = task
                    }

                    break
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // MARK: - US-406: Stream Cancellation
    func cancelAllStreamingTasks() {
        let taskCount = activeStreamingTasks.count
        guard taskCount > 0 else { return }

        print("Cancelling \(taskCount) active SSE streams (navigation/backgrounding)")

        // Cancel all Swift Task instances (triggers Task.isCancelled in stream loops)
        for (_, task) in activeStreamingTasks {
            task.cancel()
        }
        activeStreamingTasks.removeAll()

        // Collect all in-progress job IDs that need backend cleanup
        let activeJobIds = processingQueue
            .filter { $0.state == .uploading || $0.state == .analyzing }
            .compactMap { $0.jobId }

        // Fire-and-forget cleanup calls to backend with stored auth tokens
        for activeJobId in activeJobIds {
            let storedAuthToken = jobAuthTokens[activeJobId]
            Task {
                let service = TalariaService()
                do {
                    try await service.cleanup(jobId: activeJobId, authToken: storedAuthToken)
                    print("Backend cleanup sent for disconnected job: \(activeJobId)")
                } catch {
                    print("Backend cleanup failed for \(activeJobId): \(error.localizedDescription)")
                }
            }
        }

        // Clear all auth tokens (all jobs are being abandoned)
        jobAuthTokens.removeAll()

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
                fatalError("ModelContext not injected into ViewModel")
            }

            for (metadata, imageData) in queuedScans {
                let itemId = UUID()
                let task = Task {
                    await processCaptureWithImageData(itemId: itemId, imageData: imageData, modelContext: ctx)
                }
                activeStreamingTasks[itemId] = task

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

    // MARK: - US-405: Book Result Handling
    func handleBookResult(metadata: BookMetadata, rawJSON: String?, modelContext: ModelContext) {
        print("🔍 DEBUG: handleBookResult called for: \(metadata.title)")

        // Route ALL results to review queue (no auto-add)
        let pendingBook = PendingBookResult(
            metadata: metadata,
            rawJSON: rawJSON,
            thumbnailData: nil
        )

        print("🔍 DEBUG: PendingBookResult created successfully, id: \(pendingBook.id)")

        withAnimation(.swissSpring) {
            pendingReviewBooks.append(pendingBook)
        }

        print("🔍 DEBUG: Appended to pendingReviewBooks, new count: \(pendingReviewBooks.count)")

        print("📋 Book added to review queue: \(metadata.title) (pending: \(pendingReviewBooks.count))")

        // Haptic feedback for new review item
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // MARK: - Review Queue Actions
    func approveBook(_ pendingBook: PendingBookResult, modelContext: ModelContext) {
        let isbn = pendingBook.metadata.isbn ?? "UNKNOWN-\(UUID().uuidString)"

        // Duplicate detection at approve time
        do {
            if let duplicate = try DuplicateDetection.findDuplicate(isbn: isbn, in: modelContext) {
                pendingBookBeingApproved = pendingBook
                pendingBookMetadata = pendingBook.metadata
                pendingRawJSON = pendingBook.rawJSON
                duplicateBook = duplicate
                withAnimation(.swissSpring) {
                    showDuplicateAlert = true
                }
                return
            }
        } catch {
            // Proceed with add on detection failure
        }

        // Use resolved values (prefers user edits over AI results)
        addBookToLibrary(
            title: pendingBook.resolvedTitle,
            author: pendingBook.resolvedAuthor,
            metadata: pendingBook.metadata,
            rawJSON: pendingBook.rawJSON,
            modelContext: modelContext
        )

        withAnimation(.swissSpring) {
            pendingReviewBooks.removeAll { $0.id == pendingBook.id }
        }

        print("✅ Book approved and added to library: \(pendingBook.resolvedTitle)")
    }

    func rejectBook(_ pendingBook: PendingBookResult) {
        withAnimation(.swissSpring) {
            pendingReviewBooks.removeAll { $0.id == pendingBook.id }
        }

        print("❌ Book rejected from review queue: \(pendingBook.metadata.title)")
    }

    func approveAllBooks(modelContext: ModelContext) {
        let count = pendingReviewBooks.count
        for book in pendingReviewBooks {
            addBookToLibrary(
                title: book.resolvedTitle,
                author: book.resolvedAuthor,
                metadata: book.metadata,
                rawJSON: book.rawJSON,
                modelContext: modelContext
            )
        }

        withAnimation(.swissSpring) {
            pendingReviewBooks.removeAll()
        }

        print("✅ All \(count) books approved and added to library")
    }

    func addBookToLibrary(title: String? = nil, author: String? = nil, metadata: BookMetadata, rawJSON: String?, modelContext: ModelContext) {
        let publishedDate: Date?
        if let dateString = metadata.publishedDate {
            let formatter = ISO8601DateFormatter()
            publishedDate = formatter.date(from: dateString)
        } else {
            publishedDate = nil
        }

        let newBook = Book(
            title: title ?? metadata.title,        // Use override if provided
            author: author ?? metadata.author,      // Use override if provided
            isbn: metadata.isbn ?? "UNKNOWN-\(UUID().uuidString)",
            coverUrl: metadata.coverUrl,
            format: metadata.format,
            publisher: metadata.publisher,
            publishedDate: publishedDate,
            pageCount: metadata.pageCount,
            spineConfidence: metadata.confidence,
            addedDate: Date(),
            rawJSON: rawJSON
        )

        modelContext.insert(newBook)

        do {
            try modelContext.save()
            print("✅ Book added to library: \(title ?? metadata.title)")

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

        } catch {
            print("❌ Failed to save book: \(error)")
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

    func updatePendingBookEdits(id: UUID, title: String?, author: String?) {
        if let index = pendingReviewBooks.firstIndex(where: { $0.id == id }) {
            pendingReviewBooks[index].editedTitle = title
            pendingReviewBooks[index].editedAuthor = author
        }
    }

    func dismissDuplicateAlert() {
        withAnimation(.swissSpring) {
            showDuplicateAlert = false
            duplicateBook = nil
            pendingBookMetadata = nil
            pendingRawJSON = nil
            pendingBookBeingApproved = nil
        }
    }

    func addDuplicateAnyway(modelContext: ModelContext) {
        withAnimation(.swissSpring) {
            showDuplicateAlert = false
            if let metadata = pendingBookMetadata {
                addBookToLibrary(metadata: metadata, rawJSON: pendingRawJSON, modelContext: modelContext)
            }
            // Remove from review queue if it was an approve-time duplicate
            if let pending = pendingBookBeingApproved {
                pendingReviewBooks.removeAll { $0.id == pending.id }
            }
            duplicateBook = nil
            pendingBookMetadata = nil
            pendingRawJSON = nil
            pendingBookBeingApproved = nil
        }
    }

    // MARK: - Resource Cleanup
    private func performCleanup(jobId: String?, tempFileURL: URL?, talariaService: TalariaService, authToken: String? = nil) async {
        if let jobId = jobId {
            do {
                try await talariaService.cleanup(jobId: jobId, authToken: authToken)
                print("🗑️ Server cleanup successful for job: \(jobId)")
            } catch {
                print("⚠️ Server cleanup failed for job \(jobId): \(error.localizedDescription)")
            }
        }

        if let tempFileURL = tempFileURL {
            do {
                try FileManager.default.removeItem(at: tempFileURL)
                print("🗑️ Local temp file cleanup successful: \(tempFileURL.lastPathComponent)")
            } catch CocoaError.fileNoSuchFile {
                print("ℹ️ Temp file already deleted: \(tempFileURL.lastPathComponent)")
            } catch {
                print("⚠️ Local temp file cleanup failed for \(tempFileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Image Processing
    static func processImage(_ imageData: Data) async throws -> URL {
        guard let image = UIImage(data: imageData) else {
            throw ImageProcessingError.invalidImageData
        }

        let resized = resizeImage(image, maxDimension: 1920)

        guard let jpegData = resized.jpegData(compressionQuality: 0.85) else {
            throw ImageProcessingError.compressionFailed
        }

        let filename = "\(UUID().uuidString).jpg"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        try jpegData.write(to: fileURL)

        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1800)) // 30 minutes
            do {
                try FileManager.default.removeItem(at: fileURL)
                print("🗑️ Fallback cleanup for temp file: \(filename)")
            } catch CocoaError.fileNoSuchFile {
            } catch {
                print("⚠️ Fallback cleanup failed for \(filename): \(error.localizedDescription)")
            }
        }

        return fileURL
    }

    static func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height

        let newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: min(size.width, maxDimension), height: min(size.width, maxDimension) / aspectRatio)
        } else {
            newSize = CGSize(width: min(size.height, maxDimension) * aspectRatio, height: min(size.height, maxDimension))
        }

        if newSize.width >= size.width && newSize.height >= size.height {
            return image
        }

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
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
