import SwiftUI

struct ReviewCardView: View {
    let book: PendingBookResult
    let onApprove: () -> Void
    let onReject: () -> Void
    let onEdit: (String?, String?) -> Void
    var onShowOverlay: (() -> Void)?

    @State private var isEditing = false
    @State private var editedTitle: String
    @State private var editedAuthor: String

    init(
        book: PendingBookResult, onApprove: @escaping () -> Void, onReject: @escaping () -> Void,
        onEdit: @escaping (String?, String?) -> Void,
        onShowOverlay: (() -> Void)? = nil
    ) {
        self.book = book
        self.onApprove = onApprove
        self.onReject = onReject
        self.onEdit = onEdit
        self.onShowOverlay = onShowOverlay
        self._editedTitle = State(initialValue: book.resolvedTitle)
        self._editedAuthor = State(initialValue: book.resolvedAuthor)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail (if available from processing item)
            if let thumbData = book.thumbnailData,
               let thumbnail = UIImage(data: thumbData) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .bottomTrailing) {
                        if onShowOverlay != nil {
                            Image(systemName: "magnifyingglass")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.internationalOrange)
                                .clipShape(Circle())
                                .offset(x: 4, y: 4)
                        }
                    }
                    .onTapGesture {
                        onShowOverlay?()
                    }
            }

            VStack(alignment: .leading, spacing: 12) {
                // Confidence badge + edit button
                HStack {
                    confidenceBadge
                    Spacer()
                    Button(action: {
                        isEditing.toggle()
                    }) {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                            .font(.title3)
                            .foregroundColor(.internationalOrange)
                    }
                }

                ReviewEditForm(
                    isEditing: isEditing,
                    book: book,
                    editedTitle: $editedTitle,
                    editedAuthor: $editedAuthor,
                    onEdit: onEdit
                )

                // ISBN (JetBrains Mono for data)
                if let isbn = book.metadata.isbn {
                    Text("ISBN: \(isbn)")
                        .font(.custom("JetBrainsMono-Regular", size: 12))
                        .foregroundColor(.swissText.opacity(0.6))
                }

                // Action Buttons
                HStack(spacing: 12) {
                    // Approve Button
                    Button(action: onApprove) {
                        Text("Approve")
                            .font(.body.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.internationalOrange)
                            .cornerRadius(8)
                    }
                    .accessibilityIdentifier("review_approve_button")

                    // Reject Button
                    Button(action: onReject) {
                        Text("Reject")
                            .font(.body.bold())
                            .foregroundColor(.swissText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.swissText, lineWidth: 1)
                            )
                    }
                    .accessibilityIdentifier("review_reject_button")
                }
            }
        }
        .padding(16)
        .swissGlassCard()
    }

    private var confidenceBadge: some View {
        let confidence = book.confidence ?? 1.0
        let (icon, color, label) = confidenceDisplay(confidence)

        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption.bold())
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(6)
    }

    private func confidenceDisplay(_ confidence: Double) -> (String, Color, String) {
        if confidence >= 0.8 {
            return ("checkmark.circle.fill", .green, "\(Int(confidence * 100))%")
        } else if confidence >= 0.5 {
            return ("exclamationmark.triangle.fill", .orange, "\(Int(confidence * 100))%")
        } else {
            return ("xmark.octagon.fill", .red, "\(Int(confidence * 100))%")
        }
    }
}
