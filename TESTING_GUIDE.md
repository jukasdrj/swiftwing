# Testing Guide: Talaria Workflow Fixes

**Date:** 2026-02-03
**Fixes Applied:** All 3 critical fixes complete
**Build Status:** ✅ 0 errors, 0 warnings

---

## Quick Test Plan

### Test 1: Single Book Scan (Deduplication)

**Goal:** Verify no duplicate books appear in Review Queue

**Steps:**
1. Open SwiftWing in Simulator
2. Navigate to Camera tab
3. Snap a single book spine photo
4. Watch processing queue (should show 1 item)
5. Navigate to Review tab

**Expected Result:**
- ✅ Exactly 1 book in Review Queue
- ✅ No duplicate entries
- ✅ Logs show: `📋 Book added to review queue: <title> (pending: 1)`
- ❌ Should NOT see: `⚠️ Duplicate book result suppressed`

**Check Logs:**
```bash
# In Xcode console, filter for:
🔍 DEBUG: handleBookResult called for:
📋 Book added to review queue:
⚠️ Duplicate book result suppressed  # Should NOT appear for single book
```

---

### Test 2: Multi-Book Scan (Deduplication)

**Goal:** Verify each book appears exactly once

**Prerequisites:**
- Enable "EnableMultiBookScanning" in Settings (if feature flag exists)

**Steps:**
1. Snap bookshelf photo with 3-5 books
2. Watch for segmented preview overlay
3. Count processing items (should match detected books)
4. Wait for all to complete
5. Navigate to Review tab

**Expected Result:**
- ✅ Count in Review Queue matches detected books
- ✅ No duplicates
- ✅ Each book has unique title/author

**Check Logs:**
```bash
📚 Detected N books in shelf photo
📋 Book added to review queue: Book 1 (pending: 1)
📋 Book added to review queue: Book 2 (pending: 2)
📋 Book added to review queue: Book 3 (pending: 3)
# Should NOT see multiple "Book 1" entries
```

---

### Test 3: Empty Metadata (Validation)

**Goal:** Verify empty titles/authors are rejected

**Setup:**
Mock Talaria response (or modify handleBookResult temporarily):

```swift
// Temporary test in handleBookResult - ADD AT TOP
if metadata.title == "TEST_EMPTY_TITLE" {
    let emptyMetadata = BookMetadata(
        title: "",
        author: "Test Author",
        isbn: "1234567890"
    )
    handleBookResult(metadata: emptyMetadata, rawJSON: nil, modelContext: modelContext)
    return
}
```

**Steps:**
1. Scan book with title containing "TEST_EMPTY_TITLE"
2. Watch for rejection message

**Expected Result:**
- ✅ Error overlay appears: "Book title is empty - unable to add to review queue"
- ✅ No book in Review Queue
- ✅ Log shows: `❌ Rejected book result: empty title`

**Repeat for empty author:**
```swift
let emptyMetadata = BookMetadata(
    title: "Test Book",
    author: "",
    isbn: "1234567890"
)
```

**Expected:**
- ✅ Error overlay: "Book author is empty - unable to add to review queue"
- ✅ Log shows: `❌ Rejected book result: empty author`

---

### Test 4: Low Confidence Warning (Validation)

**Goal:** Verify low confidence results still pass but are logged

**Setup:**
Mock response with low confidence:

```swift
let lowConfidenceMetadata = BookMetadata(
    title: "Test Book",
    author: "Test Author",
    isbn: "1234567890",
    confidence: 0.2  // 20% confidence
)
```

**Expected Result:**
- ✅ Book appears in Review Queue
- ✅ Log shows: `⚠️ Low confidence result: 20% for 'Test Book'`
- ✅ Book is in "Needs Review" section (red) due to low confidence

---

### Test 5: Results Fetch Failure (Error Recovery)

**Goal:** Verify failed scans stay in queue for retry

**Setup:**
This is harder to test without real backend. Options:

**Option A: Simulate with breakpoint**
1. Set breakpoint in CameraViewModel.swift line 540 (fetchResults call)
2. Manually throw error in debugger
3. Continue execution

**Option B: Mock network failure**
Temporarily modify fetchResults to throw error:

```swift
// In TalariaService.fetchResults
throw NetworkError.serverError(500)  // Temporary test code
```

**Steps:**
1. Scan book
2. Wait for `.complete` event
3. Results fetch fails

**Expected Result:**
- ✅ Item stays in queue (NOT removed)
- ✅ State changes to `.error` (red border)
- ✅ Error message: "Failed to fetch results. Check network and retry."
- ✅ Log shows: `💡 Item kept in queue for manual retry`
- ✅ Item has `retryContext` populated

**Verify Retry Context:**
```swift
// In Xcode debugger:
po processingQueue.first?.retryContext
// Should show: resultsUrl, authToken, jobId
```

---

### Test 6: Manual Retry (Error Recovery)

**Goal:** Verify retry mechanism works

**Prerequisites:**
- Test 5 completed (item in error state with retry context)
- **TODO:** Retry button needs to be added to UI first

**Steps:**
1. Item in error state from Test 5
2. Tap "Retry" button (when implemented)
3. Watch processing queue

**Expected Result:**
- ✅ Item state changes to `.analyzing`
- ✅ Progress message: "Retrying..."
- ✅ Books appear in Review Queue on success
- ✅ Item marked as `.done` and auto-removed after 5s

**Check Logs:**
```bash
🔄 Retrying results fetch for job: <jobId>
📚 Retry successful: Received N books
📋 Book added to review queue: <title> (pending: N)
```

---

## Real Talaria Backend Tests

### Prerequisites
- Access to Talaria API endpoint
- Valid authentication credentials
- Test books with known ISBNs

### Test 7: Understand SSE Event Pattern

**Goal:** Document which events Talaria actually sends

**Steps:**
1. Scan a single book
2. Capture all SSE events

**Method 1: cURL**
```bash
# Get jobId from app logs
curl -N -H "Authorization: Bearer $TOKEN" \
  "https://api.oooefam.net/v3/jobs/scans/$JOB_ID/stream" | tee talaria_events.log
```

**Method 2: Xcode Console**
Enable verbose SSE logging in TalariaService.swift:

```swift
// In streamEvents function, add detailed logging
print("📡 SSE RAW: event=\(event), data=\(data)")
```

**Questions to Answer:**
1. Does Talaria send `.result` for single book? YES / NO
2. Does Talaria send `.complete` for single book? YES / NO
3. Does `.complete` include inline books? YES / NO
4. For multi-book, does Talaria send `.result` per book? YES / NO
5. Are books duplicated in `.result` + `.complete`? YES / NO

**Document findings in:** `TALARIA_EVENT_PATTERNS.md`

---

### Test 8: Duplicate Detection in Wild

**Goal:** Confirm deduplication works with real Talaria

**Based on Test 7 results:**

**Scenario A: If both .result + .complete fire**
- Expected: Deduplication guard suppresses second occurrence
- Check logs for: `⚠️ Duplicate book result suppressed`
- Verify: Exactly 1 book in Review Queue

**Scenario B: If only .complete fires**
- Expected: No deduplication needed
- Check logs: No duplicate suppression messages
- Verify: Exactly 1 book in Review Queue

---

## Debug Commands

### Check Processing Queue State
```swift
// In Xcode debugger (lldb):
po viewModel.processingQueue.count
po viewModel.processingQueue.map { ($0.id, $0.state, $0.retryContext != nil) }
```

### Check Review Queue State
```swift
po viewModel.pendingReviewBooks.count
po viewModel.pendingReviewBooks.map { ($0.metadata.title, $0.scannedDate) }
```

### Force Duplicate Test
```swift
// In handleBookResult, temporarily disable deduplication:
// let isDuplicate = false  // Comment out real logic
```

### Force Validation Test
```swift
// Call handleBookResult directly with test data:
let testMetadata = BookMetadata(title: "", author: "Test", isbn: "123")
viewModel.handleBookResult(metadata: testMetadata, rawJSON: nil, modelContext: modelContext)
```

---

## Performance Benchmarks

### Baseline Metrics (Before Fixes)
- Camera cold start: < 0.5s
- Image processing: < 500ms
- SSE first event: < 500ms

### With Fixes Applied
Expected overhead:
- Deduplication check: < 1ms (array scan is fast)
- Validation check: < 1ms (string trim + isEmpty)
- Error recovery: 0ms (only on error path)

**Should NOT impact happy path performance.**

---

## Regression Tests

### Verify No Breaking Changes

**Test A: Normal Single Book Flow**
1. Scan book
2. Verify appears in Review Queue
3. Approve book
4. Verify appears in Library

**Test B: Multi-Book Flow (if enabled)**
1. Scan bookshelf
2. Verify all books in Review Queue
3. Approve all
4. Verify all in Library

**Test C: Offline Mode**
1. Turn off network
2. Scan book
3. Verify queued with gray border
4. Turn on network
5. Verify auto-upload and appears in Review Queue

**Test D: Rate Limiting**
1. Scan 11 books quickly (exceeds 10/20min limit)
2. Verify rate limit overlay appears
3. Wait for countdown
4. Verify queued scans auto-upload

---

## Known Limitations

### What's NOT Tested Yet
- [ ] UI retry button (needs implementation)
- [ ] Thumbnail data in Review Queue (enhancement)
- [ ] Result verification (enhancement)
- [ ] Real Talaria event patterns (needs backend)

### Edge Cases to Consider
- Book with same title/author but different ISBN
- Book with no ISBN (fallback to title+author matching)
- Network failure during different SSE events
- Very long titles/authors (UI truncation)

---

## Success Criteria

Before declaring production-ready:

- [x] Fix #1 (Deduplication) implemented ✅
- [x] Fix #2 (Error Recovery) implemented ✅
- [x] Fix #3 (Validation) implemented ✅
- [x] Build: 0 errors, 0 warnings ✅
- [ ] Test 1-6 passed (manual tests)
- [ ] Test 7-8 passed (real Talaria)
- [ ] Regression tests passed
- [ ] UI retry button implemented
- [ ] Talaria event patterns documented

---

## Quick Reference: What Changed

| File | Function | What Changed |
|------|----------|--------------|
| CameraViewModel.swift:1058-1073 | handleBookResult | Added deduplication guard |
| CameraViewModel.swift:1058-1080 | handleBookResult | Added validation logic |
| CameraViewModel.swift:540-559 | processCaptureWithImageData | Updated error handler |
| CameraViewModel.swift | retryResultsFetch | New function |
| ProcessingItem.swift | ProcessingItem | Added retryContext field |
| ProcessingItem.swift | ResultsFetchRetryContext | New struct |

---

## Next Steps After Testing

1. If tests pass → Deploy to TestFlight
2. If duplicates found → Adjust deduplication logic
3. If validation too strict → Adjust validation rules
4. If retry doesn't work → Debug retry context storage

**Current Status:** Ready for manual testing with simulator and real backend
