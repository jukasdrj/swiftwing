import Foundation

/// Owns Vision framework state and bounding-box related logic for the camera feature.
/// Extracted from CameraViewModel to keep vision concerns isolated.
@MainActor
@Observable
final class CameraVisionCoordinator {

    // MARK: - State

    var detectedText: [TextRegion]     = []
    var detectedISBN: String?          = nil
    var captureGuidance: CaptureGuidance = .noBookDetected
    var detectedObjects: [DetectedObject] = []

    // MARK: - UserDefaults-backed toggle

    var isVisionEnabled: Bool {
        // Default true when key is absent (false is the zero value, so we
        // treat "not set" the same as "true").
        UserDefaults.standard.bool(forKey: "isVisionEnabled") != false
    }

    func setVisionEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "isVisionEnabled")
    }

    // MARK: - Result Handling

    /// Process a VisionResult from CameraManager and update state accordingly.
    /// Returns true when a spine/barcode was newly detected (caller may fire haptics).
    @discardableResult
    func handle(result: VisionResult) -> Bool {
        switch result {
        case .textRegions(let regions):
            detectedText    = regions
            detectedObjects = []
            captureGuidance = generateGuidance(from: regions)
            return false

        case .barcode(let barcodeResult):
            detectedObjects = []
            if barcodeResult.isValidISBN {
                detectedISBN    = barcodeResult.isbn
                captureGuidance = .spineDetected
                return true   // caller should fire haptic
            }
            return false

        case .objects(let objects):
            detectedObjects = objects
            captureGuidance = generateObjectGuidance(from: objects)
            return false

        case .noContent:
            // Throttled frames — preserve last known state
            return false
        }
    }

    /// Whether the camera is actively scanning (used for adaptive throttling).
    var isActivelyScanning: Bool {
        captureGuidance == .spineDetected
    }

    // MARK: - Guidance Generation

    private func generateGuidance(from regions: [TextRegion]) -> CaptureGuidance {
        let highConfidence = regions.filter { $0.confidence > 0.7 }
        if highConfidence.count >= 3 {
            return .spineDetected
        } else if highConfidence.count > 0 {
            return .moveCloser
        } else {
            return .noBookDetected
        }
    }

    private func generateObjectGuidance(from objects: [DetectedObject]) -> CaptureGuidance {
        let highConfidence = objects.filter { $0.confidence > 0.85 }
        if !highConfidence.isEmpty {
            return .spineDetected
        } else if !objects.isEmpty {
            return .moveCloser
        } else {
            return .noBookDetected
        }
    }
}
