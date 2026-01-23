# Task Plan: US-408 - Rate Limit Handling (429 Too Many Requests)

## Goal
Implement rate limit detection and user-friendly countdown UI when Talaria returns 429 responses, ensuring no scanned images are lost during cooldown periods.

## Phases

### Phase 1: Explore Current Implementation [complete]
- [x] Read NetworkService to understand upload flow
- [x] Read SSE event handling code
- [x] Check if 429 handling already exists (found in NetworkActor.swift:297-301)
- [x] Identify where to add rate limit logic
- [x] Review camera/scanning UI structure

### Phase 2: Implement 429 Detection & Parsing [complete]
- [x] Add 429 status code handling in upload endpoint (already existed in NetworkActor.swift:297-301)
- [x] Parse `Retry-After` header (seconds)
- [x] Create RateLimitState actor for thread-safe state management
- [x] Queue pending scans locally during cooldown

### Phase 3: Build Rate Limit UI [complete]
- [x] Create RateLimitOverlay component with countdown timer
- [x] Implement countdown timer (updates every second)
- [x] Disable shutter button during cooldown (gray, opacity 0.3)
- [x] Show "Rate limit reached. Try again in [countdown]." message
- [x] Display queued scans count

### Phase 4: Auto-Recovery Logic [complete]
- [x] Automatically re-enable shutter when cooldown expires
- [x] Process queued scans after recovery
- [x] Clear rate limit state
- [x] Update countdown every second in startRateLimitCountdown()

### Phase 5: Testing & Verification [in_progress]
- [ ] Test with mocked 429 response (Retry-After: 60)
- [ ] Verify countdown updates correctly
- [ ] Verify shutter disabled during cooldown
- [ ] Verify queued images aren't lost
- [x] Run build with xcsift (0 errors, 0 warnings) ✅

### Phase 6: Quality Check & Commit [pending]
- [x] Final build verification (0 errors, 0 warnings)
- [ ] Commit: `feat: US-408 - Rate Limit Handling (429 Too Many Requests)`
- [ ] Signal completion

## Decision Log
| Decision | Rationale | Alternatives Considered |
|----------|-----------|-------------------------|
| - | - | - |

## Errors Encountered
| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| - | - | - | - |

## Files to Create/Modify
### Created:
- `swiftwing/RateLimitState.swift` - Actor for thread-safe rate limit state management
- `swiftwing/RateLimitOverlay.swift` - UI overlay with countdown timer

### Modified:
- `swiftwing/NetworkActor.swift:228-238` - Changed to throw 429 immediately (no sleep)
- `swiftwing/CameraView.swift` - Added rate limit state, overlay, countdown timer, auto-recovery logic

## Lessons Learned
- TBD
