# End-to-End Integration Test Plan: Swiftwing ↔ Talaria

## Overview

This plan demonstrates the full book scanning pipeline: test image → Talaria API → Gemini Vision → enrichment → SSE stream → books in Review queue → Library.

**No camera hardware needed** — uses a bundled test image injected programmatically.

## Prerequisites

- Xcode installed with iOS 26 SDK
- iPhone 17 Pro Max simulator available
- Internet connection (hits real Talaria API at `https://api.oooefam.net`)
- `xcsift` CLI tool installed (xcodebuild output formatter)

## What's Already Built

| Component | Location | Purpose |
|-----------|----------|---------|
| Test image | `test_book_stack.jpg` (in Xcode bundle) | 1.2MB photo of 5 book spines |
| Launch arg | `INJECT_TEST_IMAGE` | Bypasses camera, auto-scans test image |
| Launch arg | `CLEAR_DATA` | Wipes SwiftData for clean slate |
| XCUITest file | `swiftwingUITests/IntegrationUITests.swift` | 2 automated test cases |
| Debug log | `/tmp/swiftwing-integration-test.log` | File-based SSE event trace |

## Quick Run (Automated)

### One Command
```bash
cd /Users/juju/dev_repos/swiftwing

# Run both integration tests
xcodebuild test \
  -project swiftwing.xcodeproj \
  -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:swiftwingUITests/IntegrationUITests \
  2>&1 | xcsift
```

**Expected result:** `passed_tests: 2, failed_tests: 0`

### Verify Debug Log
```bash
cat /tmp/swiftwing-integration-test.log
```

**Expected log entries:**
```
INJECT_TEST_IMAGE: Starting test image injection
INJECT_TEST_IMAGE: Found image in bundle at ...
UPLOAD: Success! jobId=..., streamUrl=...
SSE_STREAM: Connection established, status=200
SSE: progress event: analyzing_image
SSE: progress event: Identified 5 books
SSE: result event: 'This Is How It Always Is' by 'LAURI FRANK'
SSE: result event: 'THE LUMINARIES' by 'ELEANOR CATTON'
handleBookResult: title='...' author='...'
SSE: COMPLETE event!
```

## Detailed Run (With Talaria Log Monitoring)

### Step 1: Start Talaria Log Tail (Terminal 1)
```bash
cd /Users/juju/dev_repos/talaria
npx wrangler tail --format=json 2>&1 | tee /tmp/talaria-tail.log
```

### Step 2: Run Integration Test (Terminal 2)
```bash
cd /Users/juju/dev_repos/swiftwing

# Clear old log
rm -f /tmp/swiftwing-integration-test.log

# Run test
xcodebuild test \
  -project swiftwing.xcodeproj \
  -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:swiftwingUITests/IntegrationUITests/testFullScanPipeline \
  2>&1 | xcsift
```

### Step 3: Analyze Results

**Client side:**
```bash
cat /tmp/swiftwing-integration-test.log
```

**Server side:**
```bash
# Look for the scan job in Talaria logs
grep -i "scan\|gemini\|enrichment\|result" /tmp/talaria-tail.log | head -50
```

**Correlate by jobId** — both logs will reference the same UUID.

## What the Test Does (Step by Step)

### Test 1: `testFullScanPipeline`

1. **App launches** with `INJECT_TEST_IMAGE` + `CLEAR_DATA` args
2. **CameraView `.task`** detects `INJECT_TEST_IMAGE` flag
3. **Loads** `test_book_stack.jpg` from bundle (1.2MB)
4. **Uploads** to `POST https://api.oooefam.net/v3/jobs/scans` (multipart)
5. **SSE stream** connects to `GET .../stream` endpoint
6. **Server pipeline:**
   - Gemini 2.5 Flash analyzes image (~7s)
   - Identifies 5 book spines
   - Enriches each via Google Books waterfall
   - Streams result events (one per book)
   - Sends completed event
7. **Client receives** 5 `.result` SSE events with book metadata
8. **Books appear** in Review queue (pendingReviewBooks)
9. **XCUITest** waits up to 90s for `review_approve_all` button
10. **Taps "Approve All"** → books saved to SwiftData Library
11. **Navigates** to Library tab
12. **Verifies** at least one book cell exists

### Test 2: `testScanWithNetworkAvailable`

- Same flow as Test 1, verifies the pipeline works on a second run
- Confirms no stale state from previous test

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│  XCUITest                                                     │
│  ├── Launch app with INJECT_TEST_IMAGE + CLEAR_DATA          │
│  ├── Wait for review_approve_all button (90s timeout)         │
│  ├── Tap "Approve All"                                        │
│  └── Verify books in Library tab                              │
└─────────────────────┬────────────────────────────────────────┘
                      │ launches
┌─────────────────────▼────────────────────────────────────────┐
│  SwiftwingApp                                                 │
│  ├── CameraView.task { INJECT_TEST_IMAGE handler }           │
│  │   └── Fire-and-forget Task {                               │
│  │       └── processCaptureWithImageData(imageData)           │
│  │           ├── talariaService.uploadScan(imageData)         │
│  │           ├── talariaService.streamEvents(streamUrl)       │
│  │           │   └── AsyncThrowingStream (byte-by-byte SSE)  │
│  │           └── for try await event in stream:               │
│  │               ├── .progress → update UI                    │
│  │               ├── .result → handleBookResult()             │
│  │               │   └── pendingReviewBooks.append(book)      │
│  │               └── .complete → cleanup                      │
│  └── ReviewQueueView                                          │
│       ├── Shows pendingReviewBooks                            │
│       ├── "Approve All" button (a11y: review_approve_all)    │
│       └── Saves to SwiftData Book model                      │
└─────────────────────┬────────────────────────────────────────┘
                      │ HTTPS
┌─────────────────────▼────────────────────────────────────────┐
│  Talaria API (https://api.oooefam.net)                        │
│  ├── POST /v3/jobs/scans                                      │
│  │   └── Returns { jobId, sseUrl, authToken }                │
│  ├── JobStateManagerDO (Durable Object)                       │
│  │   ├── Gemini 2.5 Flash vision analysis                    │
│  │   ├── Google Books enrichment waterfall                    │
│  │   └── broadcastSSEUpdate('result', { book: {...} })       │
│  ├── GET /v3/jobs/scans/{jobId}/stream (SSE)                 │
│  │   ├── event: progress (5+ events)                         │
│  │   ├── event: result (1 per book, nested book:{} object)   │
│  │   └── event: completed (with resultsUrl)                  │
│  └── KV: scan-results:{jobId} (full book data)               │
└──────────────────────────────────────────────────────────────┘
```

## Key Technical Details

### SSE Event Format (Result)
Server sends book data **nested under `book` key**:
```json
{
  "jobId": "uuid",
  "status": "enriching_metadata",
  "message": "Enriched book 2 of 5",
  "progress": 0.5,
  "book": {
    "title": "THE LUMINARIES",
    "author": "ELEANOR CATTON",
    "isbn": null,
    "enrichmentStatus": "success"
  }
}
```

`SSEEventParser` extracts `json["book"]` before decoding `BookMetadata`.

### Fire-and-Forget Pattern
The test image scan uses `Task {}` (not `await`) inside `.task {}` to prevent SwiftUI view lifecycle cancellation. Stored in `activeStreamingTasks[itemId]`.

### Byte-by-Byte SSE Parsing
`TalariaService.streamEvents()` uses `URLSession.bytes(for:)` with manual line parsing (HTTP/3 QUIC compatibility). Each byte is accumulated in `lineBuffer`; newlines trigger line processing.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Test times out at 90s | Talaria API slow or down | Check `https://api.oooefam.net/health` |
| `handleBookResult: title='nil'` | SSEEventParser not extracting `book` dict | Verify `SSEEventParser.swift` case `"result"` extracts `json["book"]` |
| `pendingReviewBooks.count = 0` | Books rejected by validation | Check `handleBookResult` — requires non-empty title AND author |
| SSE stream exits immediately | Task cancelled by SwiftUI | Verify fire-and-forget `Task {}` pattern in CameraView |
| All SSE lines blank | `lineBuffer.append(byte)` missing | Check `TalariaService.swift` byte parser has `else` clause |
| 429 rate limit | Too many test runs | Wait 20 minutes or use different device ID |
| Build fails | Missing test image in bundle | Verify `test_book_stack.jpg` in "Copy Bundle Resources" build phase |

## Bugs Fixed During Development

| # | Bug | Root Cause | Fix Location |
|---|-----|-----------|-------------|
| 1 | SwiftUI `.task` cancellation | `await` in `.task{}` cancelled on re-render | `CameraView.swift` — fire-and-forget Task |
| 2 | Empty SSE line buffer | Missing `lineBuffer.append(byte)` | `TalariaService.swift` — added else clause |
| 3 | BookMetadata nil fields | Decoded from root JSON, not nested `book` | `SSEEventParser.swift` — extract `json["book"]` |

## Expected Timeline

| Phase | Duration | What Happens |
|-------|----------|-------------|
| Build + install | ~30s | Xcode builds, installs on sim |
| App launch | ~2s | SwiftUI loads, camera setup skipped |
| Image upload | ~2s | Multipart POST to Talaria |
| Gemini analysis | ~7-15s | AI identifies book spines |
| Enrichment | ~3-5s | Google Books metadata lookup |
| SSE streaming | ~1s | 5 result events delivered |
| Review UI | ~1s | Books appear, test taps Approve All |
| Library verify | ~1s | Test confirms books saved |
| **Total** | **~45-60s** | End-to-end automated |
