import CoreGraphics
@testable import swiftwing
import Testing

@Suite("Spine columns")
struct SpineColumnGrouperTests {
    @Test func twoSeparatedLinesBecomeTwoColumns() {
        let columns = SpineColumnGrouper.columns(from: [
            CGRect(x: 0.10, y: 0.20, width: 0.08, height: 0.50),
            CGRect(x: 0.40, y: 0.20, width: 0.08, height: 0.50),
        ])
        #expect(columns.count == 2)
        #expect(abs(columns[0].minX - 0.10) < 0.000_1)
        #expect(abs(columns[1].minX - 0.40) < 0.000_1)
    }

    @Test func aNarrowGutterStaysTwoColumns() {
        let columns = SpineColumnGrouper.columns(from: [
            CGRect(x: 0.10, y: 0.20, width: 0.06, height: 0.40),
            CGRect(x: 0.17, y: 0.20, width: 0.06, height: 0.40),
        ])
        #expect(columns.count == 2)
        #expect(abs(columns[0].minX - 0.10) < 0.000_1)
        #expect(abs(columns[1].minX - 0.17) < 0.000_1)
    }

    @Test func overlappingTitleAndAuthorStayOneColumn() {
        let columns = SpineColumnGrouper.columns(from: [
            CGRect(x: 0.20, y: 0.40, width: 0.07, height: 0.08),
            CGRect(x: 0.21, y: 0.50, width: 0.06, height: 0.08),
        ])
        #expect(columns.count == 1)
        #expect(abs(columns[0].minX - 0.20) < 0.000_1)
        #expect(abs(columns[0].height - 0.18) < 0.000_1)
    }

    @Test func aTallVerticalHoleSplitsOneStrip() {
        let columns = SpineColumnGrouper.columns(from: [
            CGRect(x: 0.20, y: 0.55, width: 0.07, height: 0.08),
            CGRect(x: 0.21, y: 0.25, width: 0.06, height: 0.08),
        ])
        #expect(columns.count == 2)
        #expect(columns.allSatisfy { abs($0.height - 0.08) < 0.000_1 })
    }

    @Test func aWideLineDoesNotBridgeOrDeleteNeighbors() {
        let columns = SpineColumnGrouper.columns(from: [
            CGRect(x: 0.10, y: 0.20, width: 0.08, height: 0.40),
            CGRect(x: 0.30, y: 0.20, width: 0.08, height: 0.40),
            CGRect(x: 0.08, y: 0.70, width: 0.32, height: 0.05),
        ])
        #expect(columns.count == 2)
        #expect(abs(columns[0].minX - 0.10) < 0.000_1)
        #expect(abs(columns[1].minX - 0.30) < 0.000_1)
    }

    @Test func wideSpinesOfSimilarWidthAllStay() {
        let columns = SpineColumnGrouper.columns(from: [
            CGRect(x: 0.05, y: 0.20, width: 0.20, height: 0.40),
            CGRect(x: 0.35, y: 0.20, width: 0.22, height: 0.40),
            CGRect(x: 0.65, y: 0.20, width: 0.24, height: 0.40),
        ])
        #expect(columns.count == 3)
    }

    @Test func aShelfWideLineIsIgnored() {
        let columns = SpineColumnGrouper.columns(from: [
            CGRect(x: 0.05, y: 0.80, width: 0.90, height: 0.05),
            CGRect(x: 0.30, y: 0.20, width: 0.08, height: 0.40),
        ])
        #expect(columns.count == 1)
        #expect(abs(columns[0].minX - 0.30) < 0.000_1)
    }

    @Test func aShortFragmentIsDropped() {
        let columns = SpineColumnGrouper.columns(from: [
            CGRect(x: 0.30, y: 0.40, width: 0.05, height: 0.04),
        ])
        #expect(columns.isEmpty)
    }
}
