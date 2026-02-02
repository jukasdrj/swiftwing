# Epic 6 Sprint 2 - Integration Test Plan

**Test Date:** 2026-02-02
**Build Status:** ✅ 0 errors, 0 warnings
**Feature Flag:** `UseOnDeviceExtraction`

---

## Test Objectives

Verify that Epic 6 Sprint 2 implementation correctly:
1. Toggles between on-device and Talaria pipelines via feature flag
2. Processes books through the on-device OCR+FM pipeline
3. Displays `.extracting` state in Review Queue
4. Opens BookDetailSheetView with editable metadata
5. Saves edited books to SwiftData library
6. Falls back to Talaria when Foundation Models unavailable

---

## Prerequisites

- [x] Build succeeds with 0 errors, 0 warnings
- [x] UseOnDeviceExtraction flag exists in FeatureFlagsDebugView.swift:20
- [x] All 11 implementation tasks completed
- [x] iOS 26+ device or simulator (for Foundation Models availability)

---

## Test Suite

### Test 1: Feature Flag Toggle (ON → On-Device Pipeline)

**Setup:**
1. Launch SwiftWing app in simulator/device
2. Navigate to Settings → Feature Flags
3. Enable "Foundation Models Extraction" toggle

**Execution:**
1. Navigate to Camera tab
2. Point camera at bookshelf OR select test image
3. Tap shutter button to capture
4. Observe processing flow

**Expected Results:**
- ✅ Segmented books appear in processing queue
- ✅ Processing state shows `.extracting` (cyan border)
- ✅ Status message: "Extracting text..." → "Analyzing metadata..."
- ✅ Console logs show:
  - `[On-Device] Starting OCR...`
  - `[On-Device] Extraction complete`
  - NO Talaria API calls (no `POST /v3/jobs/scans`)

**Actual Results:**
- [ ] All expectations met
- [ ] Issues found: ___________________________

---

### Test 2: Review Queue Detail View

**Setup:**
- Continue from Test 1 with processed book in queue

**Execution:**
1. Switch to "Review" tab
2. Tap on a processed book item
3. Verify BookDetailSheetView appears

**Expected Results:**
- ✅ Sheet displays:
  - Book cover thumbnail (if available)
  - Title field (pre-filled from extraction)
  - Author field (pre-filled from extraction)
  - ISBN field (if detected)
  - Confidence badge (color-coded: green ≥90%, yellow ≥70%, red <70%)
  - "Save to Library" button (primary)
  - "Discard" button (secondary)
- ✅ All text fields are editable
- ✅ Focus state works correctly

**Actual Results:**
- [ ] All expectations met
- [ ] Issues found: ___________________________

---

### Test 3: Edit and Save to Library

**Setup:**
- Continue from Test 2 with detail sheet open

**Execution:**
1. Edit title field (e.g., fix OCR error "TH E" → "THE")
2. Edit author field (e.g., add first name)
3. Tap "Save to Library" button
4. Verify sheet dismisses
5. Navigate to Library tab

**Expected Results:**
- ✅ Book saved to SwiftData with edited metadata
- ✅ Book appears in Library grid
- ✅ Tapping book shows correct title/author
- ✅ Processing queue item removed after save

**Actual Results:**
- [ ] All expectations met
- [ ] Issues found: ___________________________

---

### Test 4: Discard Book

**Setup:**
- Process another book with on-device pipeline

**Execution:**
1. Open detail sheet
2. Tap "Discard" button

**Expected Results:**
- ✅ Sheet dismisses
- ✅ Processing queue item removed
- ✅ Book NOT saved to library

**Actual Results:**
- [ ] All expectations met
- [ ] Issues found: ___________________________

---

### Test 5: Feature Flag Toggle (OFF → Talaria Pipeline)

**Setup:**
1. Navigate to Settings → Feature Flags
2. Disable "Foundation Models Extraction" toggle

**Execution:**
1. Navigate to Camera tab
2. Capture another shelf photo
3. Observe processing flow

**Expected Results:**
- ✅ Processing states: `.preprocessing` → `.uploading` → `.analyzing`
- ✅ NO `.extracting` state shown
- ✅ Console logs show Talaria API calls:
  - `POST /v3/jobs/scans`
  - SSE streaming events
- ✅ Results populate in Review Queue (Talaria metadata)

**Actual Results:**
- [ ] All expectations met
- [ ] Issues found: ___________________________

---

### Test 6: Foundation Models Unavailable Fallback

**Setup:**
- Enable UseOnDeviceExtraction flag
- Mock Foundation Models unavailability (or use iOS <26 simulator)

**Execution:**
1. Capture shelf photo
2. Observe fallback behavior

**Expected Results:**
- ✅ Console log: `[On-Device] Foundation Models unavailable, falling back to Talaria`
- ✅ Processing continues via Talaria pipeline
- ✅ Book still appears in Review Queue with Talaria metadata

**Actual Results:**
- [ ] All expectations met
- [ ] Issues found: ___________________________

---

### Test 7: Segmentation Failure Fallback

**Setup:**
- Enable UseOnDeviceExtraction flag

**Execution:**
1. Capture image with NO books (e.g., blank wall)
2. Observe fallback behavior

**Expected Results:**
- ✅ Segmentation fails (no rectangles detected)
- ✅ processMultiBook() catches error
- ✅ Falls back to single-book pipeline: `processCaptureWithImageData`
- ✅ Error state OR offline queue (depending on network)

**Actual Results:**
- [ ] All expectations met
- [ ] Issues found: ___________________________

---

### Test 8: Confidence Badge Color Coding

**Setup:**
- Process multiple books with varying extraction quality

**Execution:**
1. Open detail sheets for different books
2. Verify confidence badge colors

**Expected Results:**
- ✅ High confidence (≥90%): Green badge
- ✅ Medium confidence (70-89%): Yellow badge
- ✅ Low confidence (<70%): Red badge
- ✅ Badge displays percentage (e.g., "92%")

**Actual Results:**
- [ ] All expectations met
- [ ] Issues found: ___________________________

---

### Test 9: Multi-Book Batch Processing

**Setup:**
- Enable UseOnDeviceExtraction flag

**Execution:**
1. Capture shelf photo with 5+ books
2. Wait for all to process
3. Verify queue behavior

**Expected Results:**
- ✅ All segmented books show individual processing states
- ✅ Each book processes through: `.extracting` → `.done`
- ✅ No race conditions or duplicate IDs
- ✅ bookItemId bug fix verified (item.id used, not new UUID())

**Actual Results:**
- [ ] All expectations met
- [ ] Issues found: ___________________________

---

### Test 10: OCR Quality on Real Books

**Setup:**
- Enable UseOnDeviceExtraction flag
- Prepare test images with known book spines

**Execution:**
1. Capture photo of physical bookshelf
2. Review extracted metadata accuracy

**Expected Results:**
- ✅ Titles extracted with >85% accuracy
- ✅ Authors extracted with >80% accuracy
- ✅ ISBNs detected when visible (if present)
- ✅ OCR handles common errors (0/O, 1/l/I confusion)

**Actual Results:**
- [ ] All expectations met
- [ ] Issues found: ___________________________

---

## Performance Benchmarks

### On-Device Pipeline Timing
- [ ] OCR completion: < 2s per book
- [ ] FM extraction: < 3s per book
- [ ] Total on-device time: < 5s per book

### Talaria Pipeline Timing (Comparison)
- [ ] Upload + SSE: ~3-7s per book (network dependent)

### Memory Usage
- [ ] No memory leaks during 10-book batch
- [ ] Peak memory: < 200MB

---

## Known Limitations

1. **Foundation Models requires iOS 26+** - Falls back to Talaria on older devices
2. **OCR quality depends on image clarity** - Blurry/angled spines may extract poorly
3. **No cover image extraction** - On-device pipeline doesn't fetch covers (Talaria does)
4. **Feature flag persists across launches** - UserDefaults stores state

---

## Bug Fix Verification

### Critical Bug: bookItemId Mismatch (Fixed in TODO-7)

**Original Issue:**
- CameraViewModel.swift:294 created `let bookItemId = UUID()`
- ProcessingItem appended to queue had different ID (`item.id`)
- Result: Lookup failures, processing updates never matched queue items

**Fix Applied:**
- Changed to `let bookItemId = item.id` at line 299

**Verification Test:**
1. Capture multi-book shelf photo
2. Check console logs for `updateQueueItem(id:)` calls
3. Verify state updates appear in Review Queue UI

**Expected:**
- ✅ All processing state updates visible in real-time
- ✅ No "item not found" errors in console

**Actual:**
- [ ] Verified - all updates match queue items

---

## Test Completion Criteria

**Sprint 2 is DONE when:**
- [ ] All 10 integration tests pass
- [ ] Performance benchmarks met
- [ ] Bug fix verification confirmed
- [ ] Both pipelines (on-device and Talaria) functional
- [ ] No regressions in Epic 4 Talaria features

---

## Notes

- This test plan covers all 9 user stories (US-A1 through US-C3)
- Tests should be run on iOS 26+ simulator for full Foundation Models support
- Manual testing required (no automated UI tests in this sprint)
- Document any issues found for Sprint 3 backlog

---

## Test Execution Log

**Tester:** _________________
**Date:** _________________
**Device:** _________________
**iOS Version:** _________________

**Overall Result:**
- [ ] ✅ All tests passed
- [ ] ⚠️ Minor issues found (list below)
- [ ] ❌ Critical issues found (block release)

**Issues Found:**
1. _______________________________________________
2. _______________________________________________
3. _______________________________________________

**Sign-off:** _________________
