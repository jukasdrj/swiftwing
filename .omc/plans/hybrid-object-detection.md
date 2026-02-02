# Hybrid Object Detection - Work Plan

**Created:** 2026-02-01
**Epic:** 2.5 (Phase 1), 3-4 (Phase 2), 6-7 (Phase 3)
**Estimated Effort:** Phase 1: ~80 min | Phase 2: ~4 hours | Phase 3: ~2 weeks
**Risk Level:** LOW (Phase 1), MEDIUM (Phase 2), HIGH (Phase 3)

---

## Executive Summary

SwiftWing currently detects book spines through text recognition (VNRecognizeTextRequest) and barcode scanning (VNDetectBarcodesRequest). While effective for clear spines with readable text or ISBN barcodes, this approach misses opportunities where the physical shape of the book spine is visible but text is not yet readable -- for example, when the camera is at mid-range or the spine is partially obscured.

This plan introduces a **hybrid object detection strategy** that evolves through three phases. Phase 1 adds rectangle detection to the existing Vision pipeline, providing immediate visual feedback when rectangular book-like shapes are found. Phase 2 silently collects detection telemetry to understand real-world scanning patterns. Phase 3 uses that data to train a purpose-built CoreML model that outperforms generic rectangle detection for book spines specifically.

The key insight is that rectangle detection is nearly free to add -- VNDetectRectanglesRequest runs in ~5-10ms and integrates directly into the existing `VisionService.processFrame()` pipeline. The existing `VisionOverlayView` provides a complete coordinate transformation template. This plan delivers Phase 1 as a shippable feature in approximately 90 minutes of development time, with Phases 2 and 3 as progressive enhancements informed by real data.

---

## Phase 1: Rectangle Detection MVP (Epic 2.5 - Immediate)

### Goals

- Add real-time rectangle detection to the camera preview
- Display green bounding boxes around detected rectangular objects (potential book spines)
- Integrate cleanly with existing text + barcode detection pipeline
- Provide enhanced capture guidance when rectangles are detected

### Deliverables

1. `VNDetectRectanglesRequest` integrated into `VisionService`
2. `DetectedObject` type added to `VisionTypes.swift`
3. `.objects([DetectedObject])` case added to `VisionResult` enum
4. `ObjectBoundingBoxView` SwiftUI overlay component
5. `CameraViewModel` wired for reactive rectangle display
6. `CameraView` overlay layer added

### Acceptance Criteria

- [ ] Green bounding boxes appear around rectangular objects in real-time
- [ ] Maximum 3 rectangles displayed simultaneously (prevent UI clutter)
- [ ] Minimum confidence threshold of 0.75 (reduce false positives)
- [ ] Existing text and barcode detection continues to work (no regressions)
- [ ] FPS remains above 55 (measured with Instruments)
- [ ] Build passes with 0 errors, 0 warnings via `xcodebuild | xcsift`
- [ ] Rectangle boxes use Swiss Glass design (green borders, frosted labels)

### Estimated Effort: ~80 minutes

| Task | Time | Files |
|------|------|-------|
| Add DetectedObject type + VisionResult case | 10 min | VisionTypes.swift |
| Add VNDetectRectanglesRequest to VisionService | 15 min | VisionService.swift |
| Create ObjectBoundingBoxView | 20 min | ObjectBoundingBoxView.swift (new) |
| Wire CameraViewModel | 15 min | CameraViewModel.swift |
| Add overlay to CameraView | 10 min | CameraView.swift |
| Build verification + manual QA | 10 min | - |

---

## Phase 2: Data Collection and Analysis (Epic 3-4 - Background)

### Goals

- Log rectangle detection patterns silently during normal usage
- Collect anonymized metrics: bounding box dimensions, aspect ratios, confidence scores
- Identify false positive/negative patterns to inform Phase 3 model training
- No user-facing features (pure telemetry)

### Deliverables

1. `DetectionTelemetry` actor for on-device logging
2. Local JSON log files in app sandbox (no network transmission)
3. Analysis script for extracting training insights
4. Privacy-compliant data collection (no images stored, only geometry)

### Acceptance Criteria

- [ ] Telemetry logs rectangle detections with timestamp, confidence, dimensions, aspect ratio
- [ ] Logs also record whether text/barcode was simultaneously detected (correlation data)
- [ ] No personally identifiable information captured
- [ ] Log rotation: max 7 days / 10MB (whichever comes first)
- [ ] Zero performance impact (async writes, batched I/O)
- [ ] User can opt out via Settings (respect privacy)

### Estimated Effort: ~4 hours

---

## Phase 3: Custom CoreML Model (Epic 6-7 - Future)

### Goals

- Train a book-spine-specific object detection model using Phase 2 data
- Replace or augment VNDetectRectanglesRequest with VNCoreMLRequest
- A/B test custom model vs rectangle detection for accuracy comparison
- Phased rollout based on accuracy metrics

### Deliverables

1. Training pipeline (Create ML or PyTorch + CoreML Tools export)
2. Book-spine CoreML model (`.mlmodelc` compiled asset)
3. `VNCoreMLRequest` integration in VisionService
4. Feature flag system for A/B testing
5. Accuracy comparison report

### Model Architecture Evaluation

| Architecture | Size | Inference Time | Pros | Cons |
|-------------|------|----------------|------|------|
| YOLOv8n | ~6 MB | ~8ms | Fast, proven object detection | Overkill for single-class |
| MobileNetV3-SSD | ~4 MB | ~6ms | Small, mobile-optimized | May lack precision |
| Custom CNN | ~2 MB | ~4ms | Tailored to book spines | Needs more training data |

### Acceptance Criteria

- [ ] Model achieves >90% precision and >85% recall on held-out test set
- [ ] Inference time < 15ms per frame (no FPS regression)
- [ ] Model size < 10 MB (app size budget)
- [ ] A/B test shows statistically significant improvement over rectangles
- [ ] Rollout: 5% -> 25% -> 50% -> 100% with monitoring at each stage
- [ ] Rollback mechanism: feature flag instantly reverts to rectangle detection

### Estimated Effort: ~2 weeks (including training iteration)

---

## Technical Implementation Details (Phase 1)

### File 1: `VisionTypes.swift` (lines 1-91)

**Changes:** Add `DetectedObject` struct and extend `VisionResult` enum.

**Location:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/VisionTypes.swift`

After line 72 (end of `BarcodeResult`), add the `DetectedObject` struct:

```swift
// MARK: - Detected Object

/// Represents a detected rectangular object (potential book spine) in the camera frame.
/// Used for object detection results from Vision framework rectangle detection.
public struct DetectedObject: Sendable {
    /// The bounding box in normalized coordinates (0.0 to 1.0)
    /// Origin is bottom-left in Vision framework coordinate system
    public let boundingBox: CGRect

    /// Confidence score of the rectangle detection (0.0 to 1.0)
    public let confidence: Float

    /// The observation UUID for tracking across frames
    public let observationUUID: UUID

    public init(boundingBox: CGRect, confidence: Float, observationUUID: UUID) {
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.observationUUID = observationUUID
    }
}
```

Modify the `VisionResult` enum (line 16-25) to add the `.objects` case:

```swift
public enum VisionResult: Sendable {
    /// Text was detected in the image with regions and confidence scores
    case textRegions([TextRegion])

    /// A barcode (ISBN) was detected in the image
    case barcode(BarcodeResult)

    /// Rectangular objects detected (potential book spines)
    case objects([DetectedObject])

    /// No meaningful content was detected in the image
    case noContent
}
```

**Thread Safety:** `DetectedObject` is `Sendable` (all properties are value types). `VisionResult` remains `Sendable` because all associated values are `Sendable`.

### File 2: `VisionService.swift` (lines 1-219)

**Changes:** Add `rectangleRequest`, configure it, include in `perform()` call, extract results.

**Location:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/VisionService.swift`

After line 25 (`barcodeRequest`), add the rectangle request property:

```swift
private let rectangleRequest = VNDetectRectanglesRequest()
```

In `init()` (after line 39, end of barcode configuration), add rectangle configuration:

```swift
// Configure rectangle detection request
rectangleRequest.minimumAspectRatio = 0.1   // Book spines are tall and narrow
rectangleRequest.maximumAspectRatio = 0.9   // Exclude near-square shapes
rectangleRequest.minimumSize = 0.05         // At least 5% of frame
rectangleRequest.maximumObservations = 3    // Limit UI clutter
rectangleRequest.minimumConfidence = 0.75   // Reduce false positives
```

In `processFrame()` (line 69), add the rectangle request to the perform array:

```swift
// Before (line 69):
try handler.perform([textRequest, barcodeRequest])

// After:
try handler.perform([textRequest, barcodeRequest, rectangleRequest])
```

After barcode extraction (after line 101), before the text regions return, add rectangle extraction:

```swift
// Extract rectangle observations (potential book spines)
var detectedObjects: [DetectedObject] = []
if let rectangleObservations = rectangleRequest.results {
    for observation in rectangleObservations {
        guard observation.confidence > 0.75 else { continue }
        let object = DetectedObject(
            boundingBox: observation.boundingBox,
            confidence: observation.confidence,
            observationUUID: observation.uuid
        )
        detectedObjects.append(object)
    }
}
```

Update the return logic (lines 103-108) to include objects:

```swift
// Return appropriate result with priority: barcode > objects > text > noContent
// Note: Barcode is already returned above (line 98)
if !detectedObjects.isEmpty {
    return VisionResult.objects(detectedObjects)
} else if !textRegions.isEmpty {
    return VisionResult.textRegions(textRegions)
} else {
    return VisionResult.noContent
}
```

**IMPORTANT DESIGN DECISION:** The result priority is `barcode > objects > text > noContent`. Barcode detection already returns early (line 98). Rectangle detection takes second priority because it provides spatial context even when text is not yet readable. Text regions remain third priority.

**Alternative considered:** Returning a composite result with all three detection types simultaneously. Rejected for Phase 1 because it would require refactoring the `VisionResult` enum into a struct with optional fields, touching every consumer. Phase 3 should revisit this when the model can provide richer results.

**IMPORTANT NOTE ON `generateGuidance(from:)`:**
`VisionService.generateGuidance(from result: VisionResult)` exists at line 158-188 but is **NOT CALLED** by `CameraViewModel`. The CameraViewModel uses its own `generateGuidance(from regions: [TextRegion])` method at line 864 (different signature, takes `[TextRegion]` not `VisionResult`). Therefore:
- **DO NOT** add a `.objects` case to `VisionService.generateGuidance()` -- it would be dead code that never executes
- The `.objects` case added to VisionService in this TODO is ONLY for the `processFrame()` return logic (lines 103-108)
- All guidance generation for object detection happens in `CameraViewModel.generateObjectGuidance(from:)` (TODO 4)
- A future cleanup task should either remove `VisionService.generateGuidance()` entirely or wire it in, but that is out of scope for this plan

However, adding `.objects` to the `VisionResult` enum will cause a **compiler error** in `VisionService.generateGuidance()` because its `switch result` is exhaustive. The executor must add a minimal handler to satisfy the compiler:

```swift
// In VisionService.generateGuidance() - add after .noContent case:
case .objects:
    // NOTE: This method is currently unused by CameraViewModel.
    // Object guidance is handled by CameraViewModel.generateObjectGuidance().
    // This case exists only to satisfy exhaustive switch requirements.
    return CaptureGuidance.holdSteady
```

### File 3: `ObjectBoundingBoxView.swift` (NEW FILE)

**Location:** `/Users/juju/dev_repos/swiftwing/swiftwing/ObjectBoundingBoxView.swift`

This is a new SwiftUI view following the exact pattern of `VisionOverlayView.swift` (lines 32-150). Key differences: green borders instead of white, no text labels, simpler structure.

```swift
//
//  ObjectBoundingBoxView.swift
//  swiftwing
//

import SwiftUI

// MARK: - ObjectBoundingBoxView

/// Real-time overlay that renders detected rectangular objects with green bounding boxes.
/// Follows the same coordinate transformation pattern as VisionOverlayView.
///
/// Features:
/// - Normalized coordinate conversion (Vision uses 0-1, bottom-left origin)
/// - Confidence-based opacity (higher confidence = more visible)
/// - Green borders to distinguish from text overlays (white)
/// - Maximum 3 boxes displayed (configured in VisionService)
struct ObjectBoundingBoxView: View {
    /// Array of detected objects from Vision framework rectangle detection
    let detectedObjects: [DetectedObject]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(detectedObjects, id: \.observationUUID) { object in
                    ObjectBoxOverlay(
                        object: object,
                        viewSize: geometry.size
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.swissSpring, value: detectedObjects.count)
                }
            }
        }
    }
}

// MARK: - ObjectBoxOverlay

/// Individual detected object overlay with green bounding box.
/// Converts Vision's normalized coordinates to SwiftUI screen space.
private struct ObjectBoxOverlay: View {
    let object: DetectedObject
    let viewSize: CGSize

    /// Opacity based on confidence level
    private var opacity: Double {
        switch object.confidence {
        case 0.9...1.0:
            return 1.0
        case 0.8..<0.9:
            return 0.7
        default:
            return 0.5
        }
    }

    /// Border width scales with confidence
    private var borderWidth: CGFloat {
        object.confidence > 0.9 ? 2.5 : 1.5
    }

    var body: some View {
        ZStack {
            // Green bounding box rectangle
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.swissDone, lineWidth: borderWidth)
                .frame(width: convertedRect.width, height: convertedRect.height)
                .opacity(opacity)

            // Small confidence badge (top-right corner)
            VStack {
                HStack {
                    Spacer()
                    Text("\(Int(object.confidence * 100))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.swissDone)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.7))
                        .cornerRadius(4)
                        .opacity(opacity)
                }
                Spacer()
            }
            .frame(width: convertedRect.width, height: convertedRect.height)
        }
        .position(x: convertedRect.midX, y: convertedRect.midY)
    }

    // MARK: - Coordinate Conversion

    /// Convert Vision normalized coordinates (0-1, bottom-left) to SwiftUI (top-left)
    /// Identical transformation to VisionOverlayView.TextRegionOverlay.convertedRect
    private var convertedRect: CGRect {
        let visionRect = object.boundingBox

        let x = visionRect.origin.x * viewSize.width
        let width = visionRect.width * viewSize.width
        let height = visionRect.height * viewSize.height
        let y = viewSize.height - (visionRect.origin.y * viewSize.height) - height

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Preview

#Preview("Object Detection - High Confidence") {
    ObjectBoundingBoxView(detectedObjects: [
        DetectedObject(
            boundingBox: CGRect(x: 0.15, y: 0.2, width: 0.1, height: 0.6),
            confidence: 0.95,
            observationUUID: UUID()
        ),
        DetectedObject(
            boundingBox: CGRect(x: 0.45, y: 0.25, width: 0.08, height: 0.5),
            confidence: 0.82,
            observationUUID: UUID()
        )
    ])
    .background(Color.swissBackground)
}

#Preview("Object Detection - Empty") {
    ObjectBoundingBoxView(detectedObjects: [])
        .background(Color.swissBackground)
}
```

### File 4: `CameraViewModel.swift` (line 55-60, line 94-123)

**Location:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`

After line 59 (`captureGuidance` property), add the detected objects property:

```swift
// MARK: - Object Detection State
var detectedObjects: [DetectedObject] = []
```

In the `onVisionResult` callback (lines 94-123), add a case for `.objects`:

```swift
// Inside the onVisionResult callback (after the .barcode case, before .noContent):
case .objects(let objects):
    self.detectedObjects = objects
    self.detectedText = []  // Clear text when showing objects
    self.captureGuidance = self.generateObjectGuidance(from: objects)
```

Also update the `.noContent` case to clear objects:

```swift
case .noContent:
    self.detectedText = []
    self.detectedObjects = []  // Clear objects
    self.captureGuidance = .noBookDetected
```

Add a guidance helper for objects (near line 864, the existing `generateGuidance` method):

```swift
/// Generate guidance when rectangular objects are detected
private func generateObjectGuidance(from objects: [DetectedObject]) -> CaptureGuidance {
    guard !objects.isEmpty else {
        return .noBookDetected
    }

    let maxConfidence = objects.map { $0.confidence }.max() ?? 0

    if maxConfidence > 0.9 {
        return .moveCloser  // Shape detected clearly, move closer for text
    } else {
        return .holdSteady  // Keep steady for better detection
    }
}
```

### File 5: `CameraView.swift` (lines 33-40)

**Location:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraView.swift`

After line 35 (existing `VisionOverlayView`), add the object detection overlay:

```swift
// Vision Framework Overlays (conditionally shown)
if viewModel.isVisionEnabled {
    VisionOverlayView(textRegions: viewModel.detectedText)
        .allowsHitTesting(false)

    // Object detection overlay (green boxes for rectangles)
    ObjectBoundingBoxView(detectedObjects: viewModel.detectedObjects)
        .allowsHitTesting(false)

    CaptureGuidanceView(guidance: viewModel.captureGuidance)
        .transition(.move(edge: .top).combined(with: .opacity))
}
```

### File 6: Xcode Project Configuration

The new file `ObjectBoundingBoxView.swift` must be added to the Xcode project target membership. This is handled automatically when the file is created within the project directory structure, but the executor should verify the file appears in the `swiftwing` target's "Compile Sources" build phase.

---

## Risk Assessment

### Phase 1 Risks

| Risk | Severity | Probability | Mitigation |
|------|----------|-------------|------------|
| UI clutter from too many boxes | Medium | Medium | `maximumObservations = 3` + confidence threshold 0.75 |
| False positives on non-book objects | Low | High | Expected; Phase 2 data collection will quantify this |
| FPS regression from additional request | Low | Low | VNDetectRectanglesRequest is ~5-10ms; existing throttling handles this |
| VisionResult enum change breaks consumers | Medium | **CERTAIN** | Adding `.objects` breaks exhaustive switches in CameraViewModel (line 99) and VisionService.generateGuidance (line 158). **Mitigated by Phase 1A grouping:** TODO 1 + TODO 4 + TODO 2 partial are applied as a single atomic unit. |
| Rectangle detection conflicts with text overlay | Low | Medium | Green vs white color coding; objects cleared when text appears |

### Phase 2 Risks

| Risk | Severity | Probability | Mitigation |
|------|----------|-------------|------------|
| Privacy concerns from telemetry | High | Low | No images stored; only geometry + confidence; opt-out in Settings |
| Disk space from logging | Low | Medium | 7-day rotation + 10MB cap |
| Performance impact from logging | Low | Low | Async batched writes; no main thread involvement |

### Phase 3 Risks

| Risk | Severity | Probability | Mitigation |
|------|----------|-------------|------------|
| Model accuracy worse than rectangles | High | Medium | A/B test; instant rollback via feature flag |
| Insufficient training data | Medium | Medium | Phase 2 runs for 4+ weeks; synthetic augmentation if needed |
| Model too large for app bundle | Low | Low | Target < 10MB; quantization if needed |
| CoreML inference latency | Medium | Low | MobileNet variants run < 10ms on A15+ chips |

---

## Performance Validation

### Targets

| Metric | Target | Measurement Method |
|--------|--------|--------------------|
| UI FPS | > 55 FPS | Instruments Core Animation FPS |
| Rectangle detection latency | < 10ms per frame | CFAbsoluteTimeGetCurrent() in processFrame() |
| Total Vision pipeline | < 25ms per frame | Aggregate of text + barcode + rectangle |
| Memory impact | < 2 MB additional | Instruments Allocations |
| Camera cold start | < 0.5s (no regression) | Existing cold start timer in CameraViewModel |

### Validation Steps

1. **Build verification:** `xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift` must report `errors: 0, warnings: 0`
2. **Performance profiling:** Run Instruments Time Profiler during 30-second scanning session
3. **FPS check:** Run Instruments Core Animation FPS during active rectangle detection
4. **Memory check:** Compare Instruments Allocations before/after feature (ensure < 2MB delta)

---

## Testing Strategy

### Unit Tests

**Coordinate transformation tests** (copy pattern from VisionOverlayView):

```swift
func testVisionToSwiftUICoordinateConversion() {
    // Vision: bottom-left origin, normalized (0-1)
    // SwiftUI: top-left origin, pixel coordinates
    let visionRect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    let viewSize = CGSize(width: 400, height: 800)

    let expectedX = 0.1 * 400  // 40
    let expectedWidth = 0.3 * 400  // 120
    let expectedHeight = 0.4 * 800  // 320
    let expectedY = 800 - (0.2 * 800) - 320  // 800 - 160 - 320 = 320

    // NOTE: ObjectBoxOverlay.convertedRect is private. To test coordinate
    // conversion, either:
    // (a) Extract the conversion into a free function or static method on
    //     ObjectBoundingBoxView that can be tested directly, OR
    // (b) Use @testable import and test the conversion formula independently
    //     by replicating the math here:
    let convertedX = visionRect.origin.x * viewSize.width
    let convertedWidth = visionRect.width * viewSize.width
    let convertedHeight = visionRect.height * viewSize.height
    let convertedY = viewSize.height - (visionRect.origin.y * viewSize.height) - convertedHeight

    XCTAssertEqual(convertedX, expectedX, accuracy: 0.001)
    XCTAssertEqual(convertedWidth, expectedWidth, accuracy: 0.001)
    XCTAssertEqual(convertedHeight, expectedHeight, accuracy: 0.001)
    XCTAssertEqual(convertedY, expectedY, accuracy: 0.001)
}
```

**VisionResult enum tests:**

```swift
func testVisionResultObjectsCase() {
    let objects = [DetectedObject(
        boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.6),
        confidence: 0.85,
        observationUUID: UUID()
    )]

    let result = VisionResult.objects(objects)

    if case .objects(let detected) = result {
        XCTAssertEqual(detected.count, 1)
        XCTAssertEqual(detected.first?.confidence, 0.85)
    } else {
        XCTFail("Expected .objects case")
    }
}
```

**Guidance generation tests:**

```swift
func testObjectGuidanceHighConfidence() {
    // >0.9 confidence should recommend .moveCloser
    let objects = [DetectedObject(
        boundingBox: .zero,
        confidence: 0.95,
        observationUUID: UUID()
    )]
    // Assert guidance == .moveCloser
}

func testObjectGuidanceMediumConfidence() {
    // 0.75-0.9 confidence should recommend .holdSteady
    let objects = [DetectedObject(
        boundingBox: .zero,
        confidence: 0.80,
        observationUUID: UUID()
    )]
    // Assert guidance == .holdSteady
}
```

### Integration Tests

- [ ] Vision pipeline processes text + barcode + rectangles without error
- [ ] Barcode detection still takes priority (returns early before rectangle check)
- [ ] Frame throttling applies uniformly to all three request types
- [ ] Disabling Vision (`toggleVision()`) stops all three request types

### Manual QA

- [ ] Point camera at a bookshelf: green boxes appear around book spines
- [ ] Move closer: text overlay starts appearing, green boxes may transition
- [ ] Point at non-book rectangles (monitors, windows): boxes appear but this is expected
- [ ] Scan a barcode: barcode detection still works correctly
- [ ] Toggle Vision off: all overlays disappear
- [ ] Background the app and return: overlays resume correctly
- [ ] Verify no visual glitches when text and object boxes overlap

### Performance Tests

- [ ] Instruments Time Profiler: processFrame() total < 25ms at p99
- [ ] Instruments Core Animation FPS: sustained > 55 during active scanning
- [ ] Instruments Allocations: no memory leaks over 5-minute session
- [ ] Battery: no measurable regression in 10-minute scanning session

---

## Rollout Plan

### Phase 1: Rectangle Detection MVP

- **Rollout:** Merge to main, ENABLED by default
- **Rationale:** High confidence in existing architecture; additive feature; easy to toggle off
- **Toggle mechanism:** Existing `isVisionEnabled` flag in CameraViewModel controls all Vision overlays
- **Rollback:** Set `rectangleRequest.maximumObservations = 0` or remove from `perform()` array

### Phase 2: Data Collection

- **Rollout:** Silent deployment alongside Phase 1 (separate PR)
- **Duration:** Minimum 2 weeks before analysis, target 4 weeks
- **Monitoring:** Log file size, detection frequency, app launch time (ensure no regression)
- **Privacy:** On-device only; opt-out via Settings toggle

### Phase 3: Custom CoreML Model

- **Rollout:** Phased
  - Week 1: 5% of users (via feature flag)
  - Week 2: 25% (if precision > 90%)
  - Week 3: 50% (if no accuracy regression)
  - Week 4: 100% (general availability)
- **Monitoring:** Accuracy metrics, crash rates, user feedback
- **Rollback:** Feature flag instantly reverts to rectangle detection

---

## Architectural Questions for Architect

1. **Parallel vs. sequential detection:** Currently all three requests (text, barcode, rectangle) run in a single `handler.perform()` call, which Vision executes sequentially on the same handler. Should we consider running rectangle detection on a separate handler to enable true parallelism? Trade-off: complexity vs. potential 5-10ms latency improvement.

2. **Overlapping detections:** When a rectangle is detected that contains text regions, should the UI show both overlays (green box + white text boxes inside)? Currently the priority system means only one type shows at a time (objects vs text). Phase 3 may need a composite result type.

3. **Result priority ordering:** The plan puts `objects` ahead of `textRegions` in priority. The rationale is that rectangles provide spatial context even when text is not readable. However, once text IS readable, the text overlay is arguably more useful. Should we return the "richest" result type instead (text > objects > noContent)?

4. **Phase 2 data collection:** Should telemetry log to on-device files (simpler, no backend dependency) or POST to a lightweight analytics endpoint (enables remote analysis without app updates)? On-device is safer for privacy but requires a mechanism to extract data for model training.

5. **VisionResult refactoring:** The current enum forces single-type results. Should Phase 1 refactor to a struct with optional fields (`textRegions: [TextRegion]?`, `objects: [DetectedObject]?`, `barcode: BarcodeResult?`) to support composite results? This would touch every consumer but future-proofs for Phase 3.

---

## Commit Strategy

### Phase 1 Commits (3 atomic commits)

**CRITICAL: Each commit MUST produce a compiling project.** The original strategy had Commit 1 touching only VisionTypes.swift, which would leave CameraViewModel with a non-exhaustive switch -- a compiler error. The revised strategy groups type definitions with their required consumers.

1. **`feat: Add DetectedObject type and ViewModel handler for object detection`**
   - Files: `VisionTypes.swift`, `CameraViewModel.swift`, `VisionService.swift` (generateGuidance exhaustive switch fix only)
   - Adds `DetectedObject` struct, `.objects` case to `VisionResult`, `.objects` handler in CameraViewModel switch, minimal `.objects` case in VisionService.generateGuidance(), and `generateObjectGuidance()` helper
   - **Result: COMPILES** (all exhaustive switches satisfied, new property + handler in place)

2. **`feat: Add rectangle detection to VisionService pipeline`**
   - Files: `VisionService.swift`
   - Adds `rectangleRequest` property, configuration in init(), inclusion in perform() array, rectangle observation extraction, updated return priority logic
   - **Result: COMPILES** (detection now produces `.objects` results)

3. **`feat: Add object detection UI overlay`**
   - Files: `ObjectBoundingBoxView.swift` (new), `CameraView.swift`
   - New SwiftUI overlay component with green bounding boxes, wired into CameraView
   - **Result: COMPILES, FEATURE COMPLETE**

### Phase 2 Commits (separate PR)

4. **`feat: Add DetectionTelemetry actor for on-device logging`**
   - New file: `DetectionTelemetry.swift`

5. **`feat: Wire telemetry into VisionService pipeline`**
   - Files: `VisionService.swift`, `CameraViewModel.swift`

### Phase 3 Commits (separate PR per stage)

6. **`feat: Add CoreML model integration with feature flag`**
7. **`feat: Add A/B test infrastructure for detection models`**
8. **`feat: Replace rectangle detection with custom CoreML model`**

---

## Success Criteria

### Phase 1 (Must achieve ALL)

- [ ] 0 build errors, 0 build warnings
- [ ] Green bounding boxes visible in camera preview when pointing at books
- [ ] Existing text overlay, barcode scanning, and capture pipeline work without regression
- [ ] FPS > 55 sustained during active scanning
- [ ] Clean code: follows existing patterns, Swift 6.2 compliant, Sendable types

### Phase 2 (Must achieve ALL)

- [ ] Telemetry running silently for 2+ weeks
- [ ] At least 1,000 detection events logged
- [ ] Analysis report generated with false positive/negative breakdown
- [ ] No user complaints about performance or privacy

### Phase 3 (Must achieve ALL)

- [ ] Custom model achieves > 90% precision, > 85% recall
- [ ] Inference time < 15ms per frame
- [ ] A/B test shows statistically significant improvement (p < 0.05)
- [ ] 100% rollout without accuracy regression

---

## Task Breakdown (Phase 1 - for executor)

### TODO 1: Add DetectedObject type to VisionTypes.swift
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/VisionTypes.swift`
**Action:** Add `DetectedObject` struct after line 72 (end of BarcodeResult). Add `.objects([DetectedObject])` case to `VisionResult` enum after line 21 (barcode case).
**COMPILATION WARNING:** This change alone will NOT compile. Adding `.objects` to `VisionResult` breaks exhaustive switches in CameraViewModel (line 99) and VisionService.generateGuidance (line 158). TODO 4 and the generateGuidance fix in TODO 2 MUST be applied in the same compilation pass. See Phase 1A in Dependencies.
**Acceptance:** Types are `Sendable`. Builds with 0 errors, 0 warnings ONLY when combined with TODO 4 and TODO 2's generateGuidance fix.

### TODO 2: Add VNDetectRectanglesRequest to VisionService
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/VisionService.swift`
**Action:**
- Add `rectangleRequest` property after line 25
- Configure in `init()` after line 39 (minimumAspectRatio: 0.1, maximumAspectRatio: 0.9, minimumSize: 0.05, maximumObservations: 3, minimumConfidence: 0.75)
- Add to `perform()` array on line 69
- Extract rectangle observations after line 101, before text return logic
- Update return priority: barcode > objects > text > noContent
- Add minimal `.objects` case to `generateGuidance()` at line 158 to satisfy exhaustive switch (this method is NOT called by CameraViewModel -- see note in Technical Implementation Details). Use `return CaptureGuidance.holdSteady` with a comment noting it is dead code.
**Acceptance:** processFrame() returns `.objects` when rectangles detected. Existing text/barcode behavior preserved. `generateGuidance()` compiles without exhaustive switch error.

### TODO 3: Create ObjectBoundingBoxView.swift
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/ObjectBoundingBoxView.swift` (NEW)
**Action:** Create SwiftUI view following VisionOverlayView pattern. Green borders (Color.swissDone), rounded rectangle stroke, confidence badge, coordinate transformation from Vision to SwiftUI. Use `\.observationUUID` as ForEach id (not `\.offset`) for stable animations.
**Acceptance:** Renders green boxes in SwiftUI Previews. Correct coordinate conversion. File appears in `swiftwing` target's "Compile Sources" build phase (verify via `xcodebuild` -- if file is not in target, build will fail with "no such module" or symbol not found).

### TODO 4: Wire CameraViewModel for object detection
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`
**DEPENDENCY:** Must be done in the same compilation unit as TODO 1. Adding `.objects` to `VisionResult` without adding the handler here causes a compiler error (non-exhaustive switch at line 99-116).
**Action:**
- Add `detectedObjects: [DetectedObject] = []` property after line 59
- Add `.objects` case handling in `onVisionResult` callback (lines 94-123)
- Clear `detectedObjects` in `.noContent` case (line 114)
- Add `generateObjectGuidance(from:)` helper near line 864
**Acceptance:** `detectedObjects` property updates reactively when rectangles are detected. Project compiles after TODO 1 + TODO 4 are applied together.

### TODO 5: Add ObjectBoundingBoxView overlay to CameraView
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraView.swift`
**Action:** Add `ObjectBoundingBoxView(detectedObjects: viewModel.detectedObjects)` after line 35 (VisionOverlayView), inside the `isVisionEnabled` conditional. Set `.allowsHitTesting(false)`.
**Acceptance:** Green boxes visible in camera preview. No hit testing interference.

### TODO 6: Build verification and manual QA
**Action:** Run `xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift` and verify 0 errors, 0 warnings.
**Acceptance:** Build succeeds. Manual testing confirms green boxes appear when pointing at rectangular objects.

---

## Dependencies

**CORRECTED DEPENDENCY GRAPH:**

Adding `.objects` to the `VisionResult` enum (TODO 1) breaks the exhaustive `switch result` in `CameraViewModel.swift` (line 99-116) and in `VisionService.generateGuidance()` (line 158-188). Therefore TODO 4 (CameraViewModel) and the `generateGuidance()` fix in TODO 2 MUST be done in the same compilation phase as TODO 1. The project will NOT compile after TODO 1 alone.

```
Phase 1A (MUST compile together):
  TODO 1 (VisionTypes) ──┬──> TODO 4 (CameraViewModel - .objects handler)
                          └──> TODO 2 partial (VisionService - generateGuidance exhaustive switch fix)

Phase 1B (can run in parallel, builds on 1A):
  TODO 2 remainder (VisionService - rectangle request + extraction)
  TODO 3 (ObjectBoundingBoxView - new file, independent)

Phase 1C (depends on 1B):
  TODO 5 (CameraView - needs TODO 3 view + TODO 4 ViewModel property)

Phase 1D (depends on all):
  TODO 6 (Build verification + manual QA)
```

**Execution order constraints:**
- TODO 1 + TODO 4 + TODO 2 (generateGuidance fix) must be done together as an atomic unit (project does not compile otherwise)
- After Phase 1A compiles, TODO 2 remainder and TODO 3 can run in parallel (independent files)
- TODO 5 depends on TODOs 3 and 4 (needs both the view and the ViewModel property)
- TODO 6 depends on all prior tasks

**Why TODOs 2, 3, 4 CANNOT all run in parallel:**
The original plan claimed these were independent. This is incorrect because:
1. Adding `.objects` to `VisionResult` (TODO 1) creates a compiler error in CameraViewModel's exhaustive switch
2. The CameraViewModel switch at line 99-116 has no `default` case -- it is exhaustive over `.textRegions`, `.barcode`, `.noContent`
3. Adding a fourth case without handling it is a Swift compiler error (not a warning)
4. Therefore TODO 4 (which adds the `.objects` handler) MUST accompany TODO 1
