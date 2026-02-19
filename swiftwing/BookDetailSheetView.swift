import SwiftUI
import SwiftData

struct ProcessingItemDetailSheet: View {
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
        _editedTitle = State(initialValue: item.bookMetadata?.title ?? "")
        _editedAuthor = State(initialValue: item.bookMetadata?.author ?? "")
    }

    /// ISBN from metadata or pre-scanned barcode
    private var resolvedISBN: String? {
        item.bookMetadata?.isbn ?? item.preScannedISBN
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.swissBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        if let imageData = item.originalImageData, let image = UIImage(data: imageData) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
                        }

                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Title")
                                    .font(.headline)
                                    .foregroundColor(.swissText)
                                TextField("Book title", text: $editedTitle)
                                    .padding(12)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                    .foregroundColor(.swissText)
                                    .focused($focusedField, equals: .title)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Author")
                                    .font(.headline)
                                    .foregroundColor(.swissText)
                                TextField("Author name", text: $editedAuthor)
                                    .padding(12)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                    .foregroundColor(.swissText)
                                    .focused($focusedField, equals: .author)
                            }

                            // Show ISBN if available (read-only)
                            if let isbn = resolvedISBN {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ISBN")
                                        .font(.headline)
                                        .foregroundColor(.swissText)
                                    Text(isbn)
                                        .font(.custom("JetBrainsMono-Regular", size: 14))
                                        .foregroundColor(.swissText.opacity(0.6))
                                }
                            }

                            // Show confidence if metadata available
                            if let confidence = item.bookMetadata?.confidence {
                                HStack(spacing: 6) {
                                    Image(systemName: confidenceIcon(confidence))
                                        .foregroundColor(confidenceColor(confidence))
                                    Text("\(Int(confidence * 100))% confidence")
                                        .font(.subheadline)
                                        .foregroundColor(.swissText.opacity(0.7))
                                }
                            }
                        }
                        .padding(16)
                        .swissGlassCard()
                    }
                    .padding()
                }
            }
            .navigationTitle("Review Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        dismiss()
                    }
                    .foregroundColor(.swissText)
                    .accessibilityIdentifier("processing_detail_discard")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(editedTitle, editedAuthor, resolvedISBN)
                        dismiss()
                    }
                    .foregroundColor(.internationalOrange)
                    .disabled(editedTitle.isEmpty || editedAuthor.isEmpty)
                    .accessibilityIdentifier("processing_detail_save")
                }
            }
        }
    }

    private func confidenceIcon(_ confidence: Double) -> String {
        if confidence >= 0.8 { return "checkmark.circle.fill" }
        if confidence >= 0.5 { return "exclamationmark.triangle.fill" }
        return "xmark.octagon.fill"
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.5 { return .orange }
        return .red
    }
}

#Preview {
    let imageData = Data()
    let item: ProcessingItem = {
        var i = ProcessingItem(imageData: imageData, state: .done, progressMessage: "Ready for review")
        i.bookMetadata = BookMetadata(
            title: "The Swift Programming Language",
            author: "Apple Inc.",
            isbn: "9781234567890",
            confidence: 0.92
        )
        return i
    }()

    ProcessingItemDetailSheet(
        item: item,
        onSave: { title, author, isbn in
            print("Saved: \(title) by \(author), ISBN: \(isbn ?? "none")")
        }
    )
}
