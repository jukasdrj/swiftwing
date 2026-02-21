import SwiftUI

/// Settings for smart auto-approve of high-confidence book scan results.
/// Persisted via UserDefaults so preferences survive app restarts.
@MainActor
@Observable
final class AutoApproveSettings {
    /// Whether auto-approve is enabled (default: true for streamlined UX)
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "autoApproveEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "autoApproveEnabled") }
    }

    /// Confidence threshold for auto-approval (default: 0.90 = 90%)
    var confidenceThreshold: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: "autoApproveThreshold")
            return stored > 0 ? stored : 0.90
        }
        set { UserDefaults.standard.set(newValue, forKey: "autoApproveThreshold") }
    }

    /// Whether to show a brief toast when books are auto-approved
    var showAutoApproveToast: Bool {
        get { UserDefaults.standard.bool(forKey: "autoApproveShowToast") != false }
        set { UserDefaults.standard.set(newValue, forKey: "autoApproveShowToast") }
    }

    init() {
        // Register defaults so isEnabled starts as true on first launch
        UserDefaults.standard.register(defaults: [
            "autoApproveEnabled": true,
            "autoApproveShowToast": true
        ])
    }
}
