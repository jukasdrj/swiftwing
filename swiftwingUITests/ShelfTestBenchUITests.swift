import XCTest

/// The debug test bench is how Device MCP and Impeccable reach a known screen
/// without a camera. These checks stay on the simulator and do not call Talaria.
@MainActor
final class ShelfTestBenchUITests: SwiftwingUITestCase {
    func testBenchClearsAndSeedsTheLibrary() {
        launchDefault()

        openBench()
        app.buttons["test_bench_clear"].tap()
        app.buttons["test_bench_done"].tap()

        XCTAssertTrue(
            waitForElement(app.staticTexts["library_empty_state"]),
            "Clear should leave the empty library"
        )

        openBench()
        XCTAssertEqual(listedShelfIDs().count, 15, "Every shelf fixture should be in the bench")
        app.buttons["test_bench_done"].tap()

        openBench()
        app.buttons["test_bench_seed"].tap()
        let status = app.staticTexts["test_bench_status"]
        XCTAssertTrue(waitForElement(status), "Seed should report a status")
        XCTAssertTrue(status.label.contains("Seeded"), "Seed status was \(status.label)")
        app.buttons["test_bench_done"].tap()

        XCTAssertTrue(
            waitForElement(app.staticTexts["library_stats_books"], timeout: 10),
            "Seed should fill the library grid"
        )
    }

    /// A SwiftUI list only exposes the rows on screen, so collect ids while scrolling.
    private func listedShelfIDs() -> Set<String> {
        var found = Set<String>()
        for _ in 0..<8 {
            for id in ShelfFixtureIDs.all where app.buttons["test_bench_shelf_\(id)"].exists {
                found.insert(id)
            }
            if found.count == ShelfFixtureIDs.all.count {
                break
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        return found
    }

    private func openBench() {
        let bench = app.buttons["test_bench_open"]
        XCTAssertTrue(waitForElement(bench), "Test bench button should be on the main tabs")
        bench.tap()
        XCTAssertTrue(waitForElement(app.buttons["test_bench_seed"]), "Test bench sheet should open")
    }
}

/// Mirrors `ShelfFixture.catalog` ids. The UI test target cannot import the app module.
private enum ShelfFixtureIDs {
    static let all = [
        "science-paperbacks",
        "blyton-double",
        "shop-wall",
        "african-studies",
        "norsk-set",
        "kazakh-set",
        "winnington-stack",
        "mitre-stacks",
        "walloon-home",
        "glass-cabinet",
        "comic-bays",
        "manga-stacks",
        "window-backlight",
        "loc-aisle",
        "account-ledgers",
    ]
}
