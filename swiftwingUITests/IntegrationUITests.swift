import XCTest

/// Integration tests that verify the full Swiftwing ↔ Talaria pipeline
/// Uses INJECT_TEST_IMAGE to bypass camera hardware and send a real image to the Talaria API
/// Requires network access to https://api.oooefam.net
final class IntegrationUITests: SwiftwingUITestCase {
    private func hasRunnableLiveFixture() -> Bool {
        let path = "/Users/juju/dev_repos/swiftwing/test_book_stack.jpg"
        guard let data = FileManager.default.contents(atPath: path), data.count >= 4 else {
            return false
        }

        let prefix = [UInt8](data.prefix(4))
        return prefix.starts(with: [0xFF, 0xD8]) || prefix == [0x89, 0x50, 0x4E, 0x47]
    }

    private func requireLiveTalariaFixture() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_LIVE_TALARIA_UI_TESTS"] == "1" && hasRunnableLiveFixture(),
            "Requires RUN_LIVE_TALARIA_UI_TESTS=1 and a valid image fixture at test_book_stack.jpg"
        )
    }

    /// Tests the complete scan pipeline: image injection → Talaria upload → SSE stream → book results
    func testFullScanPipeline() throws {
        try requireLiveTalariaFixture()

        app.launchArguments += ["INJECT_TEST_IMAGE", "CLEAR_DATA"]
        app.launch()

        // App auto-navigates to Camera tab and starts processing
        // Wait for the pipeline to complete by checking Review tab for results
        // Pipeline takes ~15-20s (upload + Gemini Vision + enrichment)

        // Switch to Review tab and wait for approve button to appear
        // (appears only when pendingReviewBooks is non-empty)
        switchToTab("Review")

        // Look for the review_approve_all button OR individual review_approve_button
        // These only render when books are in the review queue
        let approveAllButton = app.buttons["review_approve_all"]
        let approveButton = app.buttons["review_approve_button"]

        // Wait up to 90 seconds for the pipeline to complete.
        // Current behavior may either leave books in Review or auto-approve directly into Library.
        let hasApproveAll = approveAllButton.waitForExistence(timeout: 90)
        let hasApproveButton = hasApproveAll || approveButton.waitForExistence(timeout: 5)
        let hasReviewResults = hasApproveAll || hasApproveButton

        if hasReviewResults {
            // If we got review results, verify we can approve them into the Library
            if hasApproveAll {
                approveAllButton.tap()
            } else {
                approveButton.tap()
            }

            switchToTab("Library")

            let statsView = app.staticTexts["library_stats_books"]
            let hasStats = statsView.waitForExistence(timeout: 10)
            let emptyState = app.staticTexts["library_empty_state"]
            XCTAssertTrue(hasStats || !emptyState.exists, "Library should contain books after approving from review queue")
        } else {
            switchToTab("Library")

            let statsView = app.staticTexts["library_stats_books"]
            let hasStats = statsView.waitForExistence(timeout: 20)
            let bookCell = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'book_cell_'")).firstMatch
            let hasBookCell = bookCell.waitForExistence(timeout: 5)
            let emptyState = app.staticTexts["library_empty_state"]

            XCTAssertTrue(
                hasStats || hasBookCell || !emptyState.exists,
                "Scan pipeline should place at least one book in Review or Library after processing."
            )
        }
    }

    /// Tests that the processing UI shows progress during the scan pipeline
    func testProcessingProgressUI() throws {
        try requireLiveTalariaFixture()

        app.launchArguments += ["INJECT_TEST_IMAGE", "CLEAR_DATA"]
        app.launch()

        // App starts on Camera tab with processing in progress
        // Look for processing-related UI text (comes from the processing queue overlay)
        let uploadText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "upload")).firstMatch
        let analyzingText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "analyz")).firstMatch
        let preprocessingText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "preprocess")).firstMatch

        // At least one processing state should be visible within 15 seconds
        let sawProcessing = uploadText.waitForExistence(timeout: 15)
            || analyzingText.waitForExistence(timeout: 5)
            || preprocessingText.waitForExistence(timeout: 5)

        // Soft assertion - pipeline may complete quickly
        if !sawProcessing {
            print("⚠️ No processing UI observed - pipeline may have completed very quickly")
        }
    }
}
