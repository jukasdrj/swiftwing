import CoreGraphics
@testable import swiftwing
import Testing

@Suite("Live text geometry")
struct LiveTextGeometryTests {
    @Test func flipsABottomStripWhenAspectsMatch() {
        let rect = LiveTextGeometry.overlayRect(
            visionBottomLeft: CGRect(x: 0, y: 0, width: 1, height: 0.2),
            frameAspect: 1,
            viewAspect: 1
        )
        #expect(rect.origin.x == 0)
        #expect(abs(rect.origin.y - 0.8) < 0.000_1)
        #expect(rect.width == 1)
        #expect(abs(rect.height - 0.2) < 0.000_1)
    }

    @Test func centerBandOfAWideFrameFillsATallerView() {
        // 4:3 frame inside a 2:3 view crops the left and right quarters.
        let rect = LiveTextGeometry.overlayRect(
            visionBottomLeft: CGRect(x: 0.25, y: 0, width: 0.5, height: 1),
            frameAspect: 4.0 / 3.0,
            viewAspect: 2.0 / 3.0
        )
        #expect(abs(rect.origin.x) < 0.000_1)
        #expect(abs(rect.origin.y) < 0.000_1)
        #expect(abs(rect.width - 1) < 0.000_1)
        #expect(abs(rect.height - 1) < 0.000_1)
    }
}
