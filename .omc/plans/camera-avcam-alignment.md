# Camera AVCam Alignment Plan

## Context

### Original Request
Align SwiftWing's camera implementation with Apple's AVCam (AVCamBuildingACameraApp) reference code for iOS 26. Fix critical bugs in rotation handling, add missing interruption handling, enable iOS 26 performance optimizations, and improve code organization to match Apple's recommended patterns.

### Interview Summary
This is a **mid-sized refactoring task** with clear deliverables. The scope was defined by architectural comparison between:
- **AVCam reference** (`/Users/juju/dev_repos/swiftwing/camSample/AVCamBuildingACameraApp/AVCam/`)
- **SwiftWing current** (`/Users/juju/dev_repos/swiftwing/swiftwing/CameraManager.swift`, `CameraViewModel.swift`, `CameraPreviewView.swift`)

### Research Findings

**Rotation Coordinator Bug (Critical)**
- SwiftWing line 153: `AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)` -- passing `nil` for previewLayer makes the coordinator non-functional. It cannot compute `videoRotationAngleForHorizonLevelPreview` without a connected preview layer.
- AVCam line 368: `AVCaptureDevice.RotationCoordinator(device: device, previewLayer: videoPreviewLayer)` -- passes the actual connected preview layer, then observes KVO changes on both `videoRotationAngleForHorizonLevelPreview` and `videoRotationAngleForHorizonLevelCapture`.
- SwiftWing compensates with manual orientation mapping in `capturePhoto()` (lines 170-196) using `windowScene.effectiveGeometry.interfaceOrientation`, which is a fragile workaround.

**Missing Interruption Handling**
- AVCam lines 543-571: Three notification observers handle `wasInterruptedNotification`, `interruptionEndedNotification`, and `runtimeErrorNotification` (with automatic media services reset recovery).
- SwiftWing: Zero notification observers. No handling for phone calls, FaceTime interruptions, or media services resets.

**Missing iOS 26 Performance Features**
- AVCam PhotoCapture lines 121-126: Enables `isResponsiveCaptureEnabled`, `isFastCapturePrioritizationEnabled`, `maxPhotoDimensions`, and `isAutoDeferredPhotoDeliveryEnabled`.
- SwiftWing: None of these are configured. Default `AVCapturePhotoSettings()` with no performance tuning.

**Preview Layer Pattern**
- AVCam CameraPreview lines 54-56: Uses `override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }` -- the backing layer pattern where the view's root layer IS the preview layer, so frame updates are automatic.
- SwiftWing CameraPreviewView lines 18-21: Adds preview layer as a sublayer, requiring manual frame updates in `updateUIView`.

**Code Organization**
- AVCam: CameraModel (236 lines, `@Observable`, UI state only) + CaptureService (595 lines, `actor`, all capture logic).
- SwiftWing: CameraViewModel (803 lines, `@Observable`, mixes UI state with capture orchestration, processing queue, book handling, rate limiting, offline queue, SSE streaming).

---

## Work Objectives

### Core Objective
Fix the rotation coordinator bug, add system interruption resilience, enable iOS 26 capture performance features, and adopt Apple's recommended preview layer pattern -- all while preserving SwiftWing's existing Epic 2-4 functionality.

### Deliverables
1. **Working rotation coordinator** with KVO-observed preview and capture rotation angles
2. **Interruption handling** for session interruptions, interruption recovery, and media services reset
3. **iOS 26 performance features** enabled on photo output
4. **Optimized photo resolution** (1024×768) for Gemini Vision API token efficiency (516 tokens vs 3000-12000)
5. **Backing layer preview** pattern replacing sublayer approach
6. **All existing features preserved**: processing queue, SSE streaming, offline queue, rate limiting, duplicate detection, Vision processing, zoom, focus

### Definition of Done
- Rotation is fully automatic (no manual `windowScene.effectiveGeometry` mapping)
- Camera recovers from phone call / FaceTime interruptions
- Camera auto-restarts after media services reset
- Photo capture uses responsive capture + fast prioritization
- Preview layer uses backing layer pattern (no manual frame updates)
- `xcodebuild ... | xcsift` produces 0 errors, 0 warnings
- All Epic 2-4 features work: capture, processing queue, SSE upload, offline queue, rate limiting, duplicate detection, Vision overlay, zoom, focus

---

## Guardrails

### Must Have
- Swift 6.2 strict concurrency compliance (no `@unchecked Sendable` additions)
- Zero regressions in existing camera features
- Rotation works for all 4 device orientations
- Photo orientation in captured JPEG is correct regardless of device orientation
- Vision frame processing continues to receive correct orientation data
- Interruption state is surfaced to UI (so user sees feedback during phone calls)

### Must NOT Have
- Actor migration of CameraManager (task context says "only adopt actor pattern if it provides clear benefits" -- SwiftWing is single-camera, no multi-camera coordination needed)
- CameraViewModel split (separate task -- this plan focuses on CameraManager and CameraPreviewView)
- Multi-camera or camera switching support (SwiftWing is back-camera-only book scanner)
- Live Photo, movie capture, or deferred photo delivery features
- AVCaptureControls / Camera Control HUD (iPhone hardware button feature not relevant to book scanning)

---

## Task Flow and Dependencies

```
Phase 1: Critical Fixes (sequential, each builds on previous)
  Task 1.1: Fix rotation coordinator → foundation for all rotation
  Task 1.2: Adopt backing layer preview → required by Task 1.1 (coordinator needs preview layer reference)
  Task 1.3: Add interruption handling → independent but builds on stable session
  Task 1.4: Enable iOS 26 performance features → independent
  Task 1.5: Optimize photo resolution for Gemini → critical cost savings (92% token reduction)

Phase 2: Cleanup
  Task 2.1: Remove dead code from manual orientation workaround
  Task 2.2: Add interruption state to UI
  Task 2.3: Build verification
```

### Dependency Graph
```
Task 1.2 (backing layer) ──► Task 1.1 (rotation coordinator)
                                        │
Task 1.3 (interruptions) ──────────────►│
Task 1.4 (perf features) ──────────────►├──► Task 2.1 (cleanup)
Task 1.5 (resolution opt) ─────────────►│
                                         └──► Task 2.2 (UI state)
                                               └──► Task 2.3 (build verify)
```

**Why 1.2 must come before 1.1:** The rotation coordinator needs a reference to the preview layer. With the current sublayer approach, the preview layer is created inside `makeUIView` and stored on the Coordinator -- the CameraManager has no access to it. Switching to the backing layer pattern first provides a stable, accessible preview layer reference.

---

## Detailed TODOs

### Task 1.2: Adopt Backing Layer Preview Pattern
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraPreviewView.swift`

**What to change:**
1. Create a `PreviewView` class inside `CameraPreviewView` that overrides `layerClass` to return `AVCaptureVideoPreviewLayer.self`
2. Add a computed property `previewLayer` that casts `layer as! AVCaptureVideoPreviewLayer`
3. Remove the sublayer creation from `makeUIView`
4. Remove manual frame update from `updateUIView` (backing layer auto-sizes)
5. Set `session` on the preview layer in `makeUIView` via `previewLayer.session = session`
6. Set `videoGravity = .resizeAspectFill` in `makeUIView`
7. Store reference to `PreviewView` in the Coordinator (for gesture handling and for CameraManager to access the preview layer)
8. Expose the `previewLayer` from the Coordinator so CameraManager can use it for the rotation coordinator

**Acceptance criteria:**
- Camera preview fills the screen edge-to-edge
- Preview layer automatically resizes on rotation (no manual frame update)
- Pinch-to-zoom still works
- Tap-to-focus still works (uses `previewLayer.captureDevicePointConverted`)
- The preview layer reference is accessible to CameraManager for rotation coordinator setup

**AVCam reference:** `camSample/AVCamBuildingACameraApp/AVCam/Views/CameraPreview.swift` lines 34-69

**Implementation approach:**
```swift
// New PreviewView class with backing layer
class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
```

The `makeUIView` method returns a `PreviewView` instead of a generic `UIView`. The `updateUIView` becomes a no-op (or near no-op) since the backing layer auto-sizes.

**Key difference from AVCam:** SwiftWing adds pinch and tap gestures, which AVCam doesn't have on the preview. These must be preserved.

---

### Task 1.1: Fix Rotation Coordinator
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraManager.swift`

**What to change:**
1. Change `setupRotationCoordinator` to accept an `AVCaptureVideoPreviewLayer` parameter instead of the session
2. Pass the preview layer to `AVCaptureDevice.RotationCoordinator(device:previewLayer:)`
3. Add KVO observers for `videoRotationAngleForHorizonLevelPreview` and `videoRotationAngleForHorizonLevelCapture`
4. Store rotation observers (retain KVO tokens to prevent deallocation)
5. Add `updatePreviewRotation(_:)` method that sets `previewLayer.connection?.videoRotationAngle`
6. Add `updateCaptureRotation(_:)` method that sets rotation on both `photoOutput` and `videoOutput` connections
7. Remove the manual orientation mapping in `capturePhoto()` (lines 170-196)
8. Add a public method or property to expose the current capture rotation angle for the photo settings (if needed for any remaining configuration)
9. Change the `setupRotationCoordinator` call site -- it must be called AFTER the preview layer is connected (deferred from `setupSession` to a new public method)

**Acceptance criteria:**
- Photos taken in portrait have correct EXIF orientation
- Photos taken in landscape left/right have correct EXIF orientation
- Photos taken upside-down have correct EXIF orientation
- Preview rotates smoothly when device orientation changes
- Vision frame processor receives correct orientation from `connection.videoRotationAngle`
- No manual `windowScene.effectiveGeometry` code remains in capture path

**AVCam reference:** `camSample/AVCamBuildingACameraApp/AVCam/CaptureService.swift` lines 363-406

**Implementation approach:**
```swift
private var rotationObservers = [AnyObject]()

func setupRotationCoordinator(for device: AVCaptureDevice, previewLayer: AVCaptureVideoPreviewLayer) {
    rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)

    // Set initial rotation
    updatePreviewRotation(rotationCoordinator.videoRotationAngleForHorizonLevelPreview, previewLayer: previewLayer)
    updateCaptureRotation(rotationCoordinator.videoRotationAngleForHorizonLevelCapture)

    // Cancel previous observations
    rotationObservers.removeAll()

    // Observe preview rotation changes
    rotationObservers.append(
        rotationCoordinator!.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { [weak self] _, change in
            guard let self, let angle = change.newValue else { return }
            Task { @MainActor in
                self.updatePreviewRotation(angle, previewLayer: previewLayer)
            }
        }
    )

    // Observe capture rotation changes
    rotationObservers.append(
        rotationCoordinator!.observe(\.videoRotationAngleForHorizonLevelCapture, options: .new) { [weak self] _, change in
            guard let self, let angle = change.newValue else { return }
            Task { @MainActor in
                self.updateCaptureRotation(angle)
            }
        }
    )
}
```

**Lifecycle change:** The rotation coordinator setup must be deferred from `setupSession()` to after the preview view is created and connected. This means:
- `CameraPreviewView.makeUIView` creates the preview view
- CameraViewModel calls a new `CameraManager.configureRotation(previewLayer:)` method after the preview is connected
- This is a departure from the current flow but is required because the preview layer must exist first

**Risk:** The preview layer is created on the UI side but the coordinator is created in CameraManager. Need to bridge this cleanly without breaking @MainActor isolation. Both are already @MainActor, so passing the layer reference is safe.

---

### Task 1.3: Add Interruption Handling
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraManager.swift`

**What to change:**
1. Add an `@Published var isInterrupted: Bool = false` property
2. Add a private `observeNotifications()` method called during `setupSession()`
3. Observe `AVCaptureSession.wasInterruptedNotification` -- extract reason and set `isInterrupted = true` when interrupted by another app/call
4. Observe `AVCaptureSession.interruptionEndedNotification` -- set `isInterrupted = false`
5. Observe `AVCaptureSession.runtimeErrorNotification` -- check for `.mediaServicesWereReset` and auto-restart session
6. Clean up notification observers in `stopSession()` (use Task cancellation)

**Acceptance criteria:**
- When a phone call interrupts the camera, `isInterrupted` becomes `true`
- When the phone call ends, `isInterrupted` becomes `false` and the session resumes
- If media services reset, the session automatically restarts
- No crashes or data races from notification handling
- Interruption state is observable by CameraViewModel

**AVCam reference:** `camSample/AVCamBuildingACameraApp/AVCam/CaptureService.swift` lines 543-571

**Implementation approach:**
```swift
@Published var isInterrupted = false

private var notificationTasks: [Task<Void, Never>] = []

private func observeNotifications() {
    // Interruption started
    let interruptTask = Task { @MainActor [weak self] in
        for await notification in NotificationCenter.default.notifications(
            named: AVCaptureSession.wasInterruptedNotification
        ) {
            guard let self else { return }
            if let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
               let reasonValue = AVCaptureSession.InterruptionReason(rawValue: reason.integerValue) {
                self.isInterrupted = [.audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient].contains(reasonValue)
            }
        }
    }
    notificationTasks.append(interruptTask)

    // Interruption ended
    let endTask = Task { @MainActor [weak self] in
        for await _ in NotificationCenter.default.notifications(
            named: AVCaptureSession.interruptionEndedNotification
        ) {
            self?.isInterrupted = false
        }
    }
    notificationTasks.append(endTask)

    // Runtime error (media services reset)
    let errorTask = Task { @MainActor [weak self] in
        for await notification in NotificationCenter.default.notifications(
            named: AVCaptureSession.runtimeErrorNotification
        ) {
            guard let self else { return }
            if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError,
               error.code == .mediaServicesWereReset {
                if let session = self.captureSession, !session.isRunning {
                    self.startSession()
                }
            }
        }
    }
    notificationTasks.append(errorTask)
}
```

**Concurrency note:** Using `Task { @MainActor ... }` because CameraManager is already `@MainActor`. The async `for await` on NotificationCenter is the modern Swift concurrency pattern matching AVCam's approach.

---

### Task 1.4: Enable iOS 26 Performance Features
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraManager.swift`

**What to change:**
1. After creating and adding `AVCapturePhotoOutput` in `setupSession()`, configure performance features:
   - `output.isResponsiveCaptureEnabled = output.isResponsiveCaptureSupported`
   - `output.isFastCapturePrioritizationEnabled = output.isFastCapturePrioritizationSupported`
   - `output.maxPhotoQualityPrioritization = .balanced` (balance speed and quality for book scanning)
2. In `capturePhoto()`, set `photoSettings.photoQualityPrioritization = .balanced`

**Acceptance criteria:**
- `isResponsiveCaptureEnabled` is `true` after session setup (reduces shutter lag)
- `isFastCapturePrioritizationEnabled` is `true` after session setup
- Shutter lag is noticeably reduced (subjective but measurable with timing logs)
- No build warnings from using these APIs

**AVCam reference:** `camSample/AVCamBuildingACameraApp/AVCam/Capture/PhotoCapture.swift` lines 119-127

**Implementation notes:**
- `isResponsiveCaptureEnabled` reduces shutter lag by pre-preparing the capture pipeline
- `isFastCapturePrioritizationEnabled` allows rapid sequential captures (important for scanning multiple books)
- For book scanning, `.balanced` quality prioritization is optimal -- `.quality` adds processing time, `.speed` reduces detail
- **NOTE:** `maxPhotoDimensions` is configured separately in Task 1.5 for Gemini Vision API optimization

---

### Task 1.5: Optimize Photo Resolution for Gemini Vision API
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraManager.swift`

**What to change:**
1. After creating and adding `AVCapturePhotoOutput` in `setupSession()` (after Task 1.4 performance config), set optimal resolution:
   ```swift
   // Configure optimal resolution for Gemini Vision API token efficiency
   // Target: 1024×768 provides sufficient detail for book spine OCR
   // while minimizing Gemini token usage (2 tiles = 516 tokens vs 3000-12000 at full res)
   if let device = videoDevice {
       let targetDimensions = CMVideoDimensions(width: 1024, height: 768)

       // Find closest supported dimension
       if let closestDimension = device.activeFormat.supportedMaxPhotoDimensions
           .min(by: { abs($0.width - targetDimensions.width) < abs($1.width - targetDimensions.width) }) {
           output.maxPhotoDimensions = closestDimension
           print("📐 Photo output configured: \(closestDimension.width)×\(closestDimension.height) (optimized for Gemini Vision API)")
       }
   }
   ```

2. In `capturePhoto()`, set `photoSettings.maxPhotoDimensions = photoOutput.maxPhotoDimensions` to use the configured resolution

**Acceptance criteria:**
- `photoOutput.maxPhotoDimensions` is set to closest match to 1024×768 after session setup
- Photo captures produce images at ~1024×768 resolution (verify with captured JPEG dimensions)
- Gemini Vision API token usage reduced from 3000-12000 tokens to ~516 tokens per image
- OCR quality for book spines remains excellent (12-24pt text readable)
- File size per image reduced from 2-8 MB to 200-500 KB

**Rationale (Gemini 2.0 Flash Token Costs):**

| Image Size | Tokens | Cost Impact |
|------------|--------|-------------|
| ≤ 384×384 px | 258 | Too low resolution for spines |
| 768×768 px (1 tile) | 258 | Marginal for small text |
| **1024×768 px (2 tiles)** | **516** | **Optimal: 6-12x cost reduction** |
| 2048×1536 px (6 tiles) | 1,548 | Wasteful |
| 4000×3000 px (full res, 12+ tiles) | 3,096-12,000 | Very wasteful |

**Technical justification:**
- Typical book spine: 1.5" wide × 9" tall
- At 1024×768: ~68 DPI horizontal, ~85 DPI vertical
- Gemini can read text down to 8pt at this resolution
- Most book spine text: 12-24pt → **3x headroom for OCR reliability**
- Current `.high` preset captures at 12-48 MP (4000×3000 to 8000×6000 pixels) → massive overkill

**Cost savings example (1000 scans/day):**
- Full resolution: 1000 scans × 6000 tokens avg = 6M tokens/day
- Optimized: 1000 scans × 516 tokens = 516K tokens/day
- **Savings: ~92% token reduction**

**References:**
- Gemini 2.0 Flash tiling: Images are split into 768×768 tiles, each consuming 258 tokens
- [Gemini Image Understanding Docs](https://ai.google.dev/gemini-api/docs/image-understanding)
- [Gemini 2.5 Flash Image API Guide](https://blog.laozhang.ai/api-guides/gemini-2-5-flash-image-api-guide/)

---

### Task 2.1: Remove Dead Manual Orientation Code
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraManager.swift`

**What to change:**
1. Remove the entire manual orientation block from `capturePhoto()` (lines 169-196): the `windowScene.effectiveGeometry.interfaceOrientation` lookup, the switch statement mapping orientations to rotation angles, and the manual connection configuration
2. If the rotation coordinator's `updateCaptureRotation` correctly sets rotation on the photo connection, no per-capture rotation setting is needed

**Acceptance criteria:**
- `capturePhoto()` is simplified: creates settings, captures, returns data
- No reference to `UIApplication.shared.connectedScenes` or `effectiveGeometry` in capture path
- Photo orientation is still correct (verified by Task 1.1's rotation coordinator)

**Depends on:** Task 1.1 (rotation coordinator must be working first)

---

### Task 2.2: Surface Interruption State to UI
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`

**What to change:**
1. Add an `isInterrupted` computed property or observation that reads from `cameraManager.isInterrupted`
2. In `CameraView` (or wherever the camera UI lives), show an overlay or message when `isInterrupted` is true (e.g., "Camera interrupted by phone call")
3. Disable the capture button when `isInterrupted` is true

**Acceptance criteria:**
- User sees visual feedback when camera is interrupted
- Capture button is disabled during interruption
- When interruption ends, UI returns to normal state
- No hardcoded strings (use localizable pattern if project uses one, otherwise simple strings are fine for now)

**Note:** This is a lightweight UI addition. The heavy lifting is in Task 1.3 (the notification observers). This task just wires the state to the view layer.

---

### Task 2.3: Build Verification and Testing
**Commands:**
```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift
```

**Acceptance criteria:**
- 0 errors
- 0 warnings
- All existing features preserved (manual verification checklist below)

**Manual Verification Checklist (on device):**
- [ ] Camera preview appears edge-to-edge
- [ ] Pinch-to-zoom works (1x to 4x)
- [ ] Tap-to-focus works (yellow indicator appears)
- [ ] Photo capture works (flash animation, image in processing queue)
- [ ] **Photo dimensions are ~1024×768** (check captured image metadata or Talaria upload logs)
- [ ] SSE streaming works (progress updates appear)
- [ ] **Gemini token usage is ~516 tokens per image** (check Talaria API logs or Gemini usage dashboard)
- [ ] Rotate device to landscape -- preview and captured photo orient correctly
- [ ] Rotate to portrait upside down -- preview and captured photo orient correctly
- [ ] Receive phone call during scanning -- camera pauses gracefully, resumes after
- [ ] Vision text detection overlay appears when pointing at book spine
- [ ] **Book spine OCR quality is excellent** (test with 12-24pt spines, verify accuracy)
- [ ] Offline mode works (disable WiFi, capture, queue appears)
- [ ] Rate limit handling works (rapid captures trigger countdown)

---

## Risk Identification

### Risk 1: Preview Layer Reference Timing
**Risk:** The rotation coordinator needs the preview layer, but the layer is created in SwiftUI's `makeUIView`. There's a timing gap between session setup and preview view creation.

**Mitigation:** Split rotation coordinator setup into a separate method (`configureRotation(previewLayer:)`) called by CameraViewModel after the preview view appears. Use `onAppear` or a callback pattern to bridge the gap. The session can start before the coordinator is configured -- frames will use default rotation until the coordinator initializes.

**Severity:** Medium. Worst case: first few frames before coordinator setup show default rotation.

### Risk 2: KVO Observer Memory Management
**Risk:** KVO observers for rotation coordinator must be retained. If stored as `[AnyObject]` like AVCam, they need to be cleaned up when the session stops or the coordinator is replaced.

**Mitigation:** Store observers in `rotationObservers: [AnyObject]` array. Clear the array in `stopSession()` and before creating a new coordinator. The `AnyObject` tokens are automatically invalidated when removed from the array (NSKeyValueObservation pattern).

**Severity:** Low. Standard pattern, well-documented in Apple's code.

### Risk 3: Notification Observer Lifecycle
**Risk:** Async notification observers (`for await ... in NotificationCenter.default.notifications`) create long-running tasks. If not cancelled, they leak.

**Mitigation:** Store tasks in `notificationTasks: [Task<Void, Never>]`. Cancel all tasks in `stopSession()`. Use `[weak self]` in closures to prevent retain cycles.

**Severity:** Low. Standard async/await lifecycle management.

### Risk 4: Breaking Vision Frame Processing
**Risk:** The rotation coordinator's `updateCaptureRotation` sets `videoRotationAngle` on output connections. The `FrameProcessor` reads `connection.videoRotationAngle` to determine `CGImagePropertyOrientation`. If the coordinator changes the angle on the video data output connection, Vision processing should automatically get the correct orientation -- but this needs verification.

**Mitigation:** After implementation, verify that `FrameProcessor.captureOutput` still receives correct `connection.videoRotationAngle` values. The existing `CGImagePropertyOrientation(from:)` extension should continue to work since it maps angle values, not UIInterfaceOrientation values.

**Severity:** Medium. Vision text detection accuracy depends on correct orientation.

### Risk 5: @MainActor Isolation with KVO Callbacks
**Risk:** KVO callbacks fire on arbitrary threads. CameraManager is `@MainActor`. Need to dispatch KVO callbacks to MainActor.

**Mitigation:** Wrap KVO callback bodies in `Task { @MainActor in ... }` (matching AVCam's pattern at line 382-383 and 397-398). This is safe because preview layer and output connections are only modified on MainActor.

**Severity:** Low. Direct pattern from AVCam reference code.

### Risk 6: Backwards Compatibility of iOS 26 APIs
**Risk:** `isResponsiveCaptureEnabled`, `isFastCapturePrioritizationEnabled` -- need to verify these exist in iOS 26 SDK. They were introduced in iOS 17.

**Mitigation:** These APIs have been available since iOS 17. SwiftWing targets iOS 26 minimum, so no compatibility checks needed. The `isSupported` properties guard against device-specific limitations.

**Severity:** Very Low. APIs are well-established.

### Risk 7: Resolution Optimization May Degrade OCR Quality
**Risk:** Reducing photo resolution from 12-48 MP to ~1 MP (1024×768) could reduce OCR accuracy for small or degraded book spine text.

**Mitigation:**
- 1024×768 provides ~68-85 DPI, which is 3x above Gemini's 8pt text readability threshold
- Most book spines use 12-24pt text, giving significant headroom
- Test with challenging cases: old books with faded text, thin spines (< 1"), embossed titles
- If OCR accuracy drops below 95% on test set, increase to 1536×1152 (4 tiles = 1,032 tokens, still 70% cost reduction)
- Monitor production OCR accuracy metrics and adjust resolution if needed

**Severity:** Low. Resolution chosen with 3x safety margin based on Gemini documentation.

### Risk 8: Device-Specific Resolution Support
**Risk:** Not all devices support exactly 1024×768. The code finds "closest match" which might be significantly different (e.g., 1280×720 or 1920×1080).

**Mitigation:**
- Algorithm uses `min(by:)` with width difference to find closest match
- On modern iPhones, typical supported dimensions include: 1024×768, 1280×720, 1920×1080, 2048×1536
- 1024×768 is a standard 4:3 aspect ratio supported on most devices
- Log the actual selected dimensions at startup for monitoring
- If closest match is significantly different (e.g., 1920×1080), it's still vastly better than full 12MP resolution

**Severity:** Very Low. Standard resolution with wide device support.

---

## Commit Strategy

### Commit 1: Adopt backing layer preview pattern
**Files:** `CameraPreviewView.swift`
**Message:** `refactor: Adopt backing layer pattern for camera preview`

### Commit 2: Fix rotation coordinator with KVO observers
**Files:** `CameraManager.swift`, `CameraPreviewView.swift` (callback), `CameraViewModel.swift` (call site)
**Message:** `fix: Wire rotation coordinator with preview layer and KVO observers`

### Commit 3: Add interruption handling
**Files:** `CameraManager.swift`
**Message:** `feat: Add session interruption handling and media services recovery`

### Commit 4: Enable iOS 26 performance features
**Files:** `CameraManager.swift`
**Message:** `feat: Enable responsive capture and fast prioritization for iOS 26`

### Commit 5: Optimize photo resolution for Gemini Vision API
**Files:** `CameraManager.swift`
**Message:** `perf: Optimize photo resolution to 1024×768 for Gemini token efficiency (92% reduction)`

### Commit 6: Clean up dead code and wire interruption UI
**Files:** `CameraManager.swift`, `CameraViewModel.swift`
**Message:** `refactor: Remove manual orientation code and surface interruption state`

---

## Success Criteria

| Criterion | Measurement | Target |
|-----------|-------------|--------|
| Rotation coordinator functional | Preview layer passed to constructor, KVO observers active | Not nil, observers count >= 2 |
| Automatic rotation | No manual orientation mapping in capturePhoto() | Zero lines of effectiveGeometry code |
| Photo EXIF orientation | Capture in all 4 orientations, verify EXIF | Correct in all orientations |
| Interruption handling | Simulate interruption (phone call on device) | isInterrupted toggles correctly |
| Media services recovery | Kill mediaserverd in debug | Session auto-restarts |
| Responsive capture | Check `photoOutput.isResponsiveCaptureEnabled` | true |
| Fast prioritization | Check `photoOutput.isFastCapturePrioritizationEnabled` | true |
| **Photo resolution optimized** | Check `photoOutput.maxPhotoDimensions` | **~1024×768 (closest device match)** |
| **Gemini token usage** | Upload test image, check Talaria/Gemini logs | **~516 tokens (vs 3000-12000 before)** |
| **Image file size** | Check captured JPEG size | **200-500 KB (vs 2-8 MB before)** |
| **OCR quality maintained** | Scan 10 book spines with 12-24pt text | **100% accurate title/author extraction** |
| Backing layer preview | PreviewView.layerClass == AVCaptureVideoPreviewLayer | true |
| No manual frame updates | updateUIView is no-op or minimal | No frame assignment code |
| Build clean | xcodebuild ... \| xcsift | 0 errors, 0 warnings |
| Vision processing | Text detection on book spines | Still functional, correct orientation |
| Existing features | Processing queue, SSE, offline, rate limit | All preserved |

---

## Estimated Complexity
**Overall: MEDIUM**

- Phase 1 tasks are well-scoped with clear AVCam reference implementations
- No architectural migration (keeping @MainActor class, not moving to actor)
- No CameraViewModel split (separate future task)
- Biggest risk is the preview layer reference timing, which has a clear mitigation

**Estimated effort:** 4-6 focused coding hours across 6 commits.

**Cost impact:** Task 1.5 (resolution optimization) alone delivers **92% token cost reduction** on Gemini Vision API usage. For a production app scanning 1000 books/day, this saves ~$150-300/month in API costs (assuming Gemini 2.0 Flash pricing ~$0.075/1M input tokens).
