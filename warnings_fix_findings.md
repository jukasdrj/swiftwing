# Findings: SwiftWing Warning Analysis

## Warnings from Screenshot (14 total)

### ImageCacheManager.swift (1 warning)
1. **Line ~20**: `'nonisolated(unsafe)' has no effect on property 'urlSession' consider using 'nonisolated'`
   - Issue: Using `nonisolated(unsafe)` on computed property
   - Should be: Just `nonisolated` (without unsafe)

### CameraManager.swift (4 warnings)
1. **Add '@preconcurrency' to treat 'Sendable'-related errors from module 'AVFoundation' as warnings**
2. **Capture of 'session' with non-Sendable type 'AVCaptureSession' in a '@Sendable' closure**
   - AVCaptureSession not marked Sendable in iOS 26
3. **Capture of 'session' with non-Sendable type 'AVCaptureSession' in '@Sendable' closure** (duplicate)
4. **Call to main actor-isolated instance method 'locationOn()' in a synchronous nonisolated context**

### CameraPreviewView.swift (5 warnings)
1. **Main actor-isolated property 'state' can not be referenced from a nonisolated context**
2. **Main actor-isolated property 'scale' can not be referenced from a nonisolated context**
3. **Main actor-isolated property 'scale' can not be referenced from a nonisolated context** (duplicate)
4. **Call to main actor-isolated instance method 'locationOn()' in a synchronous nonisolated context**
5. **Main actor-isolated property 'view' can not be referenced from a nonisolated context**

### CameraView.swift (3 warnings)
1. **No 'async' operations occur within 'await' expression**
2. **No 'async' operations occur within 'await' expression** (duplicate)
3. **No 'async' operations occur within 'await' expression** (duplicate)

### AsyncImageWithLoading.swift (1 warning)
1. **No 'async' operations occur within 'await' expression**

## Console Runtime Errors

### CoreData/SwiftData Errors
```
CoreData: error: Failed to stat path '/var/mobile/.../default.store'
CoreData: error: Sandbox access to file-write-create denied
CoreData: error: addPersistentStoreWithType returned error NSCocoaErrorDomain (512)
CoreData: error: Recovery attempt was successful!
```

**Analysis:**
- SwiftData trying to create store in Application Support directory
- Directory doesn't exist on first launch
- SwiftData recovers automatically, but spams console
- Need to ensure directory exists or use different store location

### AVFoundation Fig Errors
```
<<<< FigXPCUtilities >>>> signalled err=-17281
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569)
(Fig) signalled err=-12710
```

**Analysis:**
- Low-level AVFoundation errors during camera initialization
- Likely due to simulator limitations or timing issues
- May not appear on real device
- Need to investigate if these are suppressible

## Root Causes

### 1. Actor Isolation Issues
**Problem:** Swift 6.2 strict concurrency checking
- AVCaptureSession not marked Sendable by Apple
- UIKit types accessed across isolation boundaries
- Main actor-isolated properties accessed from nonisolated contexts

### 2. Unnecessary Await
**Problem:** Using `await` on synchronous operations
- CameraView awaiting synchronous @MainActor methods
- AsyncImageWithLoading awaiting synchronous operations

### 3. nonisolated(unsafe) Misuse
**Problem:** Using `unsafe` variant when not needed
- ImageCacheManager computed property doesn't need `unsafe`
- Regular `nonisolated` sufficient for immutable URLSession

### 4. SwiftData Store Path
**Problem:** Default store location causes directory creation issues
- May need explicit ModelConfiguration with custom URL
- Or ensure Application Support directory exists

## Solution Approaches

### For Actor Isolation:
1. Add `@preconcurrency import AVFoundation` to suppress Sendable warnings
2. Use `nonisolated(unsafe)` correctly for AVCaptureSession captures
3. Ensure main actor isolation boundaries are respected

### For Unnecessary Await:
1. Remove `await` where operations are synchronous
2. Verify if operations truly need to be async

### For nonisolated(unsafe):
1. Change to just `nonisolated` where appropriate
2. Only use `unsafe` when truly needed for thread-unsafe types

### For SwiftData:
1. Use in-memory store configuration to avoid file system issues
2. Or explicitly create Application Support directory on launch
3. Or use explicit ModelConfiguration with known-good path

## Next Steps
1. Fix ImageCacheManager `nonisolated(unsafe)` → `nonisolated`
2. Fix CameraView unnecessary awaits
3. Fix AsyncImageWithLoading unnecessary awaits
4. Fix CameraManager actor isolation issues
5. Fix CameraPreviewView actor isolation issues
6. Address SwiftData store creation (if still an issue)
7. Investigate AVFoundation Fig errors (may be simulator-only)
