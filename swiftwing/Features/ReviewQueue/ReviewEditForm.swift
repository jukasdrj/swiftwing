import SwiftUI

/// Inline edit form for title and author fields on a review card.
/// Shows read-only text when not editing, text fields when editing.
struct ReviewEditForm: View {
    let isEditing: Bool
    let book: PendingBookResult
    @Binding var editedTitle: String
    @Binding var editedAuthor: String
    let onEdit: (String?, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title (editable if in edit mode)
            if isEditing {
                TextField("Title", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.bold())
                    .onChange(of: editedTitle) { oldValue, newValue in
                        onEdit(newValue, editedAuthor)
                    }
            } else {
                Text(book.resolvedTitle)
                    .font(.title3.bold())
                    .foregroundColor(.swissText)
            }

            // Author (editable if in edit mode)
            if isEditing {
                TextField("Author", text: $editedAuthor)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onChange(of: editedAuthor) { oldValue, newValue in
                        onEdit(editedTitle, newValue)
                    }
            } else {
                Text(book.resolvedAuthor)
                    .font(.body)
                    .foregroundColor(.swissText.opacity(0.8))
            }
        }
    }
}
