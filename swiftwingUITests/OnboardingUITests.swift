import XCTest

/// Tests for the onboarding flow shown on first app launch.
/// These tests do not pass UI_TESTING, so the camera permission gate stays on.
@MainActor
final class OnboardingUITests: XCTestCase {
    // See SwiftwingUITestCase.app. This class does not inherit that setup,
    // because it must launch without the UI_TESTING argument.
    nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Do NOT pass UI_TESTING here — we want onboarding to show.
        let application = MainActor.assumeIsolated { XCUIApplication() }
        app = application
    }

    override func tearDownWithError() throws {
        let application = app
        MainActor.assumeIsolated {
            application?.terminate()
        }
    }

    func testSkipOnboarding() throws {
        app.resetAuthorizationStatus(for: .camera)
        app.launchArguments = ["FORCE_ONBOARDING"]
        app.launch()

        let skipButton = app.buttons["onboarding_skip"]
        try XCTSkipUnless(skipButton.waitForExistence(timeout: 3), "Onboarding not shown")

        skipButton.tap()
        try assertPermissionPrimer()
    }

    func testNextThroughAllSlides() throws {
        app.resetAuthorizationStatus(for: .camera)
        app.launchArguments = ["FORCE_ONBOARDING"]
        app.launch()

        let nextButton = app.buttons["onboarding_next"]
        try XCTSkipUnless(nextButton.waitForExistence(timeout: 3), "Onboarding not shown")

        // Tap Next twice (slide 0 → 1 → 2)
        nextButton.tap()

        let nextButton2 = app.buttons["onboarding_next"]
        XCTAssertTrue(nextButton2.waitForExistence(timeout: 2), "Next button should appear on slide 2")
        nextButton2.tap()

        // Final slide should show "Get Started"
        let getStartedButton = app.buttons["onboarding_get_started"]
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 2), "Get Started button should appear on final slide")
        getStartedButton.tap()

        try assertPermissionPrimer()
    }

    /// Denying the system camera prompt must replace Continue with the Open Settings primer.
    func testDenyingSystemPromptShowsOpenSettingsPrimer() throws {
        app.resetAuthorizationStatus(for: .camera)
        app.launchArguments = ["FORCE_ONBOARDING"]
        app.launch()

        let skipButton = app.buttons["onboarding_skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "Onboarding not shown")
        skipButton.tap()

        let continueButton = app.buttons["permission_continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5), "Continue primer should be on screen")
        XCTAssertEqual(continueButton.label, "Continue")
        continueButton.tap()

        XCTAssertTrue(denySystemCameraPrompt(), "System camera prompt did not offer Don't Allow")
        dismissInAppDenialAlertIfPresent()

        XCTAssertTrue(
            app.staticTexts["Camera Access Required"].waitForExistence(timeout: 3),
            "A denial must record denied and show the Open Settings primer"
        )
        XCTAssertTrue(app.buttons["Open Settings"].exists)
        XCTAssertFalse(app.staticTexts["SwiftWing Needs Camera Access"].exists)
    }

    /// A grant made in Settings replaces the primer on the next permission read.
    /// The UI test process cannot call simctl, so this drives the Settings switch.
    /// This simulator keeps the old status for the running process, so the check
    /// is the following launch. RootView also re-reads when the scene becomes active.
    func testGrantingCameraInSettingsReplacesPrimerOnNextRead() throws {
        addUIInterruptionMonitor(withDescription: "Deny camera") { alert in
            for label in ["Don’t Allow", "Don't Allow"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        app.resetAuthorizationStatus(for: .camera)
        app.launchArguments = ["FORCE_ONBOARDING"]
        app.launch()

        let skipButton = app.buttons["onboarding_skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "Onboarding not shown")
        skipButton.tap()

        if !app.buttons["Open Settings"].waitForExistence(timeout: 2) {
            let continueButton = app.buttons["permission_continue"]
            XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
            continueButton.tap()
            XCTAssertTrue(denySystemCameraPrompt(), "System camera prompt did not offer Don't Allow")
        }

        let openSettings = app.buttons["Open Settings"]
        XCTAssertTrue(openSettings.waitForExistence(timeout: 3), "Denial should offer Open Settings")
        openSettings.tap()

        enableCameraInSettings()
        // This simulator keeps the previous authorization status for the running
        // process. The next launch is what checkCameraPermission reads. RootView
        // also re-reads when the scene becomes active, which is the device path
        // once the system reports the new status without a restart.
        app.terminate()
        app.launchArguments = ["FORCE_ONBOARDING"]
        app.launch()

        let skipAgain = app.buttons["onboarding_skip"]
        XCTAssertTrue(skipAgain.waitForExistence(timeout: 5))
        skipAgain.tap()

        XCTAssertTrue(
            app.tabBars.buttons["Library"].waitForExistence(timeout: 5),
            "A Settings grant must replace the primer on the next permission read"
        )
    }

    /// The primer is required whenever camera access is not authorized.
    /// Landing on the Library tab does not satisfy this.
    private func assertPermissionPrimer() throws {
        let permissionButton = app.buttons["permission_continue"]
        XCTAssertTrue(
            permissionButton.waitForExistence(timeout: 3),
            "Permission primer must appear when camera is not authorized"
        )
        XCTAssertFalse(
            app.tabBars.buttons["Library"].exists,
            "Library tab is not a stand-in for the permission primer"
        )
    }

    private func dismissInAppDenialAlertIfPresent() {
        let cancel = app.alerts.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) {
            cancel.tap()
        }
    }

    private func denySystemCameraPrompt() -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let labels = ["Don’t Allow", "Don't Allow"]
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            for label in labels {
                if tapIfPresent(app.buttons[label]) { return true }
                if tapIfPresent(app.alerts.buttons[label]) { return true }
                if tapIfPresent(springboard.buttons[label]) { return true }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    private func tapIfPresent(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        element.tap()
        return true
    }

    /// `openSettingsURLString` lands on the Settings root in this simulator.
    /// The app toggle is under Privacy & Security → Camera. Row queries match identifier.
    private func enableCameraInSettings() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        let privacy = settings.buttons.matching(identifier: "com.apple.settings.privacyAndSecurity").firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 5), "Privacy & Security row missing")
        if !privacy.isHittable {
            settings.swipeUp()
        }
        privacy.tap()

        // Camera sits further down the privacy list and is not in the tree until scrolled.
        let camera = settings.buttons.matching(identifier: "CAMERA").firstMatch
        var foundCamera = camera.waitForExistence(timeout: 1)
        if !foundCamera {
            for _ in 0..<8 {
                settings.swipeUp()
                if camera.waitForExistence(timeout: 1) {
                    foundCamera = true
                    break
                }
            }
        }
        XCTAssertTrue(foundCamera, "Camera row missing under Privacy & Security")
        camera.tap()

        let appSwitch = settings.switches.matching(identifier: "com.ooheynerds.swiftwing").firstMatch
        XCTAssertTrue(appSwitch.waitForExistence(timeout: 3), "Camera privacy page has no swiftoooe switch")
        if !appSwitch.isHittable {
            settings.swipeUp()
        }
        // The row's center tap does not flip the control. Hit the switch itself.
        appSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let refreshed = settings.switches.matching(identifier: "com.ooheynerds.swiftwing").firstMatch
        let value = String(describing: refreshed.value)
        XCTAssertTrue(isOn(refreshed), "Camera switch did not turn on (value \(value), hittable \(appSwitch.isHittable))")
    }

    private func isOn(_ element: XCUIElement) -> Bool {
        let value = element.value
        if let number = value as? NSNumber { return number.intValue == 1 }
        if let string = value as? String { return string == "1" }
        return false
    }
}
