import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [Book]

    var body: some View {
        VStack(spacing: 20) {
            Text("Books: \(books.count)")
                .font(.title)

            Button("Add Dummy Book") {
                addDummyBook()
            }
            .buttonStyle(.borderedProminent)
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
}

#Preview {
    LibraryView()
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
