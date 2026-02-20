import XCTest

/// Tests for cross-tab navigation and tab bar behavior
final class NavigationUITests: SwiftwingUITestCase {

    func testTabSwitching() throws {
        launchDefault()

        // Library tab should be selected by default
        let libraryTab = app.tabBars.buttons["Library"]
        XCTAssertTrue(waitForElement(libraryTab), "Library tab should exist")

        // Switch to Review tab
        let reviewTab = app.tabBars.buttons["Review"]
        XCTAssertTrue(waitForElement(reviewTab), "Review tab should exist")
        reviewTab.tap()

        // Verify Review tab content loads (navigation title "Review Queue")
        let reviewTitle = app.navigationBars["Review Queue"]
        XCTAssertTrue(waitForElement(reviewTitle, timeout: 3), "Review Queue title should appear")

        // Switch to Camera tab
        let cameraTab = app.tabBars.buttons["Camera"]
        XCTAssertTrue(waitForElement(cameraTab), "Camera tab should exist")
        cameraTab.tap()

        // Switch back to Library tab
        libraryTab.tap()
    }

    func testLibraryBadgeWithSeededData() throws {
        launchWithSeededLibrary()

        // Library tab should exist with a badge
        let libraryTab = app.tabBars.buttons["Library"]
        XCTAssertTrue(waitForElement(libraryTab), "Library tab should exist")

        // Note: Badge values are not directly queryable via XCUITest in a straightforward way,
        // but the tab should exist and be tappable with seeded data
        libraryTab.tap()

        // Verify stats header shows book count
        let booksStats = app.staticTexts["library_stats_books"]
        XCTAssertTrue(waitForElement(booksStats, timeout: 10), "Library stats should show with seeded data")
    }
}
