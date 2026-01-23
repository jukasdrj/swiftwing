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
    @State private var showExportSheet = false
    @State private var exportFileURL: URL?
    @State private var showEmptyLibraryAlert = false
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

    // Adaptive grid layout that responds to device size and orientation
    // iPhone portrait: 3 columns | iPhone landscape: 5 columns
    // iPad portrait: 5 columns | iPad landscape: 7 columns
    private let adaptiveColumns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 16)
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
            .accessibilityLabel("Search books by title or author")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        exportLibrary()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.swissText)
                            .accessibilityLabel("Export library to CSV")
                    }
                }

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
                            .accessibilityLabel("Sort library")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selectedBook) { book in
            BookDetailSheet(book: book)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showExportSheet) {
            if let fileURL = exportFileURL {
                ActivityViewController(activityItems: [fileURL])
            }
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
        .alert("No books to export", isPresented: $showEmptyLibraryAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your library is empty. Scan some books first!")
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
                LazyVGrid(columns: adaptiveColumns, spacing: 20) {
                    ForEach(filteredBooks, id: \.id) { book in
                        BookGridCell(book: book) {
                            // Delete button handler (swipe-action alternative for grid)
                            bookToDelete = book
                            showDeleteConfirmation = true
                        }
                        .accessibilityLabel("\(book.title) by \(book.author)")
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
                .accessibilityHidden(true)

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
        .accessibilityLabel("No books. Tap camera tab to scan.")
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

    /// US-318: Export library to CSV
    private func exportLibrary() {
        // Check if library is empty
        guard !books.isEmpty else {
            showEmptyLibraryAlert = true
            return
        }

        // Generate CSV
        let csv = LibraryExporter.generateCSV(from: books)
        let filename = LibraryExporter.generateFilename()

        // Save to temporary file
        do {
            let fileURL = try LibraryExporter.saveToTemporaryFile(csv: csv, filename: filename)
            exportFileURL = fileURL
            showExportSheet = true
        } catch {
            print("Failed to export library: \(error)")
        }
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
                    .accessibilityHidden(true) // Title is redundant

                // Delete button overlay (swipe-action alternative for grid)
                if let onDelete = onDelete {
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

            // Title (2 lines max, truncated)
            Text(book.title)
                .font(.caption.weight(.medium))
                .foregroundColor(.swissText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true) // Parent VStack has combined label
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
    @State private var editedNotes: String
    @State private var isNotesExpanded = false

    init(book: Book) {
        self.book = book
        _editedTitle = State(initialValue: book.title)
        _editedAuthor = State(initialValue: book.author)
        _editedISBN = State(initialValue: book.isbn)
        _editedFormat = State(initialValue: book.format ?? "")
        _editedPublisher = State(initialValue: book.publisher ?? "")
        _editedPublishedDate = State(initialValue: book.publishedDate)
        _editedPageCount = State(initialValue: book.pageCount != nil ? String(book.pageCount!) : "")
        _editedNotes = State(initialValue: book.notes ?? "")
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

                        // Epic 5: Reading status fields (display only, no editing UI yet)
                        if let status = book.readingStatus {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reading Status")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(status)
                                    .font(.body)
                                    .foregroundColor(.swissText)
                            }
                        }

                        if let dateRead = book.dateRead {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Date Read")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(dateRead.formatted(date: .long, time: .omitted))
                                    .font(.body)
                                    .foregroundColor(.swissText)
                            }
                        }

                        if let rating = book.userRating {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your Rating")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text("\(rating) / 5 ⭐️")
                                    .font(.body)
                                    .foregroundColor(.swissText)
                            }
                        }

                        Spacer()
                    }
                }
                .padding(24)

                // Personal Notes Section (Expandable)
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation(.swissSpring) {
                            isNotesExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Personal Notes")
                                .font(.headline)
                                .foregroundColor(.swissText)

                            Spacer()

                            Image(systemName: isNotesExpanded ? "chevron.up" : "chevron.down")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 24)

                    if isNotesExpanded {
                        TextEditor(text: $editedNotes)
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .foregroundColor(.swissText)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .overlay(alignment: .topLeading) {
                                if editedNotes.isEmpty {
                                    Text("Add personal notes...")
                                        .foregroundColor(.gray)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 16)
                                        .allowsHitTesting(false)
                                }
                            }
                            .padding(.horizontal, 24)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.vertical, 16)
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
            .onDisappear {
                // Auto-save notes on sheet dismiss (even if not in edit mode)
                if editedNotes != (book.notes ?? "") {
                    book.notes = editedNotes.isEmpty ? nil : editedNotes
                    try? modelContext.save()
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
        book.notes = editedNotes.isEmpty ? nil : editedNotes

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
        editedNotes = book.notes ?? ""
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
                .font(.title2)
                .imageScale(.medium)
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

// MARK: - Library Export Utilities (US-318)
struct LibraryExporter {
    /// Generate CSV content from an array of books
    /// Headers: ISBN, Title, Author, Format, Publisher, Date Added, Notes
    static func generateCSV(from books: [Book]) -> String {
        var csv = "ISBN,Title,Author,Format,Publisher,Date Added,Notes\n"

        for book in books {
            let fields = [
                escapeCSVField(book.isbn),
                escapeCSVField(book.title),
                escapeCSVField(book.author),
                escapeCSVField(book.format ?? ""),
                escapeCSVField(book.publisher ?? ""),
                formatDate(book.addedDate),
                escapeCSVField(book.notes ?? "")
            ]

            csv += fields.joined(separator: ",") + "\n"
        }

        return csv
    }

    /// Escape CSV field (wrap in quotes if contains comma, quote, or newline)
    private static func escapeCSVField(_ field: String) -> String {
        // Check if field needs escaping
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            // Escape existing quotes by doubling them
            let escapedField = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escapedField)\""
        }

        return field
    }

    /// Format date as YYYY-MM-DD
    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Generate filename with current date: "SwiftWing_Library_[YYYY-MM-DD].csv"
    static func generateFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        return "SwiftWing_Library_\(dateString).csv"
    }

    /// Save CSV to temporary file and return URL
    static func saveToTemporaryFile(csv: String, filename: String) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(filename)

        try csv.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }
}

/// UIKit wrapper for UIActivityViewController (sharing sheet)
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
