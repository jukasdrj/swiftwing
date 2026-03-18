import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "library-viewmodel")

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

// MARK: - Library ViewModel
@MainActor
@Observable
final class LibraryViewModel {

    // MARK: - Sort / Filter State
    var searchText: String = ""
    var showReviewNeeded: Bool {
        get { _showReviewNeeded }
        set { _showReviewNeeded = newValue }
    }
    var sortOptionRaw: String {
        get { _sortOptionRaw }
        set { _sortOptionRaw = newValue }
    }

    // AppStorage-backed backing properties (bridged via computed vars above)
    @ObservationIgnored
    @AppStorage("library_sort_option") private var _sortOptionRaw: String = LibrarySortOption.newestFirst.rawValue
    @ObservationIgnored
    @AppStorage("show_review_needed") private var _showReviewNeeded: Bool = false

    var sortOption: LibrarySortOption {
        LibrarySortOption(rawValue: sortOptionRaw) ?? .newestFirst
    }

    // MARK: - Selection State (US-320)
    var isSelectionMode: Bool = false
    var selectedBookIDs: Set<UUID> = []
    var showBulkDeleteConfirmation: Bool = false

    // MARK: - Sheet / Alert State
    var selectedBook: Book?
    var bookToDelete: Book?
    var showDeleteConfirmation: Bool = false
    var showExportSheet: Bool = false
    var exportFileURL: URL?
    var showEmptyLibraryAlert: Bool = false

    // MARK: - Refresh State
    var isRefreshing: Bool = false

    // MARK: - Performance (US-321)
    var prefetchCoordinator = LibraryPrefetchCoordinator()
    var renderStartTime: CFAbsoluteTime?

    // MARK: - Cached Stats (US-321)
    private(set) var cachedUniqueAuthorsCount: Int = 0
    private(set) var cachedReviewNeededCount: Int = 0
    private(set) var cachedMostCommonFormat: String = "N/A"

    // MARK: - Cached Filtered Books
    private(set) var cachedFilteredBooks: [Book] = []

    // MARK: - Derived Properties

    var uniqueAuthorsCount: Int { cachedUniqueAuthorsCount }
    var reviewNeededCount: Int { cachedReviewNeededCount }
    var mostCommonFormatText: String { cachedMostCommonFormat }

    func sortedBooks(from books: [Book]) -> [Book] {
        switch sortOption {
        case .newestFirst:
            return books.sorted { $0.addedDate > $1.addedDate }
        case .oldestFirst:
            return books.sorted { $0.addedDate < $1.addedDate }
        case .titleAZ:
            return books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .authorAZ:
            return books.sorted { $0.author.localizedStandardCompare($1.author) == .orderedAscending }
        }
    }

    func filteredBooks(from books: [Book]) -> [Book] {
        if cachedFilteredBooks.isEmpty && searchText.isEmpty && !showReviewNeeded && !books.isEmpty {
            return sortedBooks(from: books)
        }
        return cachedFilteredBooks
    }

    // MARK: - Filter / Stats Updates

    func updateFilteredBooks(from books: [Book]) {
        var result = sortedBooks(from: books)

        if !searchText.isEmpty {
            result = result.filter { book in
                book.title.localizedStandardContains(searchText) ||
                book.author.localizedStandardContains(searchText)
            }
        }

        if showReviewNeeded {
            result = result.filter { ($0.spineConfidence ?? 1.0) < 0.8 }
        }

        cachedFilteredBooks = result
    }

    func updateLibraryStats(from books: [Book]) {
        cachedUniqueAuthorsCount = Set(books.map { $0.author }).count
        cachedReviewNeededCount = books.lazy.filter { ($0.spineConfidence ?? 1.0) < 0.8 }.count

        let formatCounts = Dictionary(grouping: books.compactMap { $0.format }, by: { $0 })
            .mapValues { $0.count }

        if let mostCommon = formatCounts.max(by: { $0.value < $1.value }), !books.isEmpty {
            let percentage = Int((Double(mostCommon.value) / Double(books.count)) * 100)
            cachedMostCommonFormat = "\(mostCommon.key): \(percentage)%"
        } else {
            cachedMostCommonFormat = "N/A"
        }
    }

    // MARK: - Selection Actions (US-320)

    func enterSelectionMode() {
        withAnimation(.swissSpring) {
            isSelectionMode = true
            selectedBookIDs.removeAll()
        }
    }

    func exitSelectionMode() {
        withAnimation(.swissSpring) {
            isSelectionMode = false
            selectedBookIDs.removeAll()
        }
    }

    func toggleBookSelection(_ book: Book) {
        withAnimation(.spring(duration: 0.2)) {
            if selectedBookIDs.contains(book.id) {
                selectedBookIDs.remove(book.id)
            } else {
                selectedBookIDs.insert(book.id)
            }
        }
    }

    func selectAllBooks(from filteredBooks: [Book]) {
        withAnimation(.swissSpring) {
            selectedBookIDs = Set(filteredBooks.map { $0.id })
        }
    }

    // MARK: - Delete Actions

    func deleteBook(_ book: Book, context: ModelContext) {
        withAnimation(.spring(duration: 0.2)) {
            context.delete(book)
            do {
                try context.save()
            } catch {
                logger.error("Failed to save after delete: \(error.localizedDescription, privacy: .public)")
            }
        }
        bookToDelete = nil
    }

    func deleteBulkBooks(from books: [Book], context: ModelContext) {
        withAnimation(.spring(duration: 0.2)) {
            for bookID in selectedBookIDs {
                if let book = books.first(where: { $0.id == bookID }) {
                    context.delete(book)
                }
            }
            do {
                try context.save()
            } catch {
                logger.error("Failed to save after bulk delete: \(error.localizedDescription, privacy: .public)")
            }
            exitSelectionMode()
        }
    }

    // MARK: - Refresh

    func performRefresh() async {
        isRefreshing = true
        try? await Task.sleep(for: .seconds(1))
        isRefreshing = false
    }

    // MARK: - Prefetch (US-321)

    func prefetchUpcomingImages(startingFrom book: Book, in filteredBooks: [Book]) {
        guard let index = filteredBooks.firstIndex(where: { $0.id == book.id }) else { return }
        let prefetchRange = min(index + 20, filteredBooks.count)
        let upcomingBooks = Array(filteredBooks[index..<prefetchRange])
        prefetchCoordinator.prefetchUpcoming(books: upcomingBooks, maxCount: 20)
    }

    // MARK: - Export (US-318)

    func exportLibrary(books: [Book]) {
        guard !books.isEmpty else {
            showEmptyLibraryAlert = true
            return
        }

        let csv = LibraryExporter.generateCSV(from: books)
        let filename = LibraryExporter.generateFilename()

        do {
            let fileURL = try LibraryExporter.saveToTemporaryFile(csv: csv, filename: filename)
            exportFileURL = fileURL
            showExportSheet = true
        } catch {
            logger.error("Failed to export library: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Debug Actions (US-321)

    #if DEBUG
    func addSampleBook(context: ModelContext) {
        let sampleBook = Book(
            title: "The Swift Programming Language",
            author: "Apple Inc.",
            isbn: "9780000000999",
            coverUrl: URL(string: "https://covers.openlibrary.org/b/isbn/9780000000999-L.jpg"),
            format: "Hardcover",
            spineConfidence: 0.92
        )
        withAnimation(.swissSpring) {
            context.insert(sampleBook)
            do {
                try context.save()
            } catch {
                logger.error("Failed to save sample book: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func seedLibrary(context: ModelContext) {
        DataSeeder.seedLibrary(context: context)
    }

    func testFullMetadataBook(context: ModelContext) {
        let minimalBook = Book(title: "Test Minimal", author: "Test Author", isbn: "9780000000001")
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
        let lowConfidenceBook = Book(
            title: "Low Confidence Test",
            author: "Test Author",
            isbn: "9780000000003",
            spineConfidence: 0.65
        )

        context.insert(minimalBook)
        context.insert(fullBook)
        context.insert(lowConfidenceBook)

        logger.info("US-301 Test: Minimal book created: \(minimalBook.title, privacy: .public)")
        logger.info("US-301 Test: Full metadata book created: \(fullBook.title, privacy: .public)")
        logger.info("US-301 Test: Full book has cover URL: \(fullBook.coverUrl != nil, privacy: .public)")
        logger.info("US-301 Test: Full book has publisher: \(fullBook.publisher ?? "nil", privacy: .public)")
        logger.info("US-301 Test: Full book has page count: \(fullBook.pageCount ?? 0, privacy: .public)")
        logger.info("US-301 Test: Low confidence book needs review: \(lowConfidenceBook.needsReview, privacy: .public)")
        logger.info("US-301 Test: Full book does NOT need review: \(!fullBook.needsReview, privacy: .public)")
    }

    func testDuplicateDetection(context: ModelContext) {
        let testISBN = "9780134092669"

        do {
            if let existingBook = try DuplicateDetection.findDuplicate(isbn: testISBN, in: context) {
                logger.info("US-311 Test 1: Found existing duplicate - Title: \(existingBook.title, privacy: .public), ISBN: \(existingBook.isbn, privacy: .public)")
            } else {
                logger.info("US-311 Test 1: No duplicate found (adding test book)")
                let testBook = Book(
                    title: "iOS Programming: The Big Nerd Ranch Guide",
                    author: "Christian Keur & Aaron Hillegass",
                    isbn: testISBN
                )
                context.insert(testBook)
                do {
                    try context.save()
                } catch {
                    logger.error("Failed to save test book: \(error.localizedDescription, privacy: .public)")
                }
                logger.info("US-311 Test 1: Test book added with ISBN: \(testISBN, privacy: .public)")
            }

            if let duplicate = try DuplicateDetection.findDuplicate(isbn: testISBN, in: context) {
                logger.info("US-311 Test 2: Duplicate detection working correctly - Found: \(duplicate.title, privacy: .public), ISBN match: \(duplicate.isbn == testISBN, privacy: .public)")
            } else {
                logger.error("US-311 Test 2: Duplicate detection failed")
            }

            let nonExistentISBN = "9999999999999"
            if try DuplicateDetection.findDuplicate(isbn: nonExistentISBN, in: context) == nil {
                logger.info("US-311 Test 3: Correctly returns nil for non-existent ISBN")
            } else {
                logger.error("US-311 Test 3: Incorrectly found book with non-existent ISBN")
            }
        } catch {
            logger.error("US-311 Test failed with error: \(error.localizedDescription, privacy: .public)")
        }
    }

    func generatePerformanceTestData(count: Int, container: ModelContainer) {
        logger.info("US-321: Generating \(count, privacy: .public) test books...")
        Task {
            await PerformanceTestData.generateTestDataset(
                count: count,
                container: container,
                includeCovers: true
            )
        }
    }

    func clearAllBooks(container: ModelContainer) {
        Task {
            await PerformanceTestData.clearTestData(container: container)
        }
    }

    func logImageCacheStats() {
        Task {
            let stats = await ImageCacheManager.shared.getCacheStatistics()
            PerformanceLogger.logCacheStatistics(
                memoryUsed: stats.memoryUsed,
                diskUsed: stats.diskUsed
            )
        }
    }
    #endif
}
