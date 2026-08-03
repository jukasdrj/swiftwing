import XCTest

/// Tests for the Camera tab
/// Note: Camera hardware is not available in Simulator, so tests verify UI elements exist
final class CameraUITests: SwiftwingUITestCase {

    func testCameraTabSwitch() throws {
        launchDefault()

        // Switch to Camera tab
        switchToTab("Camera")

        // Shutter button should exist (even without camera hardware)
        let shutterButton = app.buttons["camera_shutter"]
        XCTAssertTrue(waitForElement(shutterButton, timeout: 5), "Shutter button should exist on camera tab")
    }

    func testShutterButtonExists() throws {
        launchDefault()

        switchToTab("Camera")

        let shutterButton = app.buttons["camera_shutter"]
        XCTAssertTrue(waitForElement(shutterButton, timeout: 5), "Shutter button should be visible")
    }

    // MARK: - Phase 9 camera controls

    /// The zoom slider and AE/AF lock are pure overlay chrome, so they render in
    /// the Simulator even though neither can actuate without a capture device.
    func testZoomSliderAndLockControlExist() throws {
        launchDefault()

        switchToTab("Camera")

        let zoomSlider = app.sliders["camera_zoom_slider"]
        XCTAssertTrue(waitForElement(zoomSlider, timeout: 5), "Zoom slider should exist on camera tab")
        XCTAssertTrue(zoomSlider.isHittable, "Zoom slider should not be obscured by another overlay")

        let lockButton = app.buttons["camera_ae_af_lock_button"]
        XCTAssertTrue(waitForElement(lockButton, timeout: 5), "AE/AF lock button should exist")
        XCTAssertTrue(lockButton.isHittable, "AE/AF lock button should not be obscured")
    }

    /// FORCE_CAMERA_GUIDANCE clears hasSeenCameraGuidance; UI_TESTING otherwise
    /// sets it, so this is the only test that should see the coach overlay.
    func testFirstRunGuidanceAppearsThenDismisses() throws {
        app.launchArguments.append("FORCE_CAMERA_GUIDANCE")
        launchDefault()

        switchToTab("Camera")

        let dismissButton = app.buttons["camera_guidance_dismiss_button"]
        XCTAssertTrue(waitForElement(dismissButton, timeout: 5), "Guidance should appear on first camera visit")

        dismissButton.tap()

        XCTAssertTrue(
            dismissButton.waitForNonExistence(timeout: 5),
            "Guidance should disappear once dismissed"
        )

        // The controls underneath must now be reachable.
        XCTAssertTrue(app.buttons["camera_shutter"].isHittable, "Shutter should be usable after dismissal")
    }

    /// The default UI-testing launch must never show the coach overlay, otherwise
    /// every other camera test runs behind a modal.
    func testGuidanceSuppressedForNormalUITestLaunch() throws {
        launchDefault()

        switchToTab("Camera")

        XCTAssertTrue(waitForElement(app.buttons["camera_shutter"], timeout: 5))
        XCTAssertFalse(
            app.buttons["camera_guidance_dismiss_button"].exists,
            "Guidance must be suppressed under UI_TESTING"
        )
    }
}
