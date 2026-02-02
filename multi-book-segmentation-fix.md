# Multi-Book Segmentation & Talaria Results Debug Plan

## Issue 1: Only 1 Book Segmented (Expected 5)

### Root Cause Analysis

**Current Behavior:**
- Vision's `VNGenerateForegroundInstanceMaskRequest` detects only 1 instance from shelf photo
- Log shows: "📚 Successfully segmented 1 books from shelf photo"
- Expected: 5 books

**Possible Causes:**

1. **Vision API Limitation**: `VNGenerateForegroundInstanceMaskRequest` may group nearby books as single foreground object
2. **Image Quality**: Books too close together, similar colors, or poor lighting
3. **Vision Configuration**: Missing parameters to increase sensitivity

### Solution: Enhance Instance Segmentation

**Option A: Add VNRecognizeTextRequest for Spine Detection** (Recommended)
Instead of relying solely on foreground instance segmentation, use text recognition to find distinct text regions (each spine has different text):

```swift
// In InstanceSegmentationService.segmentBooks()
private func segmentBooksByTextRegions(from image: CIImage) async throws -> [SegmentedBook] {
    // Step 1: Detect text regions using VNRecognizeTextRequest
    let textRequest = VNRecognizeTextRequest()
    textRequest.recognitionLevel = .accurate
    textRequest.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(ciImage: image, options: [:])
    try handler.perform([textRequest])

    guard let textObservations = textRequest.results, !textObservations.isEmpty else {
        throw SegmentationError.noInstancesFound
    }

    // Step 2: Group text observations by vertical proximity (books on shelf)
    let groupedRegions = groupTextByVerticalProximity(textObservations)

    // Step 3: For each group, create bounding box and crop
    var books: [SegmentedBook] = []
    for (index, regionObservations) in groupedRegions.enumerated() {
        let boundingBox = calculateUnionBoundingBox(regionObservations)
        let croppedImage = cropImage(image, to: boundingBox)

        books.append(SegmentedBook(
            instanceID: index + 1,
            croppedImage: croppedImage,
            boundingBox: boundingBox
        ))
    }

    return books
}
```

**Option B: Adjust VNGenerateForegroundInstanceMaskRequest Confidence**
Try lowering the confidence threshold to detect more instances:

```swift
// Currently no configuration options exposed by iOS 26 API
// Vision framework automatically determines instances
```

**Option C: Fallback to Rectangle Detection** (Epic 4 legacy)
Use `VNDetectRectanglesRequest` to find book spines as rectangles:

```swift
private func segmentBooksByRectangles(from image: CIImage) async throws -> [SegmentedBook] {
    let request = VNDetectRectanglesRequest()
    request.minimumAspectRatio = 0.3  // Books are tall/narrow
    request.maximumAspectRatio = 0.7
    request.minimumSize = 0.05  // Minimum 5% of image
    request.maximumObservations = 20

    let handler = VNImageRequestHandler(ciImage: image, options: [:])
    try handler.perform([request])

    guard let rectangles = request.results, !rectangles.isEmpty else {
        throw SegmentationError.noInstancesFound
    }

    var books: [SegmentedBook] = []
    for (index, rect) in rectangles.enumerated() {
        let boundingBox = rect.boundingBox
        let croppedImage = cropImage(image, to: boundingBox)

        books.append(SegmentedBook(
            instanceID: index + 1,
            croppedImage: croppedImage,
            boundingBox: boundingBox
        ))
    }

    return books
}
```

### Recommended Implementation

**Hybrid Approach**: Try instance segmentation first, fall back to text regions:

```swift
func segmentBooks(from image: CIImage) async throws -> [SegmentedBook] {
    // Try instance segmentation first
    do {
        let books = try await segmentBooksByInstanceMask(from: image)
        if books.count >= 2 {
            // Instance segmentation worked well
            return books
        }
    } catch {
        print("⚠️ Instance segmentation failed: \(error)")
    }

    // Fallback to text region grouping
    print("🔄 Falling back to text region segmentation")
    return try await segmentBooksByTextRegions(from: image)
}
```

---

## Issue 2: Talaria Results Not Sent Back to App

### Debugging Steps

**1. Check Console Logs During Talaria Scan:**

Look for these log patterns:
```
📤 Upload took Xms, jobId: <uuid>
📡 SSE progress: <message>
📚 Book identified: <title> by <author>
✅ SSE stream lasted X.Xs
📚 Received X books from results API
🔍 DEBUG: handleBookResult called for: <title>
📋 Book added to review queue: <title> (pending: X)
```

**2. Verify SSE Event Handling:**

Add debug logging in `processCaptureWithImageData()`:

```swift
// After line 490: for try await event in eventStream
for try await event in eventStream {
    print("🐛 DEBUG: Received SSE event: \(event)")  // <-- ADD THIS

    switch event {
    case .result(let bookMetadata):
        print("📚 Book identified: \(bookMetadata.title) by \(bookMetadata.author)")
        handleBookResult(metadata: bookMetadata, rawJSON: rawJSON, modelContext: modelContext)
        // ADD: Verify handleBookResult was called
        print("🐛 DEBUG: handleBookResult completed for \(bookMetadata.title)")
```

**3. Check If SSE Stream Is Connecting:**

Verify Talaria API is reachable:
```swift
// After line 488: let eventStream = ...
print("🐛 DEBUG: Starting SSE stream from \(streamUrl)")
print("🐛 DEBUG: DeviceId: \(self.deviceId), AuthToken: \(authToken != nil)")
```

**4. Verify Feature Flag State:**

```swift
// In processMultiBook() after line 255
let useOnDevice = UserDefaults.standard.bool(forKey: "UseOnDeviceExtraction")
print("🐛 DEBUG: UseOnDeviceExtraction = \(useOnDevice)")
```

**5. Check If Talaria Pipeline Is Being Called:**

```swift
// At start of processCaptureWithImageData (line 385)
func processCaptureWithImageData(itemId: UUID, imageData: Data, modelContext: ModelContext) async {
    print("🐛 DEBUG: processCaptureWithImageData called for itemId: \(itemId)")
    // ... rest of method
```

---

## Action Plan

### Phase 1: Diagnose Talaria Results Issue (PRIORITY)

1. **Add Debug Logging:**
   - SSE event reception
   - handleBookResult execution
   - Feature flag state
   - Talaria API connection

2. **Test Talaria Pipeline:**
   - Disable UseOnDeviceExtraction flag
   - Capture single book photo
   - Check console logs for SSE events
   - Verify book appears in review queue

3. **Compare On-Device vs Talaria:**
   - Both should call `handleBookResult(metadata:rawJSON:modelContext:)`
   - Both should append to `pendingReviewBooks`
   - Both should log "📋 Book added to review queue"

### Phase 2: Fix Multi-Book Segmentation

1. **Implement Hybrid Segmentation:**
   - Keep existing instance segmentation
   - Add text region fallback
   - Test with 3-5 book shelf photo

2. **Validate Results:**
   - Verify all books detected
   - Check bounding boxes don't overlap
   - Ensure cropped images are clear

3. **Performance Testing:**
   - Measure segmentation time (target: <2s for 5 books)
   - Check memory usage during batch processing

---

## Test Cases

### Test 1: Talaria Pipeline (Single Book)
- Disable UseOnDeviceExtraction
- Capture photo of 1 book spine
- **Expected:** Book appears in review queue with Talaria metadata

### Test 2: Talaria Pipeline (Multi-Book)
- Disable UseOnDeviceExtraction
- Enable EnableMultiBookScanning
- Capture shelf photo (3-5 books)
- **Expected:** All books segmented and processed via Talaria

### Test 3: On-Device Pipeline (Single Book)
- Enable UseOnDeviceExtraction
- Capture photo of 1 book spine
- **Expected:** Book appears in review queue with on-device metadata

### Test 4: On-Device Pipeline (Multi-Book)
- Enable UseOnDeviceExtraction
- Enable EnableMultiBookScanning
- Capture shelf photo (3-5 books)
- **Expected:** All books segmented and processed on-device

---

## Files to Modify

### 1. InstanceSegmentationService.swift
- Add `segmentBooksByTextRegions()` method
- Add `groupTextByVerticalProximity()` helper
- Update `segmentBooks()` to use hybrid approach

### 2. CameraViewModel.swift
- Add debug logging to SSE event handler
- Add debug logging to `processCaptureWithImageData()`
- Add debug logging to `handleBookResult()`

### 3. (Optional) VisionTypes.swift
- Add `TextRegionCluster` struct for text-based segmentation

---

## Expected Outcomes

**After Talaria Debug:**
- Identify why results aren't appearing in review queue
- Verify SSE events are being received
- Confirm handleBookResult is being called

**After Multi-Book Fix:**
- All books in shelf photo detected (not just 1)
- Each book processed independently
- Review queue shows all results

---

## Next Steps

1. **Immediate:** Add debug logging to diagnose Talaria results issue
2. **Short-term:** Implement hybrid segmentation for multi-book detection
3. **Testing:** Validate both pipelines work end-to-end

Would you like me to implement the debug logging first, or proceed with the multi-book segmentation fix?
