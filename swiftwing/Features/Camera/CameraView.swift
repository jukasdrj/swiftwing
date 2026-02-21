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

            // All non-preview, non-shutter overlays delegated to CameraOverlayView
            CameraOverlayView(viewModel: viewModel, showProcessingFeedback: $showProcessingFeedback)

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
                debugLog("INJECT_TEST_IMAGE: modelContext available = true")

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
                        debugLog("INJECT_TEST_IMAGE: pendingReviewBooks.count = \(viewModel.reviewQueueManager.pendingReviewBooks.count)")
                        debugLog("INJECT_TEST_IMAGE: processingQueue.count = \(viewModel.processingQueue.count)")
                        for (i, book) in viewModel.reviewQueueManager.pendingReviewBooks.enumerated() {
                            debugLog("INJECT_TEST_IMAGE: pendingBook[\(i)] = '\(book.metadata.resolvedTitle)' by '\(book.metadata.resolvedAuthor)'")
                        }
                    }
                    Task { await viewModel.scanCoordinator.trackJob(id: itemId, task: scanTask) }
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
