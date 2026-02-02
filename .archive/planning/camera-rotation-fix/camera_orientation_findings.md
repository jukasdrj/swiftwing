# Camera Orientation Debug Findings

## Problem Statement
Camera preview displays in incorrect orientation (appears sideways/landscape when device is in portrait mode).

## Visual Evidence
- Screenshot shows camera preview rotated 90 degrees
- Books appear sideways on left side of screen
- UI elements (Camera/Library tabs) are correctly oriented
- Preview content itself is rotated

## Technical Context

### AVFoundation Orientation System
(To be populated during investigation)

### Current Implementation
(To be populated after reading code)

### Previous Fix Attempts
(To be populated from git history)

## Root Cause Hypothesis
**CONFIRMED ROOT CAUSE**: Incorrect rotation angle mapping for landscape orientations

The camera preview is showing landscape when the device is in portrait because the rotation angles for `landscapeLeft` and `landscapeRight` are STILL INCORRECT even after the most recent "fix".

## Key Discoveries

### Discovery 1: Most Recent Fix Got It BACKWARDS (Commit 791f514)
The commit message claims:
```
Fix:
- Landscape Left: 180° → 0° (home button on left = no rotation needed)
- Landscape Right: 0° → 180° (home button on right = 180° rotation)
```

**But this is WRONG**. Here's why:

### Discovery 2: AVFoundation Camera Sensor Orientation
The camera sensor is **physically landscape**. When the device is:
- **Portrait** (home button bottom): Sensor is rotated 90° CCW from device → need 90° CW rotation
- **Landscape Right** (home button right): Sensor matches device → need 0° rotation
- **Landscape Left** (home button left): Sensor is 180° from device → need 180° rotation
- **Portrait Upside Down** (home button top): Sensor is rotated 90° CW from device → need 270° rotation

### Discovery 3: Current Code (INCORRECT)
```swift
switch orientation {
case .portrait:
    rotationAngle = 90    // ✅ CORRECT
case .portraitUpsideDown:
    rotationAngle = 270   // ✅ CORRECT
case .landscapeLeft:
    rotationAngle = 0     // ❌ WRONG - should be 180
case .landscapeRight:
    rotationAngle = 180   // ❌ WRONG - should be 0
```

### Discovery 4: Why Previous Fixes Failed

**Attempt 1 (cfef4eb)**: Added complex NotificationCenter observation
- Problem: Over-engineered solution without fixing the core mapping
- Result: Still had wrong angles

**Attempt 2 (791f514)**: "Corrected" landscape angles by swapping them
- Problem: Swapped them in the WRONG direction
- Root error: Confused "home button left" with "rotate video left"
- Result: Made it worse

### Discovery 5: The Correct Mapping
Based on Apple's coordinate system and camera sensor physics:

| Device Orientation | Home Button Position | Sensor vs Device | Required Rotation |
|--------------------|---------------------|------------------|-------------------|
| `.portrait` | Bottom | 90° CCW | **90°** |
| `.portraitUpsideDown` | Top | 90° CW | **270°** |
| `.landscapeRight` | Right | Aligned | **0°** |
| `.landscapeLeft` | Left | 180° flipped | **180°** |

**The pattern**:
- "Right" = 0° (no rotation)
- "Left" = 180° (flip)

### Discovery 6: CRITICAL - Inconsistency Between Files!

**CameraPreviewView.swift** (lines 123-126): **INCORRECT**
```swift
case .landscapeLeft:
    rotationAngle = 0     // ❌ WRONG
case .landscapeRight:
    rotationAngle = 180   // ❌ WRONG
```

**CameraManager.swift** (lines 152-155): **CORRECT**
```swift
case .landscapeLeft:
    rotationAngle = 180   // ✅ CORRECT
case .landscapeRight:
    rotationAngle = 0     // ✅ CORRECT
```

**This explains the bug**: The preview layer is using the wrong angles while photo capture uses the correct angles! This means:
- Preview displays sideways (BUG visible in screenshot)
- Captured photos are correctly oriented (lucky coincidence)

**Solution**: Copy the CORRECT mapping from CameraManager.swift to CameraPreviewView.swift

---

## UPDATED ROOT CAUSE ANALYSIS (After Fix Failed)

### Discovery 7: The Angle Values Were NOT The Problem

After applying the "fix" and still seeing broken orientation, deep analysis reveals **THREE actual root causes**:

### Root Cause #1: Connection is NIL When Rotation is Set (CRITICAL)
**File:** CameraPreviewView.swift lines 106-110

The `updateOrientation(for:)` method has a guard clause:
```swift
guard let previewLayer = previewLayer,
      let connection = previewLayer.connection,  // ← This is NIL!
      let windowScene = view.window?.windowScene else {
    return  // Silently fails
}
```

**Why connection is nil:**
- Called from `makeUIView` (line 24) - session hasn't started yet
- `AVCaptureVideoPreviewLayer.connection` only exists AFTER session is running
- `CameraManager.startSession()` runs on background queue (async)
- By the time `makeUIView` returns, connection doesn't exist yet
- **Result:** Rotation is never set, preview defaults to landscape

### Root Cause #2: No Runtime Orientation Detection (CRITICAL)
**Removed in commit 791f514**

Previous code had `NotificationCenter` observer for `UIDevice.orientationDidChangeNotification`.
This was REMOVED in latest commit, replaced with "updateUIView lifecycle" approach.

**Problem:** SwiftUI `updateUIView` does NOT fire when device rotates!
- Only fires when SwiftUI state changes (session, onZoomChange, onFocusTap)
- Device rotation doesn't trigger SwiftUI state change
- **Result:** Preview never updates after initial setup (which failed anyway due to #1)

### Root Cause #3: Wrong API for iOS 26
**Should use:** `AVCaptureDevice.RotationCoordinator` (iOS 17+)

Apple's modern approach:
```swift
let rotationCoordinator = AVCaptureDevice.RotationCoordinator(
    device: camera,
    previewLayer: previewLayer
)
// Provides: videoRotationAngleForHorizonLevelPreview
// Auto-updates via KVO when rotation changes
// Handles connection lifecycle automatically
```

**Current approach problems:**
- Manual angle mapping (error-prone)
- Manual orientation detection (broken)
- Manual timing management (connection nil issue)

### Why Photo Capture Works But Preview Doesn't

**CameraManager.capturePhoto()** (lines 134-168):
- Sets rotation at **capture time** (when user taps shutter)
- By then, session is running and connection exists
- Gets fresh orientation from UIWindowScene every time
- **Works perfectly**

**CameraPreviewView** (lines 23-24):
- Tries to set rotation at **view creation time**
- Session not running, connection is nil
- Never retries, no orientation change detection
- **Fails silently**

### The Real Solution: AVCaptureDevice.RotationCoordinator

This is the **Apple-recommended** fix for iOS 17+ / iOS 26:

1. **Create coordinator** after preview layer setup
2. **Observe** `videoRotationAngleForHorizonLevelPreview` via KVO
3. **Apply** angle to `connection.videoRotationAngle` in observer
4. **Automatic** handling of connection lifecycle and orientation changes

## Reference Materials
- Apple AVCaptureVideoPreviewLayer documentation
- Apple AVCaptureConnection videoOrientation documentation
- AVCaptureVideoOrientation enum values

## Investigation Timeline
- 2026-01-30: Planning files created, investigation started
