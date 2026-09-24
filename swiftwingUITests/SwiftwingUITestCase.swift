import XCTest

/// Base class for all SwiftWing UI tests
/// Provides common setup, launch configurations, and helper methods
@MainActor
class SwiftwingUITestCase: XCTestCase {
    /// XCTest's setUpWithError() override is nonisolated, and XCUIApplication is
    /// main-actor isolated. The property is touched only from setUp and from
    /// @MainActor test methods, both of which run on the main thread.
    nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let application = MainActor.assumeIsolated { () -> XCUIApplication in
            let application = XCUIApplication()
            application.launchArguments = ["UI_TESTING"]
            return application
        }
        app = application
    }

    /// Launch app with a pre-seeded library of 25 books
    func launchWithSeededLibrary() {
        app.launchArguments.append("SEED_LIBRARY")
        app.launch()
    }

    /// Launch app with an empty library (all data cleared)
    func launchWithEmptyLibrary() {
        app.launchArguments.append("CLEAR_DATA")
        app.launch()
    }

    /// Launch app with default state (UI_TESTING only - skips onboarding)
    func launchDefault() {
        app.launch()
    }

    // MARK: - Helper Methods

    /// Wait for an element to exist with a timeout
    @discardableResult
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    /// Tap a tab by its label text
    func switchToTab(_ label: String) {
        let tab = app.tabBars.buttons[label]
        XCTAssertTrue(waitForElement(tab), "Tab '\(label)' should exist")
        tab.tap()
    }
}
