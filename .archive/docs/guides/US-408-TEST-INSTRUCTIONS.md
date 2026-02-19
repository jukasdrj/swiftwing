# US-408 Test Instructions: Rate Limit Handling

## Overview
Tests the 429 Too Many Requests rate limit handling with countdown UI and queued scans.

## Test Setup

### Option 1: Mock Server (Recommended for Testing)
Create a simple mock server that returns 429 responses:

```python
# mock_server.py
from flask import Flask, jsonify
import time

app = Flask(__name__)

@app.route('/v3/jobs/scans', methods=['POST'])
def upload_scan():
    # Return 429 with Retry-After header
    response = jsonify({"error": "Rate limit exceeded"})
    response.status_code = 429
    response.headers['Retry-After'] = '60'  # 60 seconds
    return response

if __name__ == '__main__':
    app.run(port=8080)
```

Then update `NetworkActor.swift:113` to point to `http://localhost:8080` instead of production URL.

### Option 2: Manual Verification (Without Mock Server)
Temporarily modify `NetworkActor.swift:242` to always throw rate limit error:

```swift
func uploadImage(_ imageData: Data) async throws -> UploadResponse {
    // TEST: Force rate limit error
    throw NetworkError.rateLimited(retryAfter: 60.0)

    // Original code commented out:
    // return try await performUploadWithRetry(imageData: imageData, maxRetries: 3)
}
```

## Test Cases

### Test 1: Rate Limit Detection
**Steps:**
1. Launch app in simulator
2. Navigate to Camera tab
3. Tap shutter button to capture image
4. Observe upload fails with 429 error

**Expected:**
- ✅ Rate limit overlay appears immediately
- ✅ Overlay shows "Rate Limit Reached" title
- ✅ Countdown starts at 60 seconds
- ✅ Shutter button becomes gray and disabled (opacity 0.3)

### Test 2: Countdown Timer
**Steps:**
1. Continue from Test 1
2. Watch countdown timer for 10 seconds

**Expected:**
- ✅ Countdown decrements every second (60, 59, 58, ...)
- ✅ Numbers don't jitter (monospacedDigit() modifier)
- ✅ Overlay remains visible throughout

### Test 3: Queued Scans
**Steps:**
1. While rate limited, tap shutter button multiple times (5x)
2. Observe queued scans count in overlay

**Expected:**
- ✅ Shutter button clicks are blocked (button is disabled)
- ✅ Safety check prevents captures
- ✅ No new queue items appear

**Note:** To test queueing properly, remove `.disabled(isRateLimited)` temporarily from shutter button and verify scans ARE queued.

### Test 4: Auto-Recovery
**Steps:**
1. Wait for countdown to reach 0 (or modify `retryAfter` to 10s for faster testing)
2. Observe UI updates

**Expected:**
- ✅ At countdown = 0, overlay disappears
- ✅ Shutter button re-enables (white, opacity 1.0)
- ✅ Queued scans are processed automatically
- ✅ Processing queue shows queued items being uploaded

### Test 5: Rate Limit State Persistence
**Steps:**
1. Trigger rate limit
2. Navigate to Library tab
3. Navigate back to Camera tab
4. Verify countdown is still active

**Expected:**
- ✅ Rate limit state persists across tab switches
- ✅ Countdown continues correctly
- ✅ Overlay remains visible

## Acceptance Criteria Verification

- [x] ✅ **Detect 429 response** - NetworkActor.swift:297-301
- [x] ✅ **Parse Retry-After header** - NetworkActor.swift:299-300
- [x] ✅ **Display rate limit overlay** - RateLimitOverlay.swift
- [x] ✅ **Countdown message** - "Rate limit reached. Try again in [countdown]."
- [x] ✅ **Disable shutter button** - CameraView.swift:147 (.disabled(isRateLimited))
- [x] ✅ **Countdown timer updates** - startRateLimitCountdown() updates every second
- [x] ✅ **Auto re-enable shutter** - When countdown reaches 0
- [x] ✅ **Queue pending scans** - RateLimitState.queueScan()
- [x] ✅ **Test with Retry-After: 60** - Configured in mock setup

## Cleanup After Testing

Remember to revert any temporary changes:
1. Remove mock server URL from NetworkActor.swift
2. Remove any forced rate limit errors
3. Re-enable shutter button if disabled for testing

## Build Verification

```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift
```

**Result:** ✅ 0 errors, 0 warnings
