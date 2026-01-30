@preconcurrency import AVFoundation
import UIKit

/// Camera session manager for SwiftUI
/// AVCaptureSession must be managed on main thread per Apple documentation
@MainActor
class CameraManager: ObservableObject {
    @Published private(set) var captureSession: AVCaptureSession?
    @Published var currentZoomFactor: CGFloat = 1.0
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var videoDevice: AVCaptureDevice?
    private var isConfigured = false

    // Retain delegates during capture (AVCapturePhotoOutput does not retain them)
    private var activeDelegates: [Int64: PhotoCaptureDelegate] = [:]

    // Vision processing
    let frameProcessor = FrameProcessor() // Exposed for adaptive throttling control
    private let videoProcessingQueue = DispatchQueue(label: "com.swiftwing.videoprocessing", qos: .userInitiated)
    var onVisionResult: ((VisionResult) -> Void)?

    /// Session preset for camera quality (default: .high for 30 FPS battery efficiency)
    /// Can be overridden to .photo for higher quality or .medium for lower resource usage
    var sessionPreset: AVCaptureSession.Preset = .high

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

        // Use configurable preset (default: .high for 30 FPS battery efficiency)
        session.sessionPreset = sessionPreset

        // Get back camera device
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.noCameraAvailable
        }

        // Store reference for zoom/focus control
        self.videoDevice = camera

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

        // Add video data output for Vision processing
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(frameProcessor, queue: videoProcessingQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            self.videoOutput = videoOutput
        }

        // Wire frame processor callback
        frameProcessor.onFrameProcessed = { [weak self] result in
            Task { @MainActor in
                self?.onVisionResult?(result)
            }
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
        // AVCaptureSession is not Sendable but is thread-safe for startRunning()
        nonisolated(unsafe) let unsafeSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            if !unsafeSession.isRunning {
                let startTime = CFAbsoluteTimeGetCurrent()
                unsafeSession.startRunning()
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                print("✅ Camera session started in \(String(format: "%.3f", duration))s")
            }
        }
    }

    /// Stops the capture session
    func stopSession() {
        guard let session = captureSession else { return }

        // AVCaptureSession is not Sendable but is thread-safe for stopRunning()
        nonisolated(unsafe) let unsafeSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            if unsafeSession.isRunning {
                unsafeSession.stopRunning()
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

        // Set photo orientation from effectiveGeometry (iOS 26 API)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let orientation = windowScene.effectiveGeometry.interfaceOrientation

            // Map UIInterfaceOrientation to video rotation angle
            let rotationAngle: CGFloat
            switch orientation {
            case .portrait:
                rotationAngle = 90
            case .portraitUpsideDown:
                rotationAngle = 270
            case .landscapeLeft:
                rotationAngle = 180
            case .landscapeRight:
                rotationAngle = 0
            case .unknown:
                rotationAngle = 90
            @unknown default:
                rotationAngle = 90
            }

            // Set rotation on photo connection
            if let photoConnection = photoOutput.connection(with: .video) {
                if photoConnection.isVideoRotationAngleSupported(rotationAngle) {
                    photoConnection.videoRotationAngle = rotationAngle
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate { [weak self] result in
                continuation.resume(with: result)
                // Release delegate
                self?.activeDelegates[settings.uniqueID] = nil
            }
            
            // Retain delegate
            activeDelegates[settings.uniqueID] = delegate

            // Keep delegate alive until capture completes
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    /// Sets zoom level (1.0x to 4.0x)
    /// Persists zoom level during session
    func setZoom(_ factor: CGFloat) {
        guard let device = videoDevice else { return }

        // Clamp zoom to 1.0x - 4.0x range
        let clampedFactor = min(max(factor, 1.0), 4.0)

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampedFactor
            device.unlockForConfiguration()

            // Update published property for UI
            currentZoomFactor = clampedFactor
        } catch {
            print("❌ Failed to set zoom: \(error)")
        }
    }

    /// Sets focus point at normalized coordinates (0.0-1.0)
    /// Point is in camera coordinate space (not view coordinates)
    func setFocusPoint(_ point: CGPoint) {
        guard let device = videoDevice else { return }

        // Check if device supports focus point of interest
        guard device.isFocusPointOfInterestSupported,
              device.isFocusModeSupported(.autoFocus) else {
            return
        }

        do {
            try device.lockForConfiguration()

            // Set focus point (coordinates are normalized 0.0-1.0)
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus

            // Also set exposure point for better overall image
            if device.isExposurePointOfInterestSupported,
               device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }

            device.unlockForConfiguration()
        } catch {
            print("❌ Failed to set focus point: \(error)")
        }
    }

    /// Enables or disables Vision processing on video frames
    func setVisionEnabled(_ enabled: Bool) {
        videoOutput?.connection(with: .video)?.isEnabled = enabled
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

// MARK: - Frame Processor Delegate

/// Bridge between AVCaptureVideoDataOutput and VisionService
/// - Note: @unchecked Sendable is required because AVCaptureVideoDataOutputSampleBufferDelegate
///   is an Objective-C protocol that cannot express Sendable. This is safe because:
///   (a) no mutable shared state (visionService is let, onFrameProcessed set once)
///   (b) all callbacks dispatched to single serial DispatchQueue
///   (c) standard Apple pattern for AVFoundation delegates in Swift 6.2
final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onFrameProcessed: ((VisionResult) -> Void)?
    let visionService = VisionService() // Exposed for adaptive throttling control

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Throttle processing
        guard visionService.shouldProcessFrame() else { return }

        // Extract CVPixelBuffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Determine orientation from connection
        let orientation: CGImagePropertyOrientation = .up // TODO: Map from videoRotationAngle

        // Process frame
        let result = visionService.processFrame(pixelBuffer, orientation: orientation)

        // Invoke callback
        onFrameProcessed?(result)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("[Vision] Frame dropped")
    }
}

// MARK: - Errors
enum CameraError: LocalizedError {
    case noCameraAvailable
    case cannotAddInput
    case cannotAddOutput
    case photoOutputNotConfigured
    case visionProcessingFailed

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
        case .visionProcessingFailed:
            return "Vision framework processing failed"
        }
    }
}
