# Vision Framework Integration Plan

## Context

### Original Request
Integrate iOS 26 Vision framework capabilities into SwiftWing's existing camera system to enable real-time on-device text recognition and barcode detection during live camera preview, augmenting (not replacing) the existing Talaria backend AI pipeline.

### Interview Summary
- **Epic Phase:** Epic 5 (Refactoring/Polish) - this is an enhancement to the existing camera system
- **Current Architecture:** CameraView -> CameraViewModel (734 lines, @MainActor @Observable) -> CameraManager (@MainActor class, ObservableObject) -> AVCaptureSession with AVCapturePhotoOutput only
- **Key Constraint:** CameraManager is currently @MainActor (not an actor), uses AVCapturePhotoOutput but has NO AVCaptureVideoDataOutput (required for Vision frame processing)
- **Existing Pipeline:** Capture photo -> compress JPEG -> upload to Talaria -> SSE stream results -> save to SwiftData
- **Design System:** Swiss Glass theme (black base, .ultraThinMaterial, 12px corners, spring animations)

### Research Findings

**Architecture Discovery (Critical):**
1. `CameraManager` is a `@MainActor class` (NOT an actor despite CLAUDE.md describing "CameraActor"). This is significant because adding AVCaptureVideoDataOutput delegate callbacks requires careful threading.
2. `CameraPreviewView` is a `UIViewRepresentable` with a `Coordinator` class that handles pinch-to-zoom and tap-to-focus. The Coordinator already uses `@MainActor`.
3. `CameraViewModel` at 734 lines is the brain - it manages the full capture-upload-stream-save pipeline. Vision results need to integrate here without bloating it further.
   - **IMPORTANT FILE PATH:** `CameraViewModel.swift` lives at the PROJECT ROOT (`/Users/juju/dev_repos/swiftwing/CameraViewModel.swift`), NOT inside `swiftwing/`. This is a result of the Epic 5 Phase 2A MVVM refactoring that extracted the ViewModel from the view directory. All TODO references to `CameraViewModel.swift` mean the root-level file.
4. The session currently uses `.high` preset with AVCapturePhotoOutput only. Adding AVCaptureVideoDataOutput requires session reconfiguration.

**Vision Framework Technical Constraints:**
- `VNRecognizeTextRequest` and `VNDetectBarcodesRequest` can run on the same `VNImageRequestHandler`
- Frame processing must happen OFF the main thread (use a dedicated serial DispatchQueue for the sample buffer delegate)
- Each frame at 30fps gives ~33ms budget; Vision requests typically complete in 15-30ms on A17+/M-series Neural Engine
- Must throttle processing to avoid battery drain (process every 5th-10th frame, not every frame)

**Metis Gap Detection:**
1. **Thread Safety:** AVCaptureVideoDataOutputSampleBufferDelegate callbacks arrive on a custom dispatch queue, but CameraManager is @MainActor. The delegate must be a separate non-isolated class.
2. **Memory Pressure:** Retaining CVPixelBuffer references from sample buffers can cause memory spikes. Must process and release within the delegate callback.
3. **Battery Impact:** Continuous Vision processing at 30fps will drain battery. Need adaptive throttling (process during active scanning, pause when idle).
4. **ISBN Validation:** VNDetectBarcodesRequest will detect many barcode types. Need ISBN-13/EAN-13 filtering and checksum validation before triggering auto-lookup.
5. **UI Thread Safety:** Vision results arrive on the processing queue. Must dispatch to @MainActor for UI overlay updates. Use AsyncStream to bridge the gap cleanly.
6. **Existing Flow Preservation:** The shutter button capture flow (captureImage -> processCapture -> upload) must continue working unchanged. Vision provides pre-scan intelligence, not a replacement.
7. **CameraPreviewView Overlay:** Current UIViewRepresentable returns a plain UIView. Vision text overlays need either (a) a SwiftUI overlay in CameraView, or (b) a CALayer overlay on the UIView. SwiftUI overlay is cleaner and follows existing patterns.

---

## Work Objectives

### Core Objective
Add real-time on-device Vision framework processing to the camera preview, providing instant text recognition and barcode/ISBN detection as a pre-scan intelligence layer that augments the existing Talaria upload pipeline.

### Deliverables
1. **VisionService class** - New queue-agnostic class encapsulating all Vision framework requests with frame throttling
2. **AVCaptureVideoDataOutput integration** - Sample buffer pipeline in CameraManager for frame access
3. **Real-time text overlay** - SwiftUI overlay showing detected text regions on camera preview
4. **ISBN barcode detection** - Automatic ISBN-13/EAN-13 detection with validation
5. **Smart capture guidance** - Visual feedback: "Spine detected", "Move closer", "Hold steady"
6. **Performance guardrails** - Adaptive frame throttling, memory management, battery optimization

### Definition of Done
- [ ] Vision text recognition runs during live preview with < 100ms latency to overlay update
- [ ] ISBN barcodes auto-detected and displayed before user taps shutter
- [ ] Camera cold start still < 0.5s (no regression)
- [ ] UI maintains > 55 FPS during Vision processing
- [ ] Battery impact < 8% per minute during active scanning (vs current < 5% baseline)
- [ ] Memory stays < 200MB peak during Vision processing
- [ ] All existing camera features work unchanged (zoom, focus, flash, processing queue, offline, rate limit)
- [ ] Build: 0 errors, 0 warnings
- [ ] Swift 6.2 strict concurrency: no data race warnings

---

## Guardrails

### MUST Have
- Vision processing runs on dedicated background queue (never main thread)
- Adaptive frame throttling (not every frame processed)
- ISBN validation with checksum before display
- Graceful degradation if Vision requests fail (camera continues working)
- All existing Talaria upload flow preserved unchanged
- Swift 6.2 strict concurrency compliance (no @unchecked Sendable, with ONE documented exception: `FrameProcessor` requires `@unchecked Sendable` because `AVCaptureVideoDataOutputSampleBufferDelegate` is an Obj-C protocol that cannot express Sendable in Swift. This is safe because FrameProcessor holds no mutable shared state — its only mutation is calling a synchronous VisionService method on the delegate queue it was assigned to. See TODO 2.1 for details.)
- Swiss Glass design language for all new UI elements

### MUST NOT Have
- No replacement of Talaria backend (Vision augments, doesn't replace)
- No new third-party dependencies (Vision is a system framework)
- No DispatchSemaphore or DispatchGroup with async/await (deadlock risk)
- No Task.detached (breaks actor isolation)
- No blocking the main thread for Vision processing
- No storing CVPixelBuffer references beyond the delegate callback
- No continuous full-speed processing when camera is idle/backgrounded

---

## Architecture Decision

### Where Vision Processing Lives

**Decision: New `VisionService` as a standalone class (NOT actor, NOT @MainActor)**

**Rationale:**
- Vision's `VNImageRequestHandler.perform()` is a synchronous blocking call that must run on a background queue
- An actor would serialize all requests unnecessarily (we want concurrent text + barcode detection)
- @MainActor would block the UI thread
- A plain queue-agnostic class called from AVFoundation's delegate queue matches the callback pattern exactly
- Results are published via an `AsyncStream` that the ViewModel consumes on @MainActor

**Architecture:**
```
CameraPreviewView (SwiftUI)
    |
CameraView (SwiftUI) --- VisionOverlayView (NEW - SwiftUI overlay)
    |
CameraViewModel (@MainActor @Observable)
    |                        |
CameraManager              VisionService (NEW)
(@MainActor class)         (plain class, queue-agnostic)
    |                        |
AVCaptureSession           VNImageRequestHandler
    |--- AVCapturePhotoOutput (existing)
    |--- AVCaptureVideoDataOutput (NEW) --> FrameProcessor delegate --> VisionService
```

**Data Flow:**
1. AVCaptureVideoDataOutput delivers CMSampleBuffer to FrameProcessor (on processingQueue)
2. FrameProcessor extracts CVPixelBuffer, passes to VisionService
3. VisionService runs VNRecognizeTextRequest + VNDetectBarcodesRequest
4. Results emitted via AsyncStream<VisionResult>
5. CameraViewModel consumes stream on @MainActor, updates overlay state
6. CameraView renders VisionOverlayView with detected regions

---

## Task Flow and Dependencies

```
Phase 1: Foundation (VisionService + Frame Pipeline)
    |
    v
Phase 2: CameraManager Integration (VideoDataOutput)
    |
    v
Phase 3: ViewModel Bridge (AsyncStream consumption)
    |
    v
Phase 4: UI Overlay (Text + barcode display)
    |
    v
Phase 5: Smart Capture Guidance
    |
    v
Phase 6: Performance Tuning + Battery Optimization
    |
    v
Phase 7: Xcode Project Integration + Build Verification + Integration Testing
```

---

## Detailed TODOs

### Phase 1: VisionService Foundation
**Goal:** Create the Vision processing engine as an isolated, testable unit

#### TODO 1.1: Create VisionResult types
- **File:** `swiftwing/Services/VisionTypes.swift` (NEW)
- **Action:** Define result types for Vision processing output
- **Details:**
  - **Imports required:** `import Foundation`, `import CoreGraphics` (for CGRect), `import AVFoundation` (for CGImagePropertyOrientation used in VisionService's processFrame signature)
  - `VisionResult` enum with cases: `.textRegions([TextRegion])`, `.barcode(BarcodeResult)`, `.noContent`
  - `TextRegion` struct: `boundingBox: CGRect` (normalized 0-1), `text: String`, `confidence: Float`
  - `BarcodeResult` struct: `isbn: String`, `boundingBox: CGRect`, `isValidISBN: Bool`
  - `CaptureGuidance` enum: `.spineDetected`, `.moveCloser`, `.holdSteady`, `.noBookDetected`
  - All types must be `Sendable` (required for crossing isolation boundaries)
- **Acceptance Criteria:** Types compile with strict concurrency, are Sendable, and have clear documentation

#### TODO 1.2: Create VisionService class
- **File:** `swiftwing/Services/VisionService.swift` (NEW)
- **Action:** Implement Vision framework processing engine
- **Details:**
  - **Imports required:** `import Vision`, `import CoreVideo` (for CVPixelBuffer), `import ImageIO` (for CGImagePropertyOrientation)
  - Plain class (not actor, not @MainActor), queue-agnostic design — VisionService does NOT own a DispatchQueue. Its `processFrame()` method is synchronous and runs on whatever queue the caller dispatches from (in practice, `CameraManager`'s `videoProcessingQueue`). This avoids unnecessary queue hops and keeps the threading model simple: AVFoundation delegate queue -> VisionService.processFrame() -> result callback.
  - Property: `private let textRequest = VNRecognizeTextRequest()` configured for `.fast` recognition level (real-time), English language
  - Property: `private let barcodeRequest = VNDetectBarcodesRequest()` configured for `.ean13` and `.isbn13` symbologies
  - Method: `func processFrame(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> VisionResult`
    - Creates `VNImageRequestHandler(cvPixelBuffer:orientation:options:)`
    - Performs both requests in single `handler.perform([textRequest, barcodeRequest])`
    - Extracts text observations with confidence > 0.5
    - Extracts barcode observations, validates ISBN checksum
    - Returns aggregated `VisionResult`
  - Method: `func generateGuidance(from result: VisionResult) -> CaptureGuidance`
    - If text regions detected with high confidence -> `.spineDetected`
    - If text detected but low confidence -> `.moveCloser`
    - If barcode detected -> `.spineDetected` (ISBN found)
    - If nothing detected -> `.noBookDetected`
  - Frame throttling: `private var lastProcessedTime: CFAbsoluteTime = 0` with configurable interval (default: 150ms = ~6.7 fps effective)
  - Method: `func shouldProcessFrame() -> Bool` (returns true if enough time elapsed)
- **Acceptance Criteria:** VisionService processes a sample CVPixelBuffer and returns valid VisionResult; throttling limits effective processing rate

#### TODO 1.3: ISBN validation utility
- **File:** `swiftwing/Services/VisionService.swift` (same file, private extension)
- **Action:** Implement ISBN-13 checksum validation
- **Details:**
  - Private method: `func validateISBN13(_ code: String) -> Bool`
  - Strip non-numeric characters
  - Verify exactly 13 digits
  - Verify starts with "978" or "979" (book ISBN prefix)
  - Calculate checksum: alternating weights of 1 and 3, sum mod 10 == 0
  - Return true only if all checks pass
- **Acceptance Criteria:** Correctly validates known valid/invalid ISBN-13 codes

### Phase 2: CameraManager Integration
**Goal:** Add AVCaptureVideoDataOutput to existing session without disrupting photo capture

#### TODO 2.1: Add FrameProcessor delegate class
- **File:** `swiftwing/CameraManager.swift` (MODIFY - add at bottom)
- **Action:** Create sample buffer delegate that bridges to VisionService
- **Details:**
  - New class: `FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate`
  - NOT @MainActor (delegate callbacks arrive on custom queue)
  - Property: `var onFrameProcessed: ((VisionResult) -> Void)?` callback
  - Property: `private let visionService = VisionService()`
  - Implement `captureOutput(_:didOutput:from:)`:
    - Check `visionService.shouldProcessFrame()` (throttle)
    - Extract CVPixelBuffer from CMSampleBuffer
    - Determine orientation from connection's videoRotationAngle
    - Call `visionService.processFrame(pixelBuffer, orientation:)`
    - Invoke `onFrameProcessed` callback with result
  - Implement `captureOutput(_:didDrop:from:)` for dropped frame logging
  - **@unchecked Sendable Justification (Guardrail Exception):** `FrameProcessor` must be marked `@unchecked Sendable` because `AVCaptureVideoDataOutputSampleBufferDelegate` is an Objective-C protocol that cannot be annotated `@Sendable` by Swift. This is safe because: (a) FrameProcessor holds no mutable shared state — `visionService` is a let constant and `onFrameProcessed` is set once before the session starts; (b) all delegate callbacks are dispatched to a single serial `DispatchQueue` owned by `CameraManager`, so concurrent access is impossible; (c) this is the standard pattern endorsed by Apple for AVFoundation delegate bridging in Swift 6.2.
- **Acceptance Criteria:** FrameProcessor compiles, conforms to delegate protocol, calls VisionService with throttling

#### TODO 2.2: Add AVCaptureVideoDataOutput to CameraManager
- **File:** `swiftwing/CameraManager.swift` (MODIFY)
- **Action:** Add video data output alongside existing photo output
- **Details:**
  - New properties:
    - `private var videoOutput: AVCaptureVideoDataOutput?`
    - `private let frameProcessor = FrameProcessor()`
    - `private let videoProcessingQueue = DispatchQueue(label: "com.swiftwing.videoprocessing", qos: .userInitiated)`
    - `var onVisionResult: ((VisionResult) -> Void)?` (public callback for ViewModel)
  - **Why DispatchQueue Is Not a Deadlock Risk Here:**
    The project rules (`.claude/rules/swift-conventions.md` lines 28-30) ban mixing `DispatchQueue` with `async/await`. That rule targets the pattern of calling `DispatchQueue.main.async { await someAsyncFunction() }`, which causes deadlocks. Here, `videoProcessingQueue` is used EXCLUSIVELY as AVFoundation's delegate callback queue — a mandatory AVFoundation API requirement (`setSampleBufferDelegate(_:queue:)` requires a `DispatchQueue`). No async/await code runs ON this queue. The queue receives synchronous delegate callbacks from AVFoundation, processes the frame synchronously via `VisionService.processFrame()`, then dispatches results to `@MainActor` via `Task { @MainActor in ... }`. This is a one-way bridge FROM DispatchQueue TO async/await, not mixing them bidirectionally.
  - In `setupSession()`, AFTER photo output configuration:
    - Create `AVCaptureVideoDataOutput()`
    - Set `videoSettings` to `[kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]`
    - Set `alwaysDiscardsLateVideoFrames = true` (critical for performance)
    - Set delegate to `frameProcessor` on `videoProcessingQueue`
    - Add output to session if possible (gracefully skip if not)
    - Wire `frameProcessor.onFrameProcessed` to `self.onVisionResult` (dispatch to MainActor)
  - New method: `func setVisionEnabled(_ enabled: Bool)`:
    - When false, set `videoOutput?.connection(with: .video)?.isEnabled = false`
    - When true, re-enable connection
    - Allows toggling Vision without session reconfiguration
- **Acceptance Criteria:** Session starts with both photo and video outputs; frame delegate fires; Vision can be toggled on/off; no regression in photo capture; cold start still < 0.5s

#### TODO 2.3: Update CameraError enum
- **File:** `swiftwing/CameraManager.swift` (MODIFY)
- **Action:** Add Vision-related error case
- **Details:**
  - Add case: `case cannotAddVideoOutput` with description "Cannot add video output to session"
  - This is used if `session.canAddOutput(videoOutput)` returns false (some devices may not support dual outputs)
- **Acceptance Criteria:** Error case compiles and has localized description

### Phase 3: ViewModel Bridge
**Goal:** Connect VisionService results to CameraViewModel state for UI consumption

#### TODO 3.1: Add Vision state properties to CameraViewModel
- **File:** `CameraViewModel.swift` (MODIFY - add new MARK section) — **PROJECT ROOT** (`/Users/juju/dev_repos/swiftwing/CameraViewModel.swift`)
- **Action:** Add observable state for Vision results
- **Details:**
  - New MARK section: `// MARK: - Vision Framework State`
  - Properties:
    - `var detectedTextRegions: [TextRegion] = []` (for overlay rendering)
    - `var detectedBarcode: BarcodeResult?` (for ISBN pre-scan display)
    - `var captureGuidance: CaptureGuidance = .noBookDetected` (for guidance overlay)
    - `var isVisionEnabled: Bool = true` (user toggle)
    - `private var visionUpdateTask: Task<Void, Never>?`
- **Acceptance Criteria:** Properties compile, are @Observable-compatible, initialized with safe defaults

#### TODO 3.2: Wire Vision callback in setupCamera
- **File:** `CameraViewModel.swift` (MODIFY - in setupCamera method) — **PROJECT ROOT**
- **Action:** Connect CameraManager's Vision callback to ViewModel state
- **Details:**
  - After `cameraManager.setupSession()`, add:
    ```
    cameraManager.onVisionResult = { [weak self] result in
        Task { @MainActor in
            self?.handleVisionResult(result)
        }
    }
    ```
  - New method: `private func handleVisionResult(_ result: VisionResult)`
    - Switch on result cases
    - Update `detectedTextRegions` with animation (.swissSpring, debounced)
    - Update `detectedBarcode` (with ISBN validation)
    - Update `captureGuidance` via VisionService.generateGuidance
    - If barcode detected with valid ISBN, show subtle notification
  - Debouncing: Only update UI if result differs from current state (avoid flicker)
- **Acceptance Criteria:** Vision results flow from CameraManager through callback to ViewModel state; UI updates are debounced and animated

#### TODO 3.3: Add Vision toggle method
- **File:** `CameraViewModel.swift` (MODIFY) — **PROJECT ROOT**
- **Action:** Allow enabling/disabling Vision processing
- **Details:**
  - Method: `func toggleVision()`
    - Flip `isVisionEnabled`
    - Call `cameraManager.setVisionEnabled(isVisionEnabled)`
    - If disabling, clear all Vision state (textRegions, barcode, guidance)
  - Purpose: User preference + battery saving during non-scanning activities
- **Acceptance Criteria:** Toggle works, clears state when disabled, re-enables processing when enabled

### Phase 4: UI Overlay
**Goal:** Display Vision results as a real-time overlay on the camera preview

#### TODO 4.1: Create VisionOverlayView
- **File:** `swiftwing/VisionOverlayView.swift` (NEW)
- **Action:** SwiftUI view for rendering detected text regions and barcodes
- **Details:**
  - `struct VisionOverlayView: View`
  - Properties: `let textRegions: [TextRegion]`, `let barcode: BarcodeResult?`, `let guidance: CaptureGuidance`, `let previewSize: CGSize`
  - Text region rendering:
    - For each TextRegion, draw a semi-transparent rounded rectangle at the bounding box position
    - Bounding box is normalized (0-1), convert to screen coordinates using `previewSize`
    - Note: Vision coordinates have origin at bottom-left; must flip Y axis
    - Color: `.internationalOrange.opacity(0.3)` fill, `.internationalOrange` border
    - Show recognized text as small label below the rectangle (JetBrains Mono font)
  - Barcode rendering:
    - Green highlight rectangle around detected barcode region
    - ISBN label displayed below: "ISBN: 978-..." in `.swissDone` color
    - Subtle pulse animation to draw attention
  - Use `.allowsHitTesting(false)` so overlay doesn't block camera gestures
  - Apply `.ignoresSafeArea()` to match camera preview
- **Acceptance Criteria:** Overlay renders at correct positions over camera preview; does not interfere with touch gestures; follows Swiss Glass design

#### TODO 4.2: Create CaptureGuidanceView
- **File:** `swiftwing/CaptureGuidanceView.swift` (NEW)
- **Action:** Guidance overlay showing scanning hints
- **Details:**
  - `struct CaptureGuidanceView: View`
  - Property: `let guidance: CaptureGuidance`
  - Renders at top-center of screen, below the status bar area
  - Swiss Glass overlay styling (`.swissGlassOverlay()`)
  - Content per guidance state:
    - `.spineDetected`: Green checkmark icon + "Spine detected" (fade in, stay)
    - `.moveCloser`: Yellow arrow icon + "Move closer to book" (pulse animation)
    - `.holdSteady`: Blue hand icon + "Hold steady..." (steady glow)
    - `.noBookDetected`: No overlay shown (hidden)
  - Transition: `.opacity.combined(with: .scale(scale: 0.95))` (matches existing error overlay pattern)
  - Auto-hide after 3 seconds of same state to avoid visual clutter
- **Acceptance Criteria:** Guidance appears/disappears smoothly; correct icons and text per state; non-intrusive positioning

#### TODO 4.3: Integrate overlays into CameraView
- **File:** `swiftwing/CameraView.swift` (MODIFY)
- **Action:** Add Vision overlay and guidance to the camera ZStack
- **Details:**
  - In the main ZStack, after the camera preview and before the loading spinner:
    - Add `VisionOverlayView` with text regions, barcode, guidance from viewModel
    - Need to pass `previewSize` - use GeometryReader around CameraPreviewView or a `@State` variable updated via `.onGeometryChange`
    - Add `CaptureGuidanceView` with guidance from viewModel
  - In the top-right HStack (where zoom display is), add Vision toggle button:
    - SF Symbol: `eye.slash` when disabled, `eye` when enabled
    - `.swissGlassOverlay()` styling
    - Tap action: `viewModel.toggleVision()`
  - Ensure overlay is below the shutter button / processing queue in Z order
- **Acceptance Criteria:** Overlays appear during live preview; toggle button works; no interference with existing UI elements (zoom, focus, shutter, processing queue, rate limit, offline indicator)

#### TODO 4.4: Pass detected ISBN to capture pipeline
- **File:** `CameraViewModel.swift` (MODIFY) — **PROJECT ROOT**
- **Action:** Pre-populate ISBN when barcode was detected before shutter press
- **Details:**
  - In `captureImage()`, capture the current `detectedBarcode` value
  - Pass it through the processing pipeline as optional pre-scan data
  - In `handleBookResult()`, if Talaria returns no ISBN but we have a pre-scanned one, use it
  - This provides a fallback ISBN source when the AI backend doesn't detect the barcode
  - Store in ProcessingItem as optional `preScannedISBN: String?`
  - **Equatable conformance note:** `ProcessingItem` (`swiftwing/ProcessingItem.swift`) uses Swift's synthesized `Equatable` conformance (no manual `==` implementation). Adding `preScannedISBN: String?` will be automatically included in the synthesized `==` since `String?` conforms to `Equatable`. No manual update needed.
- **Acceptance Criteria:** Pre-scanned ISBN survives through capture pipeline; used as fallback when Talaria doesn't return ISBN; doesn't override Talaria's ISBN when present

### Phase 5: Smart Capture Guidance
**Goal:** Provide intelligent scanning assistance based on Vision analysis

#### TODO 5.1: Implement guidance logic in VisionService
- **File:** `swiftwing/Services/VisionService.swift` (MODIFY)
- **Action:** Enhance `generateGuidance` with heuristics
- **Details:**
  - Analyze text region coverage: if total bounding box area < 5% of frame -> `.moveCloser`
  - Analyze text stability: track last 5 results, if bounding boxes are shifting > 10% -> `.holdSteady`
  - Analyze text content: if recognized text contains typical book spine patterns (title + author on vertical line) -> `.spineDetected`
  - Analyze barcode presence: any valid ISBN -> `.spineDetected` (highest confidence)
  - Default: `.noBookDetected`
  - Store rolling buffer of last 5 VisionResults for stability analysis
- **Acceptance Criteria:** Guidance transitions smoothly between states; stability detection prevents flickering; responds within 150ms of state change

#### TODO 5.2: Add haptic feedback for spine detection
- **File:** `CameraViewModel.swift` (MODIFY) — **PROJECT ROOT**
- **Action:** Trigger subtle haptic when spine first detected
- **Details:**
  - In `handleVisionResult`, when guidance transitions TO `.spineDetected` from any other state:
    - Trigger `UIImpactFeedbackGenerator(style: .light).impactOccurred()`
    - Only once per detection session (reset when guidance goes back to `.noBookDetected`)
  - When ISBN barcode first detected:
    - Trigger `UINotificationFeedbackGenerator().notificationOccurred(.success)`
  - Prevent haptic spam: minimum 2-second gap between haptic triggers
- **Acceptance Criteria:** User feels subtle tap when book spine enters frame; success notification when ISBN detected; no haptic spam

### Phase 6: Performance Tuning
**Goal:** Ensure Vision processing meets all performance targets

#### TODO 6.1: Adaptive frame throttling
- **File:** `swiftwing/Services/VisionService.swift` (MODIFY)
- **Action:** Implement adaptive processing rate based on device thermal state and results
- **Details:**
  - Monitor `ProcessInfo.processInfo.thermalState`
  - Throttle intervals:
    - `.nominal`: 150ms (6.7 effective fps) - default
    - `.fair`: 250ms (4 fps) - reduce processing
    - `.serious`: 500ms (2 fps) - significant reduction
    - `.critical`: Disable Vision processing entirely, notify ViewModel
  - When no content detected for 3+ seconds, reduce to 500ms (save battery)
  - When content first detected, ramp back up to 150ms
- **Acceptance Criteria:** Processing rate adapts to thermal state; battery-conscious when idle; responsive when content appears

#### TODO 6.2: Memory management verification
- **File:** `swiftwing/CameraManager.swift` (MODIFY - FrameProcessor)
- **Action:** Ensure no CVPixelBuffer leaks
- **Details:**
  - In FrameProcessor's `captureOutput`, do NOT retain the CMSampleBuffer or CVPixelBuffer beyond the callback
  - Process synchronously within the delegate callback
  - Set `alwaysDiscardsLateVideoFrames = true` (already planned in TODO 2.2)
  - Add `autoreleasepool` around Vision processing if needed
  - Performance logging: log memory usage every 60 seconds during active Vision processing
- **Acceptance Criteria:** Memory stays < 200MB during 5-minute continuous scanning session; no leaked buffers

#### TODO 6.3: Benchmark cold start regression
- **File:** `CameraViewModel.swift` (MODIFY - setupCamera) — **PROJECT ROOT**
- **Action:** Verify adding video output doesn't regress cold start time
- **Details:**
  - The existing timing code at `CameraViewModel.setupCamera()` lines 80-84 already measures cold start (`CFAbsoluteTimeGetCurrent() - coldStartTime` with a 0.5s threshold warning)
  - If > 0.5s, investigate whether video output configuration is the cause
  - Mitigation: configure video output AFTER session starts running (lazy setup)
  - If needed, defer Vision setup to after first frame is displayed (progressive enhancement)
- **Acceptance Criteria:** Cold start remains < 0.5s with Vision enabled

### Phase 7: Project Integration, Build Verification, and Testing
**Goal:** Integrate new files into Xcode project, ensure everything compiles and works together

#### TODO 7.0: Add new files to Xcode project (swiftwing.xcodeproj)
- **File:** `swiftwing.xcodeproj/project.pbxproj` (MODIFY)
- **Action:** Add all 4 new Swift files to the Xcode project target
- **Details:**
  - This project uses `.xcodeproj` (NOT Swift Package Manager), so files must be explicitly added to the project to compile
  - Files to add to the `swiftwing` target:
    1. `swiftwing/Services/VisionTypes.swift`
    2. `swiftwing/Services/VisionService.swift`
    3. `swiftwing/VisionOverlayView.swift`
    4. `swiftwing/CaptureGuidanceView.swift`
  - Each file needs entries in: PBXBuildFile, PBXFileReference, PBXGroup (under appropriate group), and PBXSourcesBuildPhase
  - Also add `import Vision` framework dependency to the target's "Frameworks and Libraries" if not already linked (Vision.framework is a system framework, should auto-link via `import Vision` in Swift, but verify)
  - **CAUTION:** This is a known failure mode in this project (documented in CLAUDE.md "Common Pitfalls") — files not added to .xcodeproj will silently fail to compile, producing "Cannot find type" errors
- **Acceptance Criteria:** All 4 new files appear in Xcode project navigator under correct groups; `xcodebuild` compiles them without "Cannot find type" errors

#### TODO 7.1: Build verification
- **Action:** Run full build with strict concurrency
- **Command:** `xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift`
- **Acceptance Criteria:** 0 errors, 0 warnings

#### TODO 7.2: Handle app lifecycle for Vision processing
- **File:** `CameraViewModel.swift` (MODIFY) — **PROJECT ROOT**
- **Action:** Ensure Vision processing pauses on background and resumes on foreground
- **Details:**
  - Background handling (pause): In the existing `scenePhase` observer or via `NotificationCenter` for `UIApplication.didEnterBackgroundNotification`:
    - Call `cameraManager.setVisionEnabled(false)` to stop frame processing
    - Clear Vision state (textRegions, barcode, guidance) to avoid stale overlays on return
  - Foreground resumption (resume): Via `NotificationCenter` for `UIApplication.didBecomeActiveNotification` or `scenePhase == .active`:
    - If `isVisionEnabled` is true (user preference), call `cameraManager.setVisionEnabled(true)` to resume processing
    - Reset VisionService's `lastProcessedTime` so throttling doesn't block the first frame after resume
  - The existing CameraManager already handles session start/stop on lifecycle transitions; Vision toggle piggybacks on the same lifecycle
- **Acceptance Criteria:** Vision processing stops when app backgrounds; resumes automatically when app returns to foreground (if user preference is enabled); no stale overlays on return

#### TODO 7.3: Integration verification checklist
- **Action:** Verify all features work together
- **Checklist:**
  - [ ] Camera preview loads with Vision overlay visible
  - [ ] Text recognition highlights appear over book spines
  - [ ] ISBN barcode detection shows ISBN label
  - [ ] Capture guidance shows appropriate messages
  - [ ] Shutter button still captures and uploads to Talaria
  - [ ] Processing queue still shows correct states
  - [ ] Zoom (pinch) works through overlay
  - [ ] Tap-to-focus works through overlay
  - [ ] Rate limiting still works
  - [ ] Offline mode still queues scans
  - [ ] Vision toggle button enables/disables processing
  - [ ] App backgrounding cancels Vision processing
  - [ ] App foregrounding resumes Vision processing (if enabled)
  - [ ] No memory leaks after 5 minutes of scanning
- **Acceptance Criteria:** All checklist items verified

---

## Commit Strategy

### Commit 1: Vision types and service foundation
**Files:** `VisionTypes.swift` (NEW), `VisionService.swift` (NEW)
**Message:** `feat: Add VisionService with text recognition and barcode detection (Vision Framework integration Phase 1)`

### Commit 2: CameraManager video output integration
**Files:** `CameraManager.swift` (MODIFIED)
**Message:** `feat: Add AVCaptureVideoDataOutput and FrameProcessor to CameraManager (Vision Phase 2)`

### Commit 3: ViewModel bridge and state management
**Files:** `CameraViewModel.swift` (MODIFIED)
**Message:** `feat: Bridge Vision results to CameraViewModel with debounced state updates (Vision Phase 3)`

### Commit 4: UI overlay and guidance views
**Files:** `VisionOverlayView.swift` (NEW), `CaptureGuidanceView.swift` (NEW), `CameraView.swift` (MODIFIED)
**Message:** `feat: Add real-time Vision overlay and capture guidance UI (Vision Phase 4)`

### Commit 5: Smart capture and ISBN pre-scan
**Files:** `CameraViewModel.swift` (MODIFIED), `ProcessingItem.swift` (MODIFIED), `VisionService.swift` (MODIFIED)
**Message:** `feat: Add smart capture guidance and ISBN pre-scan fallback (Vision Phase 5)`

### Commit 6: Performance tuning
**Files:** `VisionService.swift` (MODIFIED), `CameraManager.swift` (MODIFIED), `CameraViewModel.swift` (MODIFIED)
**Message:** `perf: Add adaptive frame throttling and memory guardrails for Vision processing (Vision Phase 6)`

### Commit 7: Xcode project integration and build verification
**Files:** `swiftwing.xcodeproj/project.pbxproj` (MODIFIED)
**Message:** `chore: Add Vision files to Xcode project and verify build (0 errors, 0 warnings)`

---

## Success Criteria

| Metric | Target | Measurement Method |
|--------|--------|--------------------|
| Text overlay latency | < 100ms from frame to UI | CFAbsoluteTimeGetCurrent() instrumentation |
| Camera cold start | < 0.5s (no regression) | Existing cold start logging |
| UI frame rate | > 55 FPS during Vision | Instruments Time Profiler |
| Battery impact | < 8% per minute | Instruments Energy Log |
| Memory peak | < 200 MB | Instruments Allocations |
| ISBN detection accuracy | > 95% for clear barcodes | Manual testing with 20+ books |
| Build cleanliness | 0 errors, 0 warnings | xcodebuild + xcsift |
| Existing feature regression | Zero regressions | Integration checklist (TODO 7.3) |

---

## Risk Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Cold start regression from video output | Medium | High | Lazy video output init after first frame; measure and compare |
| Battery drain from continuous processing | High | Medium | Adaptive throttling based on thermal state and content detection |
| Memory leak from CVPixelBuffer retention | Medium | High | Process synchronously in callback; never retain buffers; autoreleasepool |
| Vision accuracy on non-Latin scripts | Low | Low | Start with English only; add language support later |
| UI flicker from rapid Vision updates | Medium | Medium | Debounce updates; require stable detection for 2+ consecutive frames |
| Simulator limitations (no real camera) | High | Low | Test on physical device; Vision APIs work in simulator with sample images |
| Swift 6.2 concurrency warnings from delegate | Medium | Medium | Use nonisolated delegate class with explicit MainActor dispatch for UI updates |
| Session preset conflict with video output | Low | High | Test `.high` preset supports both outputs; fallback to `.medium` if needed |

---

## Files Modified Summary

### New Files (4)
1. `swiftwing/Services/VisionTypes.swift` - Result types for Vision processing
2. `swiftwing/Services/VisionService.swift` - Vision framework processing engine
3. `swiftwing/VisionOverlayView.swift` - Real-time text/barcode overlay
4. `swiftwing/CaptureGuidanceView.swift` - Smart capture guidance UI

### Modified Files (5)
1. `swiftwing/CameraManager.swift` - Add AVCaptureVideoDataOutput, FrameProcessor, Vision toggle
2. `CameraViewModel.swift` (**PROJECT ROOT:** `/Users/juju/dev_repos/swiftwing/CameraViewModel.swift`) - Add Vision state, callback wiring, guidance haptics, lifecycle handling
3. `swiftwing/CameraView.swift` - Add overlay views, toggle button, GeometryReader
4. `swiftwing/ProcessingItem.swift` - Add optional `preScannedISBN` field (synthesized Equatable handles it automatically)
5. `swiftwing.xcodeproj/project.pbxproj` - Add all 4 new files to Xcode project target

### Unchanged Files (preserving existing functionality)
- `swiftwing/Services/TalariaService.swift` - No changes
- `swiftwing/Services/NetworkTypes.swift` - No changes
- `swiftwing/CameraPreviewView.swift` - No changes (overlay handled in SwiftUI layer)
- `swiftwing/Models/Book.swift` - No changes
- `swiftwing/Theme.swift` - No changes (reusing existing design system)
- All other files - No changes
