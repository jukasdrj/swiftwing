import SwiftUI
import AVFoundation

/// Main camera view with zero-lag preview
/// Performance target: < 0.5s cold start to live feed
struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var coldStartTime: CFAbsoluteTime = 0

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
}

#Preview {
    CameraView()
        .preferredColorScheme(.dark)
}
