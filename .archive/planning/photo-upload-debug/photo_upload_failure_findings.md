# Findings: Photo Upload Failure Analysis

**Investigation Date:** 2026-01-31
**Issue:** Photos not uploaded successfully or response package not understood

---

## Repository State

### Git Status
- Branch: `main` (up to date with origin)
- Recent refactoring: CameraViewModel moved to `swiftwing/` (tracked as untracked)
- Build status: Compiles successfully (per documentation)

### Recent Changes (Last 10 Commits)
1. `c73c377` - cleanup and add .mcp.json to gitignore
2. `6b11574` - Implement AVCaptureDevice.RotationCoordinator (camera orientation)
3. `791f514` - Correct camera preview rotation angles
4. `cfef4eb` - Resolve KVO crash and orientation handling
5. `c2d6da8` - Integrate iOS 26 Vision framework

**Key Finding:** No recent commits related to upload/SSE failure

---

## V3 API Architecture Discovery

### Two-Step Result Retrieval Pattern

**Critical Insight:** Talaria V3 API changed from inline results to URL-based fetch.

#### Previous Behavior (V2)
```
SSE event: result
data: { "title": "...", "author": "..." }
→ Direct BookMetadata in event
```

#### Current Behavior (V3)
```
SSE event: complete
data: { "resultsUrl": "/v3/jobs/scans/:jobId/results" }
→ Client must fetch results from URL
```

**Implementation Location:** `TalariaService.swift:234-261`

### Code Flow Analysis

#### Step 1: Upload (Lines 80-167)
```swift
func uploadScan(image: Data, deviceId: String) async throws -> (jobId: String, streamUrl: URL)
```
- ✅ Creates multipart/form-data request
- ✅ Validates 202 Accepted response
- ✅ Parses UploadResponse → (jobId, sseUrl)
- ✅ Logs: "Upload response received"

**Status:** Working (recent fix verified this)

---

#### Step 2: SSE Stream (Lines 174-316)
```swift
nonisolated func streamEvents(streamUrl: URL, maxAttempts: Int = 3) -> AsyncThrowingStream<SSEEvent, Error>
```
- ✅ Connects to SSE endpoint
- ✅ Parses event lines
- ✅ Handles progress events
- ⚠️ **CRITICAL SECTION:** complete event handling (lines 234-261)

**Key Code Path:**
```swift
if event == "complete" {
    // 1. Extract resultsUrl from JSON
    guard let resultsUrl = try self.extractResultsUrl(from: data) else {
        print("❌ SSE: No results URL in complete event")
        throw SSEError.invalidEventFormat
    }

    // 2. Fetch results
    let books = try await self.fetchResults(from: resultsUrl)

    // 3. Emit .result for each book
    for book in books {
        continuation.yield(.result(book))
    }
} catch {
    print("❌ SSE: Failed to process complete event: \(error)")
    // ⚠️ ERROR IS SILENTLY CAUGHT - continues to .complete
}

continuation.yield(.complete)
```

**POTENTIAL BUG IDENTIFIED:** Error catch at line 256 prints to console but:
1. Does NOT throw the error up to continuation
2. Still yields `.complete` event (line 259)
3. CameraViewModel sees `.complete` but never saw `.result`

---

#### Step 3: Extract Results URL (Lines 393-400)
```swift
nonisolated private func extractResultsUrl(from jsonString: String) throws -> URL? {
    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let path = json["resultsUrl"] as? String else {
        return nil  // ⚠️ Returns nil on ANY parsing failure
    }
    return URL(string: "\(baseURL)\(path)")
}
```

**Issue:** Returns `nil` instead of throwing, making debugging hard.

---

#### Step 4: Fetch Results (Lines 403-426)
```swift
private func fetchResults(from url: URL) async throws -> [BookMetadata] {
    var request = URLRequest(url: url)
    request.setValue(self.deviceId, forHTTPHeaderField: "X-Device-ID")

    let (data, response) = try await urlSession.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        throw NetworkError.invalidResponse
    }

    struct JobResultsResponse: Codable {
        let success: Bool
        let data: JobResultsData
    }

    struct JobResultsData: Codable {
        let results: [BookMetadata]
    }

    let resultsResponse = try JSONDecoder().decode(JobResultsResponse.self, from: data)
    return resultsResponse.data.results
}
```

**Observations:**
- ✅ Proper error handling (throws on failure)
- ⚠️ No logging (can't see if this is called)
- ⚠️ No logging of HTTP status or response body

---

#### Step 5: CameraViewModel Event Handling (Lines 312-322)
```swift
case .complete:
    let streamDuration = CFAbsoluteTimeGetCurrent() - streamStart
    print("✅ SSE stream lasted \(String(format: "%.1f", streamDuration))s")

    updateQueueItem(id: item.id, state: .done, message: nil)
    await performCleanup(...)
    await removeQueueItemAfterDelay(id: item.id, delay: 5.0)
```

**Issue:** `.complete` handler marks item as "done" even if NO `.result` was received.

---

## Root Cause Hypothesis

### Most Likely Scenario
1. Upload succeeds → SSE connects → `progress` events received
2. Server sends `complete` event with `resultsUrl`
3. `extractResultsUrl` OR `fetchResults` fails silently
4. Error caught at line 256, logged to console
5. `.complete` event still yielded (line 259)
6. CameraViewModel sees `.complete`, marks as "done"
7. **User sees "success" but no book in library**

### Evidence Supporting This
- Recent SSE fixes (ralph-completion-summary.md) focused on connection, not result handling
- V3 API is new architecture (comments say "V3 Architecture")
- No logging in `extractResultsUrl` or `fetchResults`
- Catch block at line 256 swallows errors

---

## API Response Format (Expected)

### Complete Event Structure
```json
{
  "resultsUrl": "/v3/jobs/scans/1b6df1cc-82c6-4189-a0b3-1d97ff1ea82a/results"
}
```

### Results Endpoint Response
```json
{
  "success": true,
  "data": {
    "results": [
      {
        "title": "Book Title",
        "author": "Author Name",
        "isbn": "1234567890",
        "coverUrl": "https://...",
        "publisher": "Publisher",
        "publishedDate": "2024-01-01",
        "pageCount": 300,
        "format": "Hardcover",
        "confidence": 0.95
      }
    ]
  }
}
```

---

## Questions for Diagnosis

| Question | Answer Method | Priority |
|----------|---------------|----------|
| Is `complete` event received? | Check existing logs | HIGH |
| Does it contain `resultsUrl`? | Add logging to extractResultsUrl | HIGH |
| Does fetchResults succeed? | Add logging with HTTP status | HIGH |
| Are .result events yielded? | Add logging in line 253 | HIGH |
| What's the actual error? | Enhance catch block logging | CRITICAL |

---

## Related Documentation

- **Ralph Completion Summary:** `.omc/ralph-completion-summary.md`
  - Documents SSE connection fixes (2026-01-30)
  - Does NOT mention complete event or results fetch

- **TalariaService Architecture:** `TalariaService.swift:5-36`
  - Actor-isolated for Swift 6.2 concurrency
  - Manual implementation (not auto-generated)
  - V3 API two-step pattern documented in comments

- **CLAUDE.md:** Project guidelines
  - Requires 0 errors, 0 warnings
  - Mandates planning-with-files for complex tasks
  - Epic 4 (Talaria Integration) marked complete

---

---

## ISSUE #2: Processing Queue UI Visibility (USER REPORTED)

### Symptom
**User Report:** "Last validation I saw a tiny image overlaid on the live camera view, but can't touch it or see anything about it."

### UI Analysis

#### ProcessingQueueView Location (CameraView.swift:131-132)
```swift
// Processing queue (40px height above shutter)
ProcessingQueueView(items: viewModel.processingQueue, onRetry: viewModel.retryFailedItem)
    .padding(.bottom, 8)
```

**Positioned:** Above shutter button (80x80px at bottom center)
**Height:** 40px
**Items shown:** Horizontal scroll with 40x60px thumbnails

#### ProcessingThumbnailView Design (ProcessingQueueView.swift:42-129)
- **Size:** 40x60px per thumbnail
- **Border:** 2px state-based color (yellow/blue/green/red/gray)
- **Overlays:**
  - Progress text (8pt font) - "Uploading...", "Looking...", etc.
  - Error icon (16pt) - Red triangle for errors
  - Error message (7pt font, 2 lines max)
  - Retry button (24x24px) - Only for error state

### Problem Analysis

#### Issue 2A: Tiny Thumbnail Size 🔴 CRITICAL
**Current:** 40x60px thumbnails
**Problem:**
- Too small to see details
- Progress text (8pt) nearly unreadable
- Error messages (7pt) illegible
- User can't tell what's happening

**Evidence:** User says "tiny image...can't see anything about it"

#### Issue 2B: Limited Visual Feedback 🟡 MEDIUM
**Current state indicators:**
- Border color only (2px width)
- Progress text overlay (often hidden by image)
- No clear "analyzing" vs "done" distinction

**Problem:**
- Hard to tell if processing is happening
- Success state (green border + auto-remove after 5s) might not be noticed
- User doesn't know when to expect results

#### Issue 2C: No Interactivity (Except Retry) 🟡 MEDIUM
**Current:** Only error items have tap action (retry button)
**Missing:**
- Can't tap thumbnail to see larger preview
- Can't see full error message
- Can't cancel in-progress upload
- No way to see detailed status

### UI Architecture Review

#### What Works ✅
1. State-based border colors (semantic meaning)
2. Retry functionality for errors (US-407)
3. Auto-remove after completion (5s delay)
4. Horizontal scroll for multiple items
5. Count badge when > 3 items

#### What's Broken ❌
1. **Size is too small** (40x60px = 1.5x smaller than standard iOS thumbnail)
2. **Text overlays unreadable** (8pt/7pt fonts)
3. **No way to see details** (no tap-to-expand)
4. **Success state invisible** (green border for 5s then gone)

### Combined Effect: Invisible Success

**Current Flow (User Perspective):**
1. ✅ Tap shutter → White flash (visible feedback)
2. ⚠️ Tiny thumbnail appears (barely visible)
3. ⚠️ Progress text too small to read
4. ⚠️ Green border appears for 5s (user might miss it)
5. ❌ Thumbnail disappears
6. ❌ **No book in library**
7. ❓ User confused: "Did anything happen?"

**Root Cause Combination:**
- **Issue #1** (API): Results fetch fails silently → no book saved
- **Issue #2** (UI): Thumbnail too small → user doesn't see failure indicator

**Result:** User has no idea processing failed because:
- Success message shown (green border)
- No error visible (text too small)
- Item auto-removed before user notices

### Design Comparison

| Element | SwiftWing | iOS Photos | Recommendation |
|---------|-----------|------------|----------------|
| Thumbnail size | 40x60px | 80x80px | **Increase to 60x90px** |
| Progress text | 8pt | 12pt | **Increase to 10-12pt** |
| Tap action | Retry only | Preview | **Add tap-to-expand** |
| Success feedback | 5s border | Checkmark | **Add success checkmark** |
| Error visibility | Tiny text | Alert | **Show alert or sheet** |

---

## Next Investigation Steps

1. ✅ Identified UI visibility issue (Issue #2)
2. Add comprehensive logging to complete event handler (Issue #1)
3. Test with real upload to capture detailed logs
4. Verify API response format matches expectations
5. Check if issue is JSON parsing or HTTP fetch failure
6. **NEW:** Test if users can see processing queue at all
7. **NEW:** Measure actual thumbnail visibility on device
