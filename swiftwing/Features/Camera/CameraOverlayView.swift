import SwiftUI

/// Composed overlay layer for CameraView.
/// Stacks all non-preview, non-shutter overlays in a single ZStack so CameraView
/// can delegate the entire overlay concern here.
struct CameraOverlayView: View {
    var viewModel: CameraViewModel

    /// Processing-feedback visibility is owned by CameraView (shutter tap side-effect)
    /// and threaded in as a binding so the overlay can be dismissed automatically.
    @Binding var showProcessingFeedback: Bool

    var body: some View {
        ZStack {
            // MARK: Vision Framework Overlays
            if viewModel.isVisionEnabled {
                VisionOverlayView(
                    textRegions: viewModel.detectedText,
                    convertRect: viewModel.cameraManager.convertVisionRect
                )
                .allowsHitTesting(false)

                ObjectBoundingBoxView(
                    detectedObjects: viewModel.detectedObjects,
                    imageSize: viewModel.cameraManager.resolution,
                    convertRect: viewModel.cameraManager.convertVisionRect
                )
                .allowsHitTesting(false)

                CaptureGuidanceView(guidance: viewModel.captureGuidance)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // MARK: Loading Spinner
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.5)
            }

            // MARK: Camera Error
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

            // MARK: White Flash
            if viewModel.showFlash {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            // MARK: Focus Indicator
            if viewModel.showFocusIndicator, let point = viewModel.focusPoint {
                FocusIndicatorView()
                    .position(point)
                    .transition(.opacity)
            }

            // MARK: Processing Feedback (US-B2)
            if showProcessingFeedback {
                GeometryReader { geometry in
                    ProcessingFeedbackView(
                        processingCount: viewModel.processingQueue.count,
                        isVisible: $showProcessingFeedback
                    )
                    .position(x: geometry.size.width / 2, y: 200)
                }
                .zIndex(100)
            }

            // MARK: Processing Error
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

            // MARK: Truncation Warning Banner
            if viewModel.showTruncationBanner {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Some books may not have been detected")
                            .font(.subheadline)
                            .foregroundColor(.swissText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                }
                .padding(.top, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(6))
                        withAnimation(.swissSpring) {
                            viewModel.showTruncationBanner = false
                        }
                    }
                }
            }

            // MARK: Segmented Preview Overlay
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
                .padding(.bottom, 160)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // MARK: Scan Complete Banner
            if let banner = viewModel.reviewQueueManager.scanCompleteBanner {
                VStack {
                    Spacer()

                    ScanCompleteBannerView(
                        bookCount: banner.bookCount,
                        thumbnailData: banner.thumbnailData,
                        onTap: {
                            viewModel.reviewQueueManager.dismissScanCompleteBanner()
                            viewModel.requestedTab = 1
                        },
                        onDismiss: {
                            viewModel.reviewQueueManager.dismissScanCompleteBanner()
                        }
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 180)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(99)
            }

            // MARK: Auto-Approve Toast
            if viewModel.reviewQueueManager.showAutoApproveToastFlag,
               let title = viewModel.reviewQueueManager.autoApprovedBookTitle
            {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Added: \(title)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.swissText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .swissGlassCard()
                    .padding(.top, 100)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(98)
            }

            // MARK: Zoom Level + Offline Indicator (top-right)
            VStack {
                HStack {
                    Spacer()

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

            // MARK: Rate Limit Overlay (US-408)
            if viewModel.isRateLimited {
                RateLimitOverlay(
                    remainingSeconds: viewModel.rateLimitCountdown,
                    queuedScansCount: viewModel.queuedScansCount
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // MARK: Camera Interruption Overlay (Task 2.2)
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
    }
}
