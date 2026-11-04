import AVFoundation
import CoreGraphics
import Foundation
import Vision

struct LiveTextObservation: Sendable, Identifiable {
    let id: UUID
    let text: String
    /// Vision normalized rect. Origin is the bottom left of the upright frame.
    let visionBottomLeft: CGRect
}

/// Maps a Vision rect onto the aspect-filled camera preview.
enum LiveTextGeometry {
    static func overlayRect(
        visionBottomLeft: CGRect,
        frameAspect: CGFloat,
        viewAspect: CGFloat
    ) -> CGRect {
        let upright = CGRect(
            x: visionBottomLeft.origin.x,
            y: 1 - visionBottomLeft.origin.y - visionBottomLeft.height,
            width: visionBottomLeft.width,
            height: visionBottomLeft.height
        )
        guard frameAspect > 0, viewAspect > 0, frameAspect != viewAspect else {
            return upright
        }

        if frameAspect > viewAspect {
            let visibleWidth = viewAspect / frameAspect
            let cropX = (1 - visibleWidth) / 2
            return CGRect(
                x: (upright.origin.x - cropX) / visibleWidth,
                y: upright.origin.y,
                width: upright.width / visibleWidth,
                height: upright.height
            )
        }

        let visibleHeight = frameAspect / viewAspect
        let cropY = (1 - visibleHeight) / 2
        return CGRect(
            x: upright.origin.x,
            y: (upright.origin.y - cropY) / visibleHeight,
            width: upright.width,
            height: upright.height / visibleHeight
        )
    }
}

/// Sample-buffer delegate. Vision runs on `sampleQueue`; the handler only receives sendable rects.
/// Mutable state is guarded by `lock`.
final class LiveFrameBridge: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let sampleQueue = DispatchQueue(label: "com.ooheynerds.swiftwing.live-text")
    private let lock = NSLock()
    private var handler: (@Sendable ([LiveTextObservation]) -> Void)?
    private var lastAccepted = CFAbsoluteTime(0)

    func setHandler(_ handler: (@Sendable ([LiveTextObservation]) -> Void)?) {
        lock.withLock { self.handler = handler }
    }

    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        let accepted = lock.withLock { () -> Bool in
            guard now - lastAccepted >= 0.2 else { return false }
            lastAccepted = now
            return true
        }
        guard accepted else { return }

        let observations = Self.observations(in: sampleBuffer)
        let handler = lock.withLock { self.handler }
        handler?(observations)
    }

    private static func observations(in sampleBuffer: CMSampleBuffer) -> [LiveTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return LiveTextObservation(id: UUID(), text: trimmed, visionBottomLeft: observation.boundingBox)
        }
    }
}

/// Groups upright Vision text rects into one axis-aligned column per spine.
///
/// A line joins a column when at least half of the narrower width overlaps in X.
/// A fixed gap merges neighboring paperbacks and still splits one staggered spine.
/// A vertical hole larger than twice the median line height starts another column,
/// so a second shelf in the same strip does not become one tall box.
/// Banners are removed before the merge: wider than 0.45 of the frame, or wider than
/// twice the median line. Nothing is discarded because a union grew too wide.
enum SpineColumnGrouper {
    /// Half of the narrower width must sit inside the column.
    static let minimumOverlapFraction: CGFloat = 0.5
    /// Wider than this, a line is a shelf label rather than spine text.
    static let maximumLineWidth: CGFloat = 0.45
    /// Wider than this multiple of the median line width, a line is a banner.
    static let maximumWidthMultiple: CGFloat = 2
    /// A hole taller than this multiple of the median line height splits a column.
    static let maximumVerticalGapMultiple: CGFloat = 2
    /// Shorter than this, a column is a scrap of text.
    static let minimumColumnHeight: CGFloat = 0.06

    static func columns(from boxes: [CGRect]) -> [CGRect] {
        let valid = boxes.filter { $0.width > 0 && $0.height > 0 }
        let withinFrame = valid.filter { $0.width <= maximumLineWidth }
        guard !withinFrame.isEmpty else { return [] }

        let medianWidth = median(withinFrame.map(\.width))
        let lines = withinFrame.filter { $0.width <= medianWidth * maximumWidthMultiple }
        guard !lines.isEmpty else { return [] }

        let sorted = lines.sorted { $0.midX < $1.midX }
        var groups: [[CGRect]] = []
        for box in sorted {
            // A line can overlap an earlier column and not the latest one.
            // Join every column it overlaps, or one spine becomes two.
            let hits = groups.indices.filter { overlaps(box, union(groups[$0])) }
            if hits.isEmpty {
                groups.append([box])
                continue
            }
            var merged = hits.flatMap { groups[$0] }
            merged.append(box)
            for index in hits.reversed() {
                groups.remove(at: index)
            }
            groups.append(merged)
        }

        let columns = groups.flatMap { splitVertically($0) }
        return columns
            .filter { $0.height >= minimumColumnHeight }
            .sorted { $0.midX < $1.midX }
    }

    private static func overlaps(_ line: CGRect, _ column: CGRect) -> Bool {
        let overlap = min(line.maxX, column.maxX) - max(line.minX, column.minX)
        guard overlap > 0 else { return false }
        let narrower = min(line.width, column.width)
        guard narrower > 0 else { return false }
        return overlap / narrower >= minimumOverlapFraction
    }

    /// Splits one X-cluster where the text leaves a tall hole.
    private static func splitVertically(_ boxes: [CGRect]) -> [CGRect] {
        let sorted = boxes.sorted { $0.minY < $1.minY }
        guard let first = sorted.first else { return [] }
        let maxGap = median(sorted.map(\.height)) * maximumVerticalGapMultiple
        var runs: [[CGRect]] = [[first]]
        var runMaxY = first.maxY
        for box in sorted.dropFirst() {
            if box.minY - runMaxY > maxGap {
                runs.append([box])
                runMaxY = box.maxY
            } else {
                runs[runs.count - 1].append(box)
                runMaxY = max(runMaxY, box.maxY)
            }
        }
        return runs.map(union)
    }

    private static func union(_ boxes: [CGRect]) -> CGRect {
        guard let first = boxes.first else { return .zero }
        let minX = boxes.map(\.minX).min() ?? first.minX
        let minY = boxes.map(\.minY).min() ?? first.minY
        let maxX = boxes.map(\.maxX).max() ?? first.maxX
        let maxY = boxes.map(\.maxY).max() ?? first.maxY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}

struct SpineTrack: Identifiable, Equatable, Sendable {
    var id: UUID
    var rect: CGRect
    var missed: Int
    /// True when this frame matched an outline from the previous frame.
    var matchedThisFrame: Bool

    /// Solid after a match. A first sighting is dim. A coasting miss fades, then the tracker drops it.
    var displayOpacity: Double {
        if matchedThisFrame {
            return 1
        }
        if missed == 0 {
            return 0.45
        }
        return max(0.2, 0.7 - Double(missed - 1) * 0.2)
    }
}

/// Smooths spine columns and keeps an identity while a spine stays in frame.
enum SpineTracker {
    static let alpha: CGFloat = 0.45
    /// Maximum midX distance, in normalized units, that continues a track.
    static let matchDistance: CGFloat = 0.08
    static let dropAfter = 3

    static func step(tracks: [SpineTrack], observed: [CGRect]) -> [SpineTrack] {
        // Assign the closest pair first. Walking tracks left to right lets the
        // left track take an observation that sits closer to its neighbor.
        let ordered = tracks.sorted { $0.rect.midX < $1.rect.midX }
        var pairs: [(track: Int, observation: Int, distance: CGFloat)] = []
        for (trackIndex, track) in ordered.enumerated() {
            for (observationIndex, rect) in observed.enumerated() {
                let distance = abs(rect.midX - track.rect.midX)
                if distance <= matchDistance {
                    pairs.append((trackIndex, observationIndex, distance))
                }
            }
        }
        pairs.sort { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            if lhs.track != rhs.track { return lhs.track < rhs.track }
            return lhs.observation < rhs.observation
        }

        var matchedObservation = Array(repeating: -1, count: ordered.count)
        var usedTracks = Set<Int>()
        var usedObservations = Set<Int>()
        for pair in pairs {
            if usedTracks.contains(pair.track) || usedObservations.contains(pair.observation) {
                continue
            }
            matchedObservation[pair.track] = pair.observation
            usedTracks.insert(pair.track)
            usedObservations.insert(pair.observation)
        }

        var next: [SpineTrack] = []
        for (trackIndex, track) in ordered.enumerated() {
            let observationIndex = matchedObservation[trackIndex]
            if observationIndex >= 0 {
                next.append(
                    SpineTrack(
                        id: track.id,
                        rect: lerp(track.rect, observed[observationIndex], alpha),
                        missed: 0,
                        matchedThisFrame: true
                    )
                )
            } else {
                let missed = track.missed + 1
                if missed <= dropAfter {
                    next.append(
                        SpineTrack(
                            id: track.id,
                            rect: track.rect,
                            missed: missed,
                            matchedThisFrame: false
                        )
                    )
                }
            }
        }
        for (observationIndex, rect) in observed.enumerated() where !usedObservations.contains(observationIndex) {
            next.append(
                SpineTrack(id: UUID(), rect: rect, missed: 0, matchedThisFrame: false)
            )
        }
        return next.sorted { $0.rect.midX < $1.rect.midX }
    }

    private static func lerp(_ from: CGRect, _ to: CGRect, _ alpha: CGFloat) -> CGRect {
        CGRect(
            x: from.origin.x + (to.origin.x - from.origin.x) * alpha,
            y: from.origin.y + (to.origin.y - from.origin.y) * alpha,
            width: from.size.width + (to.size.width - from.size.width) * alpha,
            height: from.size.height + (to.size.height - from.size.height) * alpha
        )
    }
}
