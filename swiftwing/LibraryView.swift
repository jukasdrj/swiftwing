import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var isRefreshing = false

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
    }

    // MARK: - Library Grid
    private var libraryGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(filteredBooks, id: \.id) { book in
                    BookGridCell(book: book)
                        .transition(.scale.combined(with: .opacity))
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

    var body: some View {
        VStack(spacing: 8) {
            // Cover image with 100x150 aspect ratio
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

#Preview {
    LibraryView()
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
