# CRITICAL BUG: Missing Results Fetch After SSE Completion

## Root Cause Analysis

### What's Happening
1. User captures image ✅
2. Image uploads to Talaria ✅
3. SSE stream shows progress events ✅
4. Talaria identifies 6 books ✅
5. SSE stream sends "completed" event with `resultsUrl` ✅
6. **App ignores resultsUrl and never fetches book data** ❌
7. **No books added to pendingReviewBooks** ❌
8. **Review queue remains empty** ❌

### Evidence from Logs

**SSE "result" events are NOT book data:**
```
event: result
data: {"jobId":"...","status":"enriching_metadata","message":"Enriched bo..."}
```
☝️ This is a STATUS UPDATE, not BookMetadata!

**The actual books are at a URL:**
```
event: completed
data: {"type":"complete","jobId":"...","resultsUrl":"/v3/jobs/ai_scan/sca..."}
```
☝️ The `resultsUrl` contains the actual book array!

### Code Gap

**TalariaService.swift - parseSSEEvent():**
- Line 448: `case "completed"` returns `.complete`
- **MISSING:** Extract and return resultsUrl from data

**CameraViewModel.swift - SSE handling:**
- Line 357: `case .complete` just cleans up
- **MISSING:** Fetch results from URL and process books

### Current parseSSEEvent Implementation
```swift
case "complete", "completed":
    return .complete  // ❌ Loses resultsUrl!
```

**Should be:**
```swift
case "complete", "completed":
    if let jsonData = data.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
       let resultsUrl = json["resultsUrl"] as? String {
        return .complete(resultsUrl: resultsUrl)  // ✅ Preserve URL
    }
    return .complete(resultsUrl: nil)  // No results URL
```

---

## Implementation Plan

### Phase 1: Update SSEEvent Enum (5 min)

**File:** `swiftwing/Services/NetworkTypes.swift`

**Change:** Add resultsUrl parameter to `.complete` case

**Before:**
```swift
case complete  // Job finished successfully
```

**After:**
```swift
case complete(resultsUrl: String?)  // Job finished, fetch results from URL
```

### Phase 2: Update parseSSEEvent (10 min)

**File:** `swiftwing/Services/TalariaService.swift`

**Location:** Lines 448-449

**Implementation:**
```swift
case "complete", "completed":
    // Extract resultsUrl from completion event
    guard let jsonData = data.data(using: .utf8) else {
        return .complete(resultsUrl: nil)
    }

    if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
       let resultsUrl = json["resultsUrl"] as? String {
        print("✅ SSE: Completed with results at: \(resultsUrl)")
        return .complete(resultsUrl: resultsUrl)
    } else {
        print("⚠️ SSE: Completed without resultsUrl")
        return .complete(resultsUrl: nil)
    }
```

### Phase 3: Add fetchResults Method to TalariaService (15 min)

**File:** `swiftwing/Services/TalariaService.swift`

**Add new method after cleanup():**

```swift
/// Fetch scan results from the resultsUrl provided in SSE completion event
/// - Parameter resultsUrl: Relative URL path (e.g. "/v3/jobs/ai_scan/scan_...")
/// - Parameter authToken: Auth token for the job
/// - Returns: Array of BookMetadata objects
func fetchResults(resultsUrl: String, authToken: String) async throws -> [BookMetadata] {
    // Construct full URL
    guard let url = URL(string: baseURL + resultsUrl) else {
        throw NetworkError.invalidRequest
    }

    print("🔍 Fetching results from: \(url.absoluteString)")

    // Create request with auth
    var request = URLRequest(url: url)
    request.addValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    request.httpMethod = "GET"

    // Execute request
    let (data, response) = try await urlSession.data(for: request)

    // Check HTTP status
    guard let httpResponse = response as? HTTPURLResponse else {
        throw NetworkError.invalidResponse
    }

    guard httpResponse.statusCode == 200 else {
        print("❌ Results fetch failed: HTTP \(httpResponse.statusCode)")
        throw NetworkError.serverError(httpResponse.statusCode)
    }

    // Parse JSON response
    // Expected format: {"results": [BookMetadata, ...], "status": "completed", ...}
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let resultsArray = json?["results"] as? [[String: Any]] else {
        throw NetworkError.invalidResponse
    }

    // Decode each book
    var books: [BookMetadata] = []
    for bookJSON in resultsArray {
        let bookData = try JSONSerialization.data(withJSONObject: bookJSON)
        let book = try JSONDecoder().decode(BookMetadata.self, from: bookData)
        books.append(book)
    }

    print("✅ Fetched \(books.count) books from results URL")
    return books
}
```

### Phase 4: Update CameraViewModel SSE Handling (15 min)

**File:** `swiftwing/CameraViewModel.swift`

**Location:** Lines 357-372 (`.complete` case)

**Implementation:**
```swift
case .complete(let resultsUrl):
    let streamDuration = CFAbsoluteTimeGetCurrent() - streamStart
    print("✅ SSE stream lasted \(String(format: "%.1f", streamDuration))s")

    // Fetch actual book results from URL
    if let url = resultsUrl,
       let jid = jobId,
       let authToken = jobAuthTokens[jid] {
        print("📥 Fetching book results from: \(url)")

        do {
            let books = try await talariaService.fetchResults(
                resultsUrl: url,
                authToken: authToken
            )

            print("📚 Received \(books.count) books from results API")

            // Process each book
            for book in books {
                // Encode to raw JSON for debugging
                let rawJSON: String?
                if let jsonData = try? JSONEncoder().encode(book),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    rawJSON = jsonString
                } else {
                    rawJSON = nil
                }

                handleBookResult(metadata: book, rawJSON: rawJSON, modelContext: modelContext)
            }

        } catch {
            print("❌ Failed to fetch results: \(error)")
            // Don't block cleanup on results fetch failure
        }
    } else {
        print("⚠️ No resultsUrl in completion event")
    }

    updateQueueItem(id: item.id, state: .done, message: nil)

    // Cleanup resources (non-blocking)
    await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService, authToken: authToken)

    // Remove auth token (job is done)
    if let jid = jobId {
        jobAuthTokens.removeValue(forKey: jid)
    }

    // Auto-remove from queue after 5 seconds
    await removeQueueItemAfterDelay(id: item.id, delay: 5.0)
```

### Phase 5: Fix Existing .result Case (10 min)

**The current `.result` case is trying to decode wrong data format.**

**File:** `swiftwing/CameraViewModel.swift`
**Location:** Lines 343-356

**Current issue:** "result" events have `status`/`message`, not `BookMetadata`

**Two options:**

**Option A: Keep for backward compatibility (if old API versions send books in stream)**
```swift
case .result(let bookMetadata):
    // Legacy: Some API versions send books in SSE stream
    print("📚 Book identified (legacy stream): \(bookMetadata.title) by \(bookMetadata.author)")

    let rawJSON: String?
    if let jsonData = try? JSONEncoder().encode(bookMetadata),
       let jsonString = String(data: jsonData, encoding: .utf8) {
        rawJSON = jsonString
    } else {
        rawJSON = nil
    }

    handleBookResult(metadata: bookMetadata, rawJSON: rawJSON, modelContext: modelContext)
```

**Option B: Remove entirely (if new API never sends books in stream)**
```swift
// .result case removed - all books fetched from resultsUrl in .complete
```

**Recommendation:** Option A (keep for backward compatibility with older API versions)

---

## Testing Plan

### Test 1: Verify Results Fetch (Happy Path)
1. Clear app data
2. Capture image of book spine
3. Watch Xcode logs for:
   ```
   ✅ SSE: Completed with results at: /v3/jobs/ai_scan/scan_...
   🔍 Fetching results from: https://api.oooefam.net/v3/jobs/ai_scan/scan_...
   ✅ Fetched 6 books from results URL
   🔍 DEBUG: handleBookResult called for: <Book Title>
   📋 Book added to review queue: <Book Title> (pending: 1)
   ```
4. Navigate to Review tab
5. Verify 6 books appear in queue
6. Approve one book
7. Verify it appears in Library tab

### Test 2: Verify Auth Token Usage
1. Capture image
2. Verify fetch request includes `Authorization: Bearer <token>`
3. Verify 200 OK response
4. Verify books parsed correctly

### Test 3: Error Handling
1. Disconnect internet during results fetch
2. Verify error logged but cleanup still happens
3. Verify queue item shows as done (not stuck)

### Test 4: Multiple Books
1. Capture shelf with 5+ books
2. Verify all books fetched
3. Verify all appear in review queue
4. Verify can approve/reject each individually

---

## Success Criteria

- [  ] SSEEvent.complete includes resultsUrl parameter
- [  ] parseSSEEvent extracts resultsUrl from "completed" event data
- [  ] TalariaService.fetchResults() method exists and works
- [  ] CameraViewModel calls fetchResults() on .complete
- [  ] Books are added to pendingReviewBooks after fetch
- [  ] Review tab shows books after SSE completion
- [  ] Can approve books to library
- [  ] Can reject books from queue
- [  ] Auth token is used in fetch request
- [  ] Cleanup still happens if fetch fails

---

## Current Status
**Phase:** Not started
**Blocking Issue:** No results fetch after SSE completion
**Impact:** CRITICAL - Zero books being saved to library

## Next Action
**Start Phase 1:** Update SSEEvent.complete to include resultsUrl parameter

This is the HIGHEST PRIORITY bug - without this, the app cannot save any books.
