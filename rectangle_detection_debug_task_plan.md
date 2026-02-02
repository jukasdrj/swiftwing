# Rectangle Detection Debugging Task Plan

## Goal
Investigate why real-time rectangle detection isn't showing bounding boxes in the camera view.

## Observed Symptoms
1. ✅ Camera works (captures images successfully)
2. ✅ Talaria upload works (SSE stream shows 6 books identified)
3. ❌ No Vision framework output in logs (besides "[Vision] Frame dropped")
4. ❌ No green bounding boxes visible in camera preview
5. ❌ No detectedObjects being populated

## Root Cause Hypotheses

### Hypothesis 1: Vision Processing Not Detecting Rectangles
**Likelihood:** HIGH
- VisionService has NO logging - can't see what it's detecting
- Rectangles might not match book spine parameters (aspect ratio 0.1-0.9)
- Confidence threshold might be too high (0.75 minimum)

**Test:**
- Add diagnostic logging to VisionService.processFrame()
- Log rectangle count, confidence scores, bounding boxes
- Check if VNDetectRectanglesRequest is finding ANY rectangles

### Hypothesis 2: UI Rendering Issue
**Likelihood:** MEDIUM
- ObjectBoundingBoxView might not be rendering correctly
- Coordinate transformation (Vision → SwiftUI) might be incorrect
- ForEach might not be iterating due to empty array

**Test:**
- Add logging to ObjectBoundingBoxView to show when it renders
- Log detectedObjects count in CameraViewModel
- Verify GeometryReader provides valid size

### Hypothesis 3: isVisionEnabled Toggle Off
**Likelihood:** LOW
- Default value is `true` in CameraViewModel
- But worth checking if user toggled it off

**Test:**
- Add log statement when isVisionEnabled changes
- Verify overlay rendering path is executed

### Hypothesis 4: Frame Throttling Too Aggressive
**Likelihood:** LOW
- `visionService.shouldProcessFrame()` might be rejecting too many frames
- Frame dropping messages suggest frames ARE being processed

**Test:**
- Check throttling logic in VisionService
- Temporarily disable throttling to test

## Implementation Plan

### Phase 1: Add Diagnostic Logging (15 min)
**Files:** VisionService.swift, CameraViewModel.swift, ObjectBoundingBoxView.swift

1. **VisionService.swift** (lines ~55-135):
   - Add log at start of processFrame(): "🔍 Vision: Processing frame..."
   - Log rectangle detection results: "📦 Vision: Found \(count) rectangles"
   - For each rectangle: log confidence, boundingBox, observationUUID
   - Log final VisionResult type returned

2. **CameraViewModel.swift** (lines ~119-122):
   - In `.objects` case handler: log count and confidence scores
   - Log generateObjectGuidance() output

3. **ObjectBoundingBoxView.swift** (line ~17):
   - Add `.onAppear { print("🎨 ObjectBoundingBoxView rendered with \(detectedObjects.count) objects") }`
   - Log geometry size in convertToViewCoordinates()

### Phase 2: Test with Actual Camera (5 min)
- Run app in simulator with diagnostic logs
- Point camera at book spines (or any rectangular objects)
- Observe logs to see:
  - Is Vision processing frames?
  - Are rectangles being detected?
  - What are confidence scores?
  - Are objects reaching CameraViewModel?
  - Is UI rendering?

### Phase 3: Adjust Detection Parameters (10 min)
Based on Phase 2 findings:

**If NO rectangles detected:**
- Lower confidence threshold from 0.75 to 0.5
- Expand aspect ratio range (0.05-0.95)
- Reduce minimum size from 0.05 to 0.02

**If rectangles detected but confidence too low:**
- Adjust minimumConfidence in VisionService init()
- Adjust threshold in generateObjectGuidance() (currently 0.85)

**If rectangles detected but not rendering:**
- Fix coordinate transformation in ObjectBoundingBoxView
- Check imageSize parameter (currently hardcoded to 1920x1080)

### Phase 4: Fix Root Cause (15 min)
Apply findings from Phase 2-3 to fix the actual issue.

## Success Criteria
- ✅ Vision framework logs show rectangle detection attempts
- ✅ Rectangles detected with confidence > 0.5 for test objects
- ✅ detectedObjects array populated in CameraViewModel
- ✅ Green bounding boxes visible in camera preview
- ✅ Bounding boxes track objects as camera moves

## Current Status
- Phase: Not started
- Blocking Issue: No diagnostic visibility into Vision processing

## Next Action
Start Phase 1: Add diagnostic logging to VisionService.swift
