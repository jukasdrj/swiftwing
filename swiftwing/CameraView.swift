import SwiftUI
import AVFoundation

/// Main camera view with zero-lag preview
/// Performance target: < 0.5s cold start to live feed
struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var coldStartTime: CFAbsoluteTime = 0
    @State private var showFlash = false

    var body: some View {
        ZStack {
            // Camera preview (edge-to-edge)
            if let session = cameraManager.captureSession {
                CameraPreviewView(session: session)
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

            // Shutter button (80x80px white ring at bottom center)
            VStack {
                Spacer()

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

        // TODO: Actual image capture logic will be added in next story
        // For now, just simulate processing
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms simulation

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        print("📸 Image processed in \(String(format: "%.3f", duration))s")
    }
}

#Preview {
    CameraView()
        .preferredColorScheme(.dark)
}
