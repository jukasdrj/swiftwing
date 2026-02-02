// /Users/juju/dev_repos/swiftwing/swiftwing/SegmentedPreviewOverlay.swift

import SwiftUI

/// Shows the segmented image preview with detected book regions highlighted
/// Appears as a semi-transparent overlay on the camera view after initial detection
struct SegmentedPreviewOverlay: View {
    let imageData: Data
    let totalBooks: Int
    let currentBook: Int
    let totalProcessed: Int

    var body: some View {
        VStack(spacing: 16) {
            // Segmented image with bounding boxes
            if let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.internationalOrange.opacity(0.5), lineWidth: 2)
                    )
                    .frame(maxHeight: 200)
            }

            // Book count badge
            HStack(spacing: 8) {
                Image(systemName: "books.vertical")
                    .font(.body)
                Text("\(totalBooks) books detected")
                    .font(.body.bold())
            }
            .foregroundColor(.swissText)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .swissGlassOverlay()

            // Progress bar (if processing has started)
            if totalProcessed > 0 {
                VStack(spacing: 8) {
                    ProgressView(value: Double(totalProcessed), total: Double(totalBooks))
                        .progressViewStyle(.linear)
                        .tint(.internationalOrange)
                        .frame(width: 200)

                    Text("Processing book \(currentBook)/\(totalBooks)")
                        .font(.caption)
                        .foregroundColor(.swissText.opacity(0.8))
                }
            }
        }
        .padding(24)
        .swissGlassCard()
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
