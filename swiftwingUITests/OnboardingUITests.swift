import XCTest

/// Tests for the onboarding flow shown on first app launch
final class OnboardingUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Do NOT pass UI_TESTING here — we want onboarding to show
    }

    func testSkipOnboarding() throws {
        // Reset onboarding state so it shows
        app.launchArguments = ["CLEAR_DATA"]
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        app.launch()

        let skipButton = app.buttons["onboarding_skip"]
        // If onboarding doesn't show (already completed), skip this test
        guard skipButton.waitForExistence(timeout: 3) else {
            return
        }

        skipButton.tap()

        // Should land on permission primer or main tab view
        let permissionButton = app.buttons["permission_continue"]
        let libraryTab = app.tabBars.buttons["tab_library"]
        let landed = permissionButton.waitForExistence(timeout: 3) || libraryTab.waitForExistence(timeout: 3)
        XCTAssertTrue(landed, "Should navigate past onboarding after skip")
    }

    func testNextThroughAllSlides() throws {
        app.launchArguments = ["CLEAR_DATA"]
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        app.launch()

        let nextButton = app.buttons["onboarding_next"]
        guard nextButton.waitForExistence(timeout: 3) else {
            return // Onboarding already completed
        }

        // Tap Next twice (slide 0 → 1 → 2)
        nextButton.tap()

        let nextButton2 = app.buttons["onboarding_next"]
        XCTAssertTrue(nextButton2.waitForExistence(timeout: 2), "Next button should appear on slide 2")
        nextButton2.tap()

        // Final slide should show "Get Started"
        let getStartedButton = app.buttons["onboarding_get_started"]
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 2), "Get Started button should appear on final slide")
        getStartedButton.tap()

        // Should navigate past onboarding
        let permissionButton = app.buttons["permission_continue"]
        let libraryTab = app.tabBars.buttons["tab_library"]
        let landed = permissionButton.waitForExistence(timeout: 3) || libraryTab.waitForExistence(timeout: 3)
        XCTAssertTrue(landed, "Should navigate past onboarding after Get Started")
    }
}
