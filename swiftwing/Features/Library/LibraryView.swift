import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "library")

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [Book]

    @State private var viewModel = LibraryViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    let filtered = viewModel.filteredBooks(from: books)
                    if books.isEmpty {
                        emptyStateView
                    } else if filtered.isEmpty && !viewModel.searchText.isEmpty {
                        searchEmptyStateView
                    } else if filtered.isEmpty && viewModel.showReviewNeeded {
                        reviewNeededEmptyStateView
                    } else {
                        LibraryGridView(
                            books: filtered,
                            uniqueAuthorsCount: viewModel.uniqueAuthorsCount,
                            mostCommonFormatText: viewModel.mostCommonFormatText,
                            selectedBook: $viewModel.selectedBook,
                            bookToDelete: $viewModel.bookToDelete,
                            showDeleteConfirmation: $viewModel.showDeleteConfirmation,
                            isSelectionMode: viewModel.isSelectionMode,
                            selectedBookIDs: viewModel.selectedBookIDs,
                            onToggleSelection: { viewModel.toggleBookSelection($0) },
                            onPrefetch: { viewModel.prefetchUpcomingImages(startingFrom: $0, in: filtered) },
                            onRefresh: { await viewModel.performRefresh() }
                        )
                    }
                }
                .background(Color.swissBackground.ignoresSafeArea())

                // US-320: Bottom toolbar in selection mode
                if viewModel.isSelectionMode && !viewModel.selectedBookIDs.isEmpty {
                    selectionToolbar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search title or author")
            .onChange(of: viewModel.searchText) { _, _ in viewModel.updateFilteredBooks(context: modelContext) }
            .onChange(of: viewModel.showReviewNeeded) { _, _ in viewModel.updateFilteredBooks(context: modelContext) }
            .onChange(of: viewModel.sortOptionRaw) { _, _ in viewModel.updateFilteredBooks(context: modelContext) }
            .onChange(of: books) { _, _ in
                viewModel.updateFilteredBooks(context: modelContext)
                viewModel.updateLibraryStats(from: books)
            }
            .onAppear {
                viewModel.updateFilteredBooks(context: modelContext)
                viewModel.updateLibraryStats(from: books)
            }
            .onDisappear {
                viewModel.cancelLoading()
            }
            .toolbar {
                LibraryToolbarContent(
                    isSelectionMode: viewModel.isSelectionMode,
                    showReviewNeeded: viewModel.showReviewNeeded,
                    reviewNeededCount: viewModel.reviewNeededCount,
                    searchText: viewModel.searchText,
                    sortOption: viewModel.sortOption,
                    onCancelSelection: { viewModel.exitSelectionMode() },
                    onExport: { viewModel.exportLibrary(books: books) },
                    onToggleReviewFilter: {
                        viewModel.showReviewNeeded.toggle()
                        viewModel.updateFilteredBooks(context: modelContext)
                    },
                    onSelectSort: {
                        viewModel.sortOptionRaw = $0.rawValue
                        viewModel.updateFilteredBooks(context: modelContext)
                    },
                    onSelectOrSelectAll: {
                        if viewModel.isSelectionMode {
                            viewModel.selectAllBooks(from: viewModel.cachedFilteredBooks)
                        } else {
                            viewModel.enterSelectionMode()
                        }
                    }
                )
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $viewModel.selectedBook) { book in
            BookDetailSheet(book: book)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showExportSheet) {
            if let fileURL = viewModel.exportFileURL {
                ActivityViewController(activityItems: [fileURL])
            }
        }
        .alert("Delete \"\(viewModel.bookToDelete?.title ?? "this book")\"?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.bookToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let book = viewModel.bookToDelete {
                    viewModel.deleteBook(book, context: modelContext)
                }
            }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("No books to export", isPresented: $viewModel.showEmptyLibraryAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your library is empty. Scan some books first!")
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 24) {
Image(systemName: "books.vertical")
    .font(.system(size: 80))
    .foregroundStyle(.swissText)
    .shadow(color: .white.opacity(0.4), radius: 20, x: 0, y: 8)
    .background(.ultraThinMaterial)
    .clipShape(Circle())
    .accessibilityHidden(true)

            Text("No Books Yet")
                .font(.title2.bold())
                .foregroundStyle(.swissText)
                .accessibilityIdentifier("library_empty_state")

            Text("Tap the camera tab to scan your first book spine. SwiftWing will identify it automatically.")
                .font(.body)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            #if DEBUG
            VStack(spacing: 12) {
                NavigationLink(destination: FeatureFlagsDebugView()) {
                    Label("Feature Flags", systemImage: "flag.fill")
                }
                .swissGlassButton()
                .accessibilityIdentifier("debug_feature_flags")

                Button("Add Sample Book") {
                    viewModel.addSampleBook(context: modelContext)
                }
                .swissGlassButton()
                .accessibilityIdentifier("debug_add_sample")

                Button("Seed Library") {
                    viewModel.seedLibrary(context: modelContext)
                }
                .swissGlassButton()
                .accessibilityIdentifier("debug_seed_library")

                Button("Generate 100 Books (Performance Test)") {
                    viewModel.generatePerformanceTestData(count: 100, container: modelContext.container)
                }
                .swissGlassButton()
                .accessibilityIdentifier("debug_generate_100")

                Button("Generate 1000 Books (Stress Test)") {
                    viewModel.generatePerformanceTestData(count: 1000, container: modelContext.container)
                }
                .swissGlassButton()
                .accessibilityIdentifier("debug_generate_1000")

                Button("Clear All Books") {
                    viewModel.clearAllBooks(container: modelContext.container)
                }
                .swissGlassButton()
                .accessibilityIdentifier("debug_clear_all")

                Button("Test US-301 Schema") {
                    viewModel.testFullMetadataBook(context: modelContext)
                }
                .swissGlassButton()
                .accessibilityIdentifier("debug_test_schema")

                Button("Test US-311 Duplicate Detection") {
                    viewModel.testDuplicateDetection(context: modelContext)
                }
                .swissGlassButton()
                .accessibilityIdentifier("debug_test_duplicates")

                Button("Log Cache Statistics") {
                    viewModel.logImageCacheStats()
                }
                .swissGlassButton()
                .accessibilityIdentifier("debug_log_cache")
            }
            .padding(.top, 12)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("No books. Tap camera tab to scan.")
    }

    // MARK: - Search Empty State
    private var searchEmptyStateView: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "magnifyingglass")
        } description: {
            Text("No books match \"\(viewModel.searchText)\".")
        }
        .accessibilityIdentifier("library_no_results")
    }

    // MARK: - Review Needed Empty State (US-319)
    private var reviewNeededEmptyStateView: some View {
        ContentUnavailableView(
            "No Books Need Review",
            systemImage: "checkmark.circle",
            description: Text("All your books have high AI confidence scores!")
        )
        .accessibilityIdentifier("library_no_review_needed")
    }

    // MARK: - Selection Toolbar (US-320)
    private var selectionToolbar: some View {
        HStack {
            Button {
                viewModel.showBulkDeleteConfirmation = true
            } label: {
                Label("Delete Selected (\(viewModel.selectedBookIDs.count))", systemImage: "trash")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .clipShape(.rect(cornerRadius: 12))
            }
            .accessibilityIdentifier("library_bulk_delete")
            .accessibilityLabel("Delete \(viewModel.selectedBookIDs.count) selected books")
        }
        .padding()
        .background(
            Color.black.opacity(0.95)
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .alert("Delete \(viewModel.selectedBookIDs.count) books?", isPresented: $viewModel.showBulkDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                viewModel.deleteBulkBooks(from: books, context: modelContext)
            }
        } message: {
            Text("This cannot be undone.")
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
                VStack(spacing: 20) {
                    AsyncImageWithLoading(url: book.coverUrl, title: book.title, author: book.author)
                        .frame(width: 140, height: 210)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)

                    if let confidence = book.spineConfidence {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(confidenceColor(confidence))
                                .frame(width: 8, height: 8)
                            Text("AI Confidence: \(Int(confidence * 100))%")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        MetadataField(label: "Title", value: $editedTitle, isEditing: isEditing)
                        MetadataField(label: "Author", value: $editedAuthor, isEditing: isEditing)
                        MetadataField(label: "ISBN", value: $editedISBN, isEditing: isEditing)

                        if isEditing || !editedFormat.isEmpty {
                            MetadataField(label: "Format", value: $editedFormat, isEditing: isEditing, placeholder: "e.g., Hardcover, Paperback")
                        }
                        if isEditing || !editedPublisher.isEmpty {
                            MetadataField(label: "Publisher", value: $editedPublisher, isEditing: isEditing, placeholder: "Publisher name")
                        }
                        if isEditing || editedPublishedDate != nil {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Published Date")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
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
                                        .foregroundStyle(.swissText)
                                }
                            }
                        }
                        if isEditing || !editedPageCount.isEmpty {
                            MetadataField(label: "Page Count", value: $editedPageCount, isEditing: isEditing, placeholder: "e.g., 432")
                                .keyboardType(.numberPad)
                        }

                        if let status = book.readingStatus {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reading Status")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                                Text(status.rawValue)
                                    .font(.body)
                                    .foregroundStyle(.swissText)
                            }
                        }
                        if let dateRead = book.dateRead {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Date Read")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                                Text(dateRead.formatted(date: .long, time: .omitted))
                                    .font(.body)
                                    .foregroundStyle(.swissText)
                            }
                        }
                        if let rating = book.userRating {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your Rating")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                                Text("\(rating) / 5 ⭐️")
                                    .font(.body)
                                    .foregroundStyle(.swissText)
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            withAnimation(.swissSpring) {
                                isNotesExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Personal Notes")
                                    .font(.headline)
                                    .foregroundStyle(.swissText)
                                Spacer()
                                Image(systemName: isNotesExpanded ? "chevron.up" : "chevron.down")
                                    .foregroundStyle(.gray)
                            }
                        }
                        .padding(.horizontal, 24)

                        if isNotesExpanded {
                            TextEditor(text: $editedNotes)
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(Color.black.opacity(0.3))
                                .clipShape(.rect(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                )
                                .foregroundStyle(.swissText)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .overlay(alignment: .topLeading) {
                                    if editedNotes.isEmpty {
                                        Text("Add personal notes...")
                                            .foregroundStyle(.gray)
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
                .padding(.top, 16)
            }
            .background(Color.swissBackground)
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isEditing {
                        Button("Cancel") { cancelEditing() }
                            .foregroundStyle(.swissText)
                            .accessibilityIdentifier("detail_cancel_button")
                    } else {
                        Button("Close") { dismiss() }
                            .foregroundStyle(.swissText)
                            .accessibilityIdentifier("detail_close_button")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button("Save") { saveChanges() }
                            .foregroundStyle(.internationalOrange)
                            .bold()
                            .accessibilityIdentifier("detail_save_button")
                    } else {
                        Button("Edit") { isEditing = true }
                            .foregroundStyle(.internationalOrange)
                            .accessibilityIdentifier("detail_edit_button")
                    }
                }
            }
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence > 0.8 { return .green }
        if confidence >= 0.6 { return .yellow }
        return .red
    }

    private func saveChanges() {
        book.title = editedTitle
        book.author = editedAuthor
        book.isbn = editedISBN
        book.format = editedFormat.isEmpty ? nil : editedFormat
        book.publisher = editedPublisher.isEmpty ? nil : editedPublisher
        book.publishedDate = editedPublishedDate
        book.notes = editedNotes.isEmpty ? nil : editedNotes
        book.pageCount = Int(editedPageCount)
        isEditing = false
    }

    private func cancelEditing() {
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
                .foregroundStyle(.gray)
            if isEditing {
                TextField(placeholder.isEmpty ? label : placeholder, text: $value)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(keyboardType)
            } else {
                Text(value.isEmpty ? "Not set" : value)
                    .font(.body)
                    .foregroundStyle(value.isEmpty ? .gray : .swissText)
            }
        }
    }
}

// MARK: - Library Export Utilities (US-318)
struct LibraryExporter {
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

    private static func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escapedField = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escapedField)\""
        }
        return field
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func generateFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        return "SwiftWing_Library_\(dateString).csv"
    }

    static func saveToTemporaryFile(csv: String, filename: String) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(filename)
        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}

// MARK: - UIKit Activity View Controller
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    LibraryView()
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
