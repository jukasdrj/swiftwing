import AVFoundation

/// Camera session manager for SwiftUI
/// AVCaptureSession must be managed on main thread per Apple documentation
@MainActor
class CameraManager: ObservableObject {
    @Published private(set) var captureSession: AVCaptureSession?
    private var isConfigured = false

    /// Configures AVCaptureSession
    /// Performance target: < 0.5s cold start
    func setupSession() throws {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Return if already configured
        if isConfigured, captureSession != nil {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ Camera reused existing session in \(String(format: "%.3f", duration))s")
            return
        }

        let session = AVCaptureSession()

        // Use 30 FPS preset for battery efficiency
        session.sessionPreset = .high

        // Get back camera device
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.noCameraAvailable
        }

        // Configure device input
        let input = try AVCaptureDeviceInput(device: camera)

        session.beginConfiguration()

        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            throw CameraError.cannotAddInput
        }

        session.commitConfiguration()

        self.captureSession = session
        self.isConfigured = true

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        print("✅ Camera session configured in \(String(format: "%.3f", duration))s")
    }

    /// Starts the capture session on background queue (non-blocking)
    func startSession() {
        guard let session = captureSession else { return }

        // Start on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            if !session.isRunning {
                let startTime = CFAbsoluteTimeGetCurrent()
                session.startRunning()
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                print("✅ Camera session started in \(String(format: "%.3f", duration))s")
            }
        }
    }

    /// Stops the capture session
    func stopSession() {
        guard let session = captureSession else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            if session.isRunning {
                session.stopRunning()
                print("⏸️ Camera session stopped")
            }
        }
    }
}

// MARK: - Errors
enum CameraError: LocalizedError {
    case noCameraAvailable
    case cannotAddInput

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable:
            return "No camera device available"
        case .cannotAddInput:
            return "Cannot add camera input to session"
        }
    }
}
