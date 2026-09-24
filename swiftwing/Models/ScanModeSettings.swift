import SwiftUI

/// Which engine turns a spine photo into a review-queue book.
enum ScanMode: String, CaseIterable, Sendable {
    case talaria
    case onDevice

    var displayName: String {
        switch self {
        case .talaria: "Talaria"
        case .onDevice: "On-Device"
        }
    }
}

/// Persists the capture engine. Read once per shutter tap, not per frame.
@MainActor
@Observable
final class ScanModeSettings {
    private let defaults: UserDefaults

    /// Stored so SwiftUI observes picker changes. UserDefaults is the durable copy.
    var mode: ScanMode {
        didSet { defaults.set(mode.rawValue, forKey: Self.storageKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.storageKey: ScanMode.talaria.rawValue])
        let stored = defaults.string(forKey: Self.storageKey) ?? ""
        self.mode = ScanMode(rawValue: stored) ?? .talaria
    }

    private static let storageKey = "scanMode"
}
