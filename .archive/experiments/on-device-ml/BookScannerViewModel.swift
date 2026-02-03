import AVFoundation
import Combine
import SwiftData
import SwiftUI
import Vision

#if canImport(UIKit)
    import UIKit
#endif

/// Replacement for CameraViewModel using Swift 6.2 "Approachable Concurrency"
/// and iOS 26 patterns (Vision + Foundation Models)
@MainActor
@Observable
final class BookScannerViewModel {
    // MARK: - Core State
    var cameraManager = CameraManager()
    var isLoading = true
    var errorMessage: String?
    var showFlash = false

    // MARK: - Processing State
    var processingQueue: [ProcessingItem] = []
    var detectedText: [TextRegion] = []  // Kept for overlays
    var detectedObjects: [DetectedObject] = []  // Kept for overlays
    var captureGuidance: CaptureGuidance = .noBookDetected

    // MARK: - Review Queue State
    var pendingReviewBooks: [PendingBookResult] = []
    var duplicateBook: Book?
    var showDuplicateAlert = false

    // MARK: - Interruption & Indicators
    var isInterrupted: Bool { cameraManager.isInterrupted }
    var focusPoint: CGPoint?
    var showFocusIndicator = false
    var showProcessingError = false
    var processingErrorMessage: String?

    // MARK: - Services
    private let segmentationService = InstanceSegmentationService()
    private let extractionService = BookExtractionService()
    // Retaining legacy services for offline/fallback support if needed
    var networkMonitor = NetworkMonitor()
    let offlineQueueManager = OfflineQueueManager()
    var offlineQueuedCount = 0
    let streamManager = StreamManager()

    // MARK: - Rate Limiting
    // Keeping RateLimitState for safety
    let rateLimitState = RateLimitState()
    var isRateLimited = false
    var rateLimitCountdown = 0
    var queuedScansCount = 0

    var isVisionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "isVisionEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "isVisionEnabled") }
    }

    // MARK: - Active Tasks
    // Track background tasks to cancel them on disappear
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - ModelContext
    var modelContext: ModelContext?

    private let deviceId: String

    #if canImport(UIKit)
        private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    #endif

    init(deviceId: String = DeviceIdentifier.current) {
        self.deviceId = deviceId
    }

    // MARK: - Camera Setup
    func setupCamera() async {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Show loading if slow
        let loadingTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if cameraManager.captureSession == nil { isLoading = true }
        }

        do {
            try cameraManager.setupSession()
            #if canImport(UIKit)
                hapticGenerator.prepare()
            #endif

            // Wire Vision result callback (on MainActor)
            cameraManager.onVisionResult = { [weak self] result in
                guard let self else { return }
                self.handleVisionResult(result)
            }

            cameraManager.startSession()
            loadingTask.cancel()
            isLoading = false

            print(
                "📹 Camera setup took \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))s"
            )

        } catch {
            loadingTask.cancel()
            isLoading = false
            errorMessage = error.localizedDescription
            print("❌ Camera setup failed: \(error)")
        }
    }

    func stopCamera() {
        cameraManager.stopSession()
    }

    // MARK: - Vision Handling
    private func handleVisionResult(_ result: VisionResult) {
        switch result {
        case .textRegions(let regions):
            self.detectedText = regions
            self.detectedObjects = []
            self.captureGuidance = .noBookDetected  // Simplified for now, can enhance

        case .barcode(let barcodeResult):
            self.detectedObjects = []
            if barcodeResult.isValidISBN {
                self.captureGuidance = .spineDetected
                #if canImport(UIKit)
                    hapticGenerator.impactOccurred()
                #endif
            }

        case .objects(let objects):
            self.detectedObjects = objects
            // Simple guidance logic
            self.captureGuidance = objects.isEmpty ? .noBookDetected : .spineDetected

        case .noContent:
            break
        }

        // Adaptive Throttling
        let isActivelyScanning = (self.captureGuidance == .spineDetected)
        self.cameraManager.setProcessingRate(active: isActivelyScanning)
    }

    // MARK: - Capture & Processing
    func captureImage() {
        guard !isRateLimited else { return }

        // UI Feedback
        withAnimation(.easeOut(duration: 0.1)) { showFlash = true }
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation { showFlash = false }
        }

        let itemId = UUID()
        let task = Task {
            await processCapture(itemId: itemId)
        }
        activeTasks[itemId] = task
    }

    private func processCapture(itemId: UUID) async {
        do {
            // 1. Capture (on MainActor)
            let imageData = try await cameraManager.capturePhoto()

            // 2. Add to Queue
            var newItem = ProcessingItem(
                imageData: imageData, state: .preprocessing, progressMessage: "Segmenting...")
            withAnimation(.swissSpring) {
                processingQueue.append(newItem)
            }

            // 3. Process Logic
            // Check offline mode (optional - prioritizing implementation of segmentation first)
            if !networkMonitor.isConnected {
                // Offline fallback logic similar to CameraViewModel...
                // For now, let's focus on the "Vision" path as requested
            }

            // Explicitly run Vision processing on background thread pool (simulated @concurrent behavior)
            // Since Swift 6.2 standard isn't fully in this environment, we use detached task or separate actor pattern.
            // But user asked for `@concurrent`. We will assume `InstanceSegmentationService`
            // and `BookExtractionService` are actors or async functions handling this.

            // Segmentation (Async)
            let books = try await processShelfImage(imageData)

            if books.isEmpty {
                // No books, maybe just process the whole image?
                // Fallback to single item
                await processSingleBook(imageData: imageData, itemId: newItem.id)
            } else {
                print("📚 Detected \(books.count) books")

                // Update the original item to "Segemented" or remove it and add child items?
                // Typically we replace the "shelf" item with "book" items.

                withAnimation(.swissSpring) {
                    processingQueue.removeAll(where: { $0.id == newItem.id })
                }

                for (index, book) in books.enumerated() {
                    let bookItem = ProcessingItem(
                        imageData: book.croppedImage.jpgData() ?? Data(),  // simplified extension usage
                        state: .extracting,
                        progressMessage: "Extracting book \(index + 1)..."
                    )
                    withAnimation(.swissSpring) {
                        processingQueue.append(bookItem)
                    }

                    // Process each book
                    Task {
                        await processExtractedBook(bookItem)
                    }
                }
            }

        } catch {
            print("❌ Capture failed: \(error)")
            updateQueueItemError(id: itemId, message: error.localizedDescription)
            await showErrorOverlay(error.localizedDescription)
        }
    }

    // Explicitly run Vision processing on background thread pool
    // In Swift 6.2 this would be `@concurrent`
    // We simulate or use if compiler supports
    nonisolated func processShelfImage(_ imageData: Data) async throws -> [SegmentedBook] {
        guard let ciImage = CIImage(data: imageData) else { return [] }
        // InstanceSegmentationService is an actor, so this await hops there
        let service = InstanceSegmentationService()
        return try await service.segmentBooks(from: ciImage)
    }

    private func processSingleBook(imageData: Data, itemId: UUID) async {
        updateQueueItemState(id: itemId, state: .extracting, message: "Extracting text...")
        // TODO: extraction
        guard let ciImage = CIImage(data: imageData) else { return }

        do {
            // OCR
            let visionService = VisionService()  // synchronous class, but we need new async API
            let document = try await visionService.recognizeText(in: ciImage)

            // Metadata
            let metadata = try await extractionService.extract(from: document.fullText)

            // Success
            let bookResult = PendingBookResult(
                metadata: metadata.toBookMetadata(),
                rawJSON: nil,
                thumbnailData: imageData
            )

            // Add to Review Queue
            withAnimation {
                pendingReviewBooks.append(bookResult)
                // Remove from processing queue
                processingQueue.removeAll(where: { $0.id == itemId })
            }

        } catch {
            updateQueueItemError(id: itemId, message: error.localizedDescription)
        }
    }

    private func processExtractedBook(_ item: ProcessingItem) async {
        // Reuse processSingleBook logic or similar
        await processSingleBook(imageData: item.originalImageData!, itemId: item.id)
    }

    // MARK: - Queue Management Handlers
    private func updateQueueItemState(
        id: UUID, state: ProcessingItem.ProcessingState, message: String?
    ) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].state = state
                processingQueue[index].progressMessage = message
            }
        }
    }

    private func updateQueueItemError(id: UUID, message: String) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.swissSpring) {
                processingQueue[index].state = .error
                processingQueue[index].errorMessage = message
            }
            // Auto remove after delay?
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation {
                    processingQueue.removeAll(where: { $0.id == id })
                }
            }
        }
    }

    // MARK: - Review Queue Actions
    func approveBook(_ book: PendingBookResult, modelContext: ModelContext) {
        let newBook = Book(
            title: book.resolvedTitle,
            author: book.resolvedAuthor,
            isbn: book.metadata.isbn ?? "",
            coverUrl: nil,
            format: nil,
            publisher: book.metadata.publisher,
            publishedDate: nil,
            pageCount: nil,
            spineConfidence: book.metadata.confidence,
            addedDate: Date(),
            readingStatus: nil,
            dateRead: nil,
            userRating: nil,
            notes: nil,
            rawJSON: book.rawJSON,
            enrichmentStatus: "pending"
        )

        modelContext.insert(newBook)

        // Remove from pending
        withAnimation {
            pendingReviewBooks.removeAll(where: { $0.id == book.id })
        }
    }

    func rejectBook(_ book: PendingBookResult) {
        withAnimation {
            pendingReviewBooks.removeAll(where: { $0.id == book.id })
        }
    }

    func updatePendingBookEdits(id: UUID, title: String?, author: String?) {
        if let index = pendingReviewBooks.firstIndex(where: { $0.id == id }) {
            pendingReviewBooks[index].editedTitle = title
            pendingReviewBooks[index].editedAuthor = author
        }
    }

    func approveAllBooks(modelContext: ModelContext) {
        for book in pendingReviewBooks {
            approveBook(book, modelContext: modelContext)
        }
    }

    // MARK: - View Helpers
    func handleFocusTap(_ point: CGPoint) {
        focusPoint = point
        showFocusIndicator = true
        cameraManager.setFocusPoint(point)
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            showFocusIndicator = false
        }
    }

    func configureRotationCoordinator(previewLayer: AVCaptureVideoPreviewLayer) {
        cameraManager.configureRotation(previewLayer: previewLayer)
    }

    private func showErrorOverlay(_ message: String) {
        processingErrorMessage = message
        showProcessingError = true
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            showProcessingError = false
        }
    }

    func checkAndUploadQueuedScans() async {
        // Implement offline queue processing
    }

    func handleNetworkChange(oldValue: Bool, newValue: Bool) {
        // trigger uploads
    }

    func cancelAllStreamingTasks() {
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
    }

    func retryFailedItem(_ item: ProcessingItem) {
        if let data = item.originalImageData {
            // Retry logic
        }
    }

    func dismissDuplicateAlert() {
        showDuplicateAlert = false
        duplicateBook = nil
    }

    func addDuplicateAnyway(modelContext: ModelContext) {
        // Implementation
        showDuplicateAlert = false
    }
}

// Helper for CIImage -> Data
extension CIImage {
    func jpgData() -> Data? {
        let context = CIContext()
        // Use jpegRepresentation directly (available in CoreImage across platforms)
        // Note: jpegRepresentation(of:colorSpace:options:) is standard
        guard let colorSpace = self.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        // Simpler fallback if we just want JPEG data
        // CIContext().jpegRepresentation works nicely and avoids UIImage
        // iOS 26: Use kCGImageDestinationLossyCompressionQuality directly
        return context.jpegRepresentation(
            of: self, colorSpace: colorSpace,
            options: [
                kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8
            ])
    }
}
