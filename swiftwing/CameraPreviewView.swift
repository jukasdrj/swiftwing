import SwiftUI
import AVFoundation
import UIKit
import Combine

/// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
/// Displays live camera feed with edge-to-edge layout
/// Rotation is handled by AVCaptureDevice.RotationCoordinator with KVO observers
/// Uses backing layer pattern (layer IS the preview layer, not a sublayer)
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let onZoomChange: (CGFloat) -> Void
    let onFocusTap: (CGPoint) -> Void
    let onPreviewLayerReady: (AVCaptureVideoPreviewLayer) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black

        // Configure preview layer (it IS the backing layer)
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        // Store reference in coordinator for gesture handling
        context.coordinator.previewView = view

        // Add pinch gesture for zoom
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)

        // Add tap gesture for focus
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        // Notify that preview layer is ready for rotation coordinator
        DispatchQueue.main.async {
            onPreviewLayerReady(view.previewLayer)
        }

        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Automatic frame sizing - no manual updates needed with backing layer
    }

    /// A UIView subclass where the layer IS the AVCaptureVideoPreviewLayer
    /// This matches AVCam's pattern for efficient, automatic layout
    class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            session: session,
            onZoomChange: onZoomChange,
            onFocusTap: onFocusTap
        )
    }

    @MainActor
    class Coordinator: NSObject {
        weak var previewView: PreviewView?
        let session: AVCaptureSession
        let onZoomChange: (CGFloat) -> Void
        let onFocusTap: (CGPoint) -> Void
        private var baseZoomFactor: CGFloat = 1.0

        init(session: AVCaptureSession, onZoomChange: @escaping (CGFloat) -> Void, onFocusTap: @escaping (CGPoint) -> Void) {
            self.session = session
            self.onZoomChange = onZoomChange
            self.onFocusTap = onFocusTap
            super.init()
        }

        /// Expose preview layer for CameraManager access
        var previewLayer: AVCaptureVideoPreviewLayer? {
            previewView?.previewLayer
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
