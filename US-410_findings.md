# Findings: US-410 - Performance Optimization (Concurrent SSE Streams)

## Overview
Research and discoveries for implementing concurrent SSE stream performance optimization.

## Current Architecture Analysis

### NetworkActor (Actual Implementation)
- **Location:** `swiftwing/NetworkActor.swift` (495 lines)
- **Pattern:** Actor-based, already thread-safe
- **Key Methods:**
  - `uploadImage(_ imageData: Data)` - Returns `UploadResponse` with `jobId` and `streamUrl`
  - `streamEvents(from streamUrl: URL)` - Returns `AsyncThrowingStream<SSEEvent, Error>`
  - `cleanupJob(_ jobId: String)` - Cleanup server resources
- **Existing Features:**
  - Retry logic with exponential backoff (3 attempts max)
  - 5-minute timeout per SSE stream
  - Rate limiting detection (429 handling)
  - Offline detection

### Current Usage Pattern (CameraView.swift:460-531)
```swift
// Current: Each scan creates its own NetworkActor instance
let networkActor = NetworkActor()
let uploadResponse = try await networkActor.uploadImage(uploadData)
let eventStream = await networkActor.streamEvents(from: uploadResponse.streamUrl)

for try await event in eventStream {
    // Process events...
}
```

**Critical Discovery:**
- ✅ NetworkActor is already an actor (thread-safe)
- ❌ **NO concurrency limiting** - each scan creates unlimited concurrent streams
- ❌ **NO performance logging** - no timing measurements
- ❌ **Each scan creates new NetworkActor instance** (should use shared/injected)

### Current Concurrency Issues
1. **Unlimited Concurrent Streams:** Nothing prevents 50 scans from creating 50 SSE connections
2. **No Queue System:** All scans fire immediately, no throttling
3. **Resource Leak Risk:** With 20+ rapid scans, memory pressure could spike
4. **No Performance Metrics:** Cannot measure upload/stream duration

## Design Decisions

### Concurrency Control Strategy
**Approach:** Actor-based StreamManager with queue

**Rationale:**
- Swift 6.2 actors provide data-race-free concurrency
- Queue ensures fairness (FIFO processing)
- Configurable limits allow tuning per device/scenario

**Configuration:**
- Default max concurrent streams: 5
- Queue capacity: Unlimited (memory permitting)
- Timeout per stream: TBD (check current implementation)

### Performance Metrics
**Key Measurements:**
1. Upload duration (ms) - `POST /v3/jobs/scans`
2. SSE stream duration (s) - From connection to `event: complete`
3. Active stream count - Real-time monitoring
4. Memory usage - Via Instruments (target: < 100 MB @ 10 streams)
5. UI FPS - Via Instruments (target: 60 FPS sustained)

### Proposed Architecture Pattern
```
CameraView.processCapturedImage()
    ↓
StreamManager.executeScanning { [NEW - Queues if over limit]
    ↓
    NetworkActor.uploadImage()
    ↓
    NetworkActor.streamEvents()
} [Existing code wrapped in limiter]
    ↓
StreamManager tracks: activeStreams (max 5)
StreamManager queues: pendingScans (FIFO)
StreamManager logs: upload duration, stream duration
```

**Key Insight:**
- Don't need to modify NetworkActor (it's already correct)
- Wrap usage in StreamManager to add concurrency control
- StreamManager = orchestration layer above NetworkActor

## Technical Discoveries

### Swift 6.2 Concurrency Best Practices
- Use actor for mutable shared state (active stream count, queue)
- AsyncStream for queue event notifications
- Structured concurrency with Task groups for stream lifecycle
- Avoid DispatchSemaphore (deadlock risk with async/await)

### Memory Considerations
- Each SSE connection: ~1-2 MB (URLSession overhead)
- Image buffers: Released after upload completes
- JSON parsing: Minimal impact (small payloads)
- **Risk Area:** Retain cycles in SSE continuation closures

### Performance Logging Format
```swift
// Example log output:
"[NetworkService] Upload took 342ms, SSE stream lasted 4.2s (jobId: abc123)"
"[StreamManager] Active streams: 5/5, Queue depth: 3"
```

## StreamManager Design

### Actor Signature
```swift
actor StreamManager {
    // Configuration
    private let maxConcurrentStreams: Int

    // State
    private var activeStreams: Int = 0
    private var pendingScans: [(UUID, () async throws -> Void)] = []

    // Metrics
    private struct ScanMetrics {
        let scanId: UUID
        let uploadStart: CFAbsoluteTime
        var uploadEnd: CFAbsoluteTime?
        var streamStart: CFAbsoluteTime?
        var streamEnd: CFAbsoluteTime?
    }
    private var activeMetrics: [UUID: ScanMetrics] = [:]

    // Public API
    init(maxConcurrentStreams: Int = 5)

    func executeScanning(
        scanId: UUID,
        operation: @escaping () async throws -> Void
    ) async throws

    func getActiveStreamCount() async -> Int
    func getQueueDepth() async -> Int
}
```

### Execution Flow
1. **Request Arrives:** `executeScanning()` called from CameraView
2. **Check Capacity:**
   - If `activeStreams < maxConcurrentStreams`: Execute immediately
   - Else: Add to `pendingScans` queue
3. **Execute:**
   - Increment `activeStreams`
   - Log start time
   - Execute operation (upload + stream)
   - Log end time
4. **Cleanup:**
   - Decrement `activeStreams`
   - Dequeue next pending scan (if any)
   - Print performance log

### Performance Logging Format
```
[StreamManager] Scan abc-123: Upload 342ms, Stream 4.2s
[StreamManager] Active: 5/5, Queue: 3
```

## Final Implementation

### Approach: Acquire/Release Pattern
**Why not closure-based?**
- Initial attempt: Wrap operation in `@Sendable` closure
- Problem: Closure cannot capture mutable vars (jobId, tempFileURL) or call MainActor methods
- Solution: Acquire/release API preserves MainActor context

### API Design
```swift
// CameraView.swift usage:
await streamManager.acquireStreamSlot(scanId: itemId)  // Suspends if 5 active
defer {
    Task { await streamManager.releaseStreamSlot(scanId: itemId) }
}
// ... upload and stream work happens here ...
```

### Key Features Implemented
1. **Concurrency Limiting:** Max 5 concurrent SSE streams (configurable via `StreamManagerConfig`)
2. **FIFO Queue:** Pending scans wait for slots using `CheckedContinuation`
3. **Performance Logging:**
   - Upload duration: `"Upload took [X]ms"`
   - Stream duration: `"SSE stream lasted [Y]s"`
   - Active count: `"Active: 5/5, Queue: 3"`
4. **Automatic Cleanup:** `defer` ensures release even on errors

### Performance Logging Examples
```
[StreamManager] Scan abc12345: Started (Active: 1/5, Queue: 0)
📤 Upload took 342ms, jobId: job-123
✅ SSE stream lasted 4.2s
[StreamManager] Scan abc12345: Completed in 4542ms (Active: 0/5, Queue: 0)
```

### Error Handling
- `defer` block ensures `releaseStreamSlot()` always called
- Failed streams decrement counter and dequeue next
- Metrics logged even on error paths

## Resolved Questions

1. **Current NetworkActor Design:** ✅
   - No concurrency limiting (ADDED via StreamManager)
   - Cleanup via `cleanupJob()` (already exists)
   - No performance logging (ADDED: upload + stream timing)

2. **Error Handling:** ✅
   - Failed streams decrement counter via `defer` block
   - Automatic dequeuing of next pending scan
   - Errors logged but queue continues processing

3. **Testing Approach:** ✅
   - Manual testing: Rapid tap capture button 20+ times
   - Check console logs for StreamManager output
   - Instruments: Memory Profiler + Core Animation (FPS)

## Performance Targets (Acceptance Criteria)

| Metric | Target | Status | Measurement Method |
|--------|--------|--------|-------------------|
| Max concurrent SSE streams | 5 (configurable) | ✅ Implemented | Code + logs |
| Queue additional scans | FIFO queue | ✅ Implemented | CheckedContinuation |
| Performance logging | Upload + Stream timing | ✅ Implemented | Console logs |
| Memory usage (10 streams) | < 100 MB | ⏳ Needs Instruments | Memory Profiler |
| UI FPS (bulk scanning) | 60 FPS | ⏳ Needs Instruments | Core Animation |
| Stress test | 20+ scans in < 30s | ⏳ Needs manual test | Rapid tapping |

## Manual Testing Instructions

### Test 1: Verify Queue Behavior
1. Open SwiftWing in Simulator
2. Go to Camera tab
3. Rapidly tap capture button 10+ times (as fast as possible)
4. Check Console for StreamManager logs:
   ```
   [StreamManager] Scan abc12345: Started (Active: 1/5, Queue: 0)
   [StreamManager] Scan def67890: Started (Active: 2/5, Queue: 0)
   ...
   [StreamManager] Scan xyz11111: Started (Active: 5/5, Queue: 0)
   [StreamManager] Scan aaa22222: Queued (Active: 5/5, Queue: 1)  ← Should see this
   ```
5. **Expected:** Max "Active: 5/5", additional scans queued
6. **Expected:** As scans complete, queued scans are dequeued

### Test 2: Verify Performance Logging
1. Perform 5+ scans
2. Check Console for timing logs:
   ```
   📤 Upload took 342ms, jobId: job-123
   ✅ SSE stream lasted 4.2s
   [StreamManager] Scan abc12345: Completed in 4542ms (Active: 4/5, Queue: 0)
   ```
3. **Expected:** Every scan shows upload time (ms) and stream duration (s)

### Test 3: Stress Test (20+ Rapid Scans)
1. Rapidly tap capture button 25 times in < 30 seconds
2. Monitor Console for:
   - No crashes or hangs
   - Queue depth never exceeds reasonable limit (< 20)
   - All scans eventually complete
3. **Expected:** App remains responsive, all scans process

## Instruments Profiling (Manual)

### Memory Profiling
1. Open Xcode → Product → Profile → Choose "Leaks" instrument
2. Add "Allocations" instrument
3. Start recording
4. Perform 20 rapid scans
5. Wait for all to complete
6. Check memory usage:
   - **Target:** < 100 MB with 10 active streams
   - Look for memory leaks (should be zero)
   - Check for retain cycles in SSE stream closures

### FPS Profiling
1. Open Xcode → Product → Profile → Choose "Core Animation" instrument
2. Enable "FPS" graph
3. Start recording
4. Perform 15-20 rapid scans while on Camera tab
5. Observe FPS graph:
   - **Target:** Maintain > 55 FPS (iOS 26 displays run at 60 FPS)
   - Check for frame drops during bulk scanning
   - Ensure UI remains responsive (buttons, animations)

## References
- Epic 4 (AI Integration) - SSE implementation details
- CLAUDE.md - Swift 6.2 concurrency patterns
- NetworkService.swift - Existing implementation

## Next Steps
1. Read NetworkService.swift to understand current implementation
2. Design StreamManager actor signature
3. Plan integration points
