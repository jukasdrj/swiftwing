# Bounding Box Overlay — Design Document

**Issue:** #22 — Tap review thumbnail to see highlighted spine in photo
**Status:** Investigation complete, ready for implementation
**Date:** 2026-02-20

---

## 1. Investigation Findings

### 1A. Talaria API Does NOT Return boundingBox Data

**Finding: The Talaria API does not send `boundingBox` in book results.**

- The OpenAPI spec (`swiftwing/OpenAPI/talaria-openapi.yaml`) defines `BookMetadata` with fields: `title`, `author`, `isbn`, `coverUrl`, `format`, `confidence`, `enrichmentStatus`. No `boundingBox` field exists in the spec.
- The SSE `result` event schema (`SSEResultEvent`) similarly has no bounding box field.
- The SSE `complete` event returns `books: [BookMetadata]` — again, no bounding box.

**Client-side code is already prepared but receives nil:**
- `NetworkTypes.swift:246-251` defines `BoundingBox` struct (x, y, width, height).
- `NetworkTypes.swift:272` defines `BookMetadata.boundingBox: BoundingBox?` as optional.
- `NetworkTypes.swift:327` uses resilient decoding: `boundingBox = try? container.decodeIfPresent(...)`.
- Since Talaria never sends this field, it always decodes as `nil`.

**Conclusion:** This is NOT a parsing bug. Talaria genuinely does not return per-book bounding box coordinates. The client struct was added speculatively for future API support.

### 1B. Talaria DOES Send Segmented Preview (Alternative)

**Finding: Talaria sends a `segmented` SSE event with an annotated image.**

- `SSEEventParser.swift:192-203` parses `event: segmented` containing:
  - `image`: Base64-encoded JPEG with bounding boxes drawn on the image
  - `totalBooks`: Number of book spines detected
- This is stored in `ProcessingItem.segmentedPreview: Data?` (line 18 of `ProcessingItem.swift`).
- The segmented preview is a **pre-rendered image** with boxes already drawn by Talaria, not raw coordinate data.

**Limitation:** The segmented preview is an opaque image — we cannot extract individual book coordinates from it, nor can we highlight a specific book on tap.

### 1C. On-Device Vision Framework Has Bounding Box Data

**Finding: VisionService already detects objects with bounding boxes.**

- `VisionTypes.swift:81-97` defines `DetectedObject` with `boundingBox: CGRect` (normalized Vision coordinates).
- `VisionService.swift` runs `VNDetectRectanglesRequest` and produces bounding boxes.
- `ObjectBoundingBoxView.swift` already renders green overlays on the camera preview.
- These are **generic rectangle detections** (potential book spines), NOT per-book-result bounding boxes.

**Gap:** Vision detects rectangles during live camera preview, but there is no mapping between "detected rectangle #3" and "book result: The Great Gatsby". The Vision detection happens before the photo is sent to Talaria, and Talaria returns books without any spatial reference.

### 1D. Original Photo Is Cleaned Up Before Review

**Finding: Temp files are deleted immediately after SSE stream completes, BEFORE the user reviews results.**

- `CameraViewModel.swift:370-372`: After SSE streaming succeeds:
  ```swift
  await scanCoordinator.cleanup(jobId: uploadResult.jobId, authToken: authToken)
  if let tempFileURL { await scanCoordinator.cleanupTempFile(tempFileURL) }
  ```
- This happens in the success path, immediately after `streamAndProcess()` returns.
- Error paths (lines 360, 416, 440) also clean up temp files.
- `ProcessingItem.originalImageData: Data?` holds the full image in memory for **retry** purposes, but items are removed from `processingQueue` after 5 seconds (line 375).

**What IS available during review:**
- `PendingBookResult.thumbnailData: Data?` — a 60x90px thumbnail (too small for meaningful bounding box overlay).
- `PendingBookResult.metadata: BookMetadata` — no bounding box (see 1A).
- The segmented preview (`ProcessingItem.segmentedPreview`) is on the `ProcessingItem`, which is auto-removed from the queue after 5 seconds.

**Conclusion:** The original photo is not retained for the review phase. Both the temp file and the processing item are cleaned up before the user interacts with the review queue.

---

## 2. Proposed Implementation Plan

### Approach: Two-Phase Implementation

#### Phase 1: Show Segmented Preview (Low effort, immediate value)

Use the Talaria-provided segmented preview image (which already has boxes drawn on it) as a "tap to expand" overlay during review.

**Files to modify:**
| File | Change |
|------|--------|
| `PendingBookResult.swift` | Add `segmentedPreviewData: Data?` field |
| `ReviewQueueManager.swift` | Pass segmented preview from ProcessingItem to PendingBookResult |
| `CameraViewModel.swift` | Retain segmented preview data when creating PendingBookResult; defer temp file cleanup until review is dismissed |
| `ReviewQueueView.swift` | Add tap gesture on thumbnail to show full-screen segmented preview overlay |
| NEW: `SegmentedPreviewOverlay.swift` | Full-screen overlay view showing the annotated image |

**Data flow:**
```
Talaria SSE → segmented event → ProcessingItem.segmentedPreview
  → copied to PendingBookResult.segmentedPreviewData
    → ReviewQueueView tap → SegmentedPreviewOverlay (full-screen)
```

**Limitations:**
- All books are highlighted in the same image — no per-book highlighting on tap.
- The image is pre-rendered by Talaria — no control over highlight style.
- If Talaria does not send a `segmented` event (older API versions), fallback to showing the original captured photo (see Phase 2).

#### Phase 2: Retain Original Photo + Overlay Talaria Coordinates (Requires API change)

Request Talaria to return per-book bounding box coordinates in the `result` or `complete` event.

**API change required (Talaria backend):**
```json
// In SSE result event:
{
  "title": "The Great Gatsby",
  "author": "F. Scott Fitzgerald",
  "isbn": "9780743273565",
  "boundingBox": { "x": 0.1, "y": 0.2, "width": 0.15, "height": 0.8 }
}
```

**Files to modify (client-side, mostly ready):**
| File | Change |
|------|--------|
| `CameraViewModel.swift` | Retain `originalImageData` in PendingBookResult; defer cleanup |
| `PendingBookResult.swift` | Add `originalImageData: Data?` field |
| `ReviewQueueView.swift` | On tap, show original photo with highlighted bounding box |
| NEW: `BookHighlightOverlayView.swift` | Full-screen view showing original photo with one book's bounding box highlighted |
| `NetworkTypes.swift` | Already has `BoundingBox` struct — no change needed |
| `OpenAPI/talaria-openapi.yaml` | Update spec to include `boundingBox` in `BookMetadata` and `SSEResultEvent` |

**Coordinate system conversion:**
- Talaria `BoundingBox` uses `(x, y, width, height)` — likely normalized [0,1] coordinates.
- The captured photo is a JPEG with known pixel dimensions.
- The overlay view needs to scale from normalized coordinates to display coordinates.
- `ObjectBoundingBoxView.swift` already implements `convertToViewCoordinates()` for Vision (bottom-left origin). Talaria may use top-left origin — **must confirm with API team**.
- Reuse or adapt the existing coordinate conversion logic.

---

## 3. Coordinate System Conversion Approach

Three coordinate systems in play:

| System | Origin | Range | Used by |
|--------|--------|-------|---------|
| Vision framework | Bottom-left | [0,1] normalized | `DetectedObject.boundingBox` |
| Talaria (proposed) | TBD (likely top-left) | [0,1] normalized | `BookMetadata.boundingBox` |
| SwiftUI view | Top-left | Points | Display overlay |

**Conversion function (adapt from `ObjectBoundingBoxView.swift:55-93`):**
```swift
func convertToViewCoordinates(
    boundingBox: BoundingBox,   // Talaria normalized coords
    imageSize: CGSize,          // Original photo dimensions
    viewSize: CGSize,           // Display view size
    originIsBottomLeft: Bool    // true for Vision, false for Talaria (TBD)
) -> CGRect
```

**Key considerations:**
- Aspect fill vs aspect fit — the overlay must match the image display mode.
- Device rotation — captured photo may be landscape while display is portrait.
- The existing `ObjectBoundingBoxView` handles all of this for Vision; same logic applies.

---

## 4. Open Questions and Blockers

### Blockers

1. **Talaria does not return per-book bounding boxes.** Phase 2 requires a backend API change. The `BoundingBox` struct exists client-side but is never populated.
   - **Action:** File a Talaria feature request for `boundingBox` in SSE `result` events.
   - **Workaround:** Phase 1 uses the segmented preview image (pre-rendered by Talaria).

2. **Original photo is deleted before review.** The cleanup in `CameraViewModel.swift:370-372` must be deferred.
   - **Action:** Move cleanup to after review queue is dismissed (approve/reject).
   - **Risk:** Memory pressure if many photos are retained. Mitigate by storing on disk (already a temp file) and only deleting after review.

### Open Questions

1. **Does Talaria always send `segmented` events?** Need to verify with API team. If not always sent, Phase 1 needs a graceful fallback.

2. **What coordinate system does Talaria use for bounding boxes (if added)?** Top-left origin (standard image coordinates) or bottom-left (Vision convention)?

3. **Memory budget for retaining original photos during review.** A single JPEG is ~2-4MB. With 7+ books from one scan, that is manageable if stored as temp files (not in-memory Data).

4. **Should the segmented preview replace the thumbnail in the review queue, or be a separate tap-to-expand interaction?** UX decision needed.

---

## 5. Graceful Fallback When boundingBox Is nil

Since `BookMetadata.boundingBox` is already optional and always nil today, the feature must degrade gracefully:

| Data Available | Behavior |
|---|---|
| `boundingBox` + original photo | Best: highlight specific book spine on tap |
| Segmented preview (no per-book coords) | Good: show annotated image with all boxes |
| Original photo only (no coords) | Acceptable: show full photo without highlights |
| Thumbnail only (no photo, no coords) | Minimal: show enlarged thumbnail (current behavior) |
| Nothing | No-op: tap does nothing or shows "preview unavailable" |

**Implementation:** Check in order: boundingBox > segmentedPreview > originalPhoto > thumbnail. Show the best available visualization.

---

## 6. Recommended Implementation Order

1. **Phase 1A** (1-2 hours): Retain segmented preview in `PendingBookResult` and show on tap. No API changes needed.
2. **Phase 1B** (1-2 hours): Defer temp file / original photo cleanup until review is dismissed. Show original photo as fallback when no segmented preview.
3. **Phase 2** (requires API change): Add `boundingBox` to Talaria API, implement per-book highlighting with interactive overlay.

**Phase 1 delivers user value immediately** — users can tap to see the annotated shelf photo with all detected spines highlighted. Phase 2 adds the per-book interactive highlighting once the API supports it.
