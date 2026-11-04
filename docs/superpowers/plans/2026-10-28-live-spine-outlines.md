# Live Spine Outlines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Draw one live outline per book spine on the camera preview when several spines are in the frame.

**Architecture:** The preview already runs Vision text recognition at 5 Hz and maps axis-aligned rects through the aspect-filled preview. Group those line rects into vertical columns, smooth each column across frames, and draw the columns instead of every word. The shutter path stays as it is: Talaria or on-device scan still owns the boxes on the captured photo.

**Review resolutions (2026-10-30):** Columns join when half of the narrower width overlaps in X. A fixed 0.015 gap is not used. Lines wider than 0.45, or wider than twice the median line width, are dropped before the merge. A vertical hole taller than twice the median line height splits a strip. There is no post-merge width cap. The overlay draws every track the tracker still holds, including a coasting miss, and fades it. The tracker still drops a track after three missed frames. Build and test commands pipe through `xcsift`.

**Landed 2026-10-30.** Grouper, tracker, and preview drawing are in the tree. `SpineColumnGrouperTests`, `SpineTrackerTests`, and `LiveTextGeometryTests` passed together: 14 tests, 0 failures, 0 warnings. The device check is still open. Nothing is committed.

**Tech Stack:** Swift 6, SwiftUI, Vision rects already produced by `LiveFrameBridge`, Swift Testing.

## Global Constraints

- One shelf facing the camera, the pose in `CameraFirstRunGuidance` ("edge to edge — one shelf at a time").
- Outlines are axis-aligned unions of Vision text rects. Vision's `boundingBox` is axis-aligned.
- A spine with no readable text gets no outline.
- Do not call `VNDetectDocumentSegmentationRequest` or `VNDetectRectanglesRequest`. A document request returns one page. A rectangle request looks for closed high-contrast quads and merges neighboring spines.
- Do not write preview outlines into the captured photo, the review queue, or `BoundingBox`.
- App sources are listed explicitly in `swiftwing.xcodeproj`. Put new types in `LiveTextDetector.swift`, which is already a member. `swiftwingTests` is a synchronized root, so a new test file is picked up without a project edit.
- Keep the 0.2 s throttle in `LiveFrameBridge`. Do not run this on every camera frame.

---

### Task 1: Column grouper

**Files:**
- Modify: `swiftwing/Features/Camera/LiveTextDetector.swift`
- Test: `swiftwingTests/Unit/Features/Camera/SpineColumnGrouperTests.swift`

**Interfaces:**
- Consumes: Vision bottom-left normalized rects (`CGRect` in 0...1).
- Produces: `SpineColumnGrouper.columns(from: [CGRect]) -> [CGRect]`, each rect the union of one spine's lines, sorted by `midX`.
- A line joins a column when `overlap / narrowerWidth >= 0.5`. A gutter of 0.01 stays two columns.
- Drop a line before the merge when its width is above 0.45 or above twice the median width of the lines that passed 0.45. Neighbors of a dropped banner stay.
- After the X cluster, split where `next.minY - runMaxY` is greater than twice the median line height of that cluster.
- Drop a column shorter than 0.06. Do not drop a column for being wide.

- [x] **Step 1: Write the failing test**

Create `swiftwingTests/Unit/Features/Camera/SpineColumnGrouperTests.swift`:

```swift
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

    @Test func overlappingTitleAndAuthorStayOneColumn() {
        let columns = SpineColumnGrouper.columns(from: [
            CGRect(x: 0.20, y: 0.40, width: 0.07, height: 0.08),
            CGRect(x: 0.21, y: 0.50, width: 0.06, height: 0.08),
        ])
        #expect(columns.count == 1)
        #expect(abs(columns[0].minX - 0.20) < 0.000_1)
        #expect(abs(columns[0].height - 0.18) < 0.000_1)
    }

    @Test func aNarrowGutterStaysTwoColumns() {
        let columns = SpineColumnGrouper.columns(from: [
            CGRect(x: 0.10, y: 0.20, width: 0.06, height: 0.40),
            CGRect(x: 0.17, y: 0.20, width: 0.06, height: 0.40),
        ])
        #expect(columns.count == 2)
    }

    @Test func aTallVerticalHoleSplitsOneStrip() {
        // The old fixture put these two lines in one column of height 0.38.
        // The hole between them is 0.22 of the frame, so they are two columns.
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
```

- [x] **Step 2: Run the test to verify it fails**

Run from `/Users/juju/dev_repos/swiftwing`:

```bash
xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -only-testing:swiftwingTests/SpineColumnGrouperTests \
  -parallel-testing-enabled NO \
  2>&1 | xcsift
```

Expected: compile failure, `SpineColumnGrouper` is not defined.

- [x] **Step 3: Add the grouper**

Append to `swiftwing/Features/Camera/LiveTextDetector.swift`:

```swift
/// Groups upright Vision text rects into one axis-aligned column per spine.
enum SpineColumnGrouper {
    static let minimumOverlapFraction: CGFloat = 0.5
    static let maximumLineWidth: CGFloat = 0.45
    static let maximumWidthMultiple: CGFloat = 2
    static let maximumVerticalGapMultiple: CGFloat = 2
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
            if let index = groups.indices.last, overlaps(box, union(groups[index])) {
                groups[index].append(box)
            } else {
                groups.append([box])
            }
        }

        let columns = groups.flatMap { splitVertically($0) }
        return columns
            .filter { $0.height >= minimumColumnHeight }
            .sorted { $0.midX < $1.midX }
    }

    private static func union(_ boxes: [CGRect]) -> CGRect {
        guard let first = boxes.first else { return .zero }
        let minX = boxes.map(\.minX).min() ?? first.minX
        let minY = boxes.map(\.minY).min() ?? first.minY
        let maxX = boxes.map(\.maxX).max() ?? first.maxX
        let maxY = boxes.map(\.maxY).max() ?? first.maxY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
```

`overlaps`, `splitVertically`, and `median` live in `LiveTextDetector.swift` with this function. Do not put `splitGap` or `maximumColumnWidth` back.

- [x] **Step 4: Run the test to verify it passes**

Same `xcodebuild` command as Step 2.

Expected: `SpineColumnGrouperTests` passed.

- [ ] **Step 5: Commit**

```bash
git add swiftwing/Features/Camera/LiveTextDetector.swift \
  swiftwingTests/Unit/Features/Camera/SpineColumnGrouperTests.swift
git commit -m "feat: group live text lines into spine columns"
```

---

### Task 2: Frame-to-frame tracker

**Files:**
- Modify: `swiftwing/Features/Camera/LiveTextDetector.swift`
- Test: `swiftwingTests/Unit/Features/Camera/SpineTrackerTests.swift`

**Interfaces:**
- Consumes: `SpineColumnGrouper.columns` output, one array per accepted frame.
- Produces: `SpineTrack` (`id`, `rect`, `missed`, `matchedThisFrame`) and `SpineTracker.step(tracks:observed:) -> [SpineTrack]`.

- [x] **Step 1: Write the failing test**

Create `swiftwingTests/Unit/Features/Camera/SpineTrackerTests.swift`:

```swift
import CoreGraphics
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
}
```

`0.218` is `0.20 + (0.24 - 0.20) * 0.45`.

- [x] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -only-testing:swiftwingTests/SpineTrackerTests \
  -parallel-testing-enabled NO \
  2>&1 | xcsift
```

Expected: compile failure, `SpineTrack` is not defined.

- [x] **Step 3: Add the tracker**

Append to `swiftwing/Features/Camera/LiveTextDetector.swift`:

```swift
struct SpineTrack: Identifiable, Equatable, Sendable {
    var id: UUID
    var rect: CGRect
    var missed: Int
    /// True when this frame matched an outline from the previous frame.
    var matchedThisFrame: Bool

    /// Solid after a match. A first sighting is dim. A coasting miss fades, then the tracker drops it.
    var displayOpacity: Double {
        if matchedThisFrame { return 1 }
        if missed == 0 { return 0.45 }
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
        var remaining = observed.sorted { $0.midX < $1.midX }
        var next: [SpineTrack] = []
        for track in tracks.sorted(by: { $0.rect.midX < $1.rect.midX }) {
            let matchIndex = remaining.indices.min { lhs, rhs in
                abs(remaining[lhs].midX - track.rect.midX) < abs(remaining[rhs].midX - track.rect.midX)
            }
            if let matchIndex, abs(remaining[matchIndex].midX - track.rect.midX) <= matchDistance {
                let observedRect = remaining.remove(at: matchIndex)
                next.append(
                    SpineTrack(
                        id: track.id,
                        rect: lerp(track.rect, observedRect, alpha),
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
        for rect in remaining {
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
```

- [x] **Step 4: Run the test to verify it passes**

Same command as Step 2.

Expected: `SpineTrackerTests` passed.

- [ ] **Step 5: Commit**

```bash
git add swiftwing/Features/Camera/LiveTextDetector.swift \
  swiftwingTests/Unit/Features/Camera/SpineTrackerTests.swift
git commit -m "feat: smooth live spine columns across frames"
```

---

### Task 3: Draw the columns on the preview

**Files:**
- Modify: `swiftwing/Features/Camera/CameraViewModel.swift` (`liveTextObservations`, `startLiveText`, `stopCamera`)
- Modify: `swiftwing/Features/Camera/CameraOverlayView.swift` (`liveTextOverlay`)

**Interfaces:**
- Consumes: `SpineColumnGrouper.columns` and `SpineTracker.step`.
- Produces: `CameraViewModel.liveSpineOutlines: [SpineTrack]`, every track `SpineTracker` still holds. A coasting miss stays visible and fades. The tracker drops it after three missed frames.

- [x] **Step 1: Replace the published word boxes with spine outlines**

In `CameraViewModel`, replace:

```swift
    /// Live viewfinder text. Updated from the video output, not the shutter path.
    var liveTextObservations: [LiveTextObservation] = []
```

with:

```swift
    /// One outline per spine in the viewfinder, including tracks coasting through a missed frame.
    var liveSpineOutlines: [SpineTrack] = []
```

In `stopCamera`, replace `liveTextObservations = []` with `liveSpineOutlines = []`.

Replace `startLiveText()` with:

```swift
    private func startLiveText() {
        cameraManager.setLiveTextHandler { [weak self] observations in
            let columns = SpineColumnGrouper.columns(from: observations.map(\.visionBottomLeft))
            Task { @MainActor in
                guard let self else { return }
                self.liveSpineOutlines = SpineTracker.step(
                    tracks: self.liveSpineOutlines,
                    observed: columns
                )
            }
        }
    }
```

- [x] **Step 2: Draw one rounded rect per outline**

In `CameraOverlayView`, replace the `ForEach(viewModel.liveTextObservations)` loop with:

```swift
                ForEach(viewModel.liveSpineOutlines) { outline in
                    let rect = LiveTextGeometry.overlayRect(
                        visionBottomLeft: outline.rect,
                        frameAspect: frameAspect,
                        viewAspect: viewAspect
                    )
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            Color.internationalOrange.opacity(outline.displayOpacity),
                            lineWidth: 1.5
                        )
                        .frame(
                            width: rect.width * geo.size.width,
                            height: rect.height * geo.size.height
                        )
                        .position(
                            x: rect.midX * geo.size.width,
                            y: rect.midY * geo.size.height
                        )
                }
```

A matched column is solid. A first sighting is dim. A coasting miss fades (`SpineTrack.displayOpacity`) and is still drawn. `LiveTextGeometry.overlayRect` already accounts for the aspect-fill crop. The stroke is a hairline so the outline reads as a framing hint.

- [x] **Step 3: Build**

```bash
xcodebuild build -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  2>&1 | xcsift
```

Expected: build succeeds. Then rerun `SpineColumnGrouperTests` and `SpineTrackerTests`.

- [ ] **Step 4: Check on a device**

Point the phone at two or three spines, upright, filling the width, the way the first-run coach describes. Include one wide book and one blank spine, then turn the phone sideways and back.

Expected: one orange hairline per spine with readable text. A blank spine has no outline. A one-frame OCR miss fades the outline instead of removing it. Word-sized boxes are gone. Columns stay vertical after rotation. Capturing a photo still sends the still to Talaria or `OnDeviceScanner`, and the review card still uses that result's `boundingBox`. If a row merges or disappears, log the raw Vision rect count next to the column count before changing a threshold.

- [ ] **Step 5: Commit**

```bash
git add swiftwing/Features/Camera/CameraViewModel.swift \
  swiftwing/Features/Camera/CameraOverlayView.swift
git commit -m "feat: show one live outline per spine"
```
