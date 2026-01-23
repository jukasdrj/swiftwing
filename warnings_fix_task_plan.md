# Task Plan: Fix All Build Warnings in SwiftWing

## Goal
Achieve ZERO warnings in SwiftWing build. Build must be 100% clean before declaring success.

## Current State
- ✅ Build succeeds (0 errors)
- ❌ 14 warnings present
- ❌ CoreData errors in console (SwiftData store creation issues)
- ❌ AVFoundation/Fig errors (camera initialization)
- ❌ Swift 6.2 concurrency warnings (actor isolation, Sendable)

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

### Phase 1: Categorize All Warnings 🔄 in_progress
**Goal:** Get structured list of ALL warnings with file/line numbers
**Actions:**
- [x] Received screenshot with warning list
- [ ] Run build with xcsift to get machine-readable warnings
- [ ] Categorize by type: actor isolation, async/await, UIKit, runtime
- [ ] Document in findings.md

### Phase 2: Fix Actor Isolation Warnings ⏸️ pending
**Goal:** Resolve Swift 6.2 concurrency warnings
**Actions:**
- TBD based on Phase 1

### Phase 3: Fix Async/Await Warnings ⏸️ pending
**Goal:** Remove unnecessary await expressions
**Actions:**
- TBD based on Phase 1

### Phase 4: Fix UIKit Integration Warnings ⏸️ pending
**Goal:** Update deprecated UIKit patterns for iOS 26
**Actions:**
- TBD based on Phase 1

### Phase 5: Fix Runtime Errors ⏸️ pending
**Goal:** Resolve CoreData and AVFoundation console errors
**Actions:**
- TBD based on Phase 1

### Phase 6: Verify Zero Warnings ⏸️ pending
**Goal:** Confirm 100% clean build
**Actions:**
- Build with xcsift
- Verify: 0 errors, 0 warnings
- Run app, check console for runtime errors
- Update CLAUDE.md with zero-warning requirement

## Errors Encountered
| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| N/A yet | - | - | - |

## Decision Log
- **Decision 1:** Use planning-with-files for systematic warning resolution
- **Decision 2:** Get machine-readable warnings via xcsift first
- **Decision 3:** Fix by category, not randomly

## Notes
- User has ZERO tolerance for warnings
- Must validate with clean build every time
- Console runtime errors also need fixing
- Screenshot shows ~14 warnings across 4 files
