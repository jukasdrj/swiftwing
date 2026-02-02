import SwiftUI

/// Debug view for toggling feature flags (Epic 6 Sprint 1)
/// DEVELOPMENT ONLY - not included in production builds
///
/// Consolidated version supporting all Epic 6 Sprint features:
/// - Sprint 1: Multi-Book Scanning
/// - Sprint 2: On-Device Extraction
/// - Sprint 3: Hybrid Enrichment
/// - Sprint 4: Analytics
struct FeatureFlagsDebugView: View {
    // Sprint 1: Multi-Book Scanning
    @AppStorage("EnableMultiBookScanning") private var multiBook = false
    @AppStorage("enableBackgroundEnrichment") private var enableBackgroundEnrichment = false
    @AppStorage("enableProgressiveResults") private var enableProgressiveResults = false

    // Sprint 2: On-Device Extraction
    @AppStorage("UseOnDeviceExtraction") private var onDeviceExtraction = false

    // Sprint 3: Hybrid Enrichment
    @AppStorage("UseTalariaTextEnrichment") private var talariaEnrichment = false

    // Sprint 4: Analytics
    @AppStorage("TrackExtractionAccuracy") private var trackAccuracy = true

    var body: some View {
        List {
            Section("Sprint 1: Multi-Book Scanning") {
                Toggle("Multi-Book Scanning", isOn: $multiBook)
                Text("Enable instance segmentation for shelf photos (1-20 books per image)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Background Enrichment", isOn: $enableBackgroundEnrichment)
                Text("Enrich books in background after extraction")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Progressive Results", isOn: $enableProgressiveResults)
                Text("Show partial results as books are detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Sprint 2: On-Device Extraction") {
                Toggle("Foundation Models Extraction", isOn: $onDeviceExtraction)
                Text("Use RecognizeDocumentsRequest + FM for title/author (iOS 26+)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Sprint 3: Hybrid Enrichment") {
                Toggle("Talaria Text Enrichment", isOn: $talariaEnrichment)
                Text("Send extracted text to Talaria for covers + metadata")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Sprint 4: Analytics") {
                Toggle("Track Accuracy", isOn: $trackAccuracy)
                Text("Log FM vs Talaria comparison for metrics")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button("Reset All Flags") {
                    multiBook = false
                    enableBackgroundEnrichment = false
                    enableProgressiveResults = false
                    onDeviceExtraction = false
                    talariaEnrichment = false
                    trackAccuracy = true
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
