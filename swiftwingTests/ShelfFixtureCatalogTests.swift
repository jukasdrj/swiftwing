import Foundation
@testable import swiftwing
import Testing

struct ShelfFixtureCatalogTests {
    @Test func catalogHasFifteenDistinctShelves() {
        let catalog = ShelfFixture.catalog
        #expect(catalog.count == 15)
        #expect(Set(catalog.map(\.id)).count == 15)
        for fixture in catalog {
            #expect(fixture.jpegURL.scheme == "https")
            #expect(fixture.jpegURL.host == "commons.wikimedia.org")
            #expect(fixture.jpegURL.query?.contains("width=1920") == true)
            #expect(fixture.fileName.isEmpty == false)
        }
    }

    @Test func shelfFixtureArgumentParses() {
        #expect(TestLaunch.shelfFixtureID(in: ["SHELF_FIXTURE=norsk-set"]) == "norsk-set")
        #expect(TestLaunch.shelfFixtureID(in: ["UI_TESTING", "INJECT_TEST_IMAGE"]) == nil)
        #expect(TestLaunch.shelfFixtureID(in: ["SHELF_FIXTURE="]) == nil)
    }

    @Test func spacesInFileNamesAreEncoded() throws {
        let fixture = try #require(ShelfFixture.catalog.first { $0.id == "african-studies" })
        #expect(fixture.jpegURL.absoluteString.contains("African%20Studies%20Bookshelf.jpg"))
    }
}
