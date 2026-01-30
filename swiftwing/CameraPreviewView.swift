import SwiftUI
import AVFoundation
import UIKit
import Combine

/// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
/// Displays live camera feed with edge-to-edge layout
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

        // Set initial rotation based on current orientation
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            context.coordinator.updateRotation(for: windowScene.effectiveGeometry.interfaceOrientation)
        }

        // Add pinch gesture for zoom
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)

        // Add tap gesture for focus
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        // Defer geometry observation until view is in window hierarchy
        DispatchQueue.main.async {
            context.coordinator.observeGeometryChanges(for: view)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame to match view bounds
        DispatchQueue.main.async {
            if let previewLayer = context.coordinator.previewLayer {
                previewLayer.frame = uiView.bounds
                // Update rotation when bounds change (handles rotation)
                if let windowScene = uiView.window?.windowScene {
                    context.coordinator.updateRotation(for: windowScene.effectiveGeometry.interfaceOrientation)
                }
            }
        }
    }



    func makeCoordinator() -> Coordinator {
        Coordinator(onZoomChange: onZoomChange, onFocusTap: onFocusTap)
    }

    @MainActor
    class Coordinator: NSObject {
        var previewLayer: AVCaptureVideoPreviewLayer?
        let onZoomChange: (CGFloat) -> Void
        let onFocusTap: (CGPoint) -> Void
        private var baseZoomFactor: CGFloat = 1.0
        private var cancellables = Set<AnyCancellable>()

        init(onZoomChange: @escaping (CGFloat) -> Void, onFocusTap: @escaping (CGPoint) -> Void) {
            self.onZoomChange = onZoomChange
            self.onFocusTap = onFocusTap
            super.init()
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

        /// Observe device orientation changes using NotificationCenter
        /// (KVO on effectiveGeometry.interfaceOrientation is not supported)
        nonisolated func observeGeometryChanges(for view: UIView) {
            // Use NotificationCenter instead of KVO to avoid crash
            NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self, weak view] in
                    guard let self, let view, let windowScene = view.window?.windowScene else { return }
                    self.updateRotation(for: windowScene.effectiveGeometry.interfaceOrientation)
                }
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func updateRotation(for orientation: UIInterfaceOrientation) {
            guard let previewLayer = previewLayer,
                  let connection = previewLayer.connection else { return }

            // Map interface orientation to video rotation angle
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

            // Animate rotation change
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            connection.videoRotationAngle = rotationAngle
            CATransaction.commit()

            print("📱 effectiveGeometry orientation changed - video rotation: \(rotationAngle)°")
        }
    }
}
