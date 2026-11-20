import AVFoundation
import os
import SwiftData
import SwiftUI

private let e2eLogger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "e2e-test")

/// Main camera view with zero-lag preview
/// Performance target: < 0.5s cold start to live feed
struct CameraView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    var viewModel: CameraViewModel

    // US-B2: Processing feedback overlay state
    @State private var showProcessingFeedback = false
    @State private var isShutterPressed = false

    // Phase 9c: one-time camera coach overlay, keyed separately from app onboarding
    @AppStorage("hasSeenCameraGuidance") private var hasSeenCameraGuidance = false
    @State private var showGuidance = false

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
                    items: viewModel.queueStateManager.processingQueue, onRetry: viewModel.retryFailedItem
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
                        try? await Task.sleep(for: .seconds(2))
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
                        .scaleEffect(isShutterPressed ? 0.95 : 1.0)
                        .animation(.spring(duration: 0.15), value: isShutterPressed)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isShutterPressed = true }
                        .onEnded { _ in isShutterPressed = false }
                )
                .accessibilityIdentifier("camera_shutter")
                .accessibilityLabel("Capture")
                .disabled(viewModel.isRateLimited || viewModel.isInterrupted)
                .haptic(.impact, trigger: viewModel.showFlash)
                .padding(.bottom, 40)
            }

            // Phase 9c: first-run coach overlay, drawn above every other layer
            if showGuidance {
                CameraFirstRunGuidance {
                    withAnimation(.swissSpring) { showGuidance = false }
                }
                .zIndex(200)
            }
        }
        .statusBar(hidden: true) // Full immersion
        .onAppear {
            if !hasSeenCameraGuidance {
                showGuidance = true
            }
        }
        .onChange(of: hasSeenCameraGuidance) { _, seen in
            if !seen {
                showGuidance = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCameraGuidance)) { _ in
            showGuidance = true
        }
        .task {
            viewModel.modelContext = modelContext
            await viewModel.setupCamera()
            await viewModel.checkAndUploadQueuedScans()

            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(TestLaunch.injectTestImage) {
                // Unstructured task: awaiting inside .task is cancelled when camera state
                // updates re-render the view. Same pattern as captureImage().
                let model = viewModel
                let context = modelContext
                Task {
                    guard let imageData = await ShelfFixtureLoader.dataForLaunchInjection() else {
                        e2eLogger.error("INJECT_TEST_IMAGE: no image")
                        return
                    }
                    let byteCount = imageData.count
                    e2eLogger.info("INJECT_TEST_IMAGE: loaded \(byteCount, privacy: .public) bytes")
                    ShelfScanInjection.start(jpeg: imageData, viewModel: model, modelContext: context)
                }
            }
            #endif
        }
        .onDisappear {
            viewModel.stopCamera()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.cancelAllStreamingTasks()
            }
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
            "Invalid image data"
        case .compressionFailed:
            "Failed to compress image"
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
                        .foregroundStyle(.swissText)
                    Text("Tap to review")
                        .font(.caption)
                        .foregroundStyle(.internationalOrange)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.internationalOrange)
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
