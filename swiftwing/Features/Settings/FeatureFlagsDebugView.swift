import SwiftUI

/// Debug view for toggling feature flags
/// DEVELOPMENT ONLY - not included in production builds
struct FeatureFlagsDebugView: View {
    @AppStorage("isVisionEnabled") private var showVisionOverlays = true

    var body: some View {
        List {
            Section("Camera Overlays") {
                Toggle("Vision Overlay (Rectangle Detection)", isOn: $showVisionOverlays)
                Text("Show green bounding boxes for detected rectangles")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button("Reset All Flags") {
                    showVisionOverlays = true
                }
                .foregroundColor(.red)
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
