import Foundation
import SwiftData

#if DEBUG
/// Development-only data seeding utility for testing and development
///
/// Provides a curated collection of diverse books spanning multiple genres and time periods.
/// Books use real ISBN-13 numbers for authenticity in testing scenarios.
///
/// Usage:
/// ```swift
/// DataSeeder.seedLibrary(context: modelContext)
/// ```
struct DataSeeder {
    /// Seeds the SwiftData store with a diverse collection of 20+ books
    ///
    /// - Parameter context: The ModelContext to insert books into
    /// - Note: Checks for existing data before seeding to prevent duplicates
    static func seedLibrary(context: ModelContext) {
        // Check if library already has data
        let descriptor = FetchDescriptor<Book>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0

        if existingCount > 0 {
            print("📚 Library already has \(existingCount) books. Skipping seed.")
            return
        }

        // Curated collection of diverse books
        let books = [
            // Science Fiction
            Book(
                title: "Dune",
                author: "Frank Herbert",
                isbn: "9780441172719"
            ),
            Book(
                title: "Neuromancer",
                author: "William Gibson",
                isbn: "9780441569595"
            ),
            Book(
                title: "The Three-Body Problem",
                author: "Liu Cixin",
                isbn: "9780765382030"
            ),
            Book(
                title: "Foundation",
                author: "Isaac Asimov",
                isbn: "9780553293357"
            ),
            Book(
                title: "Snow Crash",
                author: "Neal Stephenson",
                isbn: "9780553380958"
            ),

            // Fantasy
            Book(
                title: "The Name of the Wind",
                author: "Patrick Rothfuss",
                isbn: "9780756404079"
            ),
            Book(
                title: "The Way of Kings",
                author: "Brandon Sanderson",
                isbn: "9780765365279"
            ),
            Book(
                title: "The Hobbit",
                author: "J.R.R. Tolkien",
                isbn: "9780547928227"
            ),

            // Mystery/Thriller
            Book(
                title: "The Girl with the Dragon Tattoo",
                author: "Stieg Larsson",
                isbn: "9780307949486"
            ),
            Book(
                title: "Gone Girl",
                author: "Gillian Flynn",
                isbn: "9780307588371"
            ),
            Book(
                title: "The Silent Patient",
                author: "Alex Michaelides",
                isbn: "9781250301697"
            ),

            // Non-Fiction (Technology)
            Book(
                title: "The Pragmatic Programmer",
                author: "David Thomas & Andrew Hunt",
                isbn: "9780135957059"
            ),
            Book(
                title: "Clean Code",
                author: "Robert C. Martin",
                isbn: "9780132350884"
            ),
            Book(
                title: "Sapiens",
                author: "Yuval Noah Harari",
                isbn: "9780062316110"
            ),
            Book(
                title: "Atomic Habits",
                author: "James Clear",
                isbn: "9780735211292"
            ),

            // Non-Fiction (Science)
            Book(
                title: "A Brief History of Time",
                author: "Stephen Hawking",
                isbn: "9780553380163"
            ),
            Book(
                title: "The Selfish Gene",
                author: "Richard Dawkins",
                isbn: "9780198788607"
            ),

            // Literary Fiction
            Book(
                title: "1984",
                author: "George Orwell",
                isbn: "9780451524935"
            ),
            Book(
                title: "To Kill a Mockingbird",
                author: "Harper Lee",
                isbn: "9780061120084"
            ),
            Book(
                title: "The Great Gatsby",
                author: "F. Scott Fitzgerald",
                isbn: "9780743273565"
            ),
            Book(
                title: "One Hundred Years of Solitude",
                author: "Gabriel García Márquez",
                isbn: "9780060883287"
            ),

            // Contemporary Fiction
            Book(
                title: "Project Hail Mary",
                author: "Andy Weir",
                isbn: "9780593135204"
            ),
            Book(
                title: "Klara and the Sun",
                author: "Kazuo Ishiguro",
                isbn: "9780593318171"
            ),
            Book(
                title: "The Midnight Library",
                author: "Matt Haig",
                isbn: "9780525559474"
            ),

            // Graphic Novels
            Book(
                title: "Watchmen",
                author: "Alan Moore",
                isbn: "9781401245252"
            ),
            Book(
                title: "Saga, Vol. 1",
                author: "Brian K. Vaughan",
                isbn: "9781607066019"
            )
        ]

        // Insert books into context
        for book in books {
            context.insert(book)
        }

        // Persist to store
        do {
            try context.save()
            print("📚 Successfully seeded library with \(books.count) books")
        } catch {
            print("❌ Failed to seed library: \(error)")
        }
    }
}
#endif
