import AVFoundation
import OSLog
import QuartzCore
// Import Vision framework types and service
import Vision

#if canImport(UIKit)
    import UIKit
#endif

private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "camera")

/// Camera session manager for SwiftUI
/// AVCaptureSession must be managed on main thread per Apple documentation
@MainActor
@Observable
final class CameraManager {
    private(set) var captureSession: AVCaptureSession?
    var currentZoomFactor: CGFloat = 1.0
    var resolution: CGSize = .zero
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private(set) var videoDevice: AVCaptureDevice?  // Exposed for RotationCoordinator
    private var isConfigured = false

    // Retain delegates during capture
    private var activeDelegates: [Int64: PhotoCaptureDelegate] = [:]

    // Orientation handling (iOS 17+: Use RotationCoordinator)
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservers = [AnyObject]()
    private weak var previewLayer: AVCaptureVideoPreviewLayer?

    // Interruption handling
    var isInterrupted = false
    private var notificationTasks: [Task<Void, Never>] = []

    // Vision processing (Modernized)
    let frameProcessor = FrameProcessor()
    private let visionService = VisionService()
    var onVisionResult: ((VisionResult) -> Void)?

    // Task to consume video frames
    private var visionTask: Task<Void, Never>?

    /// Session preset
    var sessionPreset: AVCaptureSession.Preset = .high

    /// Update Vision processing rate
    func setProcessingRate(active: Bool) {
        Task {
            await visionService.setProcessingRate(active: active)
        }
    }

    /// Configures AVCaptureSession
    func setupSession() throws {
        let startTime = CFAbsoluteTimeGetCurrent()

        if isConfigured, captureSession != nil {
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = sessionPreset

        guard
            let camera = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .back)
        else {
            throw CameraError.noCameraAvailable
        }

        self.videoDevice = camera
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

            output.isResponsiveCaptureEnabled = output.isResponsiveCaptureSupported
            output.isFastCapturePrioritizationEnabled = output.isFastCapturePrioritizationSupported
            output.maxPhotoQualityPrioritization = .balanced

            // Optimized for Gemini Vision (1024x768 approx)
            let targetDimensions = CMVideoDimensions(width: 1024, height: 768)
            if let closestDimension = camera.activeFormat.supportedMaxPhotoDimensions
                .min(by: {
                    abs($0.width - targetDimensions.width) < abs($1.width - targetDimensions.width)
                })
            {
                output.maxPhotoDimensions = closestDimension
            }
        } else {
            throw CameraError.cannotAddOutput
        }

        // Configure Video Output with AsyncStream Bridge
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true

        // Use FrameProcessor as delegate
        // Note: AVFoundation still requires a serial queue for the delegate callback
        let videoQueue = DispatchQueue(label: "com.swiftwing.videoprocessing", qos: .userInitiated)
        videoOutput.setSampleBufferDelegate(frameProcessor, queue: videoQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            self.videoOutput = videoOutput
        }

        // Start consuming frames
        startVisionTask()

        session.commitConfiguration()
        self.captureSession = session
        self.isConfigured = true

        let format = camera.activeFormat.formatDescription
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        self.resolution = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))

        observeNotifications()

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("Camera session configured in \(String(format: "%.3f", duration), privacy: .public)s")
    }

    /// Consumes the AsyncStream of frames from FrameProcessor.
    /// Vision processing runs on the VisionService actor (off MainActor) to avoid
    /// blocking the UI. CVPixelBuffer is retained before dispatch since AVFoundation
    /// recycles buffers and the original may be overwritten by the next frame.
    private func startVisionTask() {
        visionTask?.cancel()

        visionTask = Task { [weak self] in
            guard let self = self else { return }

            for await frame in self.frameProcessor.frameStream {
                if Task.isCancelled { break }

                // Hold a strong reference to the pixel buffer so ARC keeps it alive
                // while the VisionService actor processes it. AVFoundation may recycle
                // the underlying buffer on the next frame callback, but our strong
                // reference prevents deallocation until processing completes.
                let retainedBuffer = frame.pixelBuffer
                let orientation = frame.orientation

                // Process on VisionService actor (off MainActor)
                let result = await self.visionService.processFrame(
                    retainedBuffer, orientation: orientation)

                // retainedBuffer released by ARC when it goes out of scope

                // Hop back to MainActor for UI update (already on MainActor via self)
                self.onVisionResult?(result)
            }
        }
    }

    func startSession() {
        guard let session = captureSession else { return }
        nonisolated(unsafe) let unsafeSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            if !unsafeSession.isRunning {
                unsafeSession.startRunning()
            }
        }
    }

    func stopSession() {
        guard let session = captureSession else { return }
        visionTask?.cancel()  // Stop processing frames

        rotationObservers.removeAll()
        rotationCoordinator = nil
        notificationTasks.forEach { $0.cancel() }
        notificationTasks.removeAll()

        nonisolated(unsafe) let unsafeSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            if unsafeSession.isRunning {
                unsafeSession.stopRunning()
            }
        }
    }

    func configureRotation(previewLayer: AVCaptureVideoPreviewLayer) {
        // Implementation remains same (RotationCoordinator pattern)
        guard let device = videoDevice else { return }
        self.previewLayer = previewLayer
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(
            device: device, previewLayer: previewLayer)
        guard let coordinator = rotationCoordinator else { return }

        if let previewConnection = previewLayer.connection {
            previewConnection.videoRotationAngle =
                coordinator.videoRotationAngleForHorizonLevelPreview
        }
        if let photoConnection = photoOutput?.connection(with: .video) {
            photoConnection.videoRotationAngle =
                coordinator.videoRotationAngleForHorizonLevelCapture
        }
        if let videoConnection = videoOutput?.connection(with: .video) {
            videoConnection.videoRotationAngle =
                coordinator.videoRotationAngleForHorizonLevelCapture
        }

        rotationObservers.removeAll()
        nonisolated(unsafe) let unsafePreviewLayer = previewLayer
        let previewObserver = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview, options: .new
        ) { _, change in
            guard let newAngle = change.newValue else { return }
            Task { @MainActor in
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.3)
                unsafePreviewLayer.connection?.videoRotationAngle = newAngle
                CATransaction.commit()
            }
        }
        rotationObservers.append(previewObserver)

        let captureObserver = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture, options: .new
        ) { [weak self] _, change in
            guard let self, let newAngle = change.newValue else { return }
            Task { @MainActor in
                if let photoConnection = self.photoOutput?.connection(with: .video) {
                    photoConnection.videoRotationAngle = newAngle
                }
                if let videoConnection = self.videoOutput?.connection(with: .video) {
                    videoConnection.videoRotationAngle = newAngle
                }
            }
        }
        rotationObservers.append(captureObserver)
    }

    /// Convert Vision normalized rect to preview layer view coordinates.
    /// Uses AVCaptureVideoPreviewLayer's native conversion which handles
    /// aspect-fill, rotation, and coordinate system differences automatically.
    ///
    /// - Parameter visionRect: Normalized CGRect from Vision (0-1, bottom-left origin)
    /// - Returns: CGRect in preview layer view coordinates, or nil if previewLayer unavailable
    func convertVisionRect(_ visionRect: CGRect) -> CGRect? {
        guard let previewLayer else { return nil }

        // Vision uses bottom-left origin, AVFoundation uses top-left
        // Flip Y: convert from bottom-left to top-left normalized space
        let flippedRect = CGRect(
            x: visionRect.origin.x,
            y: 1.0 - visionRect.origin.y - visionRect.height,
            width: visionRect.width,
            height: visionRect.height
        )

        // Use native conversion for each corner point
        // layerPointConverted handles aspect-fill scaling and rotation automatically
        let topLeft = previewLayer.layerPointConverted(
            fromCaptureDevicePoint: CGPoint(x: flippedRect.minX, y: flippedRect.minY)
        )
        let bottomRight = previewLayer.layerPointConverted(
            fromCaptureDevicePoint: CGPoint(x: flippedRect.maxX, y: flippedRect.maxY)
        )

        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }

    func capturePhoto() async throws -> Data {
        guard let photoOutput = photoOutput else {
            throw CameraError.photoOutputNotConfigured
        }
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

        return try await withCheckedThrowingContinuation { continuation in
            let uniqueID = settings.uniqueID
            let delegate = PhotoCaptureDelegate { @Sendable [weak self] result in
                continuation.resume(with: result)
                Task { @MainActor [weak self] in
                    self?.activeDelegates[uniqueID] = nil
                }
            }
            activeDelegates[settings.uniqueID] = delegate
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    // Zoom and Focus methods (unchanged)
    func setZoom(_ factor: CGFloat) {
        #if !os(macOS)
            guard let device = videoDevice else { return }
            let clampedFactor = min(max(factor, 1.0), 4.0)
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clampedFactor
                device.unlockForConfiguration()
                currentZoomFactor = clampedFactor
            } catch {
                logger.warning("Failed to configure zoom: \(error.localizedDescription)")
            }
        #endif
    }

    func setFocusPoint(_ point: CGPoint) {
        guard let device = videoDevice, device.isFocusPointOfInterestSupported,
            device.isFocusModeSupported(.autoFocus)
        else { return }
        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus
            if device.isExposurePointOfInterestSupported,
                device.isExposureModeSupported(.autoExpose)
            {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            logger.warning("Failed to configure focus: \(error.localizedDescription)")
        }
    }

    // Notification logic (unchanged)
    private func observeNotifications() {
        // ... (keep existing implementation)
        // For brevity in this write_to_file, I'm assuming we keep the existing observers
        // Re-implementing them here to ensure file completeness

        #if os(iOS)
            let interruptTask = Task { @MainActor [weak self] in
                for await notification in NotificationCenter.default.notifications(
                    named: AVCaptureSession.wasInterruptedNotification)
                {
                    guard let self else { return }
                    if let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey]
                        as AnyObject?,
                        let reasonValue = AVCaptureSession.InterruptionReason(
                            rawValue: reason.integerValue)
                    {
                        self.isInterrupted = [
                            .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient,
                        ].contains(reasonValue)
                    }
                }
            }
            notificationTasks.append(interruptTask)

            let endTask = Task { @MainActor [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: AVCaptureSession.interruptionEndedNotification)
                {
                    self?.isInterrupted = false
                }
            }
            notificationTasks.append(endTask)
        #endif

        let errorTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: AVCaptureSession.runtimeErrorNotification)
            {
                guard let self else { return }
                if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError,
                    error.code == .mediaServicesWereReset
                {
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
    private let completion: @Sendable (Result<Data, Error>) -> Void
    init(completion: @escaping @Sendable (Result<Data, Error>) -> Void) { self.completion = completion }
    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
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

// MARK: - Frame Processor Delegate (Concurrency Bridge)

/// Sendable wrapper for video frame data
/// CVPixelBuffer is thread-safe for read-only access, so @unchecked Sendable is appropriate
struct VideoFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let orientation: CGImagePropertyOrientation
}

/// Bridge between AVCaptureVideoDataOutput and AsyncStream
/// Captures frames and yields them to the stream
final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable
{

    // Stream of video frames (PixelBuffer + Orientation)
    let frameStream: AsyncStream<VideoFrame>
    private let continuation: AsyncStream<VideoFrame>.Continuation

    override init() {
        // Initialize the stream with BufferingNewest(1) to drop old frames if processing lags
        let (stream, continuation) = AsyncStream.makeStream(of: VideoFrame.self, bufferingPolicy: .bufferingNewest(1))
        self.frameStream = stream
        self.continuation = continuation
        super.init()
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let orientation = CGImagePropertyOrientation(from: connection.videoRotationAngle)

        // Yield to stream - this is non-blocking
        // Wrap in Sendable struct to satisfy Swift 6.2 concurrency
        continuation.yield(VideoFrame(pixelBuffer: pixelBuffer, orientation: orientation))
    }

    func captureOutput(
        _ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // No-op
    }
}

// MARK: - Orientation Conversion (Unchanged)
extension CGImagePropertyOrientation {
    init(from videoRotationAngle: CGFloat) {
        switch videoRotationAngle {
        case 0: self = .right
        case 90: self = .up
        case 180: self = .left
        case 270: self = .down
        default: self = .up
        }
    }
}

// MARK: - Errors (Unchanged)
enum CameraError: LocalizedError {
    case noCameraAvailable, cannotAddInput, cannotAddOutput, photoOutputNotConfigured,
        visionProcessingFailed

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable: return "No camera device available"
        case .cannotAddInput: return "Cannot add camera input to session"
        case .cannotAddOutput: return "Cannot add photo output to session"
        case .photoOutputNotConfigured: return "Photo output not configured"
        case .visionProcessingFailed: return "Vision framework processing failed"
        }
    }
}
