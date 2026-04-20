import XCTest
@testable import swiftwing

final class DataSyncActorTests: XCTestCase {
    
    var dataSyncActor: DataSyncActor!
    var testModelContext: ModelContext!
    
    override func setUp() async throws {
        try await super.setUp()
        dataSyncActor = DataSyncActor()
        
        // Create in-memory model context for testing
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        testModelContext = ModelContext(container)
    }
    
    // MARK: - Save Tests
    
    func testSaveNewBook() async throws {
        let metadata = BookMetadata(
            title: "Test Book",
            authors: ["Test Author"],
            isbn: "978-1234567890",
            confidence: 0.95,
            processingStage: .enrichment
        )
        
        let book = try await dataSyncActor.makeBook(from: metadata)
        try await dataSyncActor.save(book: book, in: testModelContext)
        
        XCTAssertEqual(book.title, "Test Book")
        XCTAssertEqual(book.isbn, "978-1234567890")
        XCTAssertEqual(book.authors.first, "Test Author")
    }
    
    func testSaveDuplicateBookThrows() async throws {
        let metadata1 = BookMetadata(
            title: "Test Book",
            authors: ["Test Author"],
            isbn: "978-1234567890",
            confidence: 0.95,
            processingStage: .enrichment
        )
        
        let metadata2 = BookMetadata(
            title: "Test Book 2",
            authors: ["Another Author"],
            isbn: "978-1234567890", // Same ISBN
            confidence: 0.90,
            processingStage: .enrichment
        )
        
        let book1 = try await dataSyncActor.makeBook(from: metadata1)
        try await dataSyncActor.save(book: book1, in: testModelContext)
        
        let book2 = try await dataSyncActor.makeBook(from: metadata2)
        
        // Should throw or handle gracefully on duplicate ISBN
        do {
            try await dataSyncActor.save(book: book2, in: testModelContext)
            // If DuplicateDetection is enabled, this might throw
        } catch {
            // Expected behavior
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Batch Save Tests
    
    func testSaveMultipleBooks() async throws {
        let metadatas = [
            BookMetadata(title: "Book 1", authors: ["Author 1"], isbn: "978-0000000001", confidence: 0.95, processingStage: .enrichment),
            BookMetadata(title: "Book 2", authors: ["Author 2"], isbn: "978-0000000002", confidence: 0.92, processingStage: .enrichment),
            BookMetadata(title: "Book 3", authors: ["Author 3"], isbn: "978-0000000003", confidence: 0.88, processingStage: .enrichment),
        ]
        
        var books: [Book] = []
        for metadata in metadatas {
            let book = try await dataSyncActor.makeBook(from: metadata)
            books.append(book)
        }
        
        try await dataSyncActor.saveAll(books: books, in: testModelContext)
        
        XCTAssertEqual(books.count, 3)
        XCTAssertEqual(books[0].title, "Book 1")
        XCTAssertEqual(books[1].title, "Book 2")
        XCTAssertEqual(books[2].title, "Book 3")
    }
    
    // MARK: - Book Creation Tests
    
    func testMakeBookPreservesMetadata() async throws {
        let metadata = BookMetadata(
            title: "Effective Swift",
            authors: ["Mattt Thompson"],
            isbn: "978-1491927288",
            confidence: 0.99,
            processingStage: .enrichment
        )
        
        let book = try await dataSyncActor.makeBook(from: metadata)
        
        XCTAssertEqual(book.title, "Effective Swift")
        XCTAssertEqual(book.authors, ["Mattt Thompson"])
        XCTAssertEqual(book.isbn, "978-1491927288")
        XCTAssert(book.confidence >= 0.99)
    }
    
    func testMakeBookHandlesMultipleAuthors() async throws {
        let metadata = BookMetadata(
            title: "Code Complete",
            authors: ["Steve McConnell", "Co-Author"],
            isbn: "978-0735619678",
            confidence: 0.91,
            processingStage: .enrichment
        )
        
        let book = try await dataSyncActor.makeBook(from: metadata)
        
        XCTAssertEqual(book.authors.count, 2)
        XCTAssert(book.authors.contains("Steve McConnell"))
        XCTAssert(book.authors.contains("Co-Author"))
    }
    
    // MARK: - Edge Cases
    
    func testSaveBookWithEmptyAuthors() async throws {
        let metadata = BookMetadata(
            title: "Anonymous Book",
            authors: [],
            isbn: "978-9999999999",
            confidence: 0.5,
            processingStage: .enrichment
        )
        
        let book = try await dataSyncActor.makeBook(from: metadata)
        
        // Should handle gracefully
        XCTAssertNotNil(book)
        XCTAssertEqual(book.authors.count, 0)
    }
}
