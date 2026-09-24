# Pass 5 — Draw the detected books

Date: 2026-09-24. Read only. Depends on passes 2–4.

Files: `swiftwing/Features/Camera/SegmentedPreviewOverlay.swift`, `swiftwing/Features/Camera/BoundingBoxOverlay.swift`, `swiftwing/Services/BoundingBox+CGRect.swift`, `swiftwing/Features/Camera/CameraViewModel.swift` (`onSegmented`, `updateQueueItemSegmented`), `swiftwing/Features/Camera/CameraOverlayView.swift` (segmented branch), `swiftwing/Features/ReviewQueue/ReviewQueueView.swift` (overlay sheet), `swiftwing/Features/ReviewQueue/ReviewCardView.swift` (magnifying-glass tap).

Do not change yet.

## 1. What starts it, and who owns it

Two views can point at a detected book. Neither is fed by the poll path that pass 4 follows.

`CameraOverlayView` shows `SegmentedPreviewOverlay` when some `ProcessingItem` is `.analyzing` and its `segmentedPreview` is non-nil. That field is set only in `updateQueueItemSegmented`, which runs from the `onSegmented` callback. `ScanJobCoordinator.streamAndProcess` never calls `onSegmented`. The overlay’s inputs (`imageData`, `totalBooks`, `currentBook`, `totalProcessed`) therefore stay at their defaults. The view draws the whole photo and the text "N books detected." It does not draw per-book rectangles.

`ReviewQueueView` presents `BoundingBoxOverlay` when `selectedBookForOverlay` has both `originalPhotoURL` and `metadata.boundingBox`. The card shows a magnifying glass when `onShowOverlay` is non-nil, and the tap sets that selection. `BoundingBoxOverlay` loads the file with `UIImage(contentsOfFile:)` and strokes `boundingBox.toCGRect(in: fitted)`.

## 2. Inputs and outputs

| View | Needs | Production poll provides |
|---|---|---|
| `SegmentedPreviewOverlay` | `SegmentedPreview` via `onSegmented` | nothing; callback is unused |
| `BoundingBoxOverlay` | temp photo URL and `BoundingBox` | photo URL from the captured temp file; box only if the results JSON included `boundingBox` |

Pass 4: the request is `format=lite`, and the spec says lite omits `boundingBox`. Treat the box as absent. The sheet’s `if let` then fails, and the presented sheet has an empty body.

`toCGRect` treats `x`, `y`, `width`, and `height` as fractions of the fitted image. The OpenAPI property text says the same (0.0–1.0). The fixture values (120.5, 200.3, 80, 150) are not fractions. If a future `format=full` payload matches the fixtures rather than the spec, the rectangle is drawn far outside the photo. If it matches the spec, `toCGRect` is the right conversion. The decode test locks the fixture numbers in. It does not lock the unit.

The photo URL points at `temporaryDirectory/<uuid>.jpg`. Pass 3 deletes that file after 30 minutes, and a successful scan also asks `cleanupTempFile` to delete it. Opening the sheet after either cleanup shows "Unable to load photo."

## 3. Failures

Handled: a missing file shows the exclamation-mark placeholder. A missing box or URL skips the overlay content.

Logged or dropped: nothing tells the user that lite omitted the box. The magnifying glass can still appear, and the sheet opens blank.

## 4. What is tested

`test_decodeBookMetadata_withBoundingBox` checks decode of a fixture box. No test presents `BoundingBoxOverlay` or `SegmentedPreviewOverlay`, and no test asserts a rectangle on screen.

## 5. Structural risk

The shelf UI cannot point at each detected book. Lite, which the client requests, strips the box the review sheet requires, and the camera overlay’s segmented callback is never invoked. Later passes should treat bounding boxes as absent.

## Do not change yet

Do not switch to `format=full` and do not draw boxes from the pixel-scale fixtures until one real full payload confirms the unit.
