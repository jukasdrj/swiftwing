import XCTest

/// Tests for the Library tab — empty state, seeding, search, sort, filter, detail sheet, selection mode
final class LibraryUITests: SwiftwingUITestCase {

    func testEmptyState() throws {
        launchWithEmptyLibrary()

        // Should show empty state
        let emptyState = app.staticTexts["library_empty_state"]
        XCTAssertTrue(waitForElement(emptyState), "Empty state should be visible when library is empty")
    }

    func testSeedLibrary() throws {
        launchWithSeededLibrary()

        // Should show books in the grid (stats header indicates book count)
        let booksStats = app.staticTexts["library_stats_books"]
        XCTAssertTrue(waitForElement(booksStats, timeout: 10), "Library stats should appear after seeding")
    }

    func testSearchFindsBook() throws {
        launchWithSeededLibrary()

        // Wait for library to load
        let booksStats = app.staticTexts["library_stats_books"]
        XCTAssertTrue(waitForElement(booksStats, timeout: 10))

        // Tap search field and type "Dune"
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(waitForElement(searchField), "Search field should exist")
        searchField.tap()
        searchField.typeText("Dune")

        // Should find the book (book cells render as buttons in the accessibility tree)
        let duneCell = app.buttons["book_cell_9780441172719"]
        XCTAssertTrue(waitForElement(duneCell, timeout: 10), "Dune should appear in search results")
    }

    func testSearchEmptyState() throws {
        launchWithSeededLibrary()

        let booksStats = app.staticTexts["library_stats_books"]
        XCTAssertTrue(waitForElement(booksStats, timeout: 10))

        // Search for nonsense
        let searchField = app.searchFields.firstMatch
        searchField.tap()
        searchField.typeText("zzzzxxxxxnonexistent")

        // Should show no results
        let noResults = app.staticTexts["library_no_results"]
        let noResultsTitle = app.staticTexts["No Results"]
        XCTAssertTrue(
            waitForElement(noResults, timeout: 10) || waitForElement(noResultsTitle, timeout: 2),
            "Should show 'No results' for nonsense search"
        )
    }

    func testSortMenuExists() throws {
        launchWithSeededLibrary()

        let booksStats = app.staticTexts["library_stats_books"]
        XCTAssertTrue(waitForElement(booksStats, timeout: 10))

        // Tap sort menu
        let sortMenu = app.buttons["library_sort_menu"]
        XCTAssertTrue(waitForElement(sortMenu), "Sort menu button should exist")
        sortMenu.tap()

        // Verify sort options appear
        let titleAZ = app.buttons["Title A-Z"]
        XCTAssertTrue(waitForElement(titleAZ, timeout: 3), "Sort option 'Title A-Z' should appear in menu")
    }

    func testReviewFilter() throws {
        launchWithSeededLibrary()

        let booksStats = app.staticTexts["library_stats_books"]
        XCTAssertTrue(waitForElement(booksStats, timeout: 10))

        // Tap review filter
        let reviewFilter = app.buttons["library_review_filter"]
        XCTAssertTrue(waitForElement(reviewFilter), "Review filter button should exist")
        reviewFilter.tap()

        // With seeded data (all high confidence), should show "No books need review" state
        let noReviewText = app.staticTexts["library_no_review_needed"]
        let noReviewTitle = app.staticTexts["No Books Need Review"]
        XCTAssertTrue(
            waitForElement(noReviewText, timeout: 10) || waitForElement(noReviewTitle, timeout: 2),
            "Should show 'No books need review' when all seeded books are high confidence"
        )
    }

    func testBookDetailSheet() throws {
        launchWithSeededLibrary()

        let booksStats = app.staticTexts["library_stats_books"]
        XCTAssertTrue(waitForElement(booksStats, timeout: 10))

        // Tap first visible book cell (Saga is first in default sort)
        let firstBook = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'book_cell_'")).firstMatch
        XCTAssertTrue(waitForElement(firstBook, timeout: 5), "A book cell should exist")
        firstBook.tap()

        // Detail sheet should appear with close button
        let closeButton = app.buttons["detail_close_button"]
        XCTAssertTrue(waitForElement(closeButton, timeout: 5), "Detail sheet close button should appear")
    }

    func testSelectMode() throws {
        launchWithSeededLibrary()

        let booksStats = app.staticTexts["library_stats_books"]
        XCTAssertTrue(waitForElement(booksStats, timeout: 10))

        // Tap Select button
        let selectButton = app.buttons["library_select_button"]
        XCTAssertTrue(waitForElement(selectButton), "Select button should exist")
        selectButton.tap()

        // Cancel selection should appear
        let cancelButton = app.buttons["library_cancel_selection"]
        XCTAssertTrue(waitForElement(cancelButton, timeout: 3), "Cancel selection button should appear in selection mode")

        // Exit selection mode
        cancelButton.tap()
        XCTAssertTrue(waitForElement(selectButton, timeout: 3), "Select button should reappear after cancelling selection")
    }

    func testExportButton() throws {
        launchWithSeededLibrary()

        let booksStats = app.staticTexts["library_stats_books"]
        XCTAssertTrue(waitForElement(booksStats, timeout: 10))

        // Export button should exist
        let exportButton = app.buttons["library_export_button"]
        XCTAssertTrue(waitForElement(exportButton), "Export button should exist in toolbar")
    }
}
