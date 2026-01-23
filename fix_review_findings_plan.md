# Task Plan: Fix Gemini Pro 3 Code Review Findings

## Goal
Fix all 5 critical findings from Gemini Pro 3 review of LibraryPrefetchCoordinator and PerformanceTestData to eliminate data races, performance bottlenecks, and architectural redundancy.

## Context
- Codebase: SwiftWing iOS 26 app (Swift 6.2, SwiftUI, SwiftData)
- Epic 3: Library performance optimizations (1000+ books, 60 FPS target)
- Files affected: LibraryPrefetchCoordinator.swift, PerformanceTestData.swift, ImageCacheManager.swift
- Critical: These are new files that were missing and causing build failures

## Success Criteria
- [ ] No data races (Swift 6 concurrency compliance)
- [ ] No UI freezing during test data generation
- [ ] Eliminated redundant prefetch logic
- [ ] Build succeeds without errors
- [ ] Performance targets maintained (60 FPS scroll, <100ms render)

## Phases

### Phase 1: Get Detailed Implementation Plan from Gemini Pro 3
**Status:** `complete`
**Assigned to:** mcp__pal__clink (Gemini Pro 3)
**Description:** Request comprehensive implementation plan with code examples
**Deliverable:** Detailed step-by-step plan in fix_review_findings.md
**Completed:** 2026-01-23 - Comprehensive plan received and documented

### Phase 2: Fix Critical Concurrency Issues (Findings #1, #3)
**Status:** `pending`
**Assigned to:** Edit tool (direct implementation)
**Description:**
- Add @MainActor to LibraryPrefetchCoordinator
- Make generateTestDataset async
**Dependencies:** Phase 1 complete

### Phase 3: Fix Performance Killers (Finding #2)
**Status:** `pending`
**Assigned to:** Edit tool (direct implementation)
**Description:** Remove UIImage(data:) check from prefetch logic
**Dependencies:** Phase 2 complete

### Phase 4: Refactor Architecture (Finding #4)
**Status:** `pending`
**Assigned to:** Edit tool (architectural refactor)
**Description:** Simplify LibraryPrefetchCoordinator to delegate to ImageCacheManager
**Dependencies:** Phase 3 complete

### Phase 5: Optimize Batch Operations (Finding #5)
**Status:** `pending`
**Assigned to:** Edit tool (SwiftData optimization)
**Description:** Improve clearTestData efficiency
**Dependencies:** Phase 4 complete

### Phase 6: Verify Build and Test
**Status:** `pending`
**Assigned to:** Bash (xcsift build)
**Description:** Ensure all changes compile and integrate properly
**Dependencies:** Phase 5 complete

## Key Decisions
| Decision | Rationale | Date |
|----------|-----------|------|
| Use planning-with-files system | Complex multi-file refactor requiring coordination | 2026-01-23 |
| Request detailed plan from Pro 3 first | Expert guidance prevents rework | 2026-01-23 |

## Errors Encountered
| Error | Phase | Resolution |
|-------|-------|------------|
| (none yet) | - | - |

## Files to Modify
- `/Users/juju/dev_repos/swiftwing/swiftwing/LibraryPrefetchCoordinator.swift`
- `/Users/juju/dev_repos/swiftwing/swiftwing/PerformanceTestData.swift`
- `/Users/juju/dev_repos/swiftwing/swiftwing/LibraryView.swift` (if generateTestDataset calls need updating)

## Notes
- All 5 findings are HIGH priority (prevent crashes, freezes, data races)
- User specifically requested clink pro3 for review and planning
- PM approach: maximize subagent utilization, strong coordination
