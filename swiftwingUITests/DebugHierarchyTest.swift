import XCTest

/// Diagnostic test for debugging accessibility hierarchy issues
/// Enable individual tests as needed — not part of regular test suite
final class DebugHierarchyTest: XCTestCase {

    override func setUpWithError() throws {
        // Skip all debug tests by default — enable manually when debugging
        try XCTSkipIf(true, "Debug hierarchy tests are disabled by default")
    }

    func testDumpAccessibilityTree() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UI_TESTING", "SEED_LIBRARY"]
        app.launch()
        sleep(3)

        // Dump full hierarchy
        print("=== ACCESSIBILITY TREE ===")
        print(app.debugDescription)
        print("=== END ===")
    }
}
