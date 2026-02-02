# Critical Bugs Task Plan

## Priority Issues

### 🔴 CRITICAL: Review Queue UI Missing (Blocks Book Addition)
**Impact:** Books are processed but never added to library
**Root Cause:** ReviewQueueView component exists but not integrated into CameraView
**User Impact:** Zero books being saved despite successful Talaria processing

### 🟡 HIGH: Rectangle Detection Not Visible
**Impact:** Real-time object detection works but provides no visual feedback
**Root Cause:** No diagnostic logging in VisionService + possible parameter tuning needed
**User Impact:** Feature appears broken (no bounding boxes visible)

---

## Issue 1: Review Queue UI Missing

### Current Behavior
1. User captures image ✅
2. Image uploads to Talaria ✅
3. Talaria identifies 6 books ✅
4. Books added to `pendingReviewBooks` array ✅
5. **ReviewQueueView NEVER shown** ❌
6. **Books sit in memory, never saved** ❌

### Code Evidence
```swift
// CameraViewModel.swift:758
// Route ALL results to review queue (no auto-add)
pendingReviewBooks.append(pendingBook)

// CameraView.swift - NO ReviewQueueView integration!
// Only shows ProcessingQueueView (uploading status)
```

### Solution Required
**Add ReviewQueueView to CameraView.swift**

**Location:** After ProcessingQueueView (around line 156)

**Implementation:**
```swift
// Processing queue (uploading status)
ProcessingQueueView(items: viewModel.processingQueue, onRetry: viewModel.retryFailedItem)
    .padding(.bottom, 8)

// Review queue (pending approval) - ADD THIS
if !viewModel.pendingReviewBooks.isEmpty {
    ReviewQueueButton(
        pendingCount: viewModel.pendingReviewBooks.count,
        onTap: { viewModel.showReviewQueue = true }
    )
    .padding(.bottom, 8)
}
```

**Sheet Presentation:**
```swift
// Add to CameraView body (after existing sheets)
.sheet(isPresented: $viewModel.showReviewQueue) {
    ReviewQueueView(
        pendingBooks: $viewModel.pendingReviewBooks,
        onApprove: { book in
            viewModel.approveBook(book, modelContext: modelContext)
        },
        onReject: { book in
            viewModel.rejectBook(book)
        }
    )
}
```

**Add State Variable to CameraViewModel:**
```swift
// Around line 60
var showReviewQueue: Bool = false
```

### Acceptance Criteria
- ✅ ReviewQueueButton appears when pendingReviewBooks.count > 0
- ✅ Tapping button opens ReviewQueueView sheet
- ✅ Approving book adds it to library (SwiftData)
- ✅ Rejecting book removes it from queue
- ✅ Queue badge shows count (1-9, or "9+" for 10+)

### Files to Modify
1. **CameraView.swift** - Add ReviewQueueButton + sheet presentation
2. **CameraViewModel.swift** - Add `showReviewQueue` state variable
3. **ReviewQueueView.swift** - Verify existing component works

---

## Issue 2: Rectangle Detection Not Visible

### Current Behavior
1. VisionService.processFrame() runs ✅
2. VNDetectRectanglesRequest executes ✅
3. **NO logging output** ❌
4. **No detectedObjects populated** ❌ (probable)
5. **No green bounding boxes shown** ❌

### Diagnostic Logging Needed

**VisionService.swift** (add around line 55):
```swift
func processFrame(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> VisionResult {
    print("🔍 Vision: Processing frame with orientation: \(orientation)")

    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)

    do {
        try handler.perform([textRequest, barcodeRequest, rectangleRequest])

        // Log rectangle detection results
        if let rectangleObservations = rectangleRequest.results {
            print("📦 Vision: Rectangle request returned \(rectangleObservations.count) observations")
            for (index, observation) in rectangleObservations.enumerated() {
                print("   Rectangle \(index+1): confidence=\(observation.confidence), bbox=\(observation.boundingBox)")
            }
        } else {
            print("📦 Vision: Rectangle request returned nil")
        }

        // ... rest of method
```

**CameraViewModel.swift** (add around line 121):
```swift
case .objects(let objects):
    print("🎯 CameraViewModel: Received \(objects.count) objects")
    for (index, object) in objects.enumerated() {
        print("   Object \(index+1): confidence=\(object.confidence), uuid=\(object.observationUUID)")
    }
    self.detectedObjects = objects
```

**ObjectBoundingBoxView.swift** (add to body):
```swift
var body: some View {
    GeometryReader { geometry in
        let _ = print("🎨 ObjectBoundingBoxView: Rendering \(detectedObjects.count) boxes, viewSize=\(geometry.size)")

        ForEach(detectedObjects, id: \.observationUUID) { object in
            // ... existing code
```

### Parameter Tuning (if no rectangles detected)

**Current parameters (VisionService.swift init):**
```swift
rectangleRequest.minimumAspectRatio = 0.1   // Too narrow?
rectangleRequest.maximumAspectRatio = 0.9   // Too restrictive?
rectangleRequest.minimumSize = 0.05         // Too large?
rectangleRequest.minimumConfidence = 0.75   // Too high?
```

**Relaxed parameters for testing:**
```swift
rectangleRequest.minimumAspectRatio = 0.05  // Wider range
rectangleRequest.maximumAspectRatio = 0.95  // More lenient
rectangleRequest.minimumSize = 0.02         // Smaller objects
rectangleRequest.minimumConfidence = 0.5    // Lower threshold
```

### Acceptance Criteria
- ✅ Vision logs show "Processing frame" every ~100ms
- ✅ Rectangle count logged for each frame
- ✅ At least SOME rectangles detected in test scene
- ✅ detectedObjects array populated in CameraViewModel
- ✅ Green bounding boxes visible on screen
- ✅ Bounding boxes track objects as camera moves

---

## Implementation Plan

### Phase 1: Fix Review Queue UI (30 min)
**CRITICAL - Do this first**

1. Add `showReviewQueue` state to CameraViewModel.swift
2. Create ReviewQueueButton component (badge with count)
3. Add ReviewQueueButton to CameraView (conditional on pendingReviewBooks.count > 0)
4. Add .sheet modifier to CameraView for ReviewQueueView
5. Test: Capture image → See review queue button → Tap → Approve book → Verify in library

### Phase 2: Add Rectangle Detection Logging (15 min)
**Diagnostic - Do this second**

1. Add logging to VisionService.processFrame()
2. Add logging to CameraViewModel .objects case
3. Add logging to ObjectBoundingBoxView body
4. Test: Run app → Point at objects → Check Xcode console for Vision logs

### Phase 3: Tune Rectangle Detection (15 min)
**Fix - Do this third, based on Phase 2 findings**

1. If NO rectangles detected → Relax parameters (aspect ratio, size, confidence)
2. If rectangles detected but low confidence → Adjust thresholds
3. If coordinate transformation wrong → Fix convertToViewCoordinates()
4. Test: Iterate until bounding boxes appear and track correctly

---

## Success Criteria

### Review Queue
- [  ] Books appear in review queue after Talaria processing
- [  ] Review queue button shows badge with count
- [  ] Tapping button opens review sheet
- [  ] Approving book adds it to library
- [  ] Rejecting book removes it from queue
- [  ] Library view shows approved books

### Rectangle Detection
- [  ] Vision logs appear in Xcode console every ~100ms
- [  ] Rectangles detected for test objects
- [  ] Green bounding boxes visible in camera view
- [  ] Bounding boxes track objects smoothly
- [  ] Confidence-based styling works (opacity + line width)

---

## Current Status
- **Phase 1**: Not started (CRITICAL)
- **Phase 2**: Not started (diagnostic)
- **Phase 3**: Not started (fix)

## Next Action
Start Phase 1: Add ReviewQueueView integration to CameraView.swift

This is BLOCKING all book additions to library and should be fixed immediately.
