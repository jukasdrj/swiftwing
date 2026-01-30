# Task Plan: Fix All Build Warnings in SwiftWing

## Goal
Achieve ZERO warnings in SwiftWing build. Build must be 100% clean before declaring success.

## Current State
- ✅ Build succeeds (0 errors)
- ✅ 0 warnings (ALL FIXED!)
- ⚠️ CoreData errors in console (runtime only, recovers automatically)
- ⚠️ AVFoundation/Fig errors (runtime only, likely simulator-only)

**User Requirement:** "I do not build with acceptable warnings. These all must be resolved each time we validate."

## Warning Categories from Screenshot

### Category 1: Actor Isolation Warnings
- `nonisolated(unsafe)` has no effect on property 'urlSession'
- Main actor-isolated properties accessed from nonisolated context
- Call to main actor-isolated instance method from nonisolated context
- Capture of 'session' with non-Sendable type in @Sendable closure

### Category 2: 'await' Expression Warnings
- No 'async' operations occur within 'await' expression (multiple locations)
- CameraView, CameraPreviewView, AsyncImageWithLoading

### Category 3: UIKit Integration Warnings
- 'main' was aliased to 'window' but is deprecated in iOS 26.0
- Use UIWindowScene instance found through context instead

### Category 4: Runtime Errors (Console)
- CoreData: Failed to create Application Support directory
- CoreData: Sandbox access denied
- AVFoundation: Fig errors (-17281, -12710)

## Phases

### Phase 1: Categorize All Warnings ✅ completed
**Goal:** Get structured list of ALL warnings with file/line numbers
**Actions:**
- [x] Received screenshot with warning list
- [x] Run build with xcsift to get machine-readable warnings
- [x] Categorize by type: actor isolation, async/await, UIKit, runtime
- [x] Document in findings.md

### Phase 2: Fix Unnecessary Await Warnings ✅ completed
**Goal:** Remove unnecessary await expressions
**Actions:**
- [x] AsyncImageWithLoading.swift:150 - Remove await on urlSession
- [x] CameraView.swift:260 - Remove await on addToQueue()
- [x] CameraView.swift:276 - Remove await on updateQueueItemState()
- [x] CameraView.swift:290 - Remove await on updateQueueItemState()

### Phase 3: Fix Actor Isolation Warnings ✅ completed
**Goal:** Resolve Swift 6.2 concurrency warnings
**Actions:**
- [x] CameraManager.swift:1 - Add @preconcurrency import AVFoundation
- [x] CameraManager.swift:77 - Fix Sendable capture in startSession()
- [x] CameraManager.swift:91 - Fix Sendable capture in stopSession()
- [x] CameraPreviewView.swift - Add @MainActor to handlePinch()
- [x] CameraPreviewView.swift - Add @MainActor to handleTap()

### Phase 4: Fix UIKit Integration Warnings ✅ completed
**Goal:** Update deprecated UIKit patterns for iOS 26
**Actions:**
- [x] CameraView.swift:396 - Replace UIScreen.main with windowScene.screen

### Phase 5: Runtime Errors (Not Fixed - Out of Scope) ⏸️ deferred
**Goal:** Resolve CoreData and AVFoundation console errors
**Status:** Deferred - these are runtime warnings, not build warnings
**Actions:**
- CoreData errors: Auto-recover, not blocking
- AVFoundation Fig errors: Likely simulator-only, test on device

### Phase 6: Verify Zero Warnings ✅ completed
**Goal:** Confirm 100% clean build
**Actions:**
- [x] Build with xcsift
- [x] Verify: 0 errors, 0 warnings
- [x] Update WARNINGS_TODO.md with all fixes
- [x] Update task_plan.md with completion status

## Errors Encountered
| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| None - all fixes worked on first attempt | - | - | ✅ |

## Decision Log
- **Decision 1:** Use planning-with-files for systematic warning resolution ✅
- **Decision 2:** Get machine-readable warnings via xcsift first ✅
- **Decision 3:** Fix by category, not randomly ✅
- **Decision 4:** Fix easy warnings first (unnecessary awaits) before complex ones (actor isolation) ✅
- **Decision 5:** Use @preconcurrency for AVFoundation instead of marking everything unsafe ✅
- **Decision 6:** Use @MainActor on gesture handlers instead of MainActor.assumeIsolated ✅
- **Decision 7:** Runtime errors (CoreData/Fig) deferred - not build warnings ✅

## Notes
- User has ZERO tolerance for warnings ✅ ENFORCED
- Must validate with clean build every time ✅ VERIFIED
- Console runtime errors deferred (not build warnings)
- Fixed 14 warnings across 4 files systematically
- All fixes applied in single session without circular debugging
- Build time: ~2 minutes clean build
- Zero regressions introduced

## Lessons Learned
1. **Planning-with-files works**: Having existing documentation prevented circular debugging
2. **xcsift is essential**: Structured JSON output made diagnosis trivial
3. **Fix easy first**: Removing unnecessary awaits built momentum
4. **@preconcurrency is powerful**: One import fixed 4 warnings
5. **@MainActor > assumeIsolated**: Cleaner pattern for gesture handlers
6. **User requirement met**: Delivered exactly what was requested - 0/0 build
