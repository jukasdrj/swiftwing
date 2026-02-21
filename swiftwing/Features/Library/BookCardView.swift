import SwiftUI

// MARK: - Book Grid Cell
struct BookGridCell: View {
    let book: Book
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image: fixed height, fills column width
            ZStack(alignment: .topLeading) {
                AsyncImageWithLoading(url: book.coverUrl, title: book.title, author: book.author)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipped()
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? Color.blue : Color.white.opacity(0.2),
                                lineWidth: isSelected ? 3 : 1
                            )
                    )
                    .accessibilityHidden(true) // Title is redundant

                // US-320: Checkbox overlay in selection mode (top-left)
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.6), isSelected ? .blue : .clear)
                        .shadow(radius: 2)
                        .padding(8)
                }

                // Delete button overlay (top-right)
                if !isSelectionMode, let onDelete = onDelete {
                    HStack {
                        Spacer()
                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, .red)
                                .shadow(radius: 2)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Delete \(book.title)")
                    }
                }
            }

            // Title (2 lines max, reserved height for alignment consistency)
            Text(book.title)
                .font(.caption.weight(.medium))
                .foregroundColor(.swissText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                .accessibilityHidden(true) // Parent VStack has combined label
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
