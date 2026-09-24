import AVFoundation
import CoreGraphics
import Foundation
import Vision

struct LiveTextObservation: Sendable, Identifiable {
    let id: UUID
    let text: String
    /// Vision normalized rect. Origin is the bottom left of the upright frame.
    let visionBottomLeft: CGRect
}

/// Maps a Vision rect onto the aspect-filled camera preview.
enum LiveTextGeometry {
    static func overlayRect(
        visionBottomLeft: CGRect,
        frameAspect: CGFloat,
        viewAspect: CGFloat
    ) -> CGRect {
        let upright = CGRect(
            x: visionBottomLeft.origin.x,
            y: 1 - visionBottomLeft.origin.y - visionBottomLeft.height,
            width: visionBottomLeft.width,
            height: visionBottomLeft.height
        )
        guard frameAspect > 0, viewAspect > 0, frameAspect != viewAspect else {
            return upright
        }

        if frameAspect > viewAspect {
            let visibleWidth = viewAspect / frameAspect
            let cropX = (1 - visibleWidth) / 2
            return CGRect(
                x: (upright.origin.x - cropX) / visibleWidth,
                y: upright.origin.y,
                width: upright.width / visibleWidth,
                height: upright.height
            )
        }

        let visibleHeight = frameAspect / viewAspect
        let cropY = (1 - visibleHeight) / 2
        return CGRect(
            x: upright.origin.x,
            y: (upright.origin.y - cropY) / visibleHeight,
            width: upright.width,
            height: upright.height / visibleHeight
        )
    }
}

/// Sample-buffer delegate. Vision runs on `sampleQueue`; the handler only receives sendable rects.
/// Mutable state is guarded by `lock`.
final class LiveFrameBridge: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let sampleQueue = DispatchQueue(label: "com.ooheynerds.swiftwing.live-text")
    private let lock = NSLock()
    private var handler: (@Sendable ([LiveTextObservation]) -> Void)?
    private var lastAccepted = CFAbsoluteTime(0)

    func setHandler(_ handler: (@Sendable ([LiveTextObservation]) -> Void)?) {
        lock.withLock { self.handler = handler }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        let accepted = lock.withLock { () -> Bool in
            guard now - lastAccepted >= 0.2 else { return false }
            lastAccepted = now
            return true
        }
        guard accepted else { return }

        let observations = Self.observations(in: sampleBuffer)
        let handler = lock.withLock { self.handler }
        handler?(observations)
    }

    private static func observations(in sampleBuffer: CMSampleBuffer) -> [LiveTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return LiveTextObservation(id: UUID(), text: trimmed, visionBottomLeft: observation.boundingBox)
        }
    }
}
