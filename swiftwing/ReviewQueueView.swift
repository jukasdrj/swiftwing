import SwiftUI
import SwiftData

struct ReviewQueueView: View {
    @Environment(\.modelContext) private var modelContext
    var viewModel: CameraViewModel

    private var sortedPendingBooks: [PendingBookResult] {
        viewModel.pendingReviewBooks.sorted { a, b in
            // Low confidence first (needs most attention)
            let confA = a.confidence ?? 1.0
            let confB = b.confidence ?? 1.0
            return confA < confB
        }
    }

    private var lowConfidenceBooks: [PendingBookResult] {
        sortedPendingBooks.filter { ($0.confidence ?? 1.0) < 0.5 }
    }

    private var mediumConfidenceBooks: [PendingBookResult] {
        sortedPendingBooks.filter {
            let c = $0.confidence ?? 1.0
            return c >= 0.5 && c < 0.8
        }
    }

    private var highConfidenceBooks: [PendingBookResult] {
        sortedPendingBooks.filter { ($0.confidence ?? 1.0) >= 0.8 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.swissBackground.ignoresSafeArea()

                // Content
                if viewModel.pendingReviewBooks.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Low confidence section (red - needs review)
                            if !lowConfidenceBooks.isEmpty {
                                SectionHeader(title: "Needs Review", count: lowConfidenceBooks.count, color: .red)
                                ForEach(lowConfidenceBooks) { book in
                                    ReviewCardView(
                                        book: book,
                                        onApprove: {
                                            viewModel.approveBook(book, modelContext: modelContext)
                                        },
                                        onReject: {
                                            viewModel.rejectBook(book)
                                        },
                                        onEdit: { editedTitle, editedAuthor in
                                            viewModel.updatePendingBookEdits(
                                                id: book.id,
                                                title: editedTitle,
                                                author: editedAuthor
                                            )
                                        }
                                    )
                                }
                            }

                            // Medium confidence section (orange - verify)
                            if !mediumConfidenceBooks.isEmpty {
                                SectionHeader(title: "Verify", count: mediumConfidenceBooks.count, color: .orange)
                                ForEach(mediumConfidenceBooks) { book in
                                    ReviewCardView(
                                        book: book,
                                        onApprove: {
                                            viewModel.approveBook(book, modelContext: modelContext)
                                        },
                                        onReject: {
                                            viewModel.rejectBook(book)
                                        },
                                        onEdit: { editedTitle, editedAuthor in
                                            viewModel.updatePendingBookEdits(
                                                id: book.id,
                                                title: editedTitle,
                                                author: editedAuthor
                                            )
                                        }
                                    )
                                }
                            }

                            // High confidence section (green - ready to add)
                            if !highConfidenceBooks.isEmpty {
                                SectionHeader(title: "Ready to Add", count: highConfidenceBooks.count, color: .green)
                                ForEach(highConfidenceBooks) { book in
                                    ReviewCardView(
                                        book: book,
                                        onApprove: {
                                            viewModel.approveBook(book, modelContext: modelContext)
                                        },
                                        onReject: {
                                            viewModel.rejectBook(book)
                                        },
                                        onEdit: { editedTitle, editedAuthor in
                                            viewModel.updatePendingBookEdits(
                                                id: book.id,
                                                title: editedTitle,
                                                author: editedAuthor
                                            )
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 24)
                    }
                }
            }
            .navigationTitle("Review Queue")
            .toolbar {
                if !viewModel.pendingReviewBooks.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Approve All") {
                            viewModel.approveAllBooks(modelContext: modelContext)
                        }
                        .foregroundColor(.internationalOrange)
                    }
                }
            }
            .overlay {
                if viewModel.showDuplicateAlert, let duplicate = viewModel.duplicateBook {
                    DuplicateBookAlert(
                        duplicateBook: duplicate,
                        onCancel: {
                            viewModel.dismissDuplicateAlert()
                        },
                        onAddAnyway: {
                            viewModel.addDuplicateAnyway(modelContext: modelContext)
                        },
                        onViewExisting: {
                            viewModel.dismissDuplicateAlert()
                        }
                    )
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.internationalOrange.opacity(0.5))

            Text("No Books to Review")
                .font(.title2.bold())
                .foregroundColor(.swissText)

            Text("Scan books with the camera to add them here for review")
                .font(.body)
                .foregroundColor(.swissText.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// Section header for confidence grouping
struct SectionHeader: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.headline.bold())
                .foregroundColor(color)

            Text("(\(count))")
                .font(.subheadline)
                .foregroundColor(color.opacity(0.7))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

struct ReviewCardView: View {
    let book: PendingBookResult
    let onApprove: () -> Void
    let onReject: () -> Void
    let onEdit: (String?, String?) -> Void

    @State private var isEditing = false
    @State private var editedTitle: String
    @State private var editedAuthor: String

    init(book: PendingBookResult, onApprove: @escaping () -> Void, onReject: @escaping () -> Void, onEdit: @escaping (String?, String?) -> Void) {
        self.book = book
        self.onApprove = onApprove
        self.onReject = onReject
        self.onEdit = onEdit
        self._editedTitle = State(initialValue: book.resolvedTitle)
        self._editedAuthor = State(initialValue: book.resolvedAuthor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Confidence badge at top
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

#Preview {
    @Previewable @State var viewModel = {
        let vm = CameraViewModel()
        vm.pendingReviewBooks = [
            PendingBookResult(
                metadata: BookMetadata(
                    title: "The Swift Programming Language",
                    author: "Apple Inc.",
                    isbn: "9781234567890",
                    coverUrl: nil,
                    publisher: "Apple Books",
                    publishedDate: nil,
                    pageCount: 500,
                    format: nil,
                    confidence: 0.95,
                    enrichmentStatus: nil
                ),
                rawJSON: nil
            ),
            PendingBookResult(
                metadata: BookMetadata(
                    title: "Low Confidence Book",
                    author: "Unknown",
                    isbn: "9780000000000",
                    coverUrl: nil,
                    publisher: nil,
                    publishedDate: nil,
                    pageCount: nil,
                    format: nil,
                    confidence: 0.35,
                    enrichmentStatus: nil
                ),
                rawJSON: nil
            ),
            PendingBookResult(
                metadata: BookMetadata(
                    title: "Medium Confidence Book",
                    author: "Someone",
                    isbn: "9781111111111",
                    coverUrl: nil,
                    publisher: nil,
                    publishedDate: nil,
                    pageCount: nil,
                    format: nil,
                    confidence: 0.65,
                    enrichmentStatus: nil
                ),
                rawJSON: nil
            )
        ]
        return vm
    }()

    ReviewQueueView(viewModel: viewModel)
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
