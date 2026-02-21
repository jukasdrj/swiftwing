import UIKit

/// Centralizes all haptic feedback for the camera feature.
/// Wraps UIImpactFeedbackGenerator so callers never create generators inline.
@MainActor
final class CameraHapticsManager {

    // MARK: - Generators

    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact  = UIImpactFeedbackGenerator(style: .heavy)

    // MARK: - Lifecycle

    /// Pre-warm generators so first haptic has minimal latency.
    func prepare() {
        mediumImpact.prepare()
        heavyImpact.prepare()
    }

    // MARK: - Feedback

    /// Fired when a book spine is detected (medium weight, positive signal).
    func spineDetected() {
        mediumImpact.impactOccurred()
    }

    /// Fired on retry-triggered interactions (medium weight).
    func retryTriggered() {
        mediumImpact.impactOccurred()
    }

    /// Fired on processing or streaming errors (heavy weight, attention signal).
    func errorOccurred() {
        heavyImpact.impactOccurred()
    }
}
