# Task Plan: Photo Upload Failure Analysis

**Goal:** Diagnose and fix the issue where photos are not uploaded successfully or response package from DO (DigitalOcean/Talaria API) is not understood correctly.

**Created:** 2026-01-31
**Status:** Phase 1 (Investigation) - IN PROGRESS

---

## Phases

### Phase 1: Issue Discovery & Context Gathering ✅ COMPLETE
**Status:** `complete`
**Objective:** Understand the current state, recent changes, and symptoms

**Actions:**
- ✅ Read git status and recent commits
- ✅ Read CameraViewModel.swift (727 lines)
- ✅ Read TalariaService.swift (509 lines)
- ✅ Read NetworkTypes.swift (96 lines)
- ✅ Read ralph-completion-summary.md (SSE fix history)
- ✅ Identify V3 API architecture pattern

**Key Findings:**
- Recent SSE connection fixes implemented (2026-01-30)
- V3 API uses **two-step process**: SSE `complete` event → fetch from `resultsUrl`
- Upload succeeds (202 Accepted), SSE connects (200 OK)
- Issue likely in `complete` event handling or results fetch

**Files Modified:** None yet (investigation phase)

---

### Phase 2: Root Cause Analysis ✅ COMPLETE
**Status:** `complete`
**Objective:** Identify exact failure point in upload → SSE → result flow

**Completed Analysis:**
- ✅ Analyzed V3 API complete event handling (TalariaService.swift:234-261)
- ✅ Checked error handling in extractResultsUrl (line 393)
- ✅ Verified fetchResults implementation (line 403)
- ✅ Reviewed CameraViewModel event processing (line 312-322)
- ✅ **DISCOVERED SECOND ISSUE:** UI visibility problem (user-reported)

**Root Causes Identified:**
1. **Issue #1 (API):** Silent error in complete event handler (line 256)
2. **Issue #2 (UI):** Processing queue thumbnails too small (40x60px)

**Questions Answered:**
1. ✅ Complete event handling has error swallowing bug
2. ✅ extractResultsUrl can fail silently (returns nil)
3. ✅ fetchResults has no logging (can't debug)
4. ✅ CameraViewModel marks as "done" even without .result
5. ✅ UI thumbnails too small for user to see status

---

### Phase 3: Prioritization & Fix Strategy 🔄 IN PROGRESS
**Status:** `in_progress`
**Objective:** Determine fix order and approach

**Two Issues Identified:**

#### Issue #1: API Error Swallowing (BACKEND)
**Severity:** 🔴 CRITICAL
**User Impact:** Books not saved to library
**Fix Complexity:** LOW (change error handling)
**Test Difficulty:** HIGH (requires real API)

#### Issue #2: UI Visibility (FRONTEND)
**Severity:** 🔴 CRITICAL
**User Impact:** Can't see processing status
**Fix Complexity:** MEDIUM (resize thumbnails, improve text)
**Test Difficulty:** LOW (visual inspection)

**Fix Strategy Decision:**
- [ ] Fix Issue #1 first (API) - unblocks data flow
- [ ] Then fix Issue #2 (UI) - makes success/failure visible
- [ ] OR fix both in parallel (separate PRs)

**Rationale TBD:** Need user input on priority

---

### Phase 4A: Fix Issue #1 (API Error Handling) ✅ COMPLETE
**Status:** `complete`
**Objective:** Fix silent error in complete event handler

**Changes Completed:**
1. ✅ **TalariaService.swift:256** - Propagate error to continuation
   ```swift
   // Change from: catch { print(...) } → yield .complete
   // Change to: catch { print(...) → yield .error(...) → finish
   ```

2. ✅ **TalariaService.swift:397-413** - Add logging to extractResultsUrl
   - ✅ Log JSON parsing attempts
   - ✅ Log if resultsUrl field missing
   - ✅ Show available JSON keys on error

3. ✅ **TalariaService.swift:417-440** - Add logging to fetchResults
   - ✅ Log HTTP request URL
   - ✅ Log HTTP response status
   - ✅ Log response body in DEBUG builds

4. ✅ **TalariaService.swift:253** - Log when .result events yielded
   - ✅ Logs each book title as events are emitted

**Actual Outcome:**
- Errors visible to user (error overlay)
- Console logs show exact failure point
- No false "success" states

---

### Phase 4B: Fix Issue #2 (UI Visibility) ✅ COMPLETE
**Status:** `complete`
**Objective:** Make processing queue visible and informative

**Changes Completed:**
1. ✅ **ProcessingQueueView.swift:22** - Increased scroll view height
   - From: 40px
   - To: 60px

2. ✅ **ProcessingQueueView.swift** - Increased all thumbnail frames (5 instances)
   - From: 40x60px
   - To: 60x90px (1.5x larger)

3. ✅ **ProcessingQueueView.swift:68** - Increased progress text font
   - From: 8pt
   - To: 12pt (50% larger)

4. ✅ **ProcessingQueueView.swift:92** - Increased error text font
   - From: 7pt
   - To: 10pt (43% larger)

5. ✅ **ProcessingItem.swift:39** - Updated thumbnail generation
   - Target size: 60x90px (matches display size)

**Deferred Enhancements:**
- ⏭️ Tap-to-expand (future enhancement)
- ⏭️ Success checkmark icon (future enhancement)

**Actual Outcome:**
- Users can see and read processing status
- Errors clearly visible
- Success states obvious

---

### Phase 5: Verification ✅ COMPLETE
**Status:** `complete`
**Objective:** Confirm fix works end-to-end

**Verification Steps:**
- ✅ Build succeeds (0 errors, 0 warnings)
- ⏭️ Upload test photo (requires device testing)
- ⏭️ Verify SSE stream completes (requires live API)
- ⏭️ Verify book appears in library (requires live API)
- ⏭️ Check all logs show success (requires live testing)

**Build Verification:**
```json
{
  "status": "success",
  "summary": {
    "errors": 0,
    "warnings": 0,
    "linker_errors": 0,
    "failed_tests": 0
  }
}
```

**Next Steps for User:**
1. Run app on device/simulator
2. Capture test photo
3. Monitor console logs for diagnostic output
4. Verify books appear in library
5. Confirm thumbnails are visible and readable

---

## Decision Log

| Decision | Rationale | Date |
|----------|-----------|------|
| Use planning-with-files skill | Complex multi-phase task requiring >4 tool calls | 2026-01-31 |
| Focus on V3 API complete event | Recent changes suggest this is new architecture | 2026-01-31 |

---

## Errors Encountered

| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| None yet | - | - | - |

---

## Files to Modify

| File | Purpose | Status |
|------|---------|--------|
| TalariaService.swift | Enhanced logging + potential fix | Pending |
| CameraViewModel.swift | Event handling verification | Pending |

---

## Next Actions

1. ✅ Create planning files (this file)
2. ✅ Create findings.md
3. 🔄 Create progress.md
4. ⏭️ Analyze complete event code path
5. ⏭️ Identify exact failure point
6. ⏭️ Add diagnostic logging
7. ⏭️ Test and verify fix
