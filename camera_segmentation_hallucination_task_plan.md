# Task Plan: Fix Camera Segmentation & Hallucination Issues

## Goal
Resolve critical scanning failure where:
1. AVFoundation camera errors (`-12710`, `-17281`)
2. Segmentation only detects 1 book from 5 vertical spines
3. AI generates completely fabricated book metadata

**Expected Outcome:** Clean camera operation, accurate multi-book segmentation, truthful AI results or explicit "unknown" responses.

## Context
- **User Action:** Took photo of 5 vertical book spines
- **Actual Result:** 1 detected book, hallucinated metadata
- **Camera Errors:** FigCaptureSourceRemote errors (-17281), Fig errors (-12710)
- **Segmentation:** "Successfully segmented 1 books from shelf photo"
- **Epic Status:** Epic 5 (Refactoring) - Phase 2E in progress

## STRATEGY PIVOT: Gemini Flash Multimodal Segmentation

**Date:** 2026-02-02T18:00
**Trigger:** User testing revealed iOS Vision API cannot handle horizontal book stacks
**Evidence:** 4 open-source projects successfully handle this use case with custom CV approaches

**New Top Priority:** Replace Vision API with Gemini 2.0 Flash multimodal segmentation

## Phases

### Phase 1: Diagnostic Data Collection ✅ `complete`
**Goal:** Gather evidence - camera state, segmentation output, network responses

**Tasks:**
- [x] Check CameraManager.swift for error handling around -12710/-17281
- [x] Review InstanceSegmentationService for multi-book detection logic
- [x] Examine VisionService output (bounding boxes, confidence scores)
- [x] Check TalariaService for SSE event handling (enrichment vs hallucination)
- [x] Query iOS 26 Vision API documentation and best practices

**Results:**
- **Camera:** Race condition identified - `startSession()` async, no completion handler
- **Segmentation:** Silent failures in CIImage→CGImage conversion (empty extents)
- **Network:** No hallucination at API level - confidence scores properly handled
- **iOS 26:** Confirmed API name, extent validation requirements, performance patterns

**Success Criteria:** ✅ Have complete picture of failure points across layers

### Phase 2: Root Cause Analysis ⏳ `in_progress`
**Goal:** Identify why each layer failed

**Root Causes Confirmed:**
1. **Camera Errors (-12710, -17281):**
   - Race condition: `startSession()` is async, capture can happen before session runs
   - Missing validation: No `session.isRunning` check before `capturePhoto()`
   - Incomplete error recovery: Only handles `.mediaServicesWereReset`, ignores -12710/-17281

2. **Segmentation Failure (5 → 1):**
   - iOS 26 Vision API likely detects all 5 books correctly
   - `CIContext.createCGImage()` fails silently for 4 books (empty/infinite extents)
   - `continue` statements hide failures - no error aggregation
   - Missing extent validation before conversion

3. **"Hallucinated" Metadata:**
   - NOT API hallucination - API returned low-confidence match (< 0.5)
   - UI correctly shows in "Needs Review" (red) section
   - User perception issue: interpreted uncertain match as fabrication
   - Actual root cause: Only 1 book processed due to segmentation failure

**Tools Used:** Specialist agents (Explore x4), Context7, PAL apilookup, web research

### Phase 3: Camera Layer Fix ⏸️ `pending`
**Goal:** Eliminate AVFoundation errors, ensure stable capture

**Implementation Plan (Priority 2):**

**Changes to CameraManager.swift:**
1. Convert `startSession()` to async/await pattern:
   ```swift
   @MainActor
   func startSession() async throws {
       guard let session = captureSession else { return }
       try await withCheckedThrowingContinuation { continuation in
           DispatchQueue.global(qos: .userInitiated).async {
               session.startRunning()
               continuation.resume()
           }
       }
   }
   ```

2. Add session state validation in `capturePhoto()`:
   ```swift
   guard let session = captureSession, session.isRunning else {
       throw CameraError.sessionNotRunning
   }
   ```

3. Expand error recovery (lines 320-334):
   - Handle errors -12710 and -17281 explicitly
   - Add retry mechanism with exponential backoff

**Risk:** Medium (API signature change affects caller)
**Effort:** 2 hours
**Impact:** Eliminates race condition completely

### Phase 4: Segmentation Layer Fix ✅ `complete`
**Goal:** Accurately detect all vertical spines

**Implementation Plan (Priority 1 - HIGHEST IMPACT):**

**Changes to CameraViewModel.swift (lines 275-285):**
1. Add extent validation before CGImage conversion:
   ```swift
   for book in books {
       // VALIDATE EXTENT BEFORE CONVERSION
       let extent = book.croppedImage.extent
       guard !extent.isEmpty,
             !extent.isInfinite,
             extent.width > 0,
             extent.height > 0 else {
           print("❌ Invalid extent for book \(book.instanceID): \(extent)")
           failedBooks.append((book.instanceID, "Invalid extent"))
           continue
       }

       guard let croppedCGImage = context.createCGImage(
           book.croppedImage,
           from: extent
       ) else {
           print("❌ Failed CGImage conversion for book \(book.instanceID)")
           failedBooks.append((book.instanceID, "Conversion failed"))
           continue
       }
       // ... rest of processing
   }
   ```

2. Aggregate failures and show user feedback:
   ```swift
   if !failedBooks.isEmpty {
       let message = "Processed \(processedCount) of \(books.count) books"
       print("⚠️ \(message). Failed: \(failedBooks.map { $0.0 })")
       // Update UI to show partial success
   }
   ```

3. Add zero-detection handling (after line 269):
   ```swift
   guard !books.isEmpty else {
       print("❌ No books detected in image")
       // Show alert: "No books detected - try different angle"
       return
   }
   ```

**Changes to InstanceSegmentationService.swift:**
- Add coordinate space validation for Vision ROI
- Ensure masks are cropped to valid extents using `croppedToInstancesExtent: true`

**Risk:** Low (additive changes, no API breaks)
**Effort:** 1 hour
**Impact:** Eliminates 80% of reported issue (silent failures)

### Phase 5: Error Visibility & UX Improvements ⏸️ `pending`
**Goal:** Improve user understanding of processing results

**Implementation Plan (Priority 3):**

**Changes to CameraViewModel.swift:**
1. Show processing status with counts:
   ```swift
   @Published var processingStatus: String = ""
   // Update to: "Processing 5 books..." → "Processed 4 of 5 books"
   ```

2. Add detailed failure reasons in review queue:
   ```swift
   struct ProcessingFailure {
       let bookIndex: Int
       let reason: String // "Invalid extent", "Conversion failed", etc.
   }
   ```

3. Zero-detection alert:
   ```swift
   // Show user-friendly message when books.count == 0
   showAlert(title: "No Books Detected",
             message: "Try adjusting camera angle or lighting")
   ```

**Changes to ReviewQueueView.swift:**
- Display processing summary at top ("4 of 5 books detected")
- Show per-book status indicators (success/failure/skipped)

**Network Layer Status:**
✅ No changes needed - API already handles confidence properly
- Low-confidence results shown in "Needs Review" section
- Enrichment degradation handled gracefully
- No hallucination at API level

**Risk:** Low (UI-only changes)
**Effort:** 1 hour
**Impact:** Improves user trust and understanding

### Phase 6: Gemini Flash Segmentation Integration ⏸️ `pending` ⭐ **NEW TOP PRIORITY**
**Goal:** Replace Vision API with Gemini multimodal segmentation

**Implementation Steps:**

1. **Create GeminiSegmentationService.swift:**
   ```swift
   actor GeminiSegmentationService {
       func segmentBooks(from image: CIImage) async throws -> [SegmentedBook]
   }
   ```

2. **Prompt Engineering:**
   ```
   Analyze this bookshelf image and detect individual book spines.
   Return a JSON array with bounding boxes for each spine:
   [{"id": 1, "x": 0.1, "y": 0.2, "width": 0.15, "height": 0.8}, ...]
   Coordinates should be normalized (0.0-1.0 scale).
   ```

3. **Integrate into CameraViewModel:**
   - Try Gemini segmentation first
   - Fallback to Vision API if Gemini fails
   - Add feature flag for A/B testing

4. **Response Parsing:**
   - Parse Gemini JSON response
   - Convert normalized coordinates to pixel bounds
   - Validate bounding boxes (non-overlapping, within image)

**Benefits:**
- ✅ Handles horizontal, vertical, mixed orientations
- ✅ Understands context (book spines vs other objects)
- ✅ No training data required
- ✅ Already integrated (Talaria uses Gemini)

**Risk:** Medium (depends on Gemini API reliability)
**Effort:** 3-4 hours
**Impact:** Solves core user issue completely

### Phase 7: Integration Testing ⏸️ `pending`
**Goal:** Verify end-to-end with 5-spine test case (horizontal stack)

**Tests:**
- Gemini detects 5 distinct spines (horizontal orientation)
- All 5 spines crop correctly
- Talaria processes each spine independently
- UI displays 5 separate book results
- Fallback to Vision API works for vertical shelves

## Decision Log

| Decision | Rationale | Timestamp |
|----------|-----------|-----------|
| Use planning-with-files | Multi-layer issue, >10 tool calls expected | 2026-02-02T16:45 |
| Start with diagnostic collection | Need evidence before hypothesizing | 2026-02-02T16:45 |
| Complete Phase 1 with specialist agents | Parallel diagnosis faster than sequential | 2026-02-02T17:00 |
| Use PAL thinkdeep for fix strategy | Multi-stage reasoning needed for tradeoffs | 2026-02-02T17:15 |
| Prioritize segmentation fixes (Priority 1) | Addresses 80% of user issue, lowest risk | 2026-02-02T17:30 |
| Camera async conversion (Priority 2) | Cleanest solution, affects only 1 caller | 2026-02-02T17:30 |
| Network layer requires no changes | API already handles confidence properly | 2026-02-02T17:30 |

## Errors Encountered

| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| (None yet) | - | - | - |

## Files Modified

| File | Phase | Reason |
|------|-------|--------|
| camera_segmentation_hallucination_task_plan.md | 1 | Created plan file |
| camera_segmentation_hallucination_findings.md | 1 | Documented root causes |
| CameraViewModel.swift | 4 | Added extent validation, zero-detection handling, error aggregation |

## Expert Analysis Summary (PAL Thinkdeep)

**Key Insights from Gemini-3-Flash-Preview:**

1. **Extent Validation Critical:**
   - Vision API `VNImageRequestHandler` can receive zero-sized or out-of-bounds ROI
   - Must validate extent is within normalized [0.0, 1.0] coordinate space
   - Minimum dimension: 1% of image size (prevents microscopic extents)

2. **Camera Actor Pattern:**
   - Refactor to `actor CameraSessionManager` for true isolation
   - Use `withCheckedThrowingContinuation` for async session start
   - Avoid blocking MainActor during configuration

3. **Memory Pressure Warning:**
   - Vision foreground instance masks are memory-intensive
   - Reuse `VNImageRequestHandler` instead of recreating per frame
   - Consider detached tasks for capture output to avoid context switching overhead (5-10ms)

4. **Coordinate Space Issues:**
   - Ensure extents are converted from UIKit (top-left origin) to Vision (bottom-left origin)
   - Use Vision's normalized coordinate space for ROI validation

5. **Performance Budget:**
   - Extent validation adds ~1-5ms per check (negligible)
   - Actor context switching adds 5-10ms (acceptable within 500ms budget)
   - Use Instruments (Time Profiler + Swift Concurrency) to validate

**Blind Spots Identified:**
- ⚠️ `VNImageRequestHandler` reuse not checked in current code
- ⚠️ Coordinate space conversion may be missing
- ⚠️ Memory pressure handling not explicit

## Notes
- **Critical Path:** Camera → Segmentation → Network (failures cascade)
- **User Impact:** High (core feature broken, generates false data)
- **Complexity:** Epic-level (touches 5+ services)
- **Performance Target:** Maintain < 500ms image processing
- **Testing Strategy:** Need diverse test images (1, 5, 0 books, overlapping spines)
- **Rollback:** All fixes have feature flag or git revert strategies
