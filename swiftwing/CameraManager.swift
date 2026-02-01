import AVFoundation

#if canImport(UIKit)
import UIKit
#endif

// Import Vision framework types and service
import Vision

/// Camera session manager for SwiftUI
/// AVCaptureSession must be managed on main thread per Apple documentation
@MainActor
class CameraManager: ObservableObject {
    @Published private(set) var captureSession: AVCaptureSession?
    @Published var currentZoomFactor: CGFloat = 1.0
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private(set) var videoDevice: AVCaptureDevice?  // Exposed for RotationCoordinator
    private var isConfigured = false

    // Retain delegates during capture (AVCapturePhotoOutput does not retain them)
    private var activeDelegates: [Int64: PhotoCaptureDelegate] = [:]

    // Orientation handling (iOS 17+: Use RotationCoordinator instead of manual orientation)
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservers = [AnyObject]()

    // Interruption handling
    @Published var isInterrupted = false
    private var notificationTasks: [Task<Void, Never>] = []

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

            // Configure iOS 26 performance features
            output.isResponsiveCaptureEnabled = output.isResponsiveCaptureSupported
            output.isFastCapturePrioritizationEnabled = output.isFastCapturePrioritizationSupported
            output.maxPhotoQualityPrioritization = .balanced  // Balance speed and quality for book scanning

            // Configure optimal resolution for Gemini Vision API token efficiency
            // Target: 1024×768 provides sufficient detail for book spine OCR
            // while minimizing Gemini token usage (2 tiles = 516 tokens vs 3000-12000 at full res)
            let targetDimensions = CMVideoDimensions(width: 1024, height: 768)

            // Find closest supported dimension
            if let closestDimension = camera.activeFormat.supportedMaxPhotoDimensions
                .min(by: { abs($0.width - targetDimensions.width) < abs($1.width - targetDimensions.width) }) {
                output.maxPhotoDimensions = closestDimension
                print("📐 Photo output configured: \(closestDimension.width)×\(closestDimension.height) (optimized for Gemini Vision API)")
            }
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

            // iOS 17+: Rotation coordinator will be configured after preview layer is ready
            // See configureRotation(previewLayer:) called from CameraViewModel
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

        // Observe session notifications for interruption handling
        observeNotifications()

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        print("✅ Camera session configured in \(String(format: "%.3f", duration))s")
    }

    /// Starts the capture session on background queue (non-blocking)
    func startSession() {
        guard let session = captureSession else { return }

        // iOS 17+: Rotation handled by RotationCoordinator, no manual observer needed

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

        // Clean up rotation coordinator and KVO observers
        rotationObservers.removeAll()
        rotationCoordinator = nil

        // Cancel notification observation tasks
        notificationTasks.forEach { $0.cancel() }
        notificationTasks.removeAll()

        // AVCaptureSession is not Sendable but is thread-safe for stopRunning()
        nonisolated(unsafe) let unsafeSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            if unsafeSession.isRunning {
                unsafeSession.stopRunning()
                print("⏸️ Camera session stopped")
            }
        }
    }

    /// Configure rotation coordinator with connected preview layer and KVO observers
    /// Must be called after preview layer is available (from CameraViewModel)
    /// Reference: AVCam sample code (CaptureService.swift lines 368-406)
    func configureRotation(previewLayer: AVCaptureVideoPreviewLayer) {
        guard let device = videoDevice else { return }

        // Create rotation coordinator with connected preview layer
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: previewLayer
        )

        guard let coordinator = rotationCoordinator else { return }

        // Set initial rotation state on connections
        if let previewConnection = previewLayer.connection {
            previewConnection.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
        }

        if let photoConnection = photoOutput?.connection(with: .video) {
            photoConnection.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
        }

        if let videoConnection = videoOutput?.connection(with: .video) {
            videoConnection.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
        }

        // Cancel previous observations
        rotationObservers.removeAll()

        // Observe preview rotation angle changes
        let previewObserver = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: .new
        ) { [weak self] _, change in
            guard let self, let newAngle = change.newValue else { return }
            Task { @MainActor in
                previewLayer.connection?.videoRotationAngle = newAngle
            }
        }
        rotationObservers.append(previewObserver)

        // Observe capture rotation angle changes
        let captureObserver = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: .new
        ) { [weak self] _, change in
            guard let self, let newAngle = change.newValue else { return }
            Task { @MainActor in
                // Update photo output connection
                if let photoConnection = self.photoOutput?.connection(with: .video) {
                    photoConnection.videoRotationAngle = newAngle
                }

                // Update video output connection (for Vision processing)
                if let videoConnection = self.videoOutput?.connection(with: .video) {
                    videoConnection.videoRotationAngle = newAngle
                }
            }
        }
        rotationObservers.append(captureObserver)

        print("📱 Rotation coordinator configured with \(rotationObservers.count) KVO observers")
    }

    /// Captures a photo and returns the image data
    /// Must be called from main actor since photoOutput is @MainActor
    func capturePhoto() async throws -> Data {
        guard let photoOutput = photoOutput else {
            throw CameraError.photoOutputNotConfigured
        }

        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced

        // Use configured photo dimensions (optimized for Gemini Vision API)
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

        // Rotation is now handled automatically by RotationCoordinator's KVO observers
        // No manual orientation setup needed - the coordinator keeps connections up-to-date

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
        #if !os(macOS)
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
        #endif
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

    // MARK: - Notification Observation
    /// Observe session notifications for interruption handling
    private func observeNotifications() {
        // Interruption started
        let interruptTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: AVCaptureSession.wasInterruptedNotification
            ) {
                guard let self else { return }
                if let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
                   let reasonValue = AVCaptureSession.InterruptionReason(rawValue: reason.integerValue) {
                    self.isInterrupted = [.audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient].contains(reasonValue)
                }
            }
        }
        notificationTasks.append(interruptTask)

        // Interruption ended
        let endTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: AVCaptureSession.interruptionEndedNotification
            ) {
                self?.isInterrupted = false
            }
        }
        notificationTasks.append(endTask)

        // Runtime error (media services reset)
        let errorTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: AVCaptureSession.runtimeErrorNotification
            ) {
                guard let self else { return }
                if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError,
                   error.code == .mediaServicesWereReset {
                    if let session = self.captureSession, !session.isRunning {
                        self.startSession()
                    }
                }
            }
        }
        notificationTasks.append(errorTask)
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
        let orientation = CGImagePropertyOrientation(from: connection.videoRotationAngle)

        // Process frame
        let result = visionService.processFrame(pixelBuffer, orientation: orientation)

        // Invoke callback
        onFrameProcessed?(result)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("[Vision] Frame dropped")
    }
}

// MARK: - Orientation Conversion

extension CGImagePropertyOrientation {
    /// Convert AVCaptureConnection videoRotationAngle to CGImagePropertyOrientation
    init(from videoRotationAngle: CGFloat) {
        // videoRotationAngle:
        // 0° = landscapeRight (home button right)
        // 90° = portrait (home button bottom)
        // 180° = landscapeLeft (home button left)
        // 270° = portraitUpsideDown (home button top)
        switch videoRotationAngle {
        case 0:
            self = .right      // landscapeRight
        case 90:
            self = .up         // portrait
        case 180:
            self = .left       // landscapeLeft
        case 270:
            self = .down       // portraitUpsideDown
        default:
            self = .up         // Default to portrait
        }
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
