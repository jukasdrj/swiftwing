import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var isRefreshing = false
    @State private var selectedBook: Book?
    @State private var bookToDelete: Book?
    @State private var showDeleteConfirmation = false

    // Dynamic query based on search text
    private var filteredBooks: [Book] {
        if searchText.isEmpty {
            return books
        } else {
            let lowercasedSearch = searchText.lowercased()
            return books.filter { book in
                book.title.lowercased().contains(lowercasedSearch) ||
                book.author.lowercased().contains(lowercasedSearch)
            }
        }
    }

    @Query(sort: [SortDescriptor(\Book.addedDate, order: .reverse)]) private var books: [Book]

    // 3-column grid with adaptive sizing
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        Group {
            if books.isEmpty {
                emptyStateView
            } else if filteredBooks.isEmpty && !searchText.isEmpty {
                searchEmptyStateView
            } else {
                libraryGridView
            }
        }
        .background(Color.swissBackground.ignoresSafeArea())
        .searchable(text: $searchText, prompt: "Search title or author")
        .sheet(item: $selectedBook) { book in
            BookDetailSheet(book: book)
                .presentationDetents([.medium])
        }
        .alert("Delete \"\(bookToDelete?.title ?? "this book")\"?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                bookToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let book = bookToDelete {
                    deleteBook(book)
                }
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - Library Grid
    private var libraryGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(filteredBooks, id: \.id) { book in
                    BookGridCell(book: book) {
                        // Delete button handler (swipe-action alternative for grid)
                        bookToDelete = book
                        showDeleteConfirmation = true
                    }
                    .transition(.asymmetric(insertion: .scale, removal: .opacity))
                    .onTapGesture {
                        selectedBook = book
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            bookToDelete = book
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await performRefresh()
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 80))
                .foregroundColor(.internationalOrange)

            Text("No books yet. Start scanning!")
                .font(.title3)
                .foregroundColor(.swissText)
                .multilineTextAlignment(.center)

            #if DEBUG
            VStack(spacing: 12) {
                Button("Seed Library") {
                    seedLibrary()
                }
                .swissGlassButton()

                Button("Test US-301 Schema") {
                    testFullMetadataBook()
                }
                .swissGlassButton()
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Search Empty State
    private var searchEmptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 80))
                .foregroundColor(.gray)

            Text("No results for '\(searchText)'")
                .font(.title3)
                .foregroundColor(.swissText)
                .multilineTextAlignment(.center)

            Text("Try searching by title or author")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions
    private func performRefresh() async {
        isRefreshing = true
        // Placeholder for Epic 4 sync
        try? await Task.sleep(for: .seconds(1))
        isRefreshing = false
    }

    private func deleteBook(_ book: Book) {
        withAnimation(.spring(duration: 0.2)) {
            modelContext.delete(book)
            try? modelContext.save()
        }
        bookToDelete = nil
    }

    #if DEBUG
    private func seedLibrary() {
        DataSeeder.seedLibrary(context: modelContext)
    }

    /// Test US-301: Verify Book schema supports both minimal and full metadata
    private func testFullMetadataBook() {
        // Test 1: Minimal book (existing pattern)
        let minimalBook = Book(
            title: "Test Minimal",
            author: "Test Author",
            isbn: "9780000000001"
        )

        // Test 2: Full metadata book (Epic 3 fields)
        let fullBook = Book(
            title: "Test Full Metadata",
            author: "Full Test Author",
            isbn: "9780000000002",
            coverUrl: URL(string: "https://covers.openlibrary.org/b/isbn/9780000000002-L.jpg"),
            format: "Hardcover",
            publisher: "Test Publisher",
            publishedDate: Date(),
            pageCount: 432,
            spineConfidence: 0.95,
            rawJSON: "{\"test\": \"data\"}"
        )

        // Test 3: Low confidence book (should trigger needsReview)
        let lowConfidenceBook = Book(
            title: "Low Confidence Test",
            author: "Test Author",
            isbn: "9780000000003",
            spineConfidence: 0.65 // Below 0.8 threshold
        )

        modelContext.insert(minimalBook)
        modelContext.insert(fullBook)
        modelContext.insert(lowConfidenceBook)

        print("✅ US-301 Test:")
        print("  - Minimal book created: \(minimalBook.title)")
        print("  - Full metadata book created: \(fullBook.title)")
        print("  - Full book has cover URL: \(fullBook.coverUrl != nil)")
        print("  - Full book has publisher: \(fullBook.publisher ?? "nil")")
        print("  - Full book has page count: \(fullBook.pageCount ?? 0)")
        print("  - Low confidence book needs review: \(lowConfidenceBook.needsReview)")
        print("  - Full book does NOT need review: \(!fullBook.needsReview)")
    }
    #endif
}

// MARK: - Book Grid Cell
struct BookGridCell: View {
    let book: Book
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            // Cover image with 100x150 aspect ratio
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: book.coverUrl) { phase in
                    switch phase {
                    case .empty:
                        placeholderView
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderView
                    @unknown default:
                        placeholderView
                    }
                }
                .frame(height: 150)
                .aspectRatio(2/3, contentMode: .fit)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )

                // Delete button overlay (swipe-action alternative for grid)
                if let onDelete = onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white, .red)
                            .shadow(radius: 2)
                    }
                    .padding(4)
                }
            }

            // Title (2 lines max, truncated)
            Text(book.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.swissText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.gray.opacity(0.6))
            )
    }
}

// MARK: - Book Detail Sheet
struct BookDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let book: Book

    @State private var isEditing = false
    @State private var editedTitle: String
    @State private var editedAuthor: String
    @State private var editedISBN: String
    @State private var editedFormat: String
    @State private var editedPublisher: String
    @State private var editedPublishedDate: Date?
    @State private var editedPageCount: String

    init(book: Book) {
        self.book = book
        _editedTitle = State(initialValue: book.title)
        _editedAuthor = State(initialValue: book.author)
        _editedISBN = State(initialValue: book.isbn)
        _editedFormat = State(initialValue: book.format ?? "")
        _editedPublisher = State(initialValue: book.publisher ?? "")
        _editedPublishedDate = State(initialValue: book.publishedDate)
        _editedPageCount = State(initialValue: book.pageCount != nil ? String(book.pageCount!) : "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    // Left: Cover image (200x300)
                    AsyncImage(url: book.coverUrl) { phase in
                        switch phase {
                        case .empty:
                            placeholderCover
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            placeholderCover
                        @unknown default:
                            placeholderCover
                        }
                    }
                    .frame(width: 200, height: 300)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )

                    // Right: Metadata VStack
                    VStack(alignment: .leading, spacing: 16) {
                        // AI Confidence (if available)
                        if let confidence = book.spineConfidence {
                            HStack(spacing: 4) {
                                Text("AI Confidence:")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text("\(Int(confidence * 100))%")
                                    .font(.caption.bold())
                                    .foregroundColor(confidenceColor(confidence))
                            }
                        }

                        // Title
                        MetadataField(
                            label: "Title",
                            value: $editedTitle,
                            isEditing: isEditing
                        )

                        // Author
                        MetadataField(
                            label: "Author",
                            value: $editedAuthor,
                            isEditing: isEditing
                        )

                        // ISBN
                        MetadataField(
                            label: "ISBN",
                            value: $editedISBN,
                            isEditing: isEditing
                        )

                        // Format
                        MetadataField(
                            label: "Format",
                            value: $editedFormat,
                            isEditing: isEditing,
                            placeholder: "e.g., Hardcover, Paperback"
                        )

                        // Publisher
                        MetadataField(
                            label: "Publisher",
                            value: $editedPublisher,
                            isEditing: isEditing,
                            placeholder: "Publisher name"
                        )

                        // Published Date
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Published Date")
                                .font(.caption)
                                .foregroundColor(.gray)

                            if isEditing {
                                DatePicker(
                                    "",
                                    selection: Binding(
                                        get: { editedPublishedDate ?? Date() },
                                        set: { editedPublishedDate = $0 }
                                    ),
                                    displayedComponents: .date
                                )
                                .labelsHidden()
                            } else {
                                Text(editedPublishedDate?.formatted(date: .long, time: .omitted) ?? "Not set")
                                    .font(.body)
                                    .foregroundColor(.swissText)
                            }
                        }

                        // Page Count
                        MetadataField(
                            label: "Page Count",
                            value: $editedPageCount,
                            isEditing: isEditing,
                            placeholder: "e.g., 432"
                        )
                        .keyboardType(.numberPad)

                        Spacer()
                    }
                }
                .padding(24)
            }
            .background(Color.swissBackground)
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isEditing {
                        Button("Cancel") {
                            cancelEditing()
                        }
                        .foregroundColor(.swissText)
                    } else {
                        Button("Close") {
                            dismiss()
                        }
                        .foregroundColor(.swissText)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button("Save") {
                            saveChanges()
                        }
                        .foregroundColor(.internationalOrange)
                        .bold()
                    } else {
                        Button("Edit") {
                            isEditing = true
                        }
                        .foregroundColor(.internationalOrange)
                    }
                }
            }
        }
    }

    private var placeholderCover: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.gray.opacity(0.6))
            )
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence > 0.8 {
            return .green
        } else if confidence >= 0.6 {
            return .yellow
        } else {
            return .red
        }
    }

    private func saveChanges() {
        book.title = editedTitle
        book.author = editedAuthor
        book.isbn = editedISBN
        book.format = editedFormat.isEmpty ? nil : editedFormat
        book.publisher = editedPublisher.isEmpty ? nil : editedPublisher
        book.publishedDate = editedPublishedDate

        if let pageCount = Int(editedPageCount) {
            book.pageCount = pageCount
        } else {
            book.pageCount = nil
        }

        try? modelContext.save()
        isEditing = false
    }

    private func cancelEditing() {
        // Reset to original values
        editedTitle = book.title
        editedAuthor = book.author
        editedISBN = book.isbn
        editedFormat = book.format ?? ""
        editedPublisher = book.publisher ?? ""
        editedPublishedDate = book.publishedDate
        editedPageCount = book.pageCount != nil ? String(book.pageCount!) : ""
        isEditing = false
    }
}

// MARK: - Metadata Field Component
struct MetadataField: View {
    let label: String
    @Binding var value: String
    let isEditing: Bool
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)

            if isEditing {
                TextField(placeholder.isEmpty ? label : placeholder, text: $value)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(keyboardType)
            } else {
                Text(value.isEmpty ? "Not set" : value)
                    .font(.body)
                    .foregroundColor(value.isEmpty ? .gray : .swissText)
            }
        }
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
