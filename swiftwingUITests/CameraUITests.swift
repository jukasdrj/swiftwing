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
}
