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

    // MARK: - US-406: Active Streaming Tasks
    var activeStreamingTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - US-408: Rate Limit State
    let rateLimitState = RateLimitState()
    var isRateLimited = false
    var rateLimitCountdown: Int = 0
    var queuedScansCount: Int = 0
    var countdownTimer: Task<Void, Never>?

    // MARK: - US-409: Offline Queue State
    var networkMonitor = NetworkMonitor()
    let offlineQueueManager = OfflineQueueManager()
    var offlineQueuedCount: Int = 0

    // MARK: - US-410: Stream Concurrency Manager
    let streamManager = StreamManager()

    // MARK: - Vision Framework State
    var isVisionEnabled: Bool = true
    var detectedText: [TextRegion] = []
    var detectedISBN: String? = nil
    var captureGuidance: CaptureGuidance = .noBookDetected

    // MARK: - Haptic Feedback
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)

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
                        // Generate guidance based on detected text regions
                        self.captureGuidance = self.generateGuidance(from: regions)

                    case .barcode(let barcodeResult):
                        if barcodeResult.isValidISBN {
                            self.detectedISBN = barcodeResult.isbn
                            self.captureGuidance = .spineDetected
                            // Haptic feedback when spine detected
                            self.hapticGenerator.impactOccurred()
                        }

                    case .noContent:
                        self.detectedText = []
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

            let (uploadedJobId, streamUrl) = try await talariaService.uploadScan(image: uploadData, deviceId: UUID().uuidString)
            jobId = uploadedJobId

            // Performance logging: upload completed
            let uploadDuration = (CFAbsoluteTimeGetCurrent() - uploadStart) * 1000 // Convert to ms
            print("📤 Upload took \(Int(uploadDuration))ms, jobId: \(uploadedJobId)")

            // Store temp file URL and job ID for cleanup (US-406)
            updateQueueItemCleanupInfo(id: item.id, tempFileURL: fileURL, jobId: uploadedJobId)

            // Switch to analyzing state
            updateQueueItem(id: item.id, state: .analyzing, message: "Analyzing...")

            // Performance logging: start SSE stream timer
            let streamStart = CFAbsoluteTimeGetCurrent()

            // Stream SSE events from Talaria
            let eventStream = talariaService.streamEvents(streamUrl: streamUrl)

            for try await event in eventStream {
                // Check for task cancellation (app backgrounding)
                if Task.isCancelled {
                    print("🛑 SSE stream cancelled (app backgrounding)")
                    await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService)
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

                case .complete:
                    let streamDuration = CFAbsoluteTimeGetCurrent() - streamStart
                    print("✅ SSE stream lasted \(String(format: "%.1f", streamDuration))s")

                    updateQueueItem(id: item.id, state: .done, message: nil)

                    // Cleanup resources (non-blocking)
                    await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService)

                    // Auto-remove from queue after 5 seconds
                    await removeQueueItemAfterDelay(id: item.id, delay: 5.0)

                case .error(let errorMessage):
                    print("❌ SSE error (jobId: \(jobId ?? "unknown")): \(errorMessage)")

                    updateQueueItemError(id: item.id, errorMessage: errorMessage)
                    await showProcessingErrorOverlay(errorMessage)

                    // Trigger error haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                    impactFeedback.impactOccurred()

                    await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService)

                case .canceled:
                    print("⚠️ SSE job canceled (jobId: \(jobId ?? "unknown"))")

                    updateQueueItem(id: item.id, state: .error, message: "Canceled")

                    await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService)

                    await removeQueueItemAfterDelay(id: item.id, delay: 3.0)
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

                await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService)

                await removeQueueItemAfterDelay(id: item.id, delay: 5.0)
            }
        }
    }

    // MARK: - Queue Management
    private func addToQueue(imageData: Data) -> ProcessingItem {
        var item = ProcessingItem(imageData: imageData, state: .uploading)
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
        print("🛑 Cancelling \(activeStreamingTasks.count) active SSE streams (app backgrounding)")
        for (_, task) in activeStreamingTasks {
            task.cancel()
        }
        activeStreamingTasks.removeAll()
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
        let isbn = metadata.isbn ?? "Unknown"

        do {
            if let duplicate = try DuplicateDetection.findDuplicate(isbn: isbn, in: modelContext) {
                pendingBookMetadata = metadata
                pendingRawJSON = rawJSON
                duplicateBook = duplicate

                withAnimation(.swissSpring) {
                    showDuplicateAlert = true
                }
            } else {
                addBookToLibrary(metadata: metadata, rawJSON: rawJSON, modelContext: modelContext)
            }
        } catch {
            Task {
                await showProcessingErrorOverlay("Failed to check for duplicates: \(error.localizedDescription)")
            }
            addBookToLibrary(metadata: metadata, rawJSON: rawJSON, modelContext: modelContext)
        }
    }

    func addBookToLibrary(metadata: BookMetadata, rawJSON: String?, modelContext: ModelContext) {
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

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

        } catch {
            print("❌ Failed to save book: \(error)")
        }
    }

    func dismissDuplicateAlert() {
        withAnimation(.swissSpring) {
            showDuplicateAlert = false
            duplicateBook = nil
            pendingBookMetadata = nil
            pendingRawJSON = nil
        }
    }

    func addDuplicateAnyway(modelContext: ModelContext) {
        withAnimation(.swissSpring) {
            showDuplicateAlert = false
            if let metadata = pendingBookMetadata {
                addBookToLibrary(metadata: metadata, rawJSON: pendingRawJSON, modelContext: modelContext)
            }
            duplicateBook = nil
            pendingBookMetadata = nil
            pendingRawJSON = nil
        }
    }

    // MARK: - Resource Cleanup
    private func performCleanup(jobId: String?, tempFileURL: URL?, talariaService: TalariaService) async {
        if let jobId = jobId {
            do {
                try await talariaService.cleanup(jobId: jobId)
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
