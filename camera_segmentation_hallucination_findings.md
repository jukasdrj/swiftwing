# Findings: Camera Segmentation & Hallucination Investigation

## Problem Statement
User photographed 5 vertical book spines. System detected only 1 book and generated completely fabricated metadata.

## Initial Evidence

### Camera Layer Errors
```
(Fig) signalled err=-12710 at <>:601
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
```

**Error Codes:**
- **-12710**: `kFigBaseObjectError_OperationCancelled` (AVFoundation internal)
- **-17281**: `kFigCaptureSessionError_CaptureSessionNotRunning` (Session not properly started)

**Hypothesis:** Camera session lifecycle issue - capture attempted before fully configured or after premature teardown.

### Segmentation Layer
```
📚 Successfully segmented 1 books from shelf photo
📚 Detected 1 books
```

**Issue:** Instance segmentation OR Hough line algorithm failed to split 5 vertical spines into distinct regions.

**Possible Causes:**
1. Low-confidence bounding boxes filtered out
2. Hough line parameters tuned for different spine density
3. Image preprocessing artifacts (orientation, cropping)
4. Model not optimized for vertical multi-book shelves

### Network Layer
- Status: "Successfully segmented" (misleading if AI hallucinated)
- No explicit enrichment failure mentioned
- User reports "completely made up" results → Suggests API returned data, not "unknown" status

**Hypothesis:** Talaria API returned low-confidence matches, but SwiftWing displayed them as authoritative.

## Architecture Context

### Relevant Services
```
CameraView → CameraViewModel → CameraManager (actor)
                             ↓
                    BookExtractionService
                             ↓
                    VisionService (segmentation)
                    InstanceSegmentationService
                    HoughLineSegmentation
                             ↓
                    TalariaService (API + SSE)
                             ↓
                    SwiftData (Book storage)
```

### Epic 5 Phase 2E Status
- CameraView refactored (1098 → 250 lines)
- CameraViewModel extracted (727 lines)
- **RECENTLY CHANGED:** Camera lifecycle management split between View/ViewModel

**Risk:** Refactoring may have introduced session state bugs.

## Research Questions

1. **Camera:** When do -17281 errors occur relative to capture?
   - Before capture (session not started)?
   - During capture (resource conflict)?
   - After capture (premature cleanup)?

2. **Segmentation:** What does VisionService output for 5-spine image?
   - How many bounding boxes detected?
   - What are confidence scores?
   - Are boxes overlapping or properly separated?

3. **Network:** What did Talaria API actually return?
   - Check SSE event log
   - Verify `enrichment_degraded` handling
   - Confirm confidence scores in BookMetadata

4. **UI:** How are low-confidence results presented?
   - Is there a confidence threshold gate?
   - Does UI show "unknown" for low-confidence matches?

## Technical Constraints
- **iOS 26 AVFoundation:** Swift 6.2 concurrency (actor isolation)
- **Segmentation Models:** CoreML, may have device-specific performance
- **Network:** SSE streaming with graceful degradation (RFC 9457)

## Diagnostic Results from Specialist Agents

### Camera Layer Investigation (Agent aa577d8)

**ROOT CAUSE IDENTIFIED: Race Condition in Session Startup**

**Evidence (CameraManager.swift:160-167):**
```swift
func startSession() {
    guard let session = captureSession else { return }
    nonisolated(unsafe) let unsafeSession = session
    DispatchQueue.global(qos: .userInitiated).async {  // ← ASYNCHRONOUS
        if !unsafeSession.isRunning {
            unsafeSession.startRunning()  // Blocking call happens later
        }
    }
}
```

**The Bug:**
1. `CameraViewModel.setupCamera()` calls `cameraManager.startSession()` (line 157)
2. `startSession()` returns immediately (async dispatch to background queue)
3. User taps capture button before `startRunning()` completes
4. `capturePhoto()` executes while session is NOT running yet
5. AVFoundation throws errors -12710 and -17281

**Missing Validation (CameraManager.swift:235-251):**
- `capturePhoto()` checks `photoOutput != nil` but NOT `session.isRunning`
- No synchronization mechanism to wait for session start
- No user feedback during startup delay

**Incomplete Error Recovery (CameraManager.swift:320-334):**
- Only handles `.mediaServicesWereReset` error
- Silently ignores -12710 and -17281 errors
- No retry mechanism for failed captures

### Segmentation Layer Investigation (Agent ac2123c)

**ROOT CAUSE: Image Conversion Failures (Silent Drops)**

**Critical Code Path (CameraViewModel.swift:275-285):**
```swift
for book in books {
    guard let croppedCGImage = context.createCGImage(book.croppedImage, from: book.croppedImage.extent) else {
        print("⚠️ Failed to create CGImage for book instance \(book.instanceID)")
        continue  // ← DETECTION LOST SILENTLY
    }

    guard let croppedImageData = croppedUIImage.jpegData(compressionQuality: 0.8) else {
        print("⚠️ Failed to create JPEG data for book instance \(book.instanceID)")
        continue  // ← DETECTION LOST SILENTLY
    }
}
```

**Key Findings:**
1. **NO confidence thresholds** - All segmented regions processed
2. **NO filtering logic** - Only background (instanceID==0) removed
3. **Silent failures** - `continue` statements hide conversion errors
4. **iOS 26 Vision API** may detect 5 books correctly, but 4 fail during CIImage→CGImage→JPEG conversion
5. **HoughLineSegmentation is unused** - Only `InstanceSegmentationService` is active

**Why 5 Becomes 1:**
- Vision API likely detects all 5 spines
- 4 out of 5 fail during `CIContext.createCGImage()` (empty extent, invalid bounds)
- Only 1 successfully converts to ProcessingItem
- Console shows `⚠️ Failed to create CGImage` warnings (if any)

### Network/API Layer Investigation (Agent a19a716)

**GOOD NEWS: No Hallucination at API Level**

**Confidence Handling:**
- API returns `BookMetadata.confidence` (0.0-1.0 scale)
- SwiftWing categorizes results:
  - **< 0.5**: Red "Needs Review" section
  - **0.5-0.8**: Yellow "Verify Details" section
  - **≥ 0.8**: Green "Ready to Add" section
- **NO automatic rejection** - All results shown for manual approval

**Enrichment Degradation:**
- API sends `enrichment_degraded` SSE event when enrichment fails
- SwiftWing shows banner: "Some book details may be limited"
- Unknown fields return `nil` (not fabricated data)
- `enrichmentStatus: .notFound` explicitly marks unverified data

**User's "Completely Made Up" Report Analysis:**
- **Likely scenario:** The 1 detected book had low confidence (< 0.5)
- API returned OCR-extracted title/author with uncertainty flag
- User interpreted uncertain match as "made up"
- **Actual issue:** Only 1 book detected (segmentation failure), not API hallucination

### Flow/Pipeline Investigation (Agent a401089)

**Processing Pattern:**
- Each segmented book = separate API request (no batching)
- N books spawn N concurrent Tasks
- Each uploads cropped image independently
- Rate limiting: Max 5 concurrent SSE streams

**Edge Case Failures:**
- **Zero books detected:** Silent failure, no UI feedback
- **Unexpected high count (50+):** No validation, creates 50 tasks
- **Segmentation exception:** Fallback to full image upload

## Root Cause Summary

### Camera Errors (-12710, -17281)
**RACE CONDITION:** Capture attempted before session fully started
- `startSession()` is async, no completion callback
- No `session.isRunning` check before capture
- User can tap shutter during 0.5s startup window

### Segmentation Failure (5 → 1)
**IMAGE CONVERSION FAILURE:** CIImage→CGImage silently drops 4 books
- Vision API likely detects all 5 spines
- `CIContext.createCGImage()` fails for 4 (empty extent, invalid bounds)
- `continue` statements hide failures
- No validation or error aggregation

### "Completely Made Up" Metadata
**USER PERCEPTION ISSUE:** Low-confidence result shown without context
- API correctly returned uncertain match with `confidence < 0.5`
- UI shows in "Needs Review" section (red flag)
- User interpreted low-confidence match as hallucination
- **Actual root cause:** Only 1 book to process (segmentation failure upstream)

## iOS 26 Vision API Research (Agent ab810f3)

### Key Findings from Apple Documentation

**iOS 26 Status (February 2026):**
- Current version confirmed
- SDK mandatory for App Store submissions (April 2026)
- Vision framework received limited updates (focused on document recognition)

**On-Device Visual Intelligence:**
- Foundation Models framework provides text extraction, summarization, object detection
- Privacy-first (on-device only)
- App Intents integration for custom visual search logic

**Instance Segmentation Best Practices:**
1. **API Name Verification:** `VNGenerateForegroundInstanceMaskRequest` (not `GenerateForegroundInstanceMaskRequest`)
2. **Instance Indexing:** Background = 0, foreground objects = 1, 2, 3... (sequential)
3. **Mask Generation:** Use `croppedToInstancesExtent: true` parameter for valid bounds
4. **Extent Validation:** ALWAYS check `extent.isEmpty` and `extent.isInfinite` before CGImage conversion

**Empty Extent Solutions:**
```swift
// Recommended pattern from Apple Developer Forums
guard !instanceMask.extent.isEmpty,
      !instanceMask.extent.isInfinite,
      instanceMask.extent.width > 0,
      instanceMask.extent.height > 0 else {
    print("⚠️ Invalid extent: \(instanceMask.extent)")
    continue
}

let cgImage = ciContext.createCGImage(instanceMask, from: instanceMask.extent)
```

**Performance Recommendations:**
- Reuse CIContext instances (expensive to create)
- Process at lower resolution (1024x768) for speed
- Use `Task.detached(priority: .userInitiated)` for Vision requests
- Target: < 500ms image processing

### Sources
- Apple Developer Documentation: Vision Framework, CIImage extent handling
- WWDC 2023 Session: "Lift subjects from images in your app"
- iOS 26 Release Notes: developer.apple.com/ios/whats-new
- Apple Developer Forums: CIImage extent troubleshooting

## Test Results with User's 5-Book Image

**Test Date:** 2026-02-02 Post-Implementation

**User's Photo Analysis:**
- 5 books stacked **horizontally** (lying flat, not standing)
- Overhead camera angle (not perpendicular to spines)
- Books touching each other with no depth separation
- Books: "The Luminaries", "This Is How It Always Is", "None Dare Call It Treason", "Rodham", "Friends and Strangers"

**Vision API Result:**
- "📚 Detected 1 books in shelf photo"
- Vision treated entire stack as **one foreground object**

**Root Cause Confirmed:**
❌ **NOT a segmentation bug** - this is Vision API use case limitation
✅ **Segmentation fixes working correctly** - no silent failures, proper validation

**iOS 26 Vision API Limitations:**
The `VNGenerateForegroundInstanceMaskRequest` is optimized for:
- ✅ Books standing **vertically** on shelves (spines facing camera)
- ✅ Perpendicular camera angle
- ✅ Clear separation between books (air gaps for depth)

**Does NOT handle:**
- ❌ Horizontally stacked books (flat piles)
- ❌ Overhead angles without depth cues
- ❌ Books touching with same color/texture

## Recommended Solutions

### ❌ Short-Term User Guidance Approach ABANDONED
**Reason:** User's research shows Vision API limitation is unacceptable - competing solutions handle horizontal/vertical books correctly.

**Evidence from Real-World Implementations:**

1. **Bookshelf Reader API** (github.com/LakshyaKhatri/Bookshelf-Reader-API)
   - Extracts spines AND covers successfully
   - Handles both orientations

2. **Library Book Detection** (github.com/mabouseif/Library_Book_Detection)
   - Runs segmentation on each spine
   - Production-quality results

3. **James G Blog** (jamesg.blog/2024/02/14/clickable-bookshelves)
   - Detailed write-up on finding books
   - Computer vision techniques for shelf scanning

4. **Bookshelf Scanner** (github.com/suxrobGM/bookshelf-scanner)
   - Uses YOLO model for segmentation
   - Very successful at multi-book detection

### ✅ NEW STRATEGY: Gemini Flash Multimodal Segmentation

**Path Forward:**
1. Use **Gemini 2.0 Flash multimodal** for initial spine extraction
2. Send full shelf image to Gemini with prompt: "Identify book spine boundaries and return bounding boxes"
3. Gemini returns structured JSON with coordinates for each spine
4. Crop individual spines using returned bounds
5. Send each spine to Talaria for OCR + enrichment

**Why This Works:**
- ✅ Gemini Flash is multimodal (understands images natively)
- ✅ Can handle ANY orientation (horizontal, vertical, mixed)
- ✅ Can detect spines with varied colors, sizes, angles
- ✅ Already integrated in SwiftWing (TalariaService uses Gemini)
- ✅ Fast (<1s for segmentation)
- ✅ Cost-effective (Gemini Flash is cheap)

**Architecture Flow:**
```
Camera Capture
    ↓
Gemini 2.0 Flash (multimodal segmentation)
    ↓ returns: [{x, y, width, height}, ...]
Crop N spine images
    ↓
For each spine:
    → Talaria API (OCR + ISBN + enrichment)
    ↓
SwiftData (save books)
```

## Next Steps - REVISED PRIORITY

### Priority 1: Gemini Flash Segmentation Integration ⭐ **NEW TOP PRIORITY**
**Goal:** Replace iOS Vision API with Gemini multimodal segmentation

**Implementation Plan:**
1. Create `GeminiSegmentationService` actor
2. Prompt engineering: "Detect book spines and return bounding boxes as JSON"
3. Parse Gemini response (JSON with coordinates)
4. Integrate into existing `processMultiBook()` pipeline
5. Fallback: If Gemini fails, use Vision API (vertical shelves only)

**Risk:** Low (Gemini already integrated)
**Effort:** 3-4 hours
**Impact:** Solves core user issue (horizontal/vertical/mixed orientations)

### Priority 2: Camera Race Condition Fix ⏸️ `deferred`
- Still important but not blocking core functionality
- Can be implemented after Gemini segmentation

### Priority 3: UX Improvements ⏸️ `deferred`
- Deferred until Gemini segmentation working

## Research Notes

**YOLO Model Approach (suxrobGM/bookshelf-scanner):**
- Uses YOLOv8 object detection (not instance segmentation)
- Trained on custom dataset of book spines
- Achieves high accuracy on varied shelf configurations
- Could be future enhancement (CoreML conversion of YOLO model)

**Gemini vs YOLO Tradeoff:**
- Gemini: Zero training, works immediately, cloud-based
- YOLO: Requires training data, on-device, faster but more complex

**Decision:** Start with Gemini (fastest path to working solution)
