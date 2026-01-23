# Findings: US-408 - Rate Limit Handling

## Root Cause Analysis
- User hits Talaria API rate limits (429 Too Many Requests)
- Need to handle gracefully with countdown UI
- Must preserve scanned images during cooldown

## Technical Discoveries

### Acceptance Criteria
1. ✅ Detect 429 response from upload endpoint
2. ✅ Parse Retry-After header (seconds)
3. ✅ Display overlay: "Rate limit reached. Try again in [countdown]."
4. ✅ Disable shutter button during cooldown
5. ✅ Show countdown timer (updates every second)
6. ✅ Auto re-enable shutter when cooldown expires
7. ✅ Queue pending scans locally (preserve images)
8. ✅ Test with mock 429 + Retry-After: 60

## Current Implementation Findings

### NetworkActor.swift (Lines 297-301, 228-238)
- ✅ **429 detection already exists**: `NetworkError.rateLimited(retryAfter: TimeInterval?)`
- ✅ **Retry-After header parsing**: Line 299-300 extracts header as `TimeInterval`
- ✅ **Automatic retry logic**: Lines 228-238 handle retry with sleep
- ❌ **Problem**: Current implementation SLEEPS the network actor, blocking other operations
- ❌ **Problem**: No UI feedback - user sees nothing during rate limit cooldown

### CameraView.swift
- Shutter button: Lines 137-145 (captures and adds to processing queue)
- Processing queue: Lines 133-134 (ProcessingQueueView component)
- Error handling: Lines 499-518 (catch block shows error overlay)
- State management: `@State` variables for queue, errors, alerts

### ProcessingItem.swift
- Processing states: `.uploading`, `.analyzing`, `.done`, `.error`
- Need to add: `.rateLimited` state for cooldown UI
- Already stores: `errorMessage`, `originalImageData` for retry

## Solution Approach

### 1. Add Rate Limit State Management
- Create `RateLimitState` actor to track:
  - `isRateLimited: Bool`
  - `retryAfterDate: Date?`
  - `queuedScans: [Data]` (preserve image data during cooldown)
- Use actor for thread-safe access from UI and network layers

### 2. Modify NetworkActor Upload Logic
- Change `performUploadWithRetry` to NOT sleep on 429
- Instead: throw `NetworkError.rateLimited` immediately
- Let CameraView handle the rate limit state and UI

### 3. Add Rate Limit UI Components
- **Overlay**: Full-screen glass overlay with countdown
  - "Rate limit reached. Try again in [countdown]."
  - Countdown timer updates every second
- **Shutter button**: Disable when rate limited
  - Show visual indicator (gray/disabled state)
- **Processing queue**: Show rate limit status on failed items

### 4. Auto-Recovery Logic
- Timer task that checks `retryAfterDate` every second
- When cooldown expires:
  - Clear rate limit state
  - Re-enable shutter button
  - Process queued scans automatically

## Expert Advice
- None yet

## Open Questions
- ✅ Where is upload endpoint? → `NetworkActor.swift:242-328`
- ✅ Where is shutter button? → `CameraView.swift:137-145`
- ✅ How are scans queued? → `ProcessingItem` in `processingQueue` array
- ✅ Error handling structure? → Catch blocks + overlay UI
