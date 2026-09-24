import Foundation
import Testing
import SwiftData
@testable import swiftwing

@Suite("LibraryViewModel low-confidence filter")
@MainActor
struct LibraryViewModelTests {
    @Test func highConfidenceNotFoundStaysOutOfTheLowConfidenceFilter() throws {
        let context = try makeSwiftDataContext()
        context.insert(Book(
            title: "Found by confidence",
            author: "Author",
            isbn: "9780000001111",
            spineConfidence: 0.4,
            enrichmentStatus: "success"
        ))
        context.insert(Book(
            title: "Not found but sure",
            author: "Author",
            isbn: "9780000002222",
            spineConfidence: 0.95,
            enrichmentStatus: "not_found"
        ))
        try context.save()

        let viewModel = LibraryViewModel()
        let previous = viewModel.showReviewNeeded
        defer { viewModel.showReviewNeeded = previous }
        viewModel.showReviewNeeded = true
        viewModel.searchText = ""
        viewModel.updateFilteredBooks(context: context)

        let titles = viewModel.filteredBooks(from: []).map(\.title)
        #expect(titles.contains("Found by confidence"))
        #expect(!titles.contains("Not found but sure"))
    }
}
