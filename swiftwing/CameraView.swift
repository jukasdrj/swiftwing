import AVFoundation
import os
import SwiftData
import SwiftUI

private let e2eLogger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "e2e-test")

/// Main camera view with zero-lag preview
/// Performance target: < 0.5s cold start to live feed
struct CameraView: View {
    @Environment(\.modelContext) private var modelContext
    var viewModel: CameraViewModel

    // US-B2: Processing feedback overlay state
    @State private var showProcessingFeedback = false

    var body: some View {
        ZStack {
            // Camera preview (edge-to-edge)
            if let session = viewModel.cameraManager.captureSession {
                CameraPreviewView(
                    session: session,
                    onZoomChange: { zoomFactor in
                        viewModel.cameraManager.setZoom(zoomFactor)
                    },
                    onFocusTap: { devicePoint in
                        viewModel.handleFocusTap(devicePoint)
                    },
                    onPreviewLayerReady: { previewLayer in
                        viewModel.configureRotationCoordinator(previewLayer: previewLayer)
                    }
                )
                .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
            }

            // Vision Framework Overlays (conditionally shown)
            if viewModel.isVisionEnabled {
                VisionOverlayView(textRegions: viewModel.detectedText)
                    .allowsHitTesting(false)

                // Object detection overlay (rectangle bounding boxes)
                ObjectBoundingBoxView(
                    detectedObjects: viewModel.detectedObjects,
                    imageSize: CGSize(width: 1920, height: 1080)  // TODO: Get actual camera resolution
                )
                .allowsHitTesting(false)

                CaptureGuidanceView(guidance: viewModel.captureGuidance)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Loading spinner (only shown if > 200ms)
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.5)
            }

            // Error overlay
            if let error = viewModel.errorMessage {
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
            if viewModel.showFlash {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            // Focus indicator (white brackets at tap location)
            if viewModel.showFocusIndicator, let point = viewModel.focusPoint {
                FocusIndicatorView()
                    .position(point)
                    .transition(.opacity)
            }

            // US-B2: Processing feedback overlay (positioned above shutter button)
            if showProcessingFeedback {
                GeometryReader { geometry in
                    ProcessingFeedbackView(
                        processingCount: viewModel.processingQueue.count,
                        isVisible: $showProcessingFeedback
                    )
                    .position(x: geometry.size.width / 2, y: 200)
                }
                .zIndex(100)  // Above all other overlays
            }

            // Processing error overlay (auto-dismiss after 5s)
            if viewModel.showProcessingError, let error = viewModel.processingErrorMessage {
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

            // Segmented preview overlay (shows when processing item has preview data)
            if let activeItem = viewModel.processingQueue.first(where: {
                $0.segmentedPreview != nil && $0.state == .analyzing
            }),
                let previewData = activeItem.segmentedPreview
            {
                SegmentedPreviewOverlay(
                    imageData: previewData,
                    totalBooks: activeItem.detectedBookCount ?? 0,
                    currentBook: activeItem.currentBookIndex ?? 0,
                    totalProcessed: activeItem.currentBookIndex ?? 0
                )
                .padding(.horizontal, 32)
                .padding(.bottom, 160)  // Above shutter button
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Scan complete banner (shown above shutter when books land in review queue)
            if let banner = viewModel.scanCompleteBanner {
                VStack {
                    Spacer()

                    ScanCompleteBannerView(
                        bookCount: banner.bookCount,
                        thumbnailData: banner.thumbnailData,
                        onTap: {
                            viewModel.dismissScanCompleteBanner()
                            viewModel.requestedTab = 1
                        },
                        onDismiss: {
                            viewModel.dismissScanCompleteBanner()
                        }
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 180)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(99)
            }

            // Zoom level display and offline indicator (top-right corner)
            VStack {
                HStack {
                    Spacer()

                    // US-409: Offline indicator with queued count
                    if !viewModel.networkMonitor.isConnected {
                        OfflineIndicatorView(offlineQueuedCount: viewModel.offlineQueuedCount)
                            .padding(.top, 60)
                            .padding(.trailing, 8)
                            .transition(.opacity)
                    }

                    Text(String(format: "%.1fx", viewModel.cameraManager.currentZoomFactor))
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
                ProcessingQueueView(
                    items: viewModel.processingQueue, onRetry: viewModel.retryFailedItem
                )
                .padding(.bottom, 8)

                // Shutter button (80x80px white ring at bottom center)
                // US-408: Disabled during rate limit cooldown
                // Task 2.2: Disable when camera is interrupted
                // US-B2: Enhanced with processing feedback overlay
                Button {
                    // Trigger capture
                    viewModel.captureImage()

                    // US-B2: Show processing feedback (count derived from live queue)
                    Task {
                        showProcessingFeedback = true

                        // Auto-dismiss after 2 seconds
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        showProcessingFeedback = false
                    }
                } label: {
                    Circle()
                        .strokeBorder(
                            viewModel.isRateLimited || viewModel.isInterrupted ? .gray : .white,
                            lineWidth: 4
                        )
                        .frame(width: 80, height: 80)
                        .contentShape(Circle())
                        .opacity(viewModel.isRateLimited || viewModel.isInterrupted ? 0.3 : 1.0)
                }
                .accessibilityIdentifier("camera_shutter")
                .accessibilityLabel("Capture")
                .disabled(viewModel.isRateLimited || viewModel.isInterrupted)
                .haptic(.impact, trigger: viewModel.showFlash)
                .padding(.bottom, 40)
            }

            // US-408: Rate limit overlay with countdown timer
            if viewModel.isRateLimited {
                RateLimitOverlay(
                    remainingSeconds: viewModel.rateLimitCountdown,
                    queuedScansCount: viewModel.queuedScansCount
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Task 2.2: Camera interruption overlay (phone call, FaceTime, etc.)
            if viewModel.isInterrupted {
                VStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)

                    VStack(spacing: 8) {
                        Text("Camera Interrupted")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.swissText)

                        Text("Phone call or FaceTime in progress")
                            .font(.subheadline)
                            .foregroundColor(.swissText.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(24)
                .swissGlassCard()
                .padding(.horizontal, 32)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

        }
        .statusBar(hidden: true)  // Full immersion
        .task {
            viewModel.modelContext = modelContext
            await viewModel.setupCamera()
            await viewModel.checkAndUploadQueuedScans()

            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("INJECT_TEST_IMAGE") {
                // Write debug log to file for integration test diagnosis
                let logFile = URL(fileURLWithPath: "/tmp/swiftwing-integration-test.log")
                func debugLog(_ msg: String) {
                    let timestamp = ISO8601DateFormatter().string(from: Date())
                    let line = "[\(timestamp)] \(msg)\n"
                    if let data = line.data(using: .utf8) {
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
                    e2eLogger.info("🧪 \(msg)")
                }

                debugLog("INJECT_TEST_IMAGE: Starting test image injection")
                debugLog("INJECT_TEST_IMAGE: modelContext available = \(modelContext != nil)")

                let imageData: Data?
                if let bundleUrl = Bundle.main.url(forResource: "test_book_stack", withExtension: "jpg") {
                    debugLog("INJECT_TEST_IMAGE: Found image in bundle at \(bundleUrl.path)")
                    imageData = try? Data(contentsOf: bundleUrl)
                } else {
                    debugLog("INJECT_TEST_IMAGE: Bundle lookup failed, trying filesystem")
                    let paths = [
                        "/Users/juju/dev_repos/swiftwing/test_book_stack.jpg",
                        ProcessInfo.processInfo.environment["TEST_IMAGE_PATH"]
                    ].compactMap { $0 }
                    imageData = paths.compactMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }.first
                }

                if let imageData = imageData {
                    debugLog("INJECT_TEST_IMAGE: Loaded \(imageData.count) bytes")
                    debugLog("INJECT_TEST_IMAGE: Launching scan (fire-and-forget)...")
                    let itemId = UUID()
                    // CRITICAL: Use fire-and-forget Task, NOT await.
                    // Awaiting inside .task{} causes cancellation when @Observable state
                    // changes trigger view re-render (SwiftUI cancels .task on identity change).
                    // This matches the normal captureImage() pattern at line 232.
                    let scanTask = Task {
                        await viewModel.processCaptureWithImageData(
                            itemId: itemId,
                            imageData: imageData,
                            modelContext: modelContext
                        )
                        debugLog("INJECT_TEST_IMAGE: processCaptureWithImageData completed")
                        debugLog("INJECT_TEST_IMAGE: pendingReviewBooks.count = \(viewModel.pendingReviewBooks.count)")
                        debugLog("INJECT_TEST_IMAGE: processingQueue.count = \(viewModel.processingQueue.count)")
                        for (i, book) in viewModel.pendingReviewBooks.enumerated() {
                            debugLog("INJECT_TEST_IMAGE: pendingBook[\(i)] = '\(book.metadata.resolvedTitle)' by '\(book.metadata.resolvedAuthor)'")
                        }
                    }
                    viewModel.activeStreamingTasks[itemId] = scanTask
                    debugLog("INJECT_TEST_IMAGE: Scan task launched successfully")
                } else {
                    debugLog("INJECT_TEST_IMAGE: ERROR - Could not load test image from any path")
                }
            }
            #endif
        }
        .onDisappear {
            viewModel.stopCamera()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
        ) { _ in
            viewModel.cancelAllStreamingTasks()
        }
        .onChange(of: viewModel.networkMonitor.isConnected) { oldValue, newValue in
            viewModel.handleNetworkChange(oldValue: oldValue, newValue: newValue)
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

// MARK: - Scan Complete Banner
struct ScanCompleteBannerView: View {
    let bookCount: Int
    let thumbnailData: Data?
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail preview
                if let data = thumbnailData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(bookCount) book\(bookCount == 1 ? "" : "s") found")
                        .font(.headline)
                        .foregroundColor(.swissText)
                    Text("Tap to review")
                        .font(.caption)
                        .foregroundColor(.internationalOrange)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.internationalOrange)
            }
            .padding(16)
            .swissGlassCard()
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.internationalOrange.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CameraView(viewModel: CameraViewModel())
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(ColorScheme.dark)
}
