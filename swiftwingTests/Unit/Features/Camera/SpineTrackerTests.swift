import CoreGraphics
import Foundation
@testable import swiftwing
import Testing

@Suite("Spine tracker")
struct SpineTrackerTests {
    @Test func aMatchedColumnKeepsItsIdentityAndMovesPartway() {
        let id = UUID()
        let previous = [
            SpineTrack(
                id: id,
                rect: CGRect(x: 0.20, y: 0.20, width: 0.08, height: 0.50),
                missed: 0,
                matchedThisFrame: false
            ),
        ]
        let next = SpineTracker.step(
            tracks: previous,
            observed: [CGRect(x: 0.24, y: 0.20, width: 0.08, height: 0.50)]
        )
        #expect(next.count == 1)
        #expect(next[0].id == id)
        #expect(next[0].matchedThisFrame)
        #expect(next[0].missed == 0)
        // 0.20 + (0.24 - 0.20) * 0.45
        #expect(abs(next[0].rect.minX - 0.218) < 0.000_1)
    }

    @Test func anUnmatchedColumnDropsAfterThreeMissedFrames() {
        var tracks = [
            SpineTrack(
                id: UUID(),
                rect: CGRect(x: 0.20, y: 0.20, width: 0.08, height: 0.50),
                missed: 0,
                matchedThisFrame: true
            ),
        ]
        for expectedMissed in 1...3 {
            tracks = SpineTracker.step(tracks: tracks, observed: [])
            #expect(tracks.count == 1)
            #expect(tracks[0].missed == expectedMissed)
            #expect(tracks[0].matchedThisFrame == false)
        }
        tracks = SpineTracker.step(tracks: tracks, observed: [])
        #expect(tracks.isEmpty)
    }

    @Test func aNewColumnArrivesUnmatched() {
        let next = SpineTracker.step(
            tracks: [],
            observed: [CGRect(x: 0.30, y: 0.20, width: 0.08, height: 0.40)]
        )
        #expect(next.count == 1)
        #expect(next[0].matchedThisFrame == false)
        #expect(next[0].missed == 0)
    }

    @Test func coastingOpacityFallsAsMissesClimb() {
        func track(missed: Int, matched: Bool) -> SpineTrack {
            SpineTrack(
                id: UUID(),
                rect: CGRect(x: 0.20, y: 0.20, width: 0.08, height: 0.50),
                missed: missed,
                matchedThisFrame: matched
            )
        }

        #expect(track(missed: 0, matched: true).displayOpacity == 1)
        #expect(track(missed: 0, matched: false).displayOpacity == 0.45)
        let firstMiss = track(missed: 1, matched: false).displayOpacity
        let thirdMiss = track(missed: 3, matched: false).displayOpacity
        #expect(firstMiss < 1)
        #expect(thirdMiss < firstMiss)
        #expect(thirdMiss > 0)
    }
}
