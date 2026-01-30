# Camera Rotation Fix - Testing Guide

## Issue Summary
**Problem:** Camera preview breaks when rotating from portrait to landscape
- Video stream appears broken/sideways
- Shutter button doesn't move from center
- Preview layer doesn't update orientation

**Root Cause:** Hardcoded 90° rotation angle in `CameraPreviewView.swift`

## Implementation Changes

### Files Modified
1. **`swiftwing/CameraPreviewView.swift`**
   - Added dynamic orientation detection
   - Implemented `updateVideoRotation()` method
   - Added `handleOrientationChange()` observer in Coordinator
   - Proper cleanup in `deinit`

### Technical Details

**Orientation Mapping:**
| Device Orientation | Video Rotation Angle |
|--------------------|---------------------|
| Portrait | 90° |
| Portrait Upside Down | 270° |
| Landscape Left | 180° |
| Landscape Right | 0° |

**Key Features:**
- ✅ Smooth 0.3s animation during rotation (via CATransaction)
- ✅ Automatic detection via `UIDevice.orientationDidChangeNotification`
- ✅ Proper memory management (observer cleanup in deinit)
- ✅ Fallback to portrait (90°) for unknown orientations

## Testing Instructions

### Manual Testing Steps

1. **Launch App in Portrait**
   ```bash
   # Build and run on simulator
   xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift

   # Then run in Xcode (Cmd+R)
   ```

2. **Verify Portrait Mode**
   - [ ] Camera preview displays correctly (upright)
   - [ ] Shutter button is centered at bottom
   - [ ] Zoom level indicator shows top-right
   - [ ] Tap-to-focus works correctly

3. **Test Landscape Left Rotation**
   - [ ] Rotate device/simulator to landscape left
   - [ ] Video stream should **smoothly rotate** (not break)
   - [ ] Shutter button should remain accessible
   - [ ] Preview layer should fill screen correctly
   - [ ] Console should show: `📱 Device orientation changed - video rotation updated to 180°`

4. **Test Landscape Right Rotation**
   - [ ] Rotate to landscape right
   - [ ] Video should rotate smoothly
   - [ ] Console should show: `📱 Device orientation changed - video rotation updated to 0°`

5. **Test Portrait Upside Down (iPad)**
   - [ ] Rotate to portrait upside down
   - [ ] Video should rotate
   - [ ] Console should show: `📱 Device orientation changed - video rotation updated to 270°`

6. **Return to Portrait**
   - [ ] Rotate back to portrait
   - [ ] Video should return to original orientation
   - [ ] Console should show: `📱 Device orientation changed - video rotation updated to 90°`

7. **Functional Tests After Rotation**
   - [ ] Capture photo in landscape → verify image saves correctly
   - [ ] Zoom gesture works in landscape
   - [ ] Tap-to-focus works in landscape
   - [ ] Processing queue displays correctly in landscape

### Simulator Testing (Xcode)

**Using Simulator Rotation Shortcuts:**
- **⌘+Left Arrow** - Rotate left (counterclockwise)
- **⌘+Right Arrow** - Rotate right (clockwise)
- **Device → Rotate Left/Right** menu

**Expected Console Output:**
```
✅ Camera session configured in 0.123s
✅ Camera session started in 0.045s
📹 Camera cold start: 0.168s (target: < 0.5s)
📱 Device orientation changed - video rotation updated to 180°
📱 Device orientation changed - video rotation updated to 0°
📱 Device orientation changed - video rotation updated to 90°
```

### Physical Device Testing

**Test on iPhone 17 Pro Max (or similar):**
1. Deploy to physical device via Xcode
2. Enable rotation lock OFF
3. Physically rotate device through all orientations
4. Verify smooth transitions
5. Test camera capture in landscape

### Performance Verification

**Rotation Performance Targets:**
- [ ] Rotation animation duration: ~0.3s (smooth)
- [ ] No frame drops during rotation
- [ ] No visual glitches or black frames
- [ ] Tap-to-focus coordinates correct after rotation

### Edge Cases to Test

1. **Rapid Rotation**
   - [ ] Quickly rotate device multiple times
   - [ ] Should handle orientation changes gracefully
   - [ ] No crashes or memory issues

2. **Capture During Rotation**
   - [ ] Press shutter while rotating
   - [ ] Should complete capture without error
   - [ ] Image orientation should be correct

3. **Processing Queue During Rotation**
   - [ ] Start scan → rotate → verify queue display
   - [ ] Queue items should remain visible and functional

4. **Rate Limit Overlay During Rotation**
   - [ ] Trigger rate limit (10 scans quickly)
   - [ ] Rotate device
   - [ ] Overlay should reposition correctly

## Known Issues / Limitations

### Not Implemented (Deferred)
- [ ] App does not support landscape-only mode
- [ ] SwiftWing is primarily designed for portrait scanning
- [ ] Full landscape UI optimization (shutter repositioning) is Epic 5+ work

### Acceptable Behavior
- Shutter button remains at bottom center (doesn't reposition to side in landscape)
- UI elements designed for portrait may overlap in landscape (by design)
- App works best in portrait mode (book scanning use case)

## Rollback Instructions

If rotation fix causes issues:

```bash
# Revert changes
git diff swiftwing/CameraPreviewView.swift
git checkout swiftwing/CameraPreviewView.swift

# Rebuild
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' clean build 2>&1 | xcsift
```

## Success Criteria

**Fix is successful if:**
1. ✅ Camera preview rotates correctly in all orientations
2. ✅ No crashes or visual glitches during rotation
3. ✅ Video stream never "breaks" or appears sideways
4. ✅ Capture functionality works in landscape
5. ✅ Performance remains within targets (no lag)

**Fix fails if:**
- ❌ Preview layer shows black screen after rotation
- ❌ Video stream is sideways or upside down in any orientation
- ❌ Rotation causes crashes or memory leaks
- ❌ Capture fails in landscape mode

## Future Enhancements (Epic 5+)

- [ ] Landscape-optimized UI layout (shutter on right side)
- [ ] Orientation lock toggle in settings
- [ ] Adaptive processing queue display for landscape
- [ ] Auto-rotate captured images based on device orientation metadata

---

**Testing Date:** _____________________
**Tester:** _____________________
**Device/Simulator:** _____________________
**Result:** ☐ PASS  ☐ FAIL
**Notes:** _____________________
