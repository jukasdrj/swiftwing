# Camera Orientation Debug Progress Log

## Session: 2026-01-30

### Planning Setup
- ✅ Created task_plan.md
- ✅ Created findings.md
- ✅ Created progress.md
- Next: Begin Phase 1 - Discovery

### Phase 1: Discovery
✅ **COMPLETE** - 13:40

**Actions Taken:**
- Read CameraViewModel.swift (799 lines)
- Read CameraView.swift (263 lines)
- Read CameraManager.swift (347 lines)
- Read CameraPreviewView.swift (143 lines)
- Analyzed git commits 791f514 and cfef4eb
- Reviewed git diff to understand what changed

**Key Discovery:**
Orientation is handled in two places with DIFFERENT values:
- CameraPreviewView.swift (WRONG values)
- CameraManager.swift (CORRECT values)

---

### Phase 2: Root Cause Analysis
✅ **COMPLETE** - 13:45

**Root Cause:**
CameraPreviewView.swift lines 123-126 have landscapeLeft and landscapeRight SWAPPED.

**Evidence:**
```swift
// CameraPreviewView.swift (WRONG)
case .landscapeLeft:  rotationAngle = 0    // Should be 180
case .landscapeRight: rotationAngle = 180  // Should be 0

// CameraManager.swift (CORRECT)
case .landscapeLeft:  rotationAngle = 180  // ✅
case .landscapeRight: rotationAngle = 0    // ✅
```

**Why Previous Fixes Failed:**
1. Commit cfef4eb: Added complex NotificationCenter logic but didn't fix the angles
2. Commit 791f514: Swapped the angles but in the WRONG direction (made it backwards)

---

### Phase 3: Solution Design
✅ **COMPLETE** - 13:50

**Solution:**
Simple 2-line fix in CameraPreviewView.swift:
- Line 124: Change `rotationAngle = 0` to `rotationAngle = 180`
- Line 126: Change `rotationAngle = 180` to `rotationAngle = 0`

**Next:** Ready for implementation (Phase 4)

---

### Phase 4: Implementation
✅ **COMPLETE** - 13:55

**Fix Applied:**
```swift
// CameraPreviewView.swift lines 123-126
case .landscapeLeft:
    rotationAngle = 180   // ← Changed from 0
case .landscapeRight:
    rotationAngle = 0     // ← Changed from 180
```

**Build Verification:**
```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift
```

**Result:** ✅ SUCCESS
- Errors: 0
- Warnings: 0
- Build time: ~30s

**Ready for Testing:**
User will now test on device/simulator to verify:
1. Portrait mode displays correctly (not sideways)
2. All 4 orientations work
3. Captured photos remain correctly oriented

---

### Phase 5: First Fix Failed
⚠️ **FAILED** - 14:00

User reported orientation still broken. The angle swap was NOT the issue.

---

### Phase 6: Deep Root Cause Analysis
✅ **COMPLETE** - 14:10

Launched architect agent (Opus) for deep AVFoundation analysis.

**REAL ROOT CAUSES DISCOVERED:**

1. **Connection is NIL** when rotation is set
   - updateOrientation() called from makeUIView (line 24)
   - Session hasn't started yet, connection doesn't exist
   - Guard clause silently returns, rotation never applied

2. **No runtime orientation detection**
   - NotificationCenter observer removed in commit 791f514
   - updateUIView doesn't fire on device rotation
   - Preview frozen at (failed) initial orientation

3. **Wrong API for iOS 26**
   - Should use AVCaptureDevice.RotationCoordinator
   - Handles connection lifecycle automatically
   - Auto-updates on rotation via KVO
   - Apple-recommended solution

**Why photos work but preview doesn't:**
- Photo capture sets rotation at CAPTURE TIME (when connection exists)
- Preview tries to set rotation at VIEW CREATION (connection is nil)

---

### Phase 7: RotationCoordinator Implementation
✅ **COMPLETE** - 14:20

**Complete rewrite of CameraPreviewView.swift:**

**Key Changes:**
```swift
// Added to Coordinator
private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
private var rotationObservation: NSKeyValueObservation?

// New method: setupRotationCoordinator()
- Polls until session.isRunning (max 2 seconds)
- Gets video device from session inputs
- Creates RotationCoordinator(device:previewLayer:)
- Applies initial rotation: coordinator.videoRotationAngleForHorizonLevelPreview
- Observes changes via KVO
- Auto-updates connection.videoRotationAngle on rotation
```

**CameraManager.swift change:**
```swift
// Line 12: Expose device for coordinator
private(set) var videoDevice: AVCaptureDevice?
```

**Build Result:** ✅ 0 errors, 5 warnings

**Next:** User testing with proper iOS 26 API implementation

---

## Test Results
(To be populated)

## Verification Checklist
- [ ] Portrait mode works
- [ ] Landscape left works
- [ ] Landscape right works
- [ ] Rotation while active works
- [ ] Captured images correctly oriented
