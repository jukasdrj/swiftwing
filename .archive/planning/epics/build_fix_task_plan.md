# Task Plan: Fix SwiftWing Build Failures After Gemini Pro 3 Review Fixes

## Goal
Get SwiftWing to build successfully after implementing 5 critical fixes from Gemini Pro 3 review of Epic 3 performance code.

## Current State
- ❌ Build failing with multiple errors
- 🔄 Circular debugging without progress
- 📝 Already have: fix_review_progress.md (incomplete tracking)
- ⚠️ Lost context multiple times, repeating same fixes

## Root Problem (Unknown - Need Diagnosis)
Repeated failures suggest:
1. Fundamental project structure issue?
2. Missing understanding of iOS 26 / Swift 6.2 patterns?
3. File organization mismatch between filesystem and Xcode?
4. SwiftData environment access patterns wrong?

## Phases

### Phase 1: Diagnostic Assessment ✅ complete
**Status:** Complete
**Goal:** Use PAL tools to get expert holistic diagnosis of ALL issues
**Actions:**
- [x] Used `mcp__pal__thinkdeep` with Gemini 2.5 Flash to analyze build failures
- [x] Provided full context: all error messages, file structure, what was tried
- [x] Got expert assessment of root cause
- [x] Documented findings in findings.md

**Result:** ROOT CAUSE IDENTIFIED - `@Environment(\.modelContainer)` is invalid in SwiftData. Only `\.modelContext` exists.

### Phase 2: Project Structure Validation ✅ complete
**Goal:** Verify Xcode project structure matches filesystem
**Actions:**
- [x] Fixed `@Environment(\.modelContainer)` → use `modelContext.container` instead
- [x] Removed duplicate ImageCacheManager.swift from swiftwing/ subdirectory
- [x] Identified missing files in Xcode project

**Result:**
- ✅ modelContainer errors FIXED
- ⚠️ NEW ISSUE: PerformanceTestData.swift and PerformanceLogger.swift exist on disk but NOT in Xcode project

### Phase 3: Add Missing Files to Xcode Project ✅ complete
**Goal:** Add PerformanceTestData.swift and PerformanceLogger.swift to Xcode project
**Actions:**
- [x] Generated UUIDs for file references
- [x] Added PBXBuildFile entries (671ACE..., DF526B...)
- [x] Added PBXFileReference entries (90075E..., 59F317...)
- [x] Added to PBXGroup (swiftwing folder)
- [x] Added to PBXSourcesBuildPhase (compile sources)

**Result:** Manually edited project.pbxproj successfully!

### Phase 4: Build Verification ✅ complete
**Goal:** Confirm clean build with xcodebuild
**Actions:**
- [x] Clean build executed
- [x] All 5 Gemini Pro 3 fixes compile successfully
- [x] 0 errors, 14 warnings (acceptable)

**Result:** ✅ BUILD SUCCESSFUL!

## ✅ ALL PHASES COMPLETE

SwiftWing now builds successfully after implementing all 5 Gemini Pro 3 review fixes:
1. ✅ Added @MainActor to LibraryPrefetchCoordinator
2. ✅ Refactored prefetch logic to delegate to ImageCacheManager
3. ✅ Made generateTestDataset async with ModelContainer
4. ✅ Made clearTestData async with batch delete
5. ✅ Updated LibraryView integration (fixed @Environment(\.modelContainer) issue)

### Phase 5: Configuration & Documentation ✅ complete
**Goal:** Set up .claude/ rules to prevent future issues
**Actions:**
- [x] Updated CLAUDE.md with mandatory xcodebuild+xcsift pattern
- [x] Updated CLAUDE.md with mandatory planning-with-files usage
- [x] Created `.claude/rules/build-workflow.md` - xcodebuild+xcsift enforcement
- [x] Created `.claude/rules/planning-mandatory.md` - Planning requirements
- [x] Created `.claude/rules/swiftdata-patterns.md` - iOS 26 SwiftData patterns
- [x] Created `.claude/README.md` - Configuration overview

**Result:**
- ✅ Future Claude sessions will follow these rules automatically
- ✅ Rules prevent: direct xcodebuild calls, skipping planning, SwiftData mistakes
- ✅ Documentation captures lessons learned from this debugging session

## Errors Encountered

| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| `cannot find 'ImageCacheManager' in scope` | 1 | Added @MainActor, refactored prefetch | ❌ Build still failed |
| Actor isolation `urlSession` access | 2-5 | Tried nonisolated, nonisolated(unsafe), await | 🔄 Circular - wrong approach |
| Duplicate ImageCacheManager files | 6 | Found root + swiftwing/ copies, deleted root | ❌ Xcode still referenced deleted file |
| Missing file reference in Xcode | 7 | Copied back to root level where Xcode expects | ✅ Partially resolved |
| `nonisolated init()` on actor invalid | 8 | Removed nonisolated from init | ✅ Fixed |
| `@Environment(\.modelContainer)` error | 9 | Added type annotation | ❌ Made worse |

## Critical Lessons
1. ⚠️ **ALWAYS** verify build BEFORE code review (was skipped initially)
2. ⚠️ **ALWAYS** use `xcodebuild` not assumptions
3. ⚠️ Need planning-with-files for complex multi-step tasks (NOW USING)
4. ⚠️ Circular logic = missing persistent memory = need files

## Decision Log
- **Decision 1:** Use planning-with-files skill (user mandated)
- **Decision 2:** Get PAL expert help before continuing (user suggested)
- **Decision 3:** Stop circular fixes, diagnose holistically first

## Notes
- Working directory: `/Users/juju/dev_repos/swiftwing`
- Epic 3: Library performance optimization (1000+ books)
- 5 fixes implemented but build never verified to work
- User frustrated with circular debugging (rightfully so)
