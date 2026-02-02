# Debugging Vision Rectangle Detection

## Current Status (Feb 2, 2026) - ✅ RESOLVED

**Problem:** Green bounding boxes not appearing in camera view when pointing at book spines.

**Root Causes Found & Fixed:**
1. ✅ **Double Throttling Bug** - FrameProcessor checked `shouldProcessFrame()` twice (once in delegate, once in processFrame)
2. ✅ **Object Persistence Bug** - `.noContent` case was clearing `detectedObjects` array on every throttled frame

**Final Status:**
- ✅ Vision framework detecting 3 rectangles per frame with 100% confidence
- ✅ FrameProcessor delegate receiving frames at 30 FPS
- ✅ Vision processing throttled to ~6.7 FPS (150ms intervals)
- ✅ ObjectBoundingBoxView rendering boxes with correct coordinates
- ✅ Bounding boxes persist between frames (no flicker)

**Commits:**
- Fix #1: Removed duplicate throttle check from FrameProcessor:415-430
- Fix #2: Changed `.noContent` case to preserve last detected objects

---

## Diagnostic Log Levels

### Level 1: FrameProcessor Delegate
**Location:** `swiftwing/CameraManager.swift:415-430`

**What to Look For:**
```
📹 FrameProcessor: Frame received, processing...
```

**If Missing:** AVCaptureVideoDataOutput delegate not being called.

**Possible Causes:**
1. videoOutput not added to session
2. Delegate not set on videoOutput
3. videoProcessingQueue not running
4. Session not started

### Level 2: Vision Processing
**Location:** `swiftwing/Services/VisionService.swift:59-95`

**What to Look For:**
```
🔍 Vision: Processing frame with orientation: up
📦 Vision: Rectangle request returned N observations
```

**If Missing:** VisionService.processFrame() not being called.

**Possible Causes:**
1. shouldProcessFrame() throttling too aggressive
2. FrameProcessor not calling visionService.processFrame()
3. Exception thrown in processFrame (silently caught)

### Level 3: CameraViewModel Callback
**Location:** `swiftwing/CameraViewModel.swift:122-127`

**What to Look For:**
```
🎯 CameraViewModel: Received N objects from Vision
   Object 1: confidence=0.XX, uuid=...
```

**If Missing:** onFrameProcessed callback not invoking or not wired.

**Possible Causes:**
1. Callback nil (check FrameProcessor logs for warning)
2. Callback wired to wrong ViewModel instance
3. Task dropped before reaching MainActor

### Level 4: UI Rendering
**Location:** `swiftwing/ObjectBoundingBoxView.swift:17-34`

**What to Look For:**
```
🎨 ObjectBoundingBoxView: Rendering N boxes, viewSize=(390, 844)
```

**Currently Showing:** "Rendering 0 boxes" → ViewModel has no objects.

---

## Code Verification Checklist

### CameraManager Setup (setupSession)

**Lines 103-114:**
```swift
// Add video data output for Vision processing
let videoOutput = AVCaptureVideoDataOutput()
videoOutput.videoSettings = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
]
videoOutput.alwaysDiscardsLateVideoFrames = true
videoOutput.setSampleBufferDelegate(frameProcessor, queue: videoProcessingQueue)

if session.canAddOutput(videoOutput) {
    session.addOutput(videoOutput)
    self.videoOutput = videoOutput
}
```

**Verify:**
- [x] videoOutput created
- [x] Delegate set to frameProcessor
- [x] Queue is videoProcessingQueue (serial)
- [x] Added to session
- [ ] **TODO:** Add log after setSampleBufferDelegate() to confirm wiring

### CameraViewModel Callback Wiring

**Lines 119-124:**
```swift
// Wire Vision processing callback
cameraManager.onVisionResult = { [weak self] result in
    Task { @MainActor in
        guard let self else { return }

        switch result {
        case .objects(let objects):
            // ...
```

**Verify:**
- [ ] onVisionResult set in setupCamera()
- [ ] Task wraps callback (MainActor isolation)
- [ ] self captured weakly (no retain cycle)
- [ ] **TODO:** Add log at start of callback to confirm it runs

### FrameProcessor Instance

**Lines 118-124 (setupSession):**
```swift
// Wire frame processor callback
frameProcessor.onFrameProcessed = { [weak self] result in
    Task { @MainActor in
        self?.onVisionResult?(result)
    }
}
```

**Verify:**
- [x] frameProcessor.onFrameProcessed set in setupSession
- [x] Callback forwards to onVisionResult
- [x] Task ensures MainActor for onVisionResult
- [ ] **TODO:** Add log to confirm this runs

---

## Manual Verification Steps

### Step 1: Verify videoOutput is Active

**Add to CameraManager.startSession() after session.startRunning():**
```swift
print("🎥 Video outputs: \(session.outputs.count)")
for output in session.outputs {
    if let videoOut = output as? AVCaptureVideoDataOutput {
        print("  - AVCaptureVideoDataOutput: delegate=\(videoOut.sampleBufferDelegate != nil)")
    } else if let photoOut = output as? AVCapturePhotoOutput {
        print("  - AVCapturePhotoOutput")
    }
}
```

**Expected:**
```
🎥 Video outputs: 2
  - AVCapturePhotoOutput
  - AVCaptureVideoDataOutput: delegate=true
```

### Step 2: Verify Callback Chain

**Add to FrameProcessor before onFrameProcessed?():**
```swift
print("📞 FrameProcessor: Invoking callback with result: \(result)")
```

**Add to CameraManager frameProcessor.onFrameProcessed closure:**
```swift
frameProcessor.onFrameProcessed = { [weak self] result in
    print("📞 CameraManager: Callback received, forwarding to onVisionResult")
    Task { @MainActor in
        self?.onVisionResult?(result)
    }
}
```

**Add to CameraViewModel.setupCamera() after setting onVisionResult:**
```swift
print("📞 CameraViewModel: onVisionResult callback registered")
```

### Step 3: Verify Frame Arrival

**Add to FrameProcessor at TOP of captureOutput (before throttle check):**
```swift
func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    print("📹 FrameProcessor: captureOutput called")

    // Throttle processing
    guard visionService.shouldProcessFrame() else {
        print("  → Throttled")
        return
    }
    // ... rest of method
```

**Expected (every ~150ms):**
```
📹 FrameProcessor: captureOutput called
  → Throttled
📹 FrameProcessor: captureOutput called
  → Throttled
📹 FrameProcessor: captureOutput called
📹 FrameProcessor: Frame received, processing...
```

---

## Common Issues & Fixes

### Issue 1: Delegate Never Called

**Symptom:** No "📹 FrameProcessor: captureOutput called" logs

**Cause:** AVCaptureVideoDataOutput not receiving frames

**Check:**
1. Session is running: `print(session.isRunning)`
2. Connection exists: `print(videoOutput.connection(with: .video) != nil)`
3. Queue exists: `print(videoProcessingQueue != nil)`

**Fix:**
```swift
// Ensure connection is enabled
if let connection = videoOutput.connection(with: .video) {
    connection.isEnabled = true
    print("✅ Video connection enabled")
}
```

### Issue 2: Callback is Nil

**Symptom:** "⚠️ FrameProcessor: onFrameProcessed callback is nil!"

**Cause:** frameProcessor.onFrameProcessed not set before frames arrive

**Check:**
1. setupSession() completes before startSession()
2. frameProcessor.onFrameProcessed set in setupSession (line 120)

**Fix:** Ensure callback set synchronously in setupSession(), not async.

### Issue 3: Throttle Too Aggressive

**Symptom:** Frames arrive but "→ Throttled" on every frame

**Cause:** shouldProcessFrame() always returns false

**Check:**
```swift
print("⏱️ Last: \(lastProcessedTime), Now: \(now), Interval: \(processingInterval), Elapsed: \(elapsed)")
```

**Fix:** Lower processingInterval from 0.15 to 0.05 (20 FPS)

### Issue 4: Vision Silently Failing

**Symptom:** FrameProcessor logs but no Vision logs

**Cause:** Exception in processFrame() caught by try/catch

**Check:** Add catch block logging in VisionService:
```swift
} catch {
    print("❌ Vision: Request failed - \(error)")
    return VisionResult.noContent
}
```

---

## Performance Expectations

### Frame Delivery
- Camera: 30 FPS (AVCaptureSession default)
- Throttle: 6.7 FPS (150ms interval)
- Vision: ~6-7 frames processed per second

### Rectangle Detection
- Observations: 0-10 per frame (depends on scene)
- Filtered: 0-3 (maxObservations = 3)
- Confidence: > 0.75 threshold

### UI Updates
- MainActor: Immediate (next RunLoop)
- Animation: 0.2s spring duration
- Frame rate: 60 FPS (ProMotion devices: 120 FPS)

---

## Next Diagnostic Step

**Priority 1:** Determine why FrameProcessor.captureOutput() isn't being called.

**Add this to CameraManager.setupSession() after line 113:**
```swift
print("✅ Video output configured:")
print("   Delegate: \(videoOutput.sampleBufferDelegate != nil)")
print("   Queue: \(String(describing: videoProcessingQueue.label))")
print("   Connection: \(videoOutput.connection(with: .video) != nil)")
```

**Add this to CameraManager.startSession() after session.startRunning():**
```swift
if let connection = videoOutput?.connection(with: .video) {
    print("📹 Video connection status:")
    print("   Enabled: \(connection.isEnabled)")
    print("   Active: \(connection.isActive)")
} else {
    print("❌ Video connection is nil!")
}
```

Run app, check console, report findings.

---

**Last Updated:** February 2, 2026
**Status:** Awaiting test results with enhanced FrameProcessor logging
