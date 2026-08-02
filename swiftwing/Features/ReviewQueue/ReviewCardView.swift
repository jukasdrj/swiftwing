import SwiftUI

struct ReviewCardView: View {
    let book: PendingBookResult
    let onApprove: () -> Void
    let onReject: () -> Void
    let onEdit: (String?, String?) -> Void
    var onShowOverlay: (() -> Void)?
    var onManualLookup: (() -> Void)?

    private let shadowColor = Color.black.opacity(0.15)
    private let shadowRadius: CGFloat = 8
    private let shadowX: CGFloat = 0
    private let shadowY: CGFloat = 4

    @State private var isEditing = false
    @State private var editedTitle: String
    @State private var editedAuthor: String

    init(
        book: PendingBookResult, onApprove: @escaping () -> Void, onReject: @escaping () -> Void,
        onEdit: @escaping (String?, String?) -> Void,
        onShowOverlay: (() -> Void)? = nil,
        onManualLookup: (() -> Void)? = nil
    ) {
        self.book = book
        self.onApprove = onApprove
        self.onReject = onReject
        self.onEdit = onEdit
        self.onShowOverlay = onShowOverlay
        self.onManualLookup = onManualLookup
        self._editedTitle = State(initialValue: book.resolvedTitle)
        self._editedAuthor = State(initialValue: book.resolvedAuthor)
    }

    /// Enrichment left this book without usable metadata, so a manual lookup is
    /// the only way forward. Once a lookup succeeds the status becomes `.success`
    /// and the button disappears on its own.
    private var needsRecovery: Bool {
        switch book.resolvedMetadata.enrichmentStatus {
        case .notFound, .circuitOpen: return true
        default: return false
        }
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
                                .foregroundStyle(.white)
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
                            .foregroundStyle(.internationalOrange)
                    }
                    .accessibilityLabel(isEditing ? "Done editing" : "Edit book details")
                }

                ReviewEditForm(
                    isEditing: isEditing,
                    book: book,
                    editedTitle: $editedTitle,
                    editedAuthor: $editedAuthor,
                    onEdit: onEdit
                )

                // ISBN (JetBrains Mono for data)
                if let isbn = book.resolvedMetadata.isbn {
                    Text("ISBN: \(isbn)")
                        .font(.custom("JetBrainsMono-Regular", size: 12))
                        .foregroundStyle(.swissText.opacity(0.6))
                }

                // Enrichment recovery — only while the lookup is still unresolved
                if needsRecovery, let onManualLookup {
                    Button(action: onManualLookup) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass.circle")
                            Text("Look up manually")
                        }
                        .font(.body.bold())
                        .foregroundStyle(Color.internationalOrange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.internationalOrange, lineWidth: 1)
                        )
                    }
                    .accessibilityIdentifier("review_manual_lookup_button")
                }

                // Action Buttons
                HStack(spacing: 12) {
                    // Approve Button
                    Button(action: onApprove) {
                        Text("Approve")
                            .font(.body.bold())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.internationalOrange)
                            .clipShape(.rect(cornerRadius: 8))
                    }
                    .accessibilityIdentifier("review_approve_button")

                    // Reject Button
                    Button(action: onReject) {
                        Text("Reject")
                            .font(.body.bold())
                            .foregroundStyle(.swissText)
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
        .shadow(color: shadowColor, radius: shadowRadius, x: shadowX, y: shadowY)
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
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .clipShape(.rect(cornerRadius: 6))
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
