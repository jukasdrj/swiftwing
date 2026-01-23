import SwiftUI
import SwiftData

// MARK: - Sort Options
enum LibrarySortOption: String, CaseIterable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"
    case titleAZ = "Title A-Z"
    case authorAZ = "Author A-Z"

    var sortDescriptors: [SortDescriptor<Book>] {
        switch self {
        case .newestFirst:
            return [SortDescriptor(\Book.addedDate, order: .reverse)]
        case .oldestFirst:
            return [SortDescriptor(\Book.addedDate, order: .forward)]
        case .titleAZ:
            return [SortDescriptor(\Book.title, order: .forward)]
        case .authorAZ:
            return [SortDescriptor(\Book.author, order: .forward)]
        }
    }

    var icon: String {
        switch self {
        case .newestFirst:
            return "calendar.badge.clock"
        case .oldestFirst:
            return "calendar"
        case .titleAZ:
            return "textformat"
        case .authorAZ:
            return "person.text.rectangle"
        }
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var isRefreshing = false
    @State private var selectedBook: Book?
    @State private var bookToDelete: Book?
    @State private var showDeleteConfirmation = false
    @AppStorage("library_sort_option") private var sortOptionRaw: String = LibrarySortOption.newestFirst.rawValue

    private var sortOption: LibrarySortOption {
        LibrarySortOption(rawValue: sortOptionRaw) ?? .newestFirst
    }

    // Sorted books based on current sort option
    private var sortedBooks: [Book] {
        let descriptor = FetchDescriptor<Book>(sortBy: sortOption.sortDescriptors)
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // Dynamic query based on search text
    private var filteredBooks: [Book] {
        if searchText.isEmpty {
            return sortedBooks
        } else {
            let lowercasedSearch = searchText.lowercased()
            return sortedBooks.filter { book in
                book.title.lowercased().contains(lowercasedSearch) ||
                book.author.lowercased().contains(lowercasedSearch)
            }
        }
    }

    // Keep original query for reactive updates
    @Query private var books: [Book]

    // 3-column grid with adaptive sizing
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(LibrarySortOption.allCases, id: \.self) { option in
                            Button {
                                withAnimation(.swissSpring) {
                                    sortOptionRaw = option.rawValue
                                }
                            } label: {
                                HStack {
                                    Label(option.rawValue, systemImage: option.icon)
                                    if option == sortOption {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.swissText)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
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
            VStack(spacing: 16) {
                // Library Stats Header
                libraryStatsHeader
                    .padding(.horizontal)
                    .padding(.top)

                // Book Grid
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
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .refreshable {
            await performRefresh()
        }
    }

    // MARK: - Library Stats Header
    private var libraryStatsHeader: some View {
        HStack(spacing: 12) {
            // Card 1: Total Books
            StatCard(
                title: "Books",
                value: "\(books.count)",
                icon: "book.fill"
            )

            // Card 2: Unique Authors
            StatCard(
                title: "Authors",
                value: "\(uniqueAuthorsCount)",
                icon: "person.fill"
            )

            // Card 3: Most Common Format
            StatCard(
                title: "Format",
                value: mostCommonFormatText,
                icon: "square.stack.3d.up.fill"
            )
        }
    }

    // MARK: - Stats Computed Properties
    private var uniqueAuthorsCount: Int {
        Set(books.map { $0.author }).count
    }

    private var mostCommonFormatText: String {
        // Count formats, excluding nil values
        let formatCounts = Dictionary(grouping: books.compactMap { $0.format }, by: { $0 })
            .mapValues { $0.count }

        guard let mostCommon = formatCounts.max(by: { $0.value < $1.value }),
              !books.isEmpty else {
            return "N/A"
        }

        let percentage = Int((Double(mostCommon.value) / Double(books.count)) * 100)
        return "\(mostCommon.key): \(percentage)%"
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            // SF Symbol: books.vertical (large, white, with subtle glow)
            Image(systemName: "books.vertical")
                .font(.system(size: 80))
                .foregroundColor(.swissText)
                .shadow(color: .white.opacity(0.3), radius: 12)

            // Title: "No Books Yet"
            Text("No Books Yet")
                .font(.title2.bold())
                .foregroundColor(.swissText)

            // Description with guidance
            Text("Tap the camera tab to scan your first book spine. SwiftWing will identify it automatically.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            #if DEBUG
            // Optional: Add Sample Book button for testing
            VStack(spacing: 12) {
                Button("Add Sample Book") {
                    addSampleBook()
                }
                .swissGlassButton()

                Button("Seed Library") {
                    seedLibrary()
                }
                .swissGlassButton()

                Button("Test US-301 Schema") {
                    testFullMetadataBook()
                }
                .swissGlassButton()

                Button("Test US-311 Duplicate Detection") {
                    testDuplicateDetection()
                }
                .swissGlassButton()
            }
            .padding(.top, 12)
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
    /// US-307: Add a single sample book for testing empty state transitions
    private func addSampleBook() {
        let sampleBook = Book(
            title: "The Swift Programming Language",
            author: "Apple Inc.",
            isbn: "9780000000999",
            coverUrl: URL(string: "https://covers.openlibrary.org/b/isbn/9780000000999-L.jpg"),
            format: "Hardcover",
            spineConfidence: 0.92
        )

        withAnimation(.swissSpring) {
            modelContext.insert(sampleBook)
            try? modelContext.save()
        }
    }

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

    /// US-311: Test duplicate detection logic
    private func testDuplicateDetection() {
        let testISBN = "9780134092669" // Test ISBN

        // Test 1: Check for existing duplicate
        if let existingBook = DuplicateDetection.findDuplicate(isbn: testISBN, in: modelContext) {
            print("✅ US-311 Test 1: Found existing duplicate")
            print("  - Title: \(existingBook.title)")
            print("  - ISBN: \(existingBook.isbn)")
        } else {
            print("✅ US-311 Test 1: No duplicate found (adding test book)")

            // Add a test book
            let testBook = Book(
                title: "iOS Programming: The Big Nerd Ranch Guide",
                author: "Christian Keur & Aaron Hillegass",
                isbn: testISBN
            )

            modelContext.insert(testBook)
            try? modelContext.save()
            print("  - Test book added with ISBN: \(testISBN)")
        }

        // Test 2: Try to find the duplicate again (should succeed after Test 1)
        if let duplicate = DuplicateDetection.findDuplicate(isbn: testISBN, in: modelContext) {
            print("✅ US-311 Test 2: Duplicate detection working correctly")
            print("  - Found: \(duplicate.title)")
            print("  - ISBN match: \(duplicate.isbn == testISBN)")
        } else {
            print("❌ US-311 Test 2: Duplicate detection failed")
        }

        // Test 3: Check non-existent ISBN
        let nonExistentISBN = "9999999999999"
        if DuplicateDetection.findDuplicate(isbn: nonExistentISBN, in: modelContext) == nil {
            print("✅ US-311 Test 3: Correctly returns nil for non-existent ISBN")
        } else {
            print("❌ US-311 Test 3: Incorrectly found book with non-existent ISBN")
        }
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
                AsyncImageWithLoading(url: book.coverUrl)
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
                    AsyncImageWithLoading(url: book.coverUrl)
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

// MARK: - Stat Card Component
struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.internationalOrange)

            // Value
            Text(value)
                .font(.title2.bold())
                .foregroundColor(.swissText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Title
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .swissGlassCard()
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
