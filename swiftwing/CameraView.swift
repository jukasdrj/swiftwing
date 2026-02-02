import SwiftUI
import AVFoundation
import SwiftData

/// Main camera view with zero-lag preview
/// Performance target: < 0.5s cold start to live feed
struct CameraView: View {
    @Environment(\.modelContext) private var modelContext
    var viewModel: CameraViewModel

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
            if let activeItem = viewModel.processingQueue.first(where: { $0.segmentedPreview != nil && $0.state == .analyzing }),
               let previewData = activeItem.segmentedPreview {
                SegmentedPreviewOverlay(
                    imageData: previewData,
                    totalBooks: activeItem.detectedBookCount ?? 0,
                    currentBook: activeItem.currentBookIndex ?? 0,
                    totalProcessed: activeItem.currentBookIndex ?? 0
                )
                .padding(.horizontal, 32)
                .padding(.bottom, 160) // Above shutter button
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
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
                ProcessingQueueView(items: viewModel.processingQueue, onRetry: viewModel.retryFailedItem)
                    .padding(.bottom, 8)

                // Shutter button (80x80px white ring at bottom center)
                // US-408: Disabled during rate limit cooldown
                // Task 2.2: Disable when camera is interrupted
                Button(action: viewModel.captureImage) {
                    Circle()
                        .strokeBorder(
                            viewModel.isRateLimited || viewModel.isInterrupted ? .gray : .white,
                            lineWidth: 4
                        )
                        .frame(width: 80, height: 80)
                        .contentShape(Circle())
                        .opacity(viewModel.isRateLimited || viewModel.isInterrupted ? 0.3 : 1.0)
                }
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
        .statusBar(hidden: true) // Full immersion
        .task {
            // Inject modelContext into viewModel
            viewModel.modelContext = modelContext
            await viewModel.setupCamera()
        }
        .onDisappear {
            viewModel.cancelAllStreamingTasks()  // NEW: Cancel SSE streams + backend cleanup
            viewModel.stopCamera()
        }
        // US-406: Cancel active SSE streams when app goes to background
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.cancelAllStreamingTasks()
        }
        // US-409: Auto-upload queued scans when network returns
        .onChange(of: viewModel.networkMonitor.isConnected) { oldValue, newValue in
            viewModel.handleNetworkChange(oldValue: oldValue, newValue: newValue)
        }
        .task {
            // US-409: Check for queued scans on startup
            await viewModel.checkAndUploadQueuedScans()
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
    CameraView(viewModel: CameraViewModel())
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
