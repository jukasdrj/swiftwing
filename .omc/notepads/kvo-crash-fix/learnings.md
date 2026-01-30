# KVO Crash Fix - Learnings

## KVO Crash Resolution (2026-01-30)

### Problem
```
'NSInternalInconsistencyException', reason: 'Cannot update for observer for the key path 
"effectiveGeometry.interfaceOrientation" from <UIWindowScene>, most likely because the value 
for the key "effectiveGeometry" has changed without an appropriate KVO notification being sent.'
```

### Root Cause
- Attempted to observe nested key path `\.effectiveGeometry.interfaceOrientation` via KVO
- `effectiveGeometry` property is not KVO-compliant in UIWindowScene
- Nested key paths require ALL intermediate properties to support KVO notifications

### Solution
**Replace KVO with NotificationCenter:**
```swift
// OLD (crashes):
windowScene.publisher(for: \.effectiveGeometry.interfaceOrientation)

// NEW (safe):
NotificationCenter.default.addObserver(
    forName: UIDevice.orientationDidChangeNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    Task { @MainActor [weak self, weak view] in
        guard let self, let view, let windowScene = view.window?.windowScene else { return }
        self.updateRotation(for: windowScene.effectiveGeometry.interfaceOrientation)
    }
}
```

### Additional Fix: Orientation Mapping
**CameraManager hardcoded orientation:**
```swift
// OLD:
let orientation: CGImagePropertyOrientation = .up // TODO

// NEW:
let orientation = CGImagePropertyOrientation(from: connection.videoRotationAngle)
```

**Extension added:**
```swift
extension CGImagePropertyOrientation {
    init(from videoRotationAngle: CGFloat) {
        // 0° = .right (landscapeRight)
        // 90° = .up (portrait)
        // 180° = .left (landscapeLeft)
        // 270° = .down (portraitUpsideDown)
    }
}
```

### Verification
✅ Build: 0 errors, 0 warnings
✅ No KVO crash on device rotation
✅ Vision text recognition receives correct orientation
✅ Preview rotates smoothly with NotificationCenter

### Lessons
1. **Not all properties support KVO** - especially iOS 26 new APIs
2. **NotificationCenter is safer** for orientation changes
3. **Always map AVCaptureConnection.videoRotationAngle** to CGImagePropertyOrientation for Vision framework
4. **weak capture lists prevent retain cycles** in notification observers
