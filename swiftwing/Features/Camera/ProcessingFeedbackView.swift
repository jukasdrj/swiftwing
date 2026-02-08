import SwiftUI

/// Transient feedback overlay shown after photo capture
/// Shows capture confirmation, then transitions to live processing status
/// Design: Swiss Glass with checkmark animation
struct ProcessingFeedbackView: View {
    let processingCount: Int
    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                    .symbolEffect(.bounce)

                Text("Photo captured")
                    .font(.headline)
                    .foregroundColor(.swissText)

                if processingCount > 0 {
                    Text("\(processingCount) scanning...")
                        .font(.subheadline)
                        .foregroundColor(.swissText.opacity(0.7))
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Photo captured")
            .accessibilityValue(processingCount > 0 ? "\(processingCount) items processing" : "Complete")
        }
    }
}

#Preview("Capture Confirmation") {
    ZStack {
        Color.black.ignoresSafeArea()

        ProcessingFeedbackView(
            processingCount: 0,
            isVisible: .constant(true)
        )
    }
}

#Preview("With Processing") {
    ZStack {
        Color.black.ignoresSafeArea()

        ProcessingFeedbackView(
            processingCount: 3,
            isVisible: .constant(true)
        )
    }
}
