import SwiftUI
import AVFoundation
import UIKit

/// Main camera view with zero-lag preview
/// Performance target: < 0.5s cold start to live feed
struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var coldStartTime: CFAbsoluteTime = 0
    @State private var showFlash = false
    @State private var processingQueue: [ProcessingItem] = []
    @State private var focusPoint: CGPoint?
    @State private var showFocusIndicator = false

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
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.swissText)

                    Text(error)
                        .font(.system(size: 15))
                        .foregroundColor(.swissText.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
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

            // Zoom level display (top-right corner)
            VStack {
                HStack {
                    Spacer()

                    Text(String(format: "%.1fx", cameraManager.currentZoomFactor))
                        .font(.custom("JetBrainsMono-Regular", size: 16))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(.top, 60)
                        .padding(.trailing, 16)
                }

                Spacer()
            }

            // Shutter button + Processing Queue
            VStack {
                Spacer()

                // Processing queue (40px height above shutter)
                ProcessingQueueView(items: processingQueue)
                    .padding(.bottom, 8)

                // Shutter button (80x80px white ring at bottom center)
                Button(action: captureImage) {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                        .contentShape(Circle())
                }
                .sensoryFeedback(.impact, trigger: showFlash)
                .padding(.bottom, 40)
            }
        }
        .statusBar(hidden: true) // Full immersion
        .task {
            await setupCamera()
        }
        .onDisappear {
            cameraManager.stopSession()
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
    private func captureImage() {
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
        Task.detached(priority: .userInitiated) {
            await self.processCapture()
        }
    }

    /// Processes the captured image (runs in parallel)
    /// Performance target: < 500ms
    private func processCapture() async {
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            // Capture photo from camera (must be on main actor)
            let imageData = try await cameraManager.capturePhoto()
            print("📸 Image captured (\(imageData.count) bytes)")

            // Add to processing queue immediately with thumbnail
            let queueItem = await addToQueue(imageData: imageData)

            // Process image: resize + compress + save
            // This runs off main thread via Task.detached
            let fileURL = try await Self.processImage(imageData)

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ Image processed in \(String(format: "%.3f", duration))s (target: < 0.5s)")
            print("📁 Saved to: \(fileURL.path)")

            if duration >= 0.5 {
                print("⚠️ WARNING: Image processing exceeded 0.5s target!")
            }

            // Update to done state
            await updateQueueItemState(id: queueItem.id, state: .done)

            // Auto-remove after 5 seconds
            await removeQueueItemAfterDelay(id: queueItem.id, delay: 5.0)

        } catch {
            print("❌ Image processing failed: \(error)")
        }
    }

    /// Adds item to processing queue and returns the item
    @MainActor
    private func addToQueue(imageData: Data) -> ProcessingItem {
        let item = ProcessingItem(imageData: imageData, state: .processing)
        withAnimation(.spring(duration: 0.2)) {
            processingQueue.append(item)
        }
        return item
    }

    /// Updates queue item state
    @MainActor
    private func updateQueueItemState(id: UUID, state: ProcessingItem.ProcessingState) {
        if let index = processingQueue.firstIndex(where: { $0.id == id }) {
            withAnimation(.spring(duration: 0.2)) {
                processingQueue[index].state = state
            }
        }
    }

    /// Removes item from queue after delay
    @MainActor
    private func removeQueueItemAfterDelay(id: UUID, delay: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        withAnimation(.spring(duration: 0.2)) {
            processingQueue.removeAll { $0.id == id }
        }
    }

    /// Processes image data: resize to max 1920px, compress to JPEG 0.85, save to temp directory
    /// Returns file URL for upload
    /// Performance target: < 500ms
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
        let screenSize = UIScreen.main.bounds.size
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
