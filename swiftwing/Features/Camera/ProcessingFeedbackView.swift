import SwiftUI

/// Transient feedback overlay shown after photo capture
/// Displays capture confirmation and multi-book processing progress
/// Design: Swiss Glass with checkmark animation and book count
struct ProcessingFeedbackView: View {
    let bookCount: Int
    let isProcessing: Bool
    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            VStack(spacing: 16) {
                if isProcessing {
                    // Processing state: spinner + count
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.internationalOrange)

                    Text("Processing \(bookCount) book\(bookCount == 1 ? "" : "s")...")
                        .font(.headline)
                        .foregroundColor(.swissText)
                } else {
                    // Capture confirmation: checkmark animation
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                        .symbolEffect(.bounce)

                    Text("Photo captured")
                        .font(.headline)
                        .foregroundColor(.swissText)
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
            .animation(.spring(duration: 0.3), value: isProcessing)
            .accessibilityLabel(isProcessing ? "Processing \(bookCount) books" : "Photo captured")
            .accessibilityValue(isProcessing ? "In progress" : "Complete")
        }
    }
}

#Preview("Capture Confirmation") {
    ZStack {
        Color.black.ignoresSafeArea()

        ProcessingFeedbackView(
            bookCount: 5,
            isProcessing: false,
            isVisible: .constant(true)
        )
    }
}

#Preview("Processing State") {
    ZStack {
        Color.black.ignoresSafeArea()

        ProcessingFeedbackView(
            bookCount: 5,
            isProcessing: true,
            isVisible: .constant(true)
        )
    }
}

#Preview("Single Book") {
    ZStack {
        Color.black.ignoresSafeArea()

        ProcessingFeedbackView(
            bookCount: 1,
            isProcessing: true,
            isVisible: .constant(true)
        )
    }
}
