import SwiftUI
import SwiftData

struct BookDetailSheetView: View {
    let item: ProcessingItem
    let onSave: (String, String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editedTitle: String
    @State private var editedAuthor: String
    @FocusState private var focusedField: Field?

    enum Field {
        case title, author
    }

    init(item: ProcessingItem, onSave: @escaping (String, String, String?) -> Void) {
        self.item = item
        self.onSave = onSave
        _editedTitle = State(initialValue: item.extractedTitle ?? "")
        _editedAuthor = State(initialValue: item.extractedAuthor ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Book spine thumbnail
                    if let imageData = item.originalImageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    }

                    // Metadata form
                    VStack(spacing: 16) {
                        // Title field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.headline)
                            TextField("Book title", text: $editedTitle)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .title)
                        }

                        // Author field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Author")
                                .font(.headline)
                            TextField("Author name", text: $editedAuthor)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .author)
                        }

                        // Confidence badge
                        if let confidence = item.confidence {
                            HStack {
                                Text("Confidence:")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                ConfidenceBadge(confidence: confidence, size: .large)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("Review Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(editedTitle, editedAuthor, item.preScannedISBN)
                        dismiss()
                    }
                    .disabled(editedTitle.isEmpty || editedAuthor.isEmpty)
                }
            }
        }
    }
}

#Preview {
    let imageData = Data() // Empty data for preview
    var item = ProcessingItem(imageData: imageData, state: .done, progressMessage: "Ready for review")
    item.extractedTitle = "Test Book"
    item.extractedAuthor = "Test Author"
    item.confidence = 0.95

    return BookDetailSheetView(
        item: item,
        onSave: { title, author, isbn in
            print("Saved: \(title) by \(author)")
        }
    )
}
