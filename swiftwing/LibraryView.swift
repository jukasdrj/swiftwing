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
    #endif
}

#Preview {
    LibraryView()
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
