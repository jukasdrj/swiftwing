import SwiftUI
import SwiftData

/// Swiss Glass styled alert for duplicate book detection
/// US-311: Duplicate Detection Warning
struct DuplicateBookAlert: View {
    let duplicateBook: Book
    let onCancel: () -> Void
    let onAddAnyway: () -> Void
    let onViewExisting: () -> Void

    var body: some View {
        ZStack {
            // Dimmed background overlay
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            // Alert card
            VStack(spacing: 20) {
                // Warning icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundColor(.internationalOrange)

                // Title
                Text("Duplicate Book Detected")
                    .font(.title3.bold())
                    .foregroundColor(.swissText)
                    .multilineTextAlignment(.center)

                // Message
                VStack(spacing: 8) {
                    Text("\"\(duplicateBook.title)\"")
                        .font(.body.bold())
                        .foregroundColor(.swissText)
                        .multilineTextAlignment(.center)

                    Text("is already in your library.")
                        .font(.body)
                        .foregroundColor(.swissText.opacity(0.8))
                        .multilineTextAlignment(.center)

                    Text("Add anyway?")
                        .font(.body)
                        .foregroundColor(.swissText.opacity(0.8))
                        .multilineTextAlignment(.center)
                }

                // Action buttons
                VStack(spacing: 12) {
                    // View Existing button (primary action)
                    Button(action: onViewExisting) {
                        Text("View Existing")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.swissBackground)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .padding(.vertical, 14)
                            .background(Color.internationalOrange)
                            .cornerRadius(10)
                    }

                    // Add Anyway button (secondary action)
                    Button(action: onAddAnyway) {
                        Text("Add Anyway")
                            .font(.body.weight(.medium))
                            .foregroundColor(.swissText)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    }

                    // Cancel button (tertiary action)
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.body.weight(.regular))
                            .foregroundColor(.swissText.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .padding(.vertical, 12)
                    }
                }
            }
            .padding(28)
            .frame(width: 320)
            .swissGlassCard()
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

#Preview {
    @Previewable @State var sampleBook = Book(
        title: "The Swift Programming Language",
        author: "Apple Inc.",
        isbn: "9780000000999"
    )

    DuplicateBookAlert(
        duplicateBook: sampleBook,
        onCancel: { print("Cancelled") },
        onAddAnyway: { print("Add Anyway") },
        onViewExisting: { print("View Existing") }
    )
    .preferredColorScheme(.dark)
}
