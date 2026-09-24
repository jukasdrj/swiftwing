import Foundation
@testable import swiftwing
import Testing

@Suite("Rate-limit temp files")
struct RateLimitStateTests {
    @Test func queuedFileSitsOutsideTheOneHourSweep() async throws {
        let state = RateLimitState()
        await state.queueScan(Data([0xFF, 0xD8, 0xFF, 0xD9]))

        let directory = RateLimitState.sessionDirectory
        let queued = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "jpg" }
        let file = try #require(queued.first)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(SwiftwingApp.tempSweepWouldDelete(file) == false)

        let topLevel = FileManager.default.temporaryDirectory.appendingPathComponent("plain.jpg")
        #expect(SwiftwingApp.tempSweepWouldDelete(topLevel))
    }
}
