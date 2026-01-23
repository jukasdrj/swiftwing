# Task Plan: US-410 - Performance Optimization (Concurrent SSE Streams)

## Goal
Implement performance optimization for concurrent SSE streams to ensure smooth bulk scanning with proper resource management and monitoring.

## Success Criteria
- Max 5 concurrent SSE streams (configurable)
- Queue system for additional scans
- Memory usage < 100 MB with 10 active streams
- UI maintains 60 FPS during bulk scanning
- Performance profiling with 20+ rapid scans
- Performance logging for uploads and SSE streams
- Documentation of findings

## Phases

### Phase 1: Analyze Current Architecture [pending]
**Goal:** Understand existing SSE stream management in NetworkService
**Tasks:**
- Read NetworkService.swift to understand current SSE implementation
- Identify where streams are created and managed
- Document current concurrency handling (or lack thereof)
- Identify injection points for concurrency limiting

**Artifacts:**
- Current architecture documented in findings.md

### Phase 2: Design Concurrency Control System [pending]
**Goal:** Design actor-based stream limiter with queue
**Tasks:**
- Design StreamManager actor with max concurrent limit (default 5)
- Design queue system for pending scan requests
- Plan performance logging integration points
- Design configuration structure

**Artifacts:**
- Architecture design in findings.md
- Class/actor signatures

### Phase 3: Implement StreamManager Actor [pending]
**Goal:** Build concurrent stream limiter
**Tasks:**
- Create StreamManager actor with concurrency control
- Implement queue for pending requests
- Add configurable max concurrent streams
- Integrate performance timing (upload duration, stream duration)
- Add memory pressure handling

**Artifacts:**
- StreamManager.swift implementation

### Phase 4: Integrate with NetworkService [pending]
**Goal:** Wire StreamManager into existing flow
**Tasks:**
- Modify NetworkService to use StreamManager
- Update uploadImage and streamEvents methods
- Add performance logging at key points
- Ensure proper cleanup on completion/error

**Artifacts:**
- Updated NetworkService.swift

### Phase 5: Add Performance Monitoring [pending]
**Goal:** Implement logging and metrics
**Tasks:**
- Add performance logging: "Upload took [X]ms, SSE stream lasted [Y]s"
- Create PerformanceMetrics structure
- Log active stream count
- Add memory usage warnings (if feasible)

**Artifacts:**
- Performance logging code

### Phase 6: Build Verification & Profiling [pending]
**Goal:** Verify implementation builds and test basic functionality
**Tasks:**
- Build with xcodebuild | xcsift (zero errors, zero warnings)
- Manual test: Trigger multiple scans rapidly
- Verify queue behavior (max 5 concurrent)
- Verify performance logs appear
- Document manual test results

**Artifacts:**
- Build success confirmation
- Manual test results in progress.md

### Phase 7: Performance Testing with Instruments [pending]
**Goal:** Profile with Instruments for memory and FPS
**Tasks:**
- Set up Instruments profiling session
- Test scenario: 20+ rapid scans in < 30 seconds
- Monitor memory usage (target: < 100 MB with 10 streams)
- Monitor FPS (target: 60 FPS maintained)
- Capture and document results

**Artifacts:**
- Instruments data screenshots/summary
- Performance findings documented

### Phase 8: Documentation & Finalization [pending]
**Goal:** Complete documentation and commit
**Tasks:**
- Add code comments explaining concurrency strategy
- Document configuration options
- Update findings.md with performance results
- Final build verification
- Commit with message: "feat: US-410 - Performance Optimization (Concurrent SSE Streams)"

**Artifacts:**
- Committed code
- Complete documentation

## Decision Log

| Decision | Rationale | Date |
|----------|-----------|------|
| Use actor for StreamManager | Swift 6.2 best practice for mutable shared state | 2026-01-23 |
| Default max 5 concurrent streams | Balance between throughput and resource usage | 2026-01-23 |
| Queue-based approach | Ensures fairness and prevents overwhelming backend | 2026-01-23 |

## Errors Encountered

| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| (none yet) | - | - | - |

## Files to Create/Modify

### New Files:
- `swiftwing/Services/StreamManager.swift` - Actor for concurrency control
- `swiftwing/Models/PerformanceMetrics.swift` - Performance logging structure (optional)

### Modified Files:
- `swiftwing/Services/NetworkService.swift` - Integration with StreamManager
- `US-410_findings.md` - Architecture and performance findings
- `US-410_progress.md` - Session log

## Current Phase
**Phase 1: Analyze Current Architecture**

## Notes
- Must use xcodebuild | xcsift for all builds (mandatory)
- Zero warnings required for completion
- Instruments profiling is critical for acceptance criteria
- Document actual memory/FPS numbers, not assumptions
