import AVFoundation
import OSLog
import QuartzCore

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

    /// True when focus and exposure are pinned via toggleExposureFocusLock().
    private(set) var isExposureFocusLocked = false

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

    /// Session preset
    var sessionPreset: AVCaptureSession.Preset = .high

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
            // Tapping to refocus overrides a manual lock. Cleared only after the
            // device actually took the new mode, so the flag can't desync.
            isExposureFocusLocked = false
        } catch {
            logger.warning("Failed to configure focus: \(error.localizedDescription)")
        }
    }

    /// Pin or release focus + exposure. Locking holds the current values so a
    /// burst of shelf captures doesn't re-hunt focus between frames.
    func toggleExposureFocusLock() {
        guard let device = videoDevice else { return }
        let shouldLock = !isExposureFocusLocked
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if shouldLock {
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            } else {
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
            }
            isExposureFocusLocked = shouldLock
        } catch {
            logger.warning("Failed to toggle AE/AF lock: \(error.localizedDescription)")
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

// MARK: - Errors
enum CameraError: LocalizedError {
    case noCameraAvailable, cannotAddInput, cannotAddOutput, photoOutputNotConfigured

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable: return "No camera device available"
        case .cannotAddInput: return "Cannot add camera input to session"
        case .cannotAddOutput: return "Cannot add photo output to session"
        case .photoOutputNotConfigured: return "Photo output not configured"
        }
    }
}
