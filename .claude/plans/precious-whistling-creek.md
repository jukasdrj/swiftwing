# Plan: Bounding Box Overlay — Issue #22

## Context

Talaria backend now returns `boundingBox` coordinates (`{ x, y, width, height }`, normalized 0.0-1.0) for each detected book spine. SwiftWing already parses this into `BookMetadata.boundingBox` via resilient SSE decoding, but the data is never surfaced in the UI. The original captured photo is also deleted before the user reaches the review queue, making overlay rendering impossible.

This plan threads bounding box + photo data through the review pipeline and adds a tap-to-view overlay on review cards.

**OpenAPI spec**: Talaria owns the spec. Once they publish the update, we pull it via `./Scripts/update-api-spec.sh`. No SwiftWing-side spec changes needed — our `BoundingBox` Codable struct already matches the new contract.

---

## Phase 1: Data Threading (4 files)

### 1a. Add `originalPhotoURL` to `PendingBookResult`
**File**: `swiftwing/Models/PendingBookResult.swift`
- Add `let originalPhotoURL: URL?` property
- Update `init()` to accept `originalPhotoURL: URL? = nil`

### 1b. Thread `tempFileURL` through callbacks
**File**: `swiftwing/ScanJobCoordinator.swift`
- Add `originalPhotoURL: URL?` parameter to `ScanJobCallbacks.onBookResult`

**File**: `swiftwing/CameraViewModel.swift`
- In `buildScanCallbacks()`, capture `tempFileURL` and pass it through `onBookResult` closure
- **Defer temp file cleanup**: Remove `cleanupTempFile` calls on the success path (lines ~360, 372). Temp file now lives until review action completes.

### 1c. Accept photo URL in ReviewQueueManager
**File**: `swiftwing/ReviewQueueManager.swift`
- Add `originalPhotoURL: URL? = nil` to `handleBookResult()` signature
- Pass through to `PendingBookResult` init
- Pass through to `autoApproveBook()` for cleanup

---

## Phase 2: BoundingBox CGRect Extension (1 new file)

**New file**: `swiftwing/Services/BoundingBox+CGRect.swift`

```swift
extension BoundingBox {
    func toCGRect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}
```

Reuses existing `BoundingBox` from `NetworkTypes.swift:246-251`.

---

## Phase 3: Bounding Box Overlay View (1 new file)

**New file**: `swiftwing/BoundingBoxOverlay.swift`

Full-screen sheet view:
- Loads original photo from `originalPhotoURL` on demand via `UIImage(contentsOfFile:)`
- Renders with `.scaledToFit()` inside `GeometryReader`
- Draws International Orange stroked rectangle at bounding box position
- Uses `aspectFitSize`/`aspectFitOffset` helpers for correct coordinate mapping
- Close button (xmark.circle.fill) top-right
- Book title label near bounding box with `.swissGlassOverlay()` styling
- Background: `Color.swissBackground`, transition: `.spring(duration: 0.2)`
- Graceful nil handling — if photo fails to load, show message

Pattern reference: `SegmentedPreviewOverlay.swift` (existing overlay style)

---

## Phase 4: ReviewCardView Tap Gesture (1 file)

**File**: `swiftwing/ReviewQueueView.swift`

### ReviewCardView changes:
- Add `onShowOverlay: (() -> Void)?` callback parameter
- Add `.onTapGesture` on thumbnail image calling `onShowOverlay`
- Add magnifying glass badge on thumbnail when overlay is available

### ReviewQueueView changes:
- Add `@State private var selectedBookForOverlay: PendingBookResult?`
- Pass `onShowOverlay` to each `ReviewCardView` — only non-nil when both `book.metadata.boundingBox != nil` AND `book.originalPhotoURL != nil`
- Add `.sheet(item: $selectedBookForOverlay)` presenting `BoundingBoxOverlay`

---

## Phase 5: Temp File Lifecycle (2 files)

### 5a. Cleanup on review action
**File**: `swiftwing/ReviewQueueManager.swift`

Add private `cleanupPhoto(_ url: URL?)` method:
- Before deleting, check no other pending result references the same URL (multiple books share one photo)
- Call from `approveBook()`, `rejectBook()`, `approveAllBooks()`, `approveHighConfidenceBooks()`

### 5b. Orphan cleanup on app launch
**File**: `swiftwing/App/SwiftwingApp.swift`

- On launch, sweep temp directory for JPEG files older than 1 hour, delete them
- Handles crash/force-quit scenarios where normal cleanup didn't run

---

## Files Summary

| File | Action | Phase |
|------|--------|-------|
| `swiftwing/Models/PendingBookResult.swift` | Edit — add `originalPhotoURL` | 1 |
| `swiftwing/ScanJobCoordinator.swift` | Edit — add URL param to callback | 1 |
| `swiftwing/CameraViewModel.swift` | Edit — thread URL, defer cleanup | 1 |
| `swiftwing/ReviewQueueManager.swift` | Edit — accept URL, add cleanup | 1, 5 |
| `swiftwing/Services/BoundingBox+CGRect.swift` | **New** — CGRect extension | 2 |
| `swiftwing/BoundingBoxOverlay.swift` | **New** — overlay view | 3 |
| `swiftwing/ReviewQueueView.swift` | Edit — tap gesture, sheet | 4 |
| `swiftwing/App/SwiftwingApp.swift` | Edit — orphan cleanup | 5 |

---

## Verification

1. **Build**: `xcodebuild ... | xcsift` — target `errors: 0, warnings: 0`
2. **Manual test**: Scan a bookshelf → review queue → tap thumbnail → verify orange rectangle aligns with spine
3. **Edge cases**: nil boundingBox (no overlay button), single book, book at frame edge
4. **Memory**: Confirm photo loaded on-demand from disk, not retained in memory
5. **Cleanup**: Approve/reject all books → verify temp files deleted; kill app → relaunch → verify orphan sweep runs
