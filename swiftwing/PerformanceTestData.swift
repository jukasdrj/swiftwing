import Foundation
import SwiftData

// MARK: - Performance Test Data Generator
/// US-321: Generator for creating large test datasets to profile library performance
/// Creates realistic book data with mock covers for performance testing
struct PerformanceTestData {

    // MARK: - Sample Book Data
    private static let sampleTitles = [
        "The Swift Programming Language", "Design Patterns", "Clean Code",
        "The Pragmatic Programmer", "Introduction to Algorithms",
        "Code Complete", "Refactoring", "Domain-Driven Design",
        "Head First Design Patterns", "Effective Modern C++",
        "Structure and Interpretation", "The Art of Computer Programming",
        "Programming Pearls", "Mythical Man-Month", "Peopleware",
        "The Clean Coder", "Working Effectively with Legacy Code",
        "Test Driven Development", "Continuous Delivery", "DevOps Handbook",
        "Site Reliability Engineering", "Building Microservices",
        "Designing Data-Intensive Applications", "Release It!",
        "The Phoenix Project", "Accelerate", "Team Topologies",
        "Software Architecture", "Patterns of Enterprise Application",
        "Enterprise Integration Patterns", "Kubernetes in Action",
        "Docker Deep Dive", "Cloud Native Patterns", "Reactive Design",
        "Functional Programming", "Category Theory for Programmers",
        "Haskell Programming", "Learn You a Haskell", "Real World Haskell",
        "Programming in Scala", "Scala for the Impatient",
        "Effective Java", "Java Concurrency in Practice",
        "Spring in Action", "Python Crash Course", "Fluent Python",
        "Learning Python", "Automate the Boring Stuff", "Deep Learning",
        "Hands-On Machine Learning", "Pattern Recognition",
        "Artificial Intelligence", "Natural Language Processing"
    ]

    private static let sampleAuthors = [
        "Apple Inc.", "Gang of Four", "Robert C. Martin",
        "Andrew Hunt & David Thomas", "Thomas H. Cormen",
        "Steve McConnell", "Martin Fowler", "Eric Evans",
        "Elisabeth Freeman", "Scott Meyers", "Harold Abelson",
        "Donald Knuth", "Jon Bentley", "Frederick P. Brooks",
        "Tom DeMarco", "Michael Feathers", "Kent Beck",
        "Jez Humble", "Gene Kim", "Niall Richard Murphy",
        "Sam Newman", "Martin Kleppmann", "Michael T. Nygard",
        "Gregor Hohpe", "Matthew Skelton", "Brendan Burns",
        "Nigel Poulton", "Cornelia Davis", "Roland Kuhn",
        "Paul Chiusano", "Bartosz Milewski", "Christopher Allen",
        "Miran Lipovača", "Bryan O'Sullivan", "Martin Odersky",
        "Cay S. Horstmann", "Joshua Bloch", "Brian Goetz",
        "Craig Walls", "Eric Matthes", "Luciano Ramalho",
        "Mark Lutz", "Al Sweigart", "Ian Goodfellow",
        "Aurélien Géron", "Christopher Bishop", "Stuart Russell",
        "Dan Jurafsky"
    ]

    private static let formats = ["Hardcover", "Paperback", "eBook", "Audiobook"]

    private static let publishers = [
        "O'Reilly Media", "Addison-Wesley", "Pragmatic Bookshelf",
        "Manning Publications", "Packt Publishing", "Apress",
        "No Starch Press", "MIT Press", "Wiley", "Pearson"
    ]

    // Mock cover URLs from Open Library (real covers for realistic loading)
    private static let sampleISBNs = [
        "9780134092669", "9780201633610", "9780132350884",
        "9780201616224", "9780262033848", "9780735619678",
        "9780201485677", "9780321125217", "9780596007126",
        "9781491950357", "9780262510875", "9780201896831",
        "9780201657883", "9780201835953", "9780321278654",
        "9780132931755", "9780201485677", "9780321503626",
        "9780321601919", "9781942788003", "9781491929483",
        "9781491903995", "9781449373320", "9780201633610"
    ]

    // MARK: - Test Dataset Generation

    /// Generate a large dataset of books for performance testing
    /// - Parameters:
    ///   - count: Number of books to generate (default: 1000)
    ///   - context: SwiftData model context to insert books into
    ///   - includeCovers: Whether to include cover URLs (affects image loading performance)
    static func generateTestDataset(
        count: Int = 1000,
        context: ModelContext,
        includeCovers: Bool = true
    ) {
        print("🔧 US-321: Generating \(count) test books for performance testing...")
        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 0..<count {
            let title = sampleTitles[i % sampleTitles.count]
            let author = sampleAuthors[i % sampleAuthors.count]
            let format = formats[i % formats.count]
            let publisher = publishers[i % publishers.count]

            // Generate unique ISBN (add index to base ISBN)
            let baseISBN = sampleISBNs[i % sampleISBNs.count]
            let prefix = String(baseISBN.prefix(9))
            let uniqueISBN = String(format: "%@%04d", prefix, i)

            // Create mock cover URL (use Open Library API)
            let coverUrl: URL? = includeCovers
                ? URL(string: "https://covers.openlibrary.org/b/isbn/\(baseISBN)-L.jpg")
                : nil

            // Vary confidence scores (80% high, 15% medium, 5% low)
            let confidence: Double
            let rand = Double.random(in: 0...1)
            if rand < 0.8 {
                confidence = Double.random(in: 0.85...0.99)  // High confidence
            } else if rand < 0.95 {
                confidence = Double.random(in: 0.6...0.84)   // Medium confidence
            } else {
                confidence = Double.random(in: 0.3...0.59)   // Low confidence
            }

            // Random publication dates (last 20 years)
            let yearsAgo = Int.random(in: 0...20)
            let publishedDate = Calendar.current.date(byAdding: .year, value: -yearsAgo, to: Date())

            // Random page counts
            let pageCount = Int.random(in: 200...800)

            // Create book with full metadata
            let book = Book(
                id: UUID(),
                title: "\(title) (Vol. \(i / sampleTitles.count + 1))",
                author: author,
                isbn: uniqueISBN,
                coverUrl: coverUrl,
                format: format,
                publisher: publisher,
                publishedDate: publishedDate,
                pageCount: pageCount,
                spineConfidence: confidence,
                addedDate: Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            )

            context.insert(book)

            // Batch save every 100 books to avoid memory pressure
            if (i + 1) % 100 == 0 {
                do {
                    try context.save()
                    print("  Saved \(i + 1)/\(count) books...")
                } catch {
                    print("  ⚠️ Failed to save batch: \(error)")
                }
            }
        }

        // Final save
        do {
            try context.save()
        } catch {
            print("  ⚠️ Failed to save final batch: \(error)")
        }

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        print("✅ Generated \(count) test books in \(String(format: "%.2f", duration * 1000))ms")
        print("  Average: \(String(format: "%.2f", (duration * 1000) / Double(count)))ms per book")
    }

    /// Clear all test data from the context
    /// - Parameter context: SwiftData model context
    static func clearTestData(context: ModelContext) {
        print("🧹 Clearing test data...")

        let descriptor = FetchDescriptor<Book>()
        guard let allBooks = try? context.fetch(descriptor) else {
            print("  No books to clear")
            return
        }

        for book in allBooks {
            context.delete(book)
        }

        do {
            try context.save()
            print("✅ Cleared \(allBooks.count) test books")
        } catch {
            print("⚠️ Failed to clear test data: \(error)")
        }
    }
}
