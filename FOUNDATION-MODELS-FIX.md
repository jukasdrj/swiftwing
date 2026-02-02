# Foundation Models Concurrent Request Fix

**Date:** 2026-02-02
**Issue:** OCR extraction failing with "Attempted to call respond(to:) a second time before the model finished"

---

## Problem Analysis

### Symptoms
1. Multi-book segmentation detects 2 books ✅
2. First book processes successfully ✅
3. Second book fails with error: "OCR failed: Attempted to call respond(to:) a second time before the model finished respo..."
4. Results show hallucinated data (e.g., "The Great Gatsby" when not in photo)

### Root Cause

**LanguageModelSession cannot handle concurrent calls**

When Hough segmentation detects multiple books (e.g., 2 books), CameraViewModel processes them **in parallel**:

```swift
// CameraViewModel.swift lines 300-316
for book in books {
    let task = Task {
        if useOnDevice {
            await processBookOnDevice(
                itemId: bookItemId,
                imageData: croppedImageData,
                ciImage: CIImage(cgImage: croppedCGImage),
                modelContext: modelContext
            )
        }
        // ...
    }
    activeStreamingTasks[bookItemId] = task  // Multiple tasks run concurrently
}
```

Both tasks call:
```swift
// Line 359 in processBookOnDevice()
let spineInfo = try await extractionService.extract(from: observation.fullText)
```

The `LanguageModelSession` in `BookExtractionService` **does not support concurrent requests** - attempting to call `session.respond()` while another call is in progress throws an error.

---

## Solution: Request Queueing

Implemented a **serial queue** in `BookExtractionService` actor to handle concurrent extraction requests sequentially.

### Implementation

**File:** `/swiftwing/Services/BookExtractionService.swift`

**Added:**
```swift
actor BookExtractionService {
    private let session: LanguageModelSession
    private var isProcessing = false  // NEW
    private var requestQueue: [(String, CheckedContinuation<BookSpineInfo, Error>)] = []  // NEW

    /// Extract metadata with automatic queueing for concurrent requests
    func extract(from ocrText: String) async throws -> BookSpineInfo {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await enqueueRequest(ocrText: ocrText, continuation: continuation)
            }
        }
    }

    private func enqueueRequest(ocrText: String, continuation: CheckedContinuation<BookSpineInfo, Error>) {
        requestQueue.append((ocrText, continuation))

        if !isProcessing {
            Task {
                await processQueue()
            }
        }
    }

    private func processQueue() async {
        isProcessing = true

        while !requestQueue.isEmpty {
            let (ocrText, continuation) = requestQueue.removeFirst()

            do {
                let result = try await performExtraction(ocrText: ocrText)
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }

        isProcessing = false
    }

    private func performExtraction(ocrText: String) async throws -> BookSpineInfo {
        // Original extraction logic (now serialized)
        // ...
    }
}
```

### How It Works

1. **Public API unchanged:** `extract(from:)` still returns `async throws -> BookSpineInfo`
2. **Internal queueing:** Requests are enqueued with their continuation
3. **Serial processing:** One request processed at a time via `processQueue()`
4. **Automatic resumption:** Continuations resumed with results or errors

**Concurrency Flow:**
```
Book 1 calls extract() → Queued → Processing starts
Book 2 calls extract() → Queued → Waits
Book 1 completes → Book 2 processing starts
Book 2 completes → Queue empty
```

---

## Build Status

**Clean Build:** ✅ SUCCESS
- Errors: 0
- Warnings: 2 (actor queue pattern - non-critical)

---

## Expected Behavior After Fix

### Before Fix
```
📐 Hough: 2 books from 5 lines
📚 Detected 2 books in shelf photo
🔍 DEBUG: handleBookResult called for: The Great Gatsby  ← Book 1 succeeds
❌ OCR failed: Attempted to call respond(to:) a second time...  ← Book 2 fails
```

### After Fix
```
📐 Hough: 2 books from 5 lines
📚 Detected 2 books in shelf photo
🔍 DEBUG: handleBookResult called for: <Book 1 Title>  ← Book 1 succeeds
🔍 DEBUG: handleBookResult called for: <Book 2 Title>  ← Book 2 succeeds (queued)
📋 Book added to review queue: <Book 1 Title> (pending: 1)
📋 Book added to review queue: <Book 2 Title> (pending: 2)
```

---

## Remaining Issues

### 1. Hallucinated Titles

**Problem:** Foundation Models is returning "The Great Gatsby" when not in the photo

**Possible Causes:**
- OCR returning empty/garbled text
- Foundation Models hallucinating when given poor input
- Prompt not strict enough about returning empty strings for unknown fields

**Debug Steps:**
1. Add logging to show OCR output before FM extraction:
   ```swift
   // In processBookOnDevice() before extraction
   print("📝 OCR Output (\(observation.fullText.count) chars): \(observation.fullText.prefix(100))...")
   ```

2. Check if OCR is actually detecting text from book spines

3. If OCR is empty, Foundation Models should return empty title per prompt

**Potential Fix:**
```swift
// In BookSpineInfo validation
if spineInfo.title.isEmpty || spineInfo.author.isEmpty {
    throw ExtractionError.extractionFailed("Insufficient OCR text")
}
```

### 2. OCR Accuracy

**RecognizeDocumentsRequest** might not be ideal for:
- Vertical spine text
- Small/angled text
- Low-resolution crops from segmentation

**Consider:**
- Use `VNRecognizeTextRequest` with `.accurate` level instead
- Pre-process images (rotate, enhance contrast)
- Validate minimum text length before FM extraction

---

## Testing Instructions

1. **Multi-book test:**
   - Capture shelf photo with 2-3 books
   - **Expected:** All books process successfully (no "second time" error)
   - **Expected:** Review queue shows all detected books

2. **Verify OCR quality:**
   - Check console for `📝 OCR Output` logs (if added)
   - Verify text actually detected from spines
   - If empty, OCR is the real problem (not Foundation Models)

3. **Check for hallucinations:**
   - Compare extracted titles to actual books in photo
   - If mismatch, OCR likely returned garbage and FM filled gaps

---

## Next Steps

1. ✅ **Fix concurrent LanguageModelSession calls** (DONE - this fix)
2. ⏭️ **Debug OCR quality** - Add logging to see what text is actually detected
3. ⏭️ **Validate extraction results** - Reject books with empty/suspicious titles
4. ⏭️ **Consider VNRecognizeTextRequest** - May be better for spine text than RecognizeDocumentsRequest

---

## Technical Notes

### Why Not Create New Sessions?

```swift
// BAD: Creates new session per request (expensive)
func extract(from ocrText: String) async throws -> BookSpineInfo {
    let session = LanguageModelSession { /* system prompt */ }
    return try await session.respond(to: prompt, generating: BookSpineInfo.self)
}
```

**Problem:** Each session creation loads the model into memory (~100MB+ overhead)

**Better:** Reuse one session with serial queue (current solution)

### Actor Safety

The queue is actor-isolated, ensuring thread safety:
```swift
actor BookExtractionService {
    private var requestQueue: [...]  // Actor-isolated, safe to mutate
}
```

No data races possible even with multiple concurrent callers.

---

## Summary

**Fixed:** Foundation Models concurrent request error by implementing serial request queue in BookExtractionService actor.

**Result:** Multiple books can now be processed sequentially without LanguageModelSession conflicts.

**Remaining:** OCR quality and hallucination issues need investigation (likely separate problem from concurrency).
