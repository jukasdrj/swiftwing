import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [Book]

    var body: some View {
        VStack(spacing: 20) {
            Text("Books: \(books.count)")
                .font(.title)

            #if DEBUG
            VStack(spacing: 12) {
                Button("Add Dummy Book") {
                    addDummyBook()
                }
                .swissGlassButton()

                Button("Seed Library") {
                    seedLibrary()
                }
                .swissGlassButton()
                .haptic(.success, trigger: books.count)

                Button("Test US-301 Schema") {
                    testFullMetadataBook()
                }
                .swissGlassButton()
            }
            #else
            Button("Add Dummy Book") {
                addDummyBook()
            }
            .buttonStyle(.borderedProminent)
            #endif
        }
        .padding()
    }

    private func addDummyBook() {
        let dummyBook = Book(
            title: "Test Book",
            author: "Test Author",
            isbn: "1234567890"
        )
        modelContext.insert(dummyBook)
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

#Preview {
    LibraryView()
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
