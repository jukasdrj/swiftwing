import AVFoundation

/// Camera session manager for SwiftUI
/// AVCaptureSession must be managed on main thread per Apple documentation
@MainActor
class CameraManager: ObservableObject {
    @Published private(set) var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
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

        // Configure photo output
        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            self.photoOutput = output
        } else {
            throw CameraError.cannotAddOutput
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

    /// Captures a photo and returns the image data
    /// Must be called from main actor since photoOutput is @MainActor
    func capturePhoto() async throws -> Data {
        guard let photoOutput = photoOutput else {
            throw CameraError.photoOutputNotConfigured
        }

        let settings = AVCapturePhotoSettings()

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate { result in
                continuation.resume(with: result)
            }

            // Keep delegate alive until capture completes
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

// MARK: - Photo Capture Delegate
private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, Error>) -> Void

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            completion(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CameraError.photoOutputNotConfigured))
            return
        }

        completion(.success(data))
    }
}

// MARK: - Errors
enum CameraError: LocalizedError {
    case noCameraAvailable
    case cannotAddInput
    case cannotAddOutput
    case photoOutputNotConfigured

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable:
            return "No camera device available"
        case .cannotAddInput:
            return "Cannot add camera input to session"
        case .cannotAddOutput:
            return "Cannot add photo output to session"
        case .photoOutputNotConfigured:
            return "Photo output not configured"
        }
    }
}
