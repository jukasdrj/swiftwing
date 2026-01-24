import SwiftUI
import AVFoundation
import UIKit
import SwiftData

/// Main camera view with zero-lag preview
/// Performance target: < 0.5s cold start to live feed
struct CameraView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var cameraManager = CameraManager()
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var coldStartTime: CFAbsoluteTime = 0
    @State private var showFlash = false
    @State private var processingQueue: [ProcessingItem] = []
    @State private var focusPoint: CGPoint?
    @State private var showFocusIndicator = false
    @State private var processingErrorMessage: String?
    @State private var showProcessingError = false

    // US-405: Duplicate detection state with full metadata
    @State private var duplicateBook: Book?
    @State private var showDuplicateAlert = false
    @State private var pendingBookMetadata: BookMetadata?
    @State private var pendingRawJSON: String?

    // US-406: Track active SSE streaming tasks for cancellation on app backgrounding
    @State private var activeStreamingTasks: [UUID: Task<Void, Never>] = [:]

    // US-408: Rate limit state
    private let rateLimitState = RateLimitState()
    @State private var isRateLimited = false
    @State private var rateLimitCountdown: Int = 0
    @State private var queuedScansCount: Int = 0
    @State private var countdownTimer: Task<Void, Never>?

    // US-409: Offline queue state
    @State private var networkMonitor = NetworkMonitor()
    private let offlineQueueManager = OfflineQueueManager()
    @State private var offlineQueuedCount: Int = 0

    // US-410: Stream concurrency manager (limit max 5 concurrent SSE streams)
    private let streamManager = StreamManager()

    var body: some View {
        ZStack {
            // Camera preview (edge-to-edge)
            if let session = cameraManager.captureSession {
                CameraPreviewView(
                    session: session,
                    onZoomChange: { zoomFactor in
                        cameraManager.setZoom(zoomFactor)
                    },
                    onFocusTap: { devicePoint in
                        handleFocusTap(devicePoint)
                    }
                )
                .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
            }

            // Loading spinner (only shown if > 200ms)
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.5)
            }

            // Error overlay
            if let error = errorMessage {
                VStack(spacing: 16) {
                    Text("Camera Error")
                        .font(.title3.bold())
                        .foregroundColor(.swissText)

                    Text(error)
                        .font(.body)
                        .foregroundColor(.swissText.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding()
                .swissGlassCard()
                .padding(24)
            }

            // White flash overlay (full-screen)
            if showFlash {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            // Focus indicator (white brackets at tap location)
            if showFocusIndicator, let point = focusPoint {
                FocusIndicatorView()
                    .position(point)
                    .transition(.opacity)
            }

            // Processing error overlay (auto-dismiss after 5s)
            if showProcessingError, let error = processingErrorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.swissError)

                    Text("Processing Failed")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.swissText)

                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.swissText.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(24)
                .swissGlassCard()
                .padding(.horizontal, 32)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Zoom level display and offline indicator (top-right corner)
            VStack {
                HStack {
                    Spacer()

                    // US-409: Offline indicator with queued count
                    if !networkMonitor.isConnected {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                                .font(.caption)
                                .foregroundColor(.swissError)

                            Text("OFFLINE")
                                .font(.jetBrainsMono)
                                .foregroundColor(.swissError)

                            if offlineQueuedCount > 0 {
                                Text("(\(offlineQueuedCount))")
                                    .font(.jetBrainsMono)
                                    .foregroundColor(.swissText.opacity(0.7))
                            }
                        }
                        .swissGlassOverlay()
                        .padding(.top, 60)
                        .padding(.trailing, 8)
                    }

                    Text(String(format: "%.1fx", cameraManager.currentZoomFactor))
                        .font(.jetBrainsMono)
                        .foregroundColor(.white)
                        .swissGlassOverlay()
                        .padding(.top, 60)
                        .padding(.trailing, 16)
                }

                Spacer()
            }

            // Shutter button + Processing Queue
            VStack {
                Spacer()

                // Processing queue (40px height above shutter)
                ProcessingQueueView(items: processingQueue, onRetry: retryFailedItem)
                    .padding(.bottom, 8)

                // Shutter button (80x80px white ring at bottom center)
                // US-408: Disabled during rate limit cooldown
                Button(action: captureImage) {
                    Circle()
                        .strokeBorder(isRateLimited ? .gray : .white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                        .contentShape(Circle())
                        .opacity(isRateLimited ? 0.3 : 1.0)
                }
                .disabled(isRateLimited)
                .haptic(.impact, trigger: showFlash)
                .padding(.bottom, 40)
            }

            // US-408: Rate limit overlay with countdown timer
            if isRateLimited {
                RateLimitOverlay(
                    remainingSeconds: rateLimitCountdown,
                    queuedScansCount: queuedScansCount
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // US-405: Duplicate book detection alert with full metadata
            if showDuplicateAlert, let duplicate = duplicateBook {
                DuplicateBookAlert(
                    duplicateBook: duplicate,
                    onCancel: {
                        withAnimation(.swissSpring) {
                            showDuplicateAlert = false
                            duplicateBook = nil
                            pendingBookMetadata = nil
                            pendingRawJSON = nil
                        }
                    },
                    onAddAnyway: {
                        withAnimation(.swissSpring) {
                            showDuplicateAlert = false
                            if let metadata = pendingBookMetadata {
                                addBookToLibrary(metadata: metadata, rawJSON: pendingRawJSON)
                            }
                            duplicateBook = nil
                            pendingBookMetadata = nil
                            pendingRawJSON = nil
                        }
                    },
                    onViewExisting: {
                        withAnimation(.swissSpring) {
                            showDuplicateAlert = false
                            // TODO: Navigate to book detail sheet when library navigation is implemented
                            // For now, just dismiss the alert
                            duplicateBook = nil
                            pendingBookMetadata = nil
                            pendingRawJSON = nil
                        }
                    }
                )
            }
        }
        .statusBar(hidden: true) // Full immersion
        .task {
            await setupCamera()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        // US-406: Cancel active SSE streams when app goes to background
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            cancelAllStreamingTasks()
        }
        // US-409: Auto-upload queued scans when network returns
        .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
            if !oldValue && newValue {
                // Network just came back online - upload queued scans
                Task {
                    await uploadQueuedScans()
                }
            }
        }
        .task {
            // US-409: Check for queued scans on startup
            await checkAndUploadQueuedScans()
        }
    }

    private func setupCamera() async {
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

    /// Captures image with non-blocking rapid-fire support
    /// Each tap creates a new parallel task - button never blocks
    /// US-408: Button is disabled during rate limit, but this is a safety check
    private func captureImage() {
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
        // Uses structured Task to maintain priority inheritance
        // US-406: Track task for cancellation on app backgrounding
        let itemId = UUID()
        let task = Task {
            await processCapture(itemId: itemId)
        }
        Task { @MainActor in
            activeStreamingTasks[itemId] = task
        }
    }

    /// US-406: Cancel all active SSE streaming tasks when app goes to background
    @MainActor
    private func cancelAllStreamingTasks() {
        print("🛑 Cancelling \(activeStreamingTasks.count) active SSE streams (app backgrounding)")
        for (_, task) in activeStreamingTasks {
            task.cancel()
        }
        activeStreamingTasks.removeAll()
    }

    /// Processes the captured image (runs in parallel)
    /// Performance target: < 500ms for image processing, then SSE streaming for AI enrichment
    /// US-406: itemId is used to track and cancel active streaming tasks
    private func processCapture(itemId: UUID) async {
        do {
            // Capture photo from camera (must be on main actor)
            let imageData = try await cameraManager.capturePhoto()
            print("📸 Image captured (\(imageData.count) bytes)")

            // US-407: Delegate to processCaptureWithImageData for processing
            await processCaptureWithImageData(itemId: itemId, imageData: imageData)
        } catch {
            print("❌ Camera capture failed: \(error)")
            await showProcessingErrorOverlay(error.localizedDescription)
        }
    }

    /// Adds item to processing queue and returns the item
    @MainActor
    private func addToQueue(imageData: Data) -> ProcessingItem {
        let item = ProcessingItem(imageData: imageData, state: .uploading)
        withAnimation(.swissSpring) {
            processingQueue.append(item)
        }
        return item
    }

    /// Updates queue item state
    @MainActor
    private func updateQueueItemState(id: UUID, state: ProcessingItem.ProcessingState) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].state = state
            }
        }
    }

    /// Updates queue item progress message
    @MainActor
    private func updateQueueItemProgress(id: UUID, message: String?) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].progressMessage = message
            }
        }
    }

    /// Updates both state and progress message atomically
    @MainActor
    private func updateQueueItem(id: UUID, state: ProcessingItem.ProcessingState, message: String?) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].state = state
                processingQueue[index].progressMessage = message
            }
        }
    }

    /// Updates queue item error message (US-407)
    @MainActor
    private func updateQueueItemError(id: UUID, errorMessage: String) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].state = .error
                processingQueue[index].errorMessage = errorMessage
            }
        }
    }

    /// Updates queue item cleanup info (temp file URL and job ID) for US-406
    @MainActor
    private func updateQueueItemCleanupInfo(id: UUID, tempFileURL: URL, jobId: String) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            processingQueue[index].tempFileURL = tempFileURL
            processingQueue[index].jobId = jobId
        }
    }

    /// Removes item from queue after delay
    @MainActor
    private func removeQueueItemAfterDelay(id: UUID, delay: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        withAnimation(.swissSpring) {
            processingQueue.removeAll { $0.id == id }
        }
    }

    /// US-407: Retry failed item by re-uploading image and opening new SSE stream
    @MainActor
    private func retryFailedItem(_ item: ProcessingItem) {
        guard item.state == .error,
              let imageData = item.originalImageData else {
            print("⚠️ Cannot retry: item not in error state or no image data")
            return
        }

        print("🔄 Retrying failed item: \(item.id)")

        // Remove the failed item from queue
        withAnimation(.swissSpring) {
            processingQueue.removeAll { $0.id == item.id }
        }

        // Trigger haptic feedback for retry action
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Re-process the image (same flow as processCapture, but with existing imageData)
        let itemId = UUID()
        let task = Task {
            await processCaptureWithImageData(itemId: itemId, imageData: imageData)
        }
        Task { @MainActor in
            activeStreamingTasks[itemId] = task
        }
    }

    /// US-407: Helper to process image data (used for both capture and retry)
    /// US-409: Enhanced to handle offline mode by queueing scans for later upload
    private func processCaptureWithImageData(itemId: UUID, imageData: Data) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        var queueItem: ProcessingItem?
        var tempFileURL: URL?
        var jobId: String?
        let networkActor = NetworkActor()

        // Cleanup task tracker when done
        defer {
            Task { @MainActor in
                activeStreamingTasks.removeValue(forKey: itemId)
            }
        }

        do {
            print("📸 Processing image data (\(imageData.count) bytes)")

            // US-409: Check if offline - if so, queue for later upload
            if !networkMonitor.isConnected {
                print("📴 Offline mode - queueing scan for later upload")

                // Add to processing queue with offline state
                let item = ProcessingItem(imageData: imageData, state: .offline, progressMessage: "Queued (offline)")
                await MainActor.run {
                    withAnimation(.swissSpring) {
                        processingQueue.append(item)
                    }
                }

                // Queue scan in FileManager for persistent storage
                let queuedId = try await offlineQueueManager.queueScan(imageData: imageData)
                print("💾 Scan queued with ID: \(queuedId)")

                // Update offline queue count
                let count = try await offlineQueueManager.getQueuedScanCount()
                await MainActor.run {
                    offlineQueuedCount = count
                }

                // Keep item in queue indefinitely until uploaded
                return
            }

            // Add to processing queue immediately with thumbnail (uploading state)
            queueItem = addToQueue(imageData: imageData)

            guard let item = queueItem else { return }

            // Process image: resize + compress + save
            let fileURL = try await Self.processImage(imageData)
            tempFileURL = fileURL

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ Image processed in \(String(format: "%.3f", duration))s (target: < 0.5s)")

            if duration >= 0.5 {
                print("⚠️ WARNING: Image processing exceeded 0.5s target!")
            }

            // Read processed image data for upload
            let uploadData = try Data(contentsOf: fileURL)

            // US-410: Performance optimization - limit concurrent SSE streams to 5
            // Prevents memory/FPS degradation during bulk scanning (20+ rapid scans)
            // If 5 streams are active, this scan waits in queue (FIFO) until slot available
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

            let uploadResponse = try await networkActor.uploadImage(uploadData)
            jobId = uploadResponse.jobId

            // Performance logging: upload completed
            let uploadDuration = (CFAbsoluteTimeGetCurrent() - uploadStart) * 1000 // Convert to ms
            print("📤 Upload took \(Int(uploadDuration))ms, jobId: \(uploadResponse.jobId)")

            // Store temp file URL and job ID for cleanup (US-406)
            updateQueueItemCleanupInfo(id: item.id, tempFileURL: fileURL, jobId: uploadResponse.jobId)

            // Switch to analyzing state
            updateQueueItem(id: item.id, state: .analyzing, message: "Analyzing...")

            // Performance logging: start SSE stream timer
            let streamStart = CFAbsoluteTimeGetCurrent()

            // Stream SSE events from Talaria
            let eventStream = await networkActor.streamEvents(from: uploadResponse.streamUrl)

            for try await event in eventStream {
                // Check for task cancellation (app backgrounding)
                if Task.isCancelled {
                    print("🛑 SSE stream cancelled (app backgrounding)")
                    await performCleanup(jobId: jobId, tempFileURL: tempFileURL, networkActor: networkActor)
                    return
                }

                switch event {
                case .progress(let message):
                    // Update progress message in queue
                    print("📡 SSE progress: \(message)")
                    updateQueueItemProgress(id: item.id, message: message)

                case .result(let bookMetadata):
                    // Book metadata received - add to library
                    print("📚 Book identified: \(bookMetadata.title) by \(bookMetadata.author)")

                    // Encode metadata to raw JSON string for debugging
                    let rawJSON: String?
                    if let jsonData = try? JSONEncoder().encode(bookMetadata),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        rawJSON = jsonString
                    } else {
                        rawJSON = nil
                    }

                    handleBookResult(metadata: bookMetadata, rawJSON: rawJSON)

                case .complete:
                    // Performance logging: SSE stream completed
                    let streamDuration = CFAbsoluteTimeGetCurrent() - streamStart
                    print("✅ SSE stream lasted \(String(format: "%.1f", streamDuration))s")

                    updateQueueItem(id: item.id, state: .done, message: nil)

                    // Cleanup resources (non-blocking)
                    await performCleanup(jobId: jobId, tempFileURL: tempFileURL, networkActor: networkActor)

                    // Auto-remove from queue after 5 seconds
                    await removeQueueItemAfterDelay(id: item.id, delay: 5.0)

                case .error(let errorMessage):
                    // AI processing failed (US-407)
                    print("❌ SSE error (jobId: \(jobId ?? "unknown")): \(errorMessage)")

                    // Update queue item with error message and trigger haptic feedback
                    updateQueueItemError(id: item.id, errorMessage: errorMessage)
                    await showProcessingErrorOverlay(errorMessage)

                    // Trigger error haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                    impactFeedback.impactOccurred()

                    // Cleanup resources even on error (non-blocking)
                    await performCleanup(jobId: jobId, tempFileURL: tempFileURL, networkActor: networkActor)

                    // Remove failed item after 5 seconds

                case .canceled:
                    // Job was canceled by user or system (US-506)
                    print("⚠️ SSE job canceled (jobId: \(jobId ?? "unknown"))")

                    // Update queue item to show canceled state
                    updateQueueItem(id: item.id, state: .error, message: "Canceled")

                    // Cleanup resources (non-blocking)
                    await performCleanup(jobId: jobId, tempFileURL: tempFileURL, networkActor: networkActor)

                    // Remove canceled item after 3 seconds (shorter than errors)
                    await removeQueueItemAfterDelay(id: item.id, delay: 3.0)
                    await removeQueueItemAfterDelay(id: item.id, delay: 5.0)
                }
            }

        } catch {
            // US-408: Check if this is a rate limit error
            if let networkError = error as? NetworkError,
               case .rateLimited(let retryAfter) = networkError {
                // Rate limit (429) - queue scan and show countdown UI
                print("⏰ Rate limited: retry after \(retryAfter ?? 0)s")

                // Queue the image data for retry after cooldown
                await rateLimitState.queueScan(imageData)

                // Set rate limit state with retry-after duration (default 60s if not provided)
                let retryDuration = retryAfter ?? 60.0
                await rateLimitState.setRateLimited(retryAfter: retryDuration)

                // Update UI state and start countdown timer
                await startRateLimitCountdown()

                // Remove queue item if it was created
                if let item = queueItem {
                    withAnimation(.swissSpring) {
                        processingQueue.removeAll { $0.id == item.id }
                    }
                }

                // Cleanup temp file (non-blocking)
                if let tempFileURL = tempFileURL {
                    try? FileManager.default.removeItem(at: tempFileURL)
                }

                return
            }

            // Other errors:
            print("❌ Image processing/upload failed: \(error)")

            // Show user-visible error overlay
            await showProcessingErrorOverlay(error.localizedDescription)

            // Update queue item to error state if it was created
            if let item = queueItem {
                updateQueueItemError(id: item.id, errorMessage: error.localizedDescription)

                // Trigger error haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                impactFeedback.impactOccurred()

                // Cleanup resources (non-blocking)
                await performCleanup(jobId: jobId, tempFileURL: tempFileURL, networkActor: networkActor)

                // Remove failed item after 5 seconds
                await removeQueueItemAfterDelay(id: item.id, delay: 5.0)
            }
        }
    }

    /// US-408: Start rate limit countdown timer
    /// Updates countdown every second and auto-recovers when expired
    @MainActor
    private func startRateLimitCountdown() async {
        // Cancel existing timer if any
        countdownTimer?.cancel()

        // Get initial remaining seconds
        rateLimitCountdown = await rateLimitState.getRemainingSeconds()
        isRateLimited = true

        // Start countdown timer
        countdownTimer = Task { @MainActor in
            while await rateLimitState.isRateLimited {
                // Update countdown display and queued scans count
                rateLimitCountdown = await rateLimitState.getRemainingSeconds()
                queuedScansCount = await rateLimitState.queuedScanCount

                // Check if expired
                if rateLimitCountdown <= 0 {
                    // Clear rate limit state
                    await rateLimitState.clearRateLimit()
                    isRateLimited = false

                    // Process queued scans
                    let queuedScans = await rateLimitState.dequeueAllScans()
                    for imageData in queuedScans {
                        let itemId = UUID()
                        let task = Task {
                            await processCaptureWithImageData(itemId: itemId, imageData: imageData)
                        }
                        activeStreamingTasks[itemId] = task
                    }

                    break
                }

                // Wait 1 second before next update
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// Shows processing error overlay with auto-dismiss after 5 seconds
    @MainActor
    private func showProcessingErrorOverlay(_ message: String) async {
        processingErrorMessage = message
        withAnimation(.swissSpring) {
            showProcessingError = true
        }

        // Auto-dismiss after 5 seconds
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        withAnimation(.swissSpring) {
            showProcessingError = false
        }

        // Clear message after fade out animation completes
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms for animation
        processingErrorMessage = nil
    }

    /// US-406: Cleanup resources after job completion or error
    /// Performs cleanup of both server-side job and local temporary file
    /// Non-blocking - failures are logged but don't crash the app
    private func performCleanup(jobId: String?, tempFileURL: URL?, networkActor: NetworkActor) async {
        // Cleanup server-side job resources
        if let jobId = jobId {
            do {
                try await networkActor.cleanupJob(jobId)
                print("🗑️ Server cleanup successful for job: \(jobId)")
            } catch {
                // Log but don't crash - server cleanup failures shouldn't affect user
                print("⚠️ Server cleanup failed for job \(jobId): \(error.localizedDescription)")
            }
        }

        // Cleanup local temporary file
        if let tempFileURL = tempFileURL {
            do {
                try FileManager.default.removeItem(at: tempFileURL)
                print("🗑️ Local temp file cleanup successful: \(tempFileURL.lastPathComponent)")
            } catch CocoaError.fileNoSuchFile {
                // File already deleted - this is fine (might have been auto-cleaned)
                print("ℹ️ Temp file already deleted: \(tempFileURL.lastPathComponent)")
            } catch {
                // Log but don't crash - temp file cleanup failures shouldn't affect user
                print("⚠️ Local temp file cleanup failed for \(tempFileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// Processes image data: resize to max 1920px, compress to JPEG 0.85, save to temp directory
    /// Returns file URL for upload
    /// Performance target: < 500ms
    /// Note: US-406 now handles explicit cleanup after job completion via performCleanup()
    static func processImage(_ imageData: Data) async throws -> URL {
        // Load UIImage
        guard let image = UIImage(data: imageData) else {
            throw ImageProcessingError.invalidImageData
        }

        // Resize to max 1920px on longest dimension
        let resized = resizeImage(image, maxDimension: 1920)

        // Compress to JPEG with 0.85 quality
        guard let jpegData = resized.jpegData(compressionQuality: 0.85) else {
            throw ImageProcessingError.compressionFailed
        }

        // Save to temporary directory with UUID filename
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        try jpegData.write(to: fileURL)

        // US-406: Explicit cleanup now happens in performCleanup() after job completion
        // Fallback: Schedule automatic cleanup after 30 minutes if explicit cleanup fails
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1800)) // 30 minutes
            do {
                try FileManager.default.removeItem(at: fileURL)
                print("🗑️ Fallback cleanup for temp file: \(filename)")
            } catch CocoaError.fileNoSuchFile {
                // File already deleted by explicit cleanup - this is expected
                // print("ℹ️ Temp file already deleted: \(filename)")
            } catch {
                // Log other errors but don't crash
                print("⚠️ Fallback cleanup failed for \(filename): \(error.localizedDescription)")
            }
        }

        return fileURL
    }

    /// Handles focus tap gesture
    /// Shows focus indicator and sets camera focus point
    @MainActor
    private func handleFocusTap(_ devicePoint: CGPoint) {
        // Set focus on camera
        cameraManager.setFocusPoint(devicePoint)

        // Convert device point back to screen coordinates for indicator
        // Device coordinates are normalized (0.0-1.0), convert to screen space
        // Use window scene screen instead of deprecated UIScreen.main
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }
        let screenSize = windowScene.screen.bounds.size
        let screenPoint = CGPoint(
            x: devicePoint.x * screenSize.width,
            y: devicePoint.y * screenSize.height
        )

        // Show focus indicator at tap location
        focusPoint = screenPoint
        withAnimation(.easeOut(duration: 0.2)) {
            showFocusIndicator = true
        }

        // Hide focus indicator after 1 second
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            withAnimation(.easeOut(duration: 0.3)) {
                showFocusIndicator = false
            }
        }
    }

    /// Resizes image to max dimension on longest side
    static func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height

        let newSize: CGSize
        if size.width > size.height {
            // Landscape or square
            newSize = CGSize(width: min(size.width, maxDimension), height: min(size.width, maxDimension) / aspectRatio)
        } else {
            // Portrait
            newSize = CGSize(width: min(size.height, maxDimension) * aspectRatio, height: min(size.height, maxDimension))
        }

        // Only resize if needed
        if newSize.width >= size.width && newSize.height >= size.height {
            return image
        }

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - US-409: Offline Queue Management

    /// Check for queued scans on app startup and upload if network available
    private func checkAndUploadQueuedScans() async {
        do {
            let count = try await offlineQueueManager.getQueuedScanCount()
            await MainActor.run {
                offlineQueuedCount = count
            }

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

    /// Upload all queued scans when network becomes available
    private func uploadQueuedScans() async {
        do {
            let queuedScans = try await offlineQueueManager.getAllQueuedScans()

            guard !queuedScans.isEmpty else {
                return
            }

            print("📤 Uploading \(queuedScans.count) queued scans")

            // Remove offline items from processing queue
            await MainActor.run {
                withAnimation(.swissSpring) {
                    processingQueue.removeAll { $0.state == .offline }
                }
            }

            // Upload each scan sequentially
            for (metadata, imageData) in queuedScans {
                // Create new processing item for upload
                let itemId = UUID()
                let task = Task {
                    await processCaptureWithImageData(itemId: itemId, imageData: imageData)
                }
                await MainActor.run {
                    activeStreamingTasks[itemId] = task
                }

                // Wait for upload to complete before starting next
                await task.value

                // Remove from offline queue
                try? await offlineQueueManager.removeQueuedScan(scanId: metadata.id)

                // Update offline count
                let count = try await offlineQueueManager.getQueuedScanCount()
                await MainActor.run {
                    offlineQueuedCount = count
                }
            }

            print("✅ All queued scans uploaded")
        } catch {
            print("❌ Failed to upload queued scans: \(error)")
        }
    }

    // MARK: - US-405: Result Event Handling

    /// Handles book addition from AI results with duplicate detection
    /// This will be called when Epic 4 AI results arrive
    /// - Parameters:
    ///   - metadata: Full BookMetadata from Talaria SSE result event
    ///   - rawJSON: Original JSON string from SSE for debugging
    @MainActor
    private func handleBookResult(metadata: BookMetadata, rawJSON: String?) {
        let isbn = metadata.isbn ?? "Unknown"

        do {
            // Check for duplicate using SwiftData predicate
            if let duplicate = try DuplicateDetection.findDuplicate(isbn: isbn, in: modelContext) {
                // Store pending metadata and rawJSON for "Add Anyway" action
                pendingBookMetadata = metadata
                pendingRawJSON = rawJSON
                duplicateBook = duplicate

                // Show duplicate alert (non-blocking)
                withAnimation(.swissSpring) {
                    showDuplicateAlert = true
                }
            } else {
                // No duplicate - add directly to library with full metadata
                addBookToLibrary(metadata: metadata, rawJSON: rawJSON)
            }
        } catch {
            // Show error to user if duplicate detection fails
            Task {
                await showProcessingErrorOverlay("Failed to check for duplicates: \(error.localizedDescription)")
            }
            // Add book anyway as a fallback (better to risk duplicate than lose data)
            addBookToLibrary(metadata: metadata, rawJSON: rawJSON)
        }
    }

    /// Adds book to library without duplicate check
    /// Used when user confirms "Add Anyway" or no duplicate exists
    /// - Parameters:
    ///   - metadata: Full BookMetadata from Talaria AI
    ///   - rawJSON: Original JSON string from SSE for debugging
    @MainActor
    private func addBookToLibrary(metadata: BookMetadata, rawJSON: String?) {
        // Parse publishedDate if present (expecting ISO 8601 or common date formats)
        let publishedDate: Date?
        if let dateString = metadata.publishedDate {
            let formatter = ISO8601DateFormatter()
            publishedDate = formatter.date(from: dateString)
        } else {
            publishedDate = nil
        }

        let newBook = Book(
            title: metadata.title,
            author: metadata.author,
            isbn: metadata.isbn ?? "Unknown",
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
            print("✅ Book added to library: \(metadata.title)")

            // US-405: Haptic success feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

        } catch {
            print("❌ Failed to save book: \(error)")
        }
    }
}

// MARK: - Errors
enum ImageProcessingError: LocalizedError {
    case invalidImageData
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Invalid image data"
        case .compressionFailed:
            return "Failed to compress image"
        }
    }
}

// MARK: - Focus Indicator
/// White square brackets [ ] that appear at tap location
/// Shows for 1 second with fade out animation
struct FocusIndicatorView: View {
    var body: some View {
        ZStack {
            // Top-left bracket
            Path { path in
                path.move(to: CGPoint(x: 20, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 20))
            }
            .stroke(Color.white, lineWidth: 2)
            .frame(width: 60, height: 60, alignment: .topLeading)

            // Top-right bracket
            Path { path in
                path.move(to: CGPoint(x: 40, y: 0))
                path.addLine(to: CGPoint(x: 60, y: 0))
                path.addLine(to: CGPoint(x: 60, y: 20))
            }
            .stroke(Color.white, lineWidth: 2)
            .frame(width: 60, height: 60, alignment: .topLeading)

            // Bottom-left bracket
            Path { path in
                path.move(to: CGPoint(x: 0, y: 40))
                path.addLine(to: CGPoint(x: 0, y: 60))
                path.addLine(to: CGPoint(x: 20, y: 60))
            }
            .stroke(Color.white, lineWidth: 2)
            .frame(width: 60, height: 60, alignment: .topLeading)

            // Bottom-right bracket
            Path { path in
                path.move(to: CGPoint(x: 60, y: 40))
                path.addLine(to: CGPoint(x: 60, y: 60))
                path.addLine(to: CGPoint(x: 40, y: 60))
            }
            .stroke(Color.white, lineWidth: 2)
            .frame(width: 60, height: 60, alignment: .topLeading)
        }
        .frame(width: 60, height: 60)
    }
}

#Preview {
    CameraView()
        .preferredColorScheme(.dark)
}
