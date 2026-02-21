import SwiftUI

// MARK: - Library Grid View
struct LibraryGridView: View {
    let books: [Book]
    @Binding var selectedBook: Book?
    @Binding var bookToDelete: Book?
    @Binding var showDeleteConfirmation: Bool
    let isSelectionMode: Bool
    let selectedBookIDs: Set<UUID>
    let onToggleSelection: (Book) -> Void
    let onPrefetch: (Book) -> Void
    let onRefresh: () async -> Void

    // Adaptive grid: iPhone portrait 3 cols, iPad landscape 7 cols
    private let adaptiveColumns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 16)
    ]

    @State private var renderStartTime: CFAbsoluteTime?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Library Stats Header
                LibraryStatsHeader(books: books)
                    .padding(.horizontal)
                    .padding(.top)

                // Book Grid
                LazyVGrid(columns: adaptiveColumns, spacing: 20) {
                    ForEach(books, id: \.id) { book in
                        BookGridCell(
                            book: book,
                            isSelectionMode: isSelectionMode,
                            isSelected: selectedBookIDs.contains(book.id),
                            onDelete: {
                                bookToDelete = book
                                showDeleteConfirmation = true
                            }
                        )
                        .accessibilityIdentifier("book_cell_\(book.isbn)")
                        .accessibilityLabel("\(book.title) by \(book.author)")
                        .transition(.asymmetric(insertion: .scale, removal: .opacity))
                        .onTapGesture {
                            if isSelectionMode {
                                onToggleSelection(book)
                            } else {
                                selectedBook = book
                            }
                        }
                        .contextMenu {
                            if !isSelectionMode {
                                Button(role: .destructive) {
                                    bookToDelete = book
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onAppear {
                            onPrefetch(book)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .refreshable {
            await onRefresh()
        }
        .onAppear {
            renderStartTime = CFAbsoluteTimeGetCurrent()
        }
        .task {
            if let startTime = renderStartTime {
                try? await Task.sleep(for: .milliseconds(16))
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                PerformanceLogger.logLibraryRendering(
                    bookCount: books.count,
                    duration: duration
                )
            }
        }
    }
}

// MARK: - Library Stats Header
struct LibraryStatsHeader: View {
    let books: [Book]

    // Stats are passed in as a computed snapshot — caller owns the cache
    var uniqueAuthorsCount: Int
    var mostCommonFormatText: String

    init(books: [Book]) {
        self.books = books
        // Compute inline; LibraryViewModel owns the cached version used externally
        uniqueAuthorsCount = Set(books.map { $0.author }).count

        let formatCounts = Dictionary(grouping: books.compactMap { $0.format }, by: { $0 })
            .mapValues { $0.count }
        if let mostCommon = formatCounts.max(by: { $0.value < $1.value }), !books.isEmpty {
            let percentage = Int((Double(mostCommon.value) / Double(books.count)) * 100)
            mostCommonFormatText = "\(mostCommon.key): \(percentage)%"
        } else {
            mostCommonFormatText = "N/A"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Books",
                value: "\(books.count)",
                icon: "book.fill"
            )
            .accessibilityIdentifier("library_stats_books")

            StatCard(
                title: "Authors",
                value: "\(uniqueAuthorsCount)",
                icon: "person.fill"
            )
            .accessibilityIdentifier("library_stats_authors")

            StatCard(
                title: "Format",
                value: mostCommonFormatText,
                icon: "square.stack.3d.up.fill"
            )
            .accessibilityIdentifier("library_stats_format")
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
            Image(systemName: icon)
                .font(.title2)
                .imageScale(.medium)
                .foregroundColor(.internationalOrange)

            Text(value)
                .font(.title2.bold())
                .foregroundColor(.swissText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .swissGlassCard()
    }
}
