# Outstanding Warnings (14 total)

## ImageCacheManager.swift (1 warning) - ✅ FIXED
1. ~~`'nonisolated(unsafe)' has no effect on property 'urlSession' consider using 'nonisolated'`~~ ✅
   - Fixed: Changed to just `nonisolated` without `unsafe`

## CameraManager.swift (4 warnings)
1. **Add '@preconcurrency' to treat 'Sendable'-related errors from module 'AVFoundation' as warnings**
   - Location: Module-level import
   - Issue: AVFoundation types not marked Sendable in iOS 26
   - Fix: Add `@preconcurrency import AVFoundation`

2. **Capture of 'session' with non-Sendable type 'AVCaptureSession' in a '@Sendable' closure**
   - Location: Async Task capturing AVCaptureSession
   - Issue: AVCaptureSession not Sendable-conformant
   - Fix: Use `nonisolated(unsafe)` or @preconcurrency

3. **Capture of 'session' with non-Sendable type 'AVCaptureSession' in '@Sendable' closure** (duplicate)
   - Same as #2, different location

4. **Call to main actor-isolated instance method 'locationOn()' in a synchronous nonisolated context**
   - Location: Calling MainActor method from actor method
   - Issue: Crossing actor boundary without await
   - Fix: Add `await` or restructure call

## CameraPreviewView.swift (5 warnings)
1. **Main actor-isolated property 'state' can not be referenced from a nonisolated context**
   - Location: UIViewRepresentable accessing @MainActor property
   - Issue: Crossing isolation boundary
   - Fix: Use `MainActor.assumeIsolated` or mark method @MainActor

2. **Main actor-isolated property 'scale' can not be referenced from a nonisolated context**
   - Same as #1, different property

3. **Main actor-isolated property 'scale' can not be referenced from a nonisolated context** (duplicate)
   - Same as #2, different location

4. **Call to main actor-isolated instance method 'locationOn()' in a synchronous nonisolated context**
   - Same issue as CameraManager #4

5. **Main actor-isolated property 'view' can not be referenced from a nonisolated context**
   - Same as #1, accessing UIView from nonisolated context

## CameraView.swift (3 warnings)
1. **No 'async' operations occur within 'await' expression**
   - Location: Line with unnecessary `await`
   - Issue: Using `await` on synchronous operation
   - Fix: Remove `await` or make operation truly async

2. **No 'async' operations occur within 'await' expression** (duplicate)
   - Same as #1, different location

3. **No 'async' operations occur within 'await' expression** (duplicate)
   - Same as #1, third location

## AsyncImageWithLoading.swift (1 warning)
1. **No 'async' operations occur within 'await' expression**
   - Location: Loading image without actual async work
   - Issue: Using `await` on synchronous operation
   - Fix: Remove `await` or restructure

## Summary by Type

### Actor Isolation Issues (9 warnings)
- CameraManager: 4
- CameraPreviewView: 5

**Root Cause:** Swift 6.2 strict concurrency checking
- AVFoundation types not marked Sendable
- UIKit types accessed across actor boundaries
- MainActor-isolated properties accessed from nonisolated contexts

**General Fixes:**
- Add `@preconcurrency import AVFoundation`
- Use `nonisolated(unsafe)` for non-Sendable captures
- Use `MainActor.assumeIsolated` in UIViewRepresentable
- Add proper `await` when crossing actor boundaries

### Unnecessary Await (4 warnings)
- CameraView: 3
- AsyncImageWithLoading: 1

**Root Cause:** Using `await` on synchronous operations

**Fix:** Remove `await` where no async work occurs

## Console Runtime Errors (Not Build Warnings)

### CoreData/SwiftData Errors
```
CoreData: error: Failed to stat path '.../default.store'
CoreData: error: Sandbox access to file-write-create denied
CoreData: error: Recovery attempt was successful!
```
- Issue: SwiftData creating Application Support directory on first launch
- Impact: Spam console but recovers automatically
- Fix: Consider explicit ModelConfiguration or directory creation

### AVFoundation Fig Errors
```
<<<< FigXPCUtilities >>>> signalled err=-17281
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0"
(Fig) signalled err=-12710
```
- Issue: Low-level AVFoundation errors during camera init
- Impact: May be simulator-only, need to test on device
- Fix: Investigate suppressibility or timing issues

## Next Session Goals
1. Fix all 4 CameraManager warnings
2. Fix all 5 CameraPreviewView warnings
3. Fix all 3 CameraView warnings
4. Fix AsyncImageWithLoading warning
5. Verify: `xcodebuild | xcsift` shows 0 errors, 0 warnings
6. Test on device to check if Fig errors persist
