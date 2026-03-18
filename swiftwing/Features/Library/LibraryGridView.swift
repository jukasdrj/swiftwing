import SwiftUI

// MARK: - Library Grid View
struct LibraryGridView: View {
    let books: [Book]
    let uniqueAuthorsCount: Int
    let mostCommonFormatText: String
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
                LibraryStatsHeader(
                    bookCount: books.count,
                    uniqueAuthorsCount: uniqueAuthorsCount,
                    mostCommonFormatText: mostCommonFormatText
                )
                .padding(.horizontal)
                .padding(.top)

                // Book Grid
                LazyVGrid(columns: adaptiveColumns, spacing: 20) {
                    ForEach(books, id: \.id) { book in
                        Button {
                            if isSelectionMode {
                                onToggleSelection(book)
                            } else {
                                selectedBook = book
                            }
                        } label: {
                            BookGridCell(
                                book: book,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedBookIDs.contains(book.id),
                                onDelete: {
                                    bookToDelete = book
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("book_cell_\(book.isbn)")
                        .accessibilityLabel("\(book.title) by \(book.author)")
                        .transition(.asymmetric(insertion: .scale, removal: .opacity))
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
    let bookCount: Int
    let uniqueAuthorsCount: Int
    let mostCommonFormatText: String

    var body: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Books",
                value: "\(bookCount)",
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
                .foregroundStyle(.internationalOrange)

            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.swissText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .swissGlassCard()
    }
}
