import SwiftUI
import AVFoundation
import UIKit
import Combine

/// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
/// Displays live camera feed with edge-to-edge layout
/// Uses AVCaptureDevice.RotationCoordinator for automatic orientation handling (iOS 17+)
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let onZoomChange: (CGFloat) -> Void
    let onFocusTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill

        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer

        // Add pinch gesture for zoom
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)

        // Add tap gesture for focus
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        // Setup rotation coordinator when session starts running
        context.coordinator.setupRotationCoordinator()

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame to match view bounds
        if let previewLayer = context.coordinator.previewLayer {
            previewLayer.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onZoomChange: onZoomChange, onFocusTap: onFocusTap)
    }

    @MainActor
    class Coordinator: NSObject {
        var previewLayer: AVCaptureVideoPreviewLayer?
        let session: AVCaptureSession
        let onZoomChange: (CGFloat) -> Void
        let onFocusTap: (CGPoint) -> Void
        private var baseZoomFactor: CGFloat = 1.0
        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?

        init(session: AVCaptureSession, onZoomChange: @escaping (CGFloat) -> Void, onFocusTap: @escaping (CGPoint) -> Void) {
            self.session = session
            self.onZoomChange = onZoomChange
            self.onFocusTap = onFocusTap
            super.init()
        }

        deinit {
            rotationObservation?.invalidate()
        }

        /// Setup AVCaptureDevice.RotationCoordinator for automatic orientation handling
        /// Called after preview layer is created
        func setupRotationCoordinator() {
            // Wait for session to be running and device to be available
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }

                // Poll until session is running (max 2 seconds)
                var attempts = 0
                while !self.session.isRunning && attempts < 20 {
                    Thread.sleep(forTimeInterval: 0.1)
                    attempts += 1
                }

                guard self.session.isRunning else {
                    print("⚠️ Session not running after 2s - rotation coordinator setup failed")
                    return
                }

                // Get video device from session input
                guard let videoInput = self.session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.hasMediaType(.video) }),
                      let previewLayer = self.previewLayer else {
                    print("⚠️ Could not find video device for rotation coordinator")
                    return
                }

                let device = videoInput.device

                Task { @MainActor in
                    // Create rotation coordinator
                    let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
                    self.rotationCoordinator = coordinator

                    // Apply initial rotation
                    if let connection = previewLayer.connection {
                        connection.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
                        print("📱 Initial rotation set: \(coordinator.videoRotationAngleForHorizonLevelPreview)°")
                    }

                    // Observe rotation changes
                    self.rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] coordinator, change in
                        guard let self,
                              let previewLayer = self.previewLayer,
                              let connection = previewLayer.connection,
                              let newAngle = change.newValue else {
                            return
                        }

                        Task { @MainActor in
                            CATransaction.begin()
                            CATransaction.setAnimationDuration(0.3)
                            CATransaction.setDisableActions(false)
                            connection.videoRotationAngle = newAngle
                            CATransaction.commit()

                            print("📱 Rotation updated: \(newAngle)°")
                        }
                    }
                }
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                // baseZoomFactor is already set from previous gesture or initialized to 1.0
                break

            case .changed:
                // Calculate new zoom factor (1.0x to 4.0x)
                let newZoom = baseZoomFactor * gesture.scale
                let clampedZoom = min(max(newZoom, 1.0), 4.0)
                onZoomChange(clampedZoom)

            case .ended, .cancelled:
                // Update base zoom for next gesture
                let finalZoom = baseZoomFactor * gesture.scale
                baseZoomFactor = min(max(finalZoom, 1.0), 4.0)

            default:
                break
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let previewLayer = previewLayer else { return }

            // Get tap location in view coordinates
            let tapPoint = gesture.location(in: gesture.view)

            // Convert to camera coordinates (normalized 0.0-1.0)
            // Preview layer uses different coordinate system
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: tapPoint)

            onFocusTap(devicePoint)
        }
    }
}
