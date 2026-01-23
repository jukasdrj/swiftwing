# Pre-Epic 3 Technical Debt Cleanup Plan

**Project:** SwiftWing iOS 26
**Date:** 2026-01-22
**PM:** Claude Code (Strong PM mode - Parallel subagents + Grok quality gates)
**Duration:** 4-6 hours estimated
**Goal:** Resolve 3 blockers before Epic 3 Library development

---

## Executive Summary

Epic 2 (Camera) completed with all 6 stories passing ✅. Code review (Grok-code-fast-1) identified 3 items requiring resolution before Epic 3:

1. **US-103 Completion** - Add dummy data seeding (missing from Epic 1)
2. **US-322 High Priority** - Fix error UI + temp file cleanup
3. **US-322 Medium Priority** - Resolve thread-safety warning

**PM Strategy:**
- **Parallel subagent execution** (maximize throughput)
- **Grok review gates** (quality assurance before code acceptance)
- **Manus planning-with-files** (persistent context across phases)

---

## Phase Structure

### Phase 1: Planning & Subagent Launch ⏳ in_progress
**Owner:** PM (Claude) + Gemini Pro 3
**Started:** 2026-01-22

- [x] Create planning files (task_plan, findings, progress)
- [x] Get Gemini Pro 3 architecture plan
- [ ] Launch Task 1 subagent (DataSeeder)
- [ ] Launch Task 2 subagent (Error UI + Cleanup)
- [ ] Launch Task 3 subagent (Thread Safety)
- [ ] Set up Grok review workflow

---

### Phase 2: Task 1 - Data Seeding (Parallel Track A) ⏸ pending
**Owner:** Subagent (general-purpose)
**Grok Review:** Required before acceptance

**Files:**
- CREATE: `swiftwing/Models/DataSeeder.swift`
- MODIFY: `swiftwing/LibraryView.swift`
- MODIFY: `swiftwing/SwiftwingApp.swift`

**Deliverables:**
- Static DataSeeder with 20+ diverse books
- Development mode toggle (debug builds only)
- "Seed Library" button in LibraryView
- App init option for auto-seeding

**Acceptance Criteria:**
- [ ] Grok review passes ✅
- [ ] Diverse data (fiction, non-fiction, multiple authors)
- [ ] Swiss Glass styling for UI elements
- [ ] No impact on Epic 2 camera code
- [ ] Production builds exclude seeding code

---

### Phase 3: Task 2 - Error UI & File Cleanup (Parallel Track B) ⏸ pending
**Owner:** Subagent (general-purpose)
**Grok Review:** Required before acceptance
**Dependency:** Can run parallel to Task 1

**Files:**
- MODIFY: `swiftwing/CameraView.swift`

**Changes:**
1. **Error UI** (Line ~210)
   - Replace `print()` with user-visible overlay
   - Use existing Swiss Glass error overlay pattern
   - Auto-dismiss after 5 seconds
   - Show error icon + message

2. **Temp File Cleanup** (Line ~260)
   - Schedule deletion 5 minutes after file creation
   - Use DispatchQueue.global().asyncAfter
   - Gracefully handle file-not-found on cleanup
   - Log cleanup operations

**Acceptance Criteria:**
- [ ] Grok review passes ✅
- [ ] Errors visible to user (not just console)
- [ ] Temp files auto-delete (5min delay)
- [ ] Swiss Glass error styling
- [ ] No breaking changes to Epic 2

---

### Phase 4: Task 3 - Thread Safety Fix (Sequential after Task 2) ⏸ pending
**Owner:** Subagent (general-purpose)
**Grok Review:** Required before acceptance
**Dependency:** Wait for Task 2 (same file conflict)

**Files:**
- MODIFY: `swiftwing/CameraView.swift`

**Changes:**
- Refactor `Task.detached` → structured `Task`
- Ensure MainActor isolation for UI state
- Fix Sendable conformance warnings
- Preserve all existing functionality

**Acceptance Criteria:**
- [ ] Grok review passes ✅
- [ ] Zero Swift 6.2 concurrency warnings
- [ ] Structured concurrency (no detached tasks)
- [ ] All Epic 2 functionality preserved

---

### Phase 5: Grok Quality Gate Reviews ⏸ pending
**Owner:** PM (Claude) + Grok-code-fast-1
**Dependency:** Each task completion

**Review Workflow per Task:**
1. Subagent completes code
2. PM sends to Grok for review
3. Grok evaluates against Epic 2 patterns
4. If PASS → Accept code
5. If FAIL → Iterate with subagent until pass

**Grok Review Criteria:**
- Swift 6.2 concurrency best practices
- Swiss Glass design consistency
- No breaking changes to Epic 2
- Performance impact analysis
- Code quality (readability, maintainability)

---

### Phase 6: Integration Testing ⏸ pending
**Owner:** PM (Claude)
**Dependency:** All tasks pass Grok review

**Tests:**
- [ ] xcodebuild compiles successfully
- [ ] Epic 2 camera still works (manual test)
- [ ] Data seeding works (manual test)
- [ ] Errors display correctly (manual test)
- [ ] Temp files cleanup (wait 5min, verify)
- [ ] No concurrency warnings (compiler output)

---

### Phase 7: Commit & Documentation ⏸ pending
**Owner:** PM (Claude)
**Dependency:** Integration tests pass

**Tasks:**
- [ ] Update findings.md with lessons learned
- [ ] Update progress.md with final status
- [ ] Use /gogo to commit changes
- [ ] Update epic-3.json if needed
- [ ] Mark US-103 and US-322 complete

---

## Parallel Execution Strategy

```
Timeline:

Phase 1: Planning (30min) ━━━━━━━━━━┓
                                    ▼
Phase 2 & 3: Parallel Development  ┃
├─ Task 1: DataSeeder (2h)   ━━━━━━┫
├─ Task 2: Error UI (1.5h)   ━━━━━━┫ ← Grok Review Gate
                                    ▼
Phase 4: Sequential Task 3 (1h)    ┃ ← Grok Review Gate
                                    ▼
Phase 5: Grok Reviews (1h)   ━━━━━━┫
                                    ▼
Phase 6: Integration Test (30min)  ┃
                                    ▼
Phase 7: Commit & Docs (30min)     ┃
                                    ▼
                              EPIC 3 READY ✅
```

**Total:** ~6 hours (with parallelization vs ~8h sequential)

---

## Risk Management

| Risk | Impact | Mitigation |
|------|--------|------------|
| Task 2 & 3 file conflict | High | Sequential execution (Task 3 waits) |
| Grok rejects code | Medium | Iterate with subagent until pass |
| Thread-safety fix breaks camera | High | Extensive manual testing Phase 6 |
| Time overrun (>6h) | Low | Defer Task 3 if critical path |

---

## Grok Quality Gates

**Gate 1: Task 1 (DataSeeder)**
- Review for: SwiftData best practices, sample data quality, debug-only code
- Pass criteria: Clean code, no production impact, diverse data

**Gate 2: Task 2 (Error UI + Cleanup)**
- Review for: Swiss Glass consistency, proper async cleanup, user experience
- Pass criteria: Professional error handling, no memory leaks, clean code

**Gate 3: Task 3 (Thread Safety)**
- Review for: Concurrency correctness, MainActor usage, no data races
- Pass criteria: Zero warnings, structured concurrency, performance maintained

---

## Success Metrics

- ✅ All 3 tasks complete
- ✅ All Grok reviews pass
- ✅ Zero breaking changes
- ✅ Epic 3 US-301 ready to start
- ✅ Code committed and pushed

---

## Notes

- **Priority:** Tasks 1 & 2 are critical; Task 3 is optional (can defer)
- **Philosophy:** Grok validates before acceptance, no rubber-stamping
- **Scope:** Strict - only fix identified issues, no scope creep
- **Quality:** Better to take 7h with quality than 5h with bugs

---

## Errors Encountered

| Error | Phase | Resolution |
|-------|-------|------------|
| (none yet) | - | - |

---

**Last Updated:** 2026-01-22 (Phase 1 in progress)
**Next Action:** Launch 3 parallel subagents + set up Grok reviews
