import AVFoundation
@testable import swiftwing
import Testing

struct CameraPhotoDimensionTests {
    @Test func prefersTheSizeNearestA1920LongEdge() {
        let supported = [
            CMVideoDimensions(width: 1024, height: 768),
            CMVideoDimensions(width: 1920, height: 1440),
            CMVideoDimensions(width: 4032, height: 3024),
        ]
        let chosen = CameraManager.preferredPhotoDimensions(supported: supported)
        #expect(chosen?.width == 1920)
        #expect(chosen?.height == 1440)
    }

    @Test func keepsTheOnlySupportedSize() {
        let chosen = CameraManager.preferredPhotoDimensions(
            supported: [CMVideoDimensions(width: 4032, height: 3024)]
        )
        #expect(chosen?.width == 4032)
        #expect(chosen?.height == 3024)
    }

    @Test func tiePrefersTheSmallerFrame() {
        let supported = [
            CMVideoDimensions(width: 2560, height: 1440),
            CMVideoDimensions(width: 1280, height: 720),
        ]
        let chosen = CameraManager.preferredPhotoDimensions(supported: supported)
        #expect(chosen?.width == 1280)
        #expect(chosen?.height == 720)
    }

    @Test func emptySupportReturnsNil() {
        let chosen = CameraManager.preferredPhotoDimensions(supported: [])
        #expect(chosen == nil)
    }
}
