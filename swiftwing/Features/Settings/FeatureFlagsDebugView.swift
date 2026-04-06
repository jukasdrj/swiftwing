import SwiftUI

/// Debug view for toggling feature flags
/// DEVELOPMENT ONLY - not included in production builds
struct FeatureFlagsDebugView: View {
    @State private var autoApproveSettings = AutoApproveSettings()

    var body: some View {
        List {
            Section("Auto-Approve") {
                Toggle("Auto-approve high confidence books", isOn: Binding(
                    get: { autoApproveSettings.isEnabled },
                    set: { autoApproveSettings.isEnabled = $0 }
                ))
                Text("Automatically add books to library when confidence exceeds threshold")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if autoApproveSettings.isEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confidence Threshold: \(Int(autoApproveSettings.confidenceThreshold * 100))%")
                            .font(.subheadline)
                        Slider(
                            value: Binding(
                                get: { autoApproveSettings.confidenceThreshold },
                                set: { autoApproveSettings.confidenceThreshold = $0 }
                            ),
                            in: 0.70...1.0,
                            step: 0.05
                        )
                        .tint(.internationalOrange)
                    }

                    Toggle("Show notification for auto-approved books", isOn: Binding(
                        get: { autoApproveSettings.showAutoApproveToast },
                        set: { autoApproveSettings.showAutoApproveToast = $0 }
                    ))
                }
            }

            Section {
                Button("Reset All Flags") {
                    autoApproveSettings.isEnabled = true
                    autoApproveSettings.confidenceThreshold = 0.90
                    autoApproveSettings.showAutoApproveToast = true
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Feature Flags")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        FeatureFlagsDebugView()
    }
    .preferredColorScheme(.dark)
}
