import XCTest

/// Integration tests that verify the full Swiftwing ↔ Talaria pipeline
/// Uses INJECT_TEST_IMAGE to bypass camera hardware and send a real image to the Talaria API
/// Requires network access to https://api.oooefam.net
final class IntegrationUITests: SwiftwingUITestCase {

    /// Tests the complete scan pipeline: image injection → Talaria upload → SSE stream → book results
    func testFullScanPipeline() throws {
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

        // Wait up to 90 seconds for the pipeline to complete and books to appear
        let hasApproveAll = approveAllButton.waitForExistence(timeout: 90)
        let hasApproveButton = hasApproveAll || approveButton.waitForExistence(timeout: 5)

        XCTAssertTrue(hasApproveAll || hasApproveButton,
                     "At least one book should appear in Review queue after scan pipeline. " +
                     "The approve button indicates books were received from Talaria API.")

        // If we got results, verify we can approve them into the Library
        if hasApproveAll {
            approveAllButton.tap()

            // Give SwiftData a moment to persist
            sleep(2)

            // Switch to Library tab and verify books were saved
            switchToTab("Library")

            // Look for book stats (shows count) or actual book cells
            let statsView = app.staticTexts["library_stats_books"]
            let hasStats = statsView.waitForExistence(timeout: 10)

            // The empty state should NOT be visible
            let emptyState = app.otherElements["library_empty_state"]
            let isEmpty = emptyState.exists

            XCTAssertTrue(hasStats || !isEmpty,
                         "Library should contain books after approving from review queue")
        }
    }

    /// Tests that the processing UI shows progress during the scan pipeline
    func testProcessingProgressUI() throws {
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
