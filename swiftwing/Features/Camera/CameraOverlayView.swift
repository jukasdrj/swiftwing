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
            visionOverlays
            feedbackOverlays
            bannerOverlays
            statusOverlays
        }
    }

    // MARK: - Vision Framework Overlays

    @ViewBuilder
    private var visionOverlays: some View {
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
    }

    // MARK: - Loading, Error, Flash, Focus, Processing Overlays

    @ViewBuilder
    private var feedbackOverlays: some View {
        // Loading Spinner
        if viewModel.isLoading {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.5)
        }

        // Camera Error
        if let error = viewModel.errorMessage {
            VStack(spacing: 16) {
                Text("Camera Error")
                    .font(.title3.bold())
                    .foregroundStyle(.swissText)
                    .dynamicTypeSize(.xSmall ... .accessibility3)

                Text(error)
                    .font(.body)
                    .foregroundStyle(.swissText.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .dynamicTypeSize(.xSmall ... .accessibility3)
            }
            .padding()
            .swissGlassCard()
            .padding(24)
        }

        // White Flash
        if viewModel.showFlash {
            Color.white
                .ignoresSafeArea()
                .transition(.opacity)
        }

        // Focus Indicator
        if viewModel.showFocusIndicator, let point = viewModel.focusPoint {
            FocusIndicatorView()
                .position(point)
                .transition(.opacity)
        }

        // Processing Feedback (US-B2)
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

        // Processing Error
        if viewModel.showProcessingError, let error = viewModel.processingErrorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.swissError)

                Text("Processing Failed")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.swissText)
                    .dynamicTypeSize(.xSmall ... .accessibility3)

                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.swissText.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .dynamicTypeSize(.xSmall ... .accessibility3)
            }
            .padding(24)
            .swissGlassCard()
            .padding(.horizontal, 32)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }

        // Camera Interruption Overlay (Task 2.2)
        if viewModel.isInterrupted {
            VStack(spacing: 12) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)

                VStack(spacing: 8) {
                    Text("Camera Interrupted")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.swissText)
                        .dynamicTypeSize(.xSmall ... .accessibility3)

                    Text("Phone call or FaceTime in progress")
                        .font(.subheadline)
                        .foregroundStyle(.swissText.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .dynamicTypeSize(.xSmall ... .accessibility3)
                }
            }
            .padding(24)
            .swissGlassCard()
            .padding(.horizontal, 32)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    // MARK: - Truncation, Segmented, Scan Complete, Auto-Approve, Rate Limit Banners

    @ViewBuilder
    private var bannerOverlays: some View {
        // Truncation Warning Banner
        if viewModel.showTruncationBanner {
            VStack {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Some books may not have been detected")
                        .font(.subheadline)
                        .foregroundStyle(.swissText)
                        .dynamicTypeSize(.xSmall ... .accessibility3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(.rect(cornerRadius: 12))
            }
            .padding(.top, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task {
                try? await Task.sleep(for: .seconds(6))
                withAnimation(.swissSpring) {
                    viewModel.showTruncationBanner = false
                }
            }
        }

        // Segmented Preview Overlay
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

        // Scan Complete Banner
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

        // Auto-Approve Toast
        if viewModel.reviewQueueManager.showAutoApproveToastFlag,
           let title = viewModel.reviewQueueManager.autoApprovedBookTitle
        {
            VStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Added: \(title)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.swissText)
                        .lineLimit(1)
                        .dynamicTypeSize(.xSmall ... .accessibility3)
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

        // Rate Limit Overlay (US-408)
        if viewModel.isRateLimited {
            RateLimitOverlay(
                remainingSeconds: viewModel.rateLimitCountdown,
                queuedScansCount: viewModel.queuedScansCount
            )
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    // MARK: - Zoom Level + Offline Indicator

    @ViewBuilder
    private var statusOverlays: some View {
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
                    .foregroundStyle(.white)
                    .dynamicTypeSize(.xSmall ... .accessibility3)
                    .swissGlassOverlay()
                    .padding(.top, 60)
                    .padding(.trailing, 16)
            }

            Spacer()
        }
    }
}
