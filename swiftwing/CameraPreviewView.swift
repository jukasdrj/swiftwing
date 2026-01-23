import SwiftUI
import AVFoundation
import UIKit

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
        previewLayer.connection?.videoRotationAngle = 90

        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer

        // Add pinch gesture for zoom
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)

        // Add tap gesture for focus
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame to match view bounds
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onZoomChange: onZoomChange, onFocusTap: onFocusTap)
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
        let onZoomChange: (CGFloat) -> Void
        let onFocusTap: (CGPoint) -> Void
        private var baseZoomFactor: CGFloat = 1.0

        init(onZoomChange: @escaping (CGFloat) -> Void, onFocusTap: @escaping (CGPoint) -> Void) {
            self.onZoomChange = onZoomChange
            self.onFocusTap = onFocusTap
        }

        @MainActor
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

        @MainActor
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
