# Talaria API Compliance Plan

**Revision:** 2 (Critic feedback incorporated)
**Reviewer:** Critic agent (Opus)
**Revision Date:** 2026-02-01

---

## Source of Truth

### Authoritative API Specifications

The gap analysis and this plan are based on two **external** specification documents from the Talaria backend repository. These files are NOT in the SwiftWing repo -- they live in the Talaria backend codebase and were provided to the planner during the research phase.

**External File Locations (read-only reference for workers):**
- `/Users/juju/dev_repos/talaria/docs/API_FLOW_DIAGRAM.md` -- Visual communication flow, SSE event sequences, reconnection protocol, error handling patterns
- `/Users/juju/dev_repos/talaria/docs/API_INTEGRATION_GUIDE.md` -- Complete endpoint contracts, response envelopes, SSE event schemas, known inconsistencies

**Why these are authoritative over the committed OpenAPI spec:**
The committed OpenAPI spec (`talaria-openapi.yaml` v3.0.0) is outdated (GAP-13). It does not document: `enrichment_degraded` events, `ping` events, inline `books[]` in completed events, `?format=lite`, RFC 9457 error format, or `Last-Event-ID` support. The external docs above represent the live API contract.

### Key API Contract Excerpts (Inlined for Worker Reference)

#### Upload Response Envelope (202 Accepted)
```json
{
  "success": true,
  "data": {
    "jobId": "abc-123",
    "authToken": "a1b2c3d4e5f6...",
    "sseUrl": "/v3/jobs/scans/abc-123/stream",
    "statusUrl": "/v3/jobs/scans/abc-123"
  },
  "_links": { "self": {...}, "stream": {...}, "cancel": {...} },
  "metadata": { "timestamp": "...", "requestId": "..." }
}
```

#### RFC 9457 Error Response (ALL HTTP 4xx/5xx)
```json
{
  "success": false,
  "type": "https://api.oooefam.net/errors/rate-limit-exceeded",
  "title": "Rate Limit Exceeded",
  "status": 429,
  "detail": "Too many requests from device",
  "instance": "/v3/jobs/scans",
  "code": "RATE_LIMIT_EXCEEDED",
  "retryable": true,
  "retryAfterMs": 60000,
  "metadata": {
    "timestamp": "2026-02-01T12:00:00.000Z",
    "requestId": "req-xyz-789"
  }
}
```

#### SSE Event Types (5 total)
```
progress           -> { type, jobId, status, progress, processedCount, totalCount, message, currentItem }
completed          -> { type, jobId, resultsUrl, summary, books? }   // books MAY be stripped (128KB DO limit)
error              -> { type, jobId, code, message, retryable }      // Simplified format, NOT RFC 9457
ping               -> { type, timestamp }                            // Every 30s keepalive
enrichment_degraded -> { type, jobId, isbn, title, reason, fallbackSource, timestamp }
```

#### SSE Event IDs
Events carry `id:` fields (format: `{timestamp}-{type}`, e.g., `1738419600000-progress`). Client MUST track and send `Last-Event-ID` header on reconnection. Server buffers events for 60 seconds.

#### Results Endpoint Response
```
GET /v3/jobs/scans/:jobId/results?format=lite
```
```json
{
  "success": true,
  "data": {
    "jobId": "abc-123",
    "status": "completed",
    "results": [
      {
        "title": "...", "author": "...", "isbn": "...",
        "confidence": 0.95, "enrichmentStatus": "success",
        "coverUrl": "https://..."
      }
    ]
  }
}
```
**Note:** The results endpoint returns `data.results` (not `data.books`). The SSE `completed` event uses `books` for inline data. These field names differ intentionally.

#### Known Inconsistencies (from API Integration Guide)
1. **Dual Error Formats:** HTTP errors use RFC 9457; SSE errors use simplified `{ type, code, message, retryable }`
2. **Books Array Stripping:** SSE `completed` may omit `books[]` (128KB DO limit) -- fall back to `/results`
3. **Status Enum Ambiguity:** Three "status" concepts: job status, scan stage, enrichment status
4. **Token Reuse Confusion:** SSE tokens reusable, WebSocket tokens one-time-use
5. **Buffered Event Timing:** Event `id:` uses delivery timestamp, `data.timestamp` uses original event time

---

## Context

### Original Request
Ensure SwiftWing's TalariaService implementation fully complies with the Talaria backend API v3 specifications as documented in the external API Flow Diagram and API Integration Guide.

### Current State Summary
- **TalariaService** (`/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift`): Actor-based network service, 569 lines
- **NetworkTypes** (`/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift`): Domain types (NetworkError, UploadResponse, BookMetadata, SSEEvent, SSEError), 113 lines
- **CameraViewModel** (`/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`): Primary consumer, 1058 lines
- **Integration Tests** (`/Users/juju/dev_repos/swiftwing/swiftwingTests/TalariaIntegrationTests.swift`): 7 test methods, 366 lines
- **Unit Tests** (`/Users/juju/dev_repos/swiftwing/swiftwingTests/TalariaServiceTests.swift`): SSEEvent references at lines 95, 117, 149, 195, 299
- **Mock Objects** (`/Users/juju/dev_repos/swiftwing/swiftwingTests/MockURLSession.swift`): References `NetworkTypes.SSEEvent` at lines 13, 37
- **Simple Mock** (`/Users/juju/dev_repos/swiftwing/swiftwingTests/SimpleURLSessionMock.swift`): References `NetworkTypes.SSEEvent` at lines 8, 9, 17, 50
- **Comprehensive Tests** (`/Users/juju/dev_repos/swiftwing/swiftwingTests/SwiftWingComprehensiveTests.swift`): SSEEvent construction tests at lines 77-141
- **OpenAPI Spec** (`/Users/juju/dev_repos/swiftwing/swiftwing/OpenAPI/talaria-openapi.yaml`): v3.0.0, committed spec (outdated)
- **Book Model** (`/Users/juju/dev_repos/swiftwing/swiftwing/Models/Book.swift`): SwiftData @Model, 83 lines

### Architectural Decisions (Critic Questions Resolved)

**Q1: Should RFC 9457 ProblemDetails be shared across all network services or scoped to TalariaService?**
**Decision: Scoped to TalariaService.** ProblemDetails is defined in NetworkTypes.swift (which is the Talaria-specific types file), but the struct itself is generic enough to be reused if other services adopt RFC 9457 later. For now, only TalariaService parses it. No shared protocol or base service needed.

**Q2: For SSE parsing testability - is extracting SSEEventParser struct acceptable?**
**Decision: Yes. Extract SSEEventParser as an internal struct.** This addresses the testability blocker where `parseSSEEvent` is `nonisolated private` on TalariaService (line 486) and cannot be tested from the test target. The parser struct will have `internal` access, enabling direct unit testing via `@testable import`.

### Research Findings: Gap Analysis

After auditing the current implementation against the backend API specifications, the following compliance gaps were identified:

---

## GAP ANALYSIS: 14 Compliance Issues Found

### CRITICAL (Must Fix - Data Loss or Integration Failure Risk)

**GAP-1: Missing RFC 9457 Problem Details Error Parsing**
- **Spec**: ALL error responses use RFC 9457 format: `{ success: false, type, title, status, detail, code, retryable, metadata }`
- **Current**: `NetworkError` enum has no structured error parsing. HTTP errors throw generic `NetworkError.serverError(Int)` or `NetworkError.invalidResponse` without reading the response body.
- **Impact**: Loses critical error context (retryable flag, error codes, metadata). Cannot distinguish between "retryable" and "permanent" failures.
- **Files**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift`, `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift`

**GAP-2: Books Array Stripping Not Handled (Known Issue #2)**
- **Spec**: SSE `completed` event may have `books[]` array STRIPPED due to 128KB DigitalOcean limit. Client MUST fall back to `/results?format=lite` endpoint.
- **Current**: The `fetchResults` method exists and CameraViewModel calls it on `.complete(resultsUrl:)`, but uses a hardcoded `ResultsResponse` struct with `results` field instead of the actual API response format. The spec says the results endpoint returns `{ success: true, data: { jobId, status, results: [...] } }`.
- **Impact**: Results fetching may silently fail if the response structure doesn't match expectations.
- **Files**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift` (lines 391-443)

**GAP-3: SSE Completed Event Missing `books[]` Inline Handling**
- **Spec**: When the SSE `completed` event DOES contain `books[]` inline (under 128KB), the client should parse them directly without a separate HTTP call.
- **Current**: `parseSSEEvent` for `complete`/`completed` only extracts `resultsUrl` from the JSON. If `books[]` is present inline, it is silently ignored. CameraViewModel always fetches from resultsUrl, making an unnecessary HTTP round-trip when books are available inline.
- **Impact**: Unnecessary network round-trip, increased latency for users.
- **Files**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift` (lines 510-523), `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift` (SSEEvent enum)

**GAP-4: Dual Error Format Handling (Known Issue #1)**
- **Spec**: HTTP error responses use RFC 9457 format, but SSE `error` events use simplified format: `{ type, jobId, code, message, retryable }`
- **Current**: SSE error parsing only extracts `message` field. Missing `code`, `retryable`, and `jobId` fields from SSE error events.
- **Impact**: Cannot determine if SSE errors are retryable. Cannot correlate SSE errors to jobs via `jobId`.
- **Files**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift` (lines 525-533), `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift`

### HIGH (Should Fix - Degraded User Experience)

**GAP-5: SSE Reconnection Missing Last-Event-ID**
- **Spec**: SSE reconnection should send `Last-Event-ID` header. Server buffers events for 60 seconds. Client should extract `id:` field from SSE events and send it on reconnect.
- **Current**: `streamEvents` retry logic reconnects but does NOT send `Last-Event-ID` header. Does NOT parse `id:` field from SSE event lines.
- **Impact**: On reconnect, client misses events that occurred during the disconnection window. May cause partial results or stuck processing state.
- **Files**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift` (lines 176-303)

**GAP-6: Missing `enrichment_degraded` SSE Event**
- **Spec**: SSE stream can emit `enrichment_degraded` event per degraded book. Format: `{ type, jobId, isbn, title, reason, fallbackSource, timestamp }`
- **Current**: `parseSSEEvent` switch-case has no handler for `enrichment_degraded`. Falls through to `default` case which throws `SSEError.invalidEventFormat` and logs a warning.
- **Impact**: Enrichment degradation goes unreported to user. May cause confusion when results have lower quality metadata.
- **Files**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift` (lines 562-567), `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift`

**GAP-7: Missing `ping` SSE Event Handling**
- **Spec**: Server sends `ping` events as keepalives every 30 seconds to prevent connection timeout.
- **Current**: No handler for `ping` events. Falls through to default case which throws `SSEError.invalidEventFormat`.
- **Impact**: Each ping event generates an error log and yields `.error("Failed to parse event...")` to the CameraViewModel, polluting the error state.
- **Files**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift` (lines 562-567)

**GAP-8: Results Endpoint URL Format Mismatch**
- **Spec**: Results endpoint is `GET /v3/jobs/scans/:jobId/results?format=lite`. The `?format=lite` query parameter is REQUIRED for optimal response size.
- **Current**: `fetchResults` takes a `resultsUrl: String` parameter and uses it as-is from the SSE event. Does not append `?format=lite` if missing. Also, the response struct assumes `{ results: [...] }` but spec says `{ success: true, data: { jobId, status, results: [...] } }`.
- **Impact**: May receive full (larger) response instead of lite format. Response parsing may fail due to struct mismatch.
- **Files**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift` (lines 391-443)

### MEDIUM (Robustness Improvements)

**GAP-9: Status Enum Ambiguity Not Modeled (Known Issue #3)**
- **Spec**: Three different "status" contexts exist:
  - Job status: `initialized | processing | completed | failed | canceled`
  - Scan stage: `analyzing_image | identifying_books | enriching_metadata | complete`
  - Enrichment status per book: `pending | success | not_found | error | circuit_open | review_needed`
- **Current**: No Swift enums model these status values. Progress messages are treated as opaque strings.
- **Impact**: Cannot programmatically react to specific scan stages (e.g., show different UI for "enriching" vs "analyzing"). Cannot detect `review_needed` enrichment status.
- **Files**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift`

**GAP-10: X-Device-ID Header Inconsistency**
- **Spec**: X-Device-ID must be UUID v4 format, REQUIRED on ALL scan endpoints. Same device ID should persist across app sessions.
- **Current**: `TalariaService.init` generates a new `UUID().uuidString` each time. `CameraViewModel.processCaptureWithImageData` generates a DIFFERENT `UUID().uuidString` per scan operation (line 307). The `uploadScan` method takes `deviceId` as a parameter, creating potential for mismatches.
- **Impact**: Backend may create multiple device profiles for same physical device. Rate limiting may not work correctly across sessions.
- **Files**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift` (lines 56, 80), `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift` (line 307)

**GAP-11: Auth Token Lifetime Not Tracked**
- **Spec**: Auth tokens (authToken) have a 2-hour lifetime. They are reusable (multiple SSE connections allowed).
- **Current**: Auth tokens are stored per-job in `CameraViewModel.jobAuthTokens` and discarded after job completion. No expiry tracking. No reuse across jobs.
- **Impact**: If a job takes >2 hours (unlikely but possible with offline queue), SSE reconnection would fail with expired token. Tokens are not reused across multiple uploads (each gets fresh token from server, which is fine but suboptimal).
- **Files**: `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift` (lines 41, 310-316)

**GAP-12: Missing `X-Device-ID` on fetchResults Request**
- **Spec**: X-Device-ID header required on ALL scan endpoints.
- **Current**: `fetchResults` only sends `Authorization: Bearer {authToken}`. Missing `X-Device-ID` header.
- **Impact**: May receive 400 error from server if X-Device-ID validation is strict.
- **Files**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift` (lines 400-404)

### LOW (Spec Alignment - Non-Breaking)

**GAP-13: OpenAPI Spec Outdated**
- **Spec**: Backend supports `enrichment_degraded`, `ping`, inline `books[]` in completed event, `?format=lite`, RFC 9457 errors.
- **Current**: Committed OpenAPI spec (`talaria-openapi.yaml`) v3.0.0 does not document these features (SSECompleteEvent is "Empty object", no enrichment_degraded, no ping, no RFC 9457 schema).
- **Impact**: Spec drift. OpenAPI spec no longer accurately represents the live API.
- **Files**: `/Users/juju/dev_repos/swiftwing/swiftwing/OpenAPI/talaria-openapi.yaml`

**GAP-14: Missing `BookMetadata.enrichmentStatus` Field**
- **Spec**: Each book in results has `enrichmentStatus` field: `pending | success | not_found | error | circuit_open | review_needed`.
- **Current**: `BookMetadata` struct has no `enrichmentStatus` property. This information is lost during deserialization.
- **Impact**: Cannot show users which books need manual review due to failed enrichment.
- **Files**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift` (lines 51-61), `/Users/juju/dev_repos/swiftwing/swiftwing/Models/Book.swift`

### OUT OF SCOPE (Documented Exclusions)

**Known Issue #5: Buffered Event Timing** -- LOW priority, documented but not addressed in this plan.
- **Problem**: Buffered events use original timestamps in `data.timestamp` but delivery timestamps in `id:` field. Client may be confused by mismatch.
- **Reason for exclusion**: This is a server-side behavior that cannot be fixed client-side. The correct client workaround (use `id:` for ordering, `data.timestamp` for display) is straightforward and does not require code changes beyond what Task 2.4 (Last-Event-ID tracking) already implements.
- **Future**: If user feedback indicates confusion, add a `deliveredAt` timestamp to the client event model.

---

## Work Objectives

### Core Objective
Bring TalariaService, NetworkTypes, and CameraViewModel into full compliance with the Talaria backend API v3 specifications, ensuring robust error handling, proper SSE event processing, and resilient reconnection behavior.

### Deliverables
1. **Updated NetworkTypes.swift** with RFC 9457 error model, status enums, enrichment types
2. **New SSEEventParser.swift** extracted from TalariaService for testability
3. **Updated TalariaService.swift** with compliant response parsing, SSE reconnection, all event types
4. **Updated CameraViewModel.swift** with inline books handling, enrichment status, persistent device ID
5. **Updated OpenAPI spec** reflecting actual backend API contract
6. **Updated ALL test files** covering compliance gaps and type changes
7. **Updated Book.swift** with enrichmentStatus field

### Definition of Done
- All 14 gaps addressed (CRITICAL: fixed, HIGH: fixed, MEDIUM: fixed or documented deferral, LOW: fixed)
- Build succeeds: 0 errors, 0 warnings via `xcodebuild ... | xcsift`
- All existing tests pass (updated for new types)
- New tests cover: RFC 9457 parsing, inline books, SSE reconnection with Last-Event-ID, enrichment_degraded event, ping event, SSEEventParser unit tests
- Code review passes (no data races, actor isolation correct)

---

## Must Have / Must NOT Have (Guardrails)

### MUST Have
- RFC 9457 error response parsing with `retryable` flag support
- Inline `books[]` extraction from SSE `completed` event (avoid unnecessary HTTP round-trip)
- Fallback to `/results?format=lite` when inline books are missing
- `Last-Event-ID` support for SSE reconnection
- `ping` and `enrichment_degraded` SSE event handlers
- `X-Device-ID` header on ALL scan endpoints including fetchResults
- Persistent device ID across app sessions (UserDefaults)
- Status enums for job status, scan stage, enrichment status
- `enrichmentStatus` field on BookMetadata
- Extracted SSEEventParser struct with `internal` access for testability

### Must NOT Have
- Breaking changes to CameraViewModel's public interface (other views depend on it)
- New external dependencies (use Foundation/URLSession only)
- Changes to the SwiftData migration schema version unless absolutely necessary
- Removal of backward-compatible event handling (unknown events must still be ignored gracefully)
- Changes to the multipart upload format (photos[] field name)
- Modifications to the image preprocessing pipeline

---

## Task Flow and Dependencies

```
Phase 1: NetworkTypes Compliance (Foundation)
    |
    +--> Task 1.1: Add RFC 9457 ProblemDetails model
    +--> Task 1.2: Add status enums (JobStatus, ScanStage, EnrichmentStatus)
    +--> Task 1.3: Update SSEEvent enum (inline books, enrichment_degraded, ping)
    +--> Task 1.4: Update SSEError with richer error context (SSEErrorInfo)
    +--> Task 1.5: Add enrichmentStatus to BookMetadata
    |
Phase 2: TalariaService Compliance (Core Logic) [depends on Phase 1]
    |
    +--> Task 2.1: Add RFC 9457 error response parsing to uploadScan
    +--> Task 2.2: Add RFC 9457 error response parsing to cleanup and fetchResults
    +--> Task 2.3: Update SSE parseSSEEvent for completed (inline books), enrichment_degraded, ping
    +--> Task 2.4: Add Last-Event-ID tracking and header to SSE reconnection
    +--> Task 2.5: Fix fetchResults response format ({ success, data: { results } }) and add ?format=lite
    +--> Task 2.6: Add X-Device-ID header to fetchResults
    +--> Task 2.7: Update SSE error parsing (extract code, retryable, jobId)
    +--> Task 2.8: Extract SSEEventParser struct for testability (NEW)
    |
Phase 3: CameraViewModel Compliance (Integration) [depends on Phase 2]
    |
    +--> Task 3.1: Handle inline books from SSE completed event (skip fetchResults when books present)
    +--> Task 3.2: Implement persistent device ID (UserDefaults) with init injection
    +--> Task 3.3: Surface enrichment_degraded to user (toast/banner)
    +--> Task 3.4: Use retryable flag from errors to auto-retry vs show permanent error
    |
Phase 4: Book Model Update [depends on Phase 1]
    |
    +--> Task 4.1: Add enrichmentStatus to Book @Model
    +--> Task 4.2: Map enrichmentStatus from BookMetadata during book creation
    |
Phase 5: OpenAPI Spec Update [independent]
    |
    +--> Task 5.1: Update talaria-openapi.yaml to reflect v3 compliance features
    |
Phase 6: Testing [depends on Phases 2, 3, 4]
    |
    +--> Task 6.1: Add unit tests for RFC 9457 ProblemDetails parsing
    +--> Task 6.2: Add unit tests for SSEEventParser (extracted parsing logic)
    +--> Task 6.3: Add unit tests for Last-Event-ID extraction and reconnection
    +--> Task 6.4: Update ALL existing test files for type changes (EXPANDED SCOPE)
    +--> Task 6.5: Build verification (0 errors, 0 warnings)
    |
Phase 7: Documentation [depends on Phase 6]
    |
    +--> Task 7.1: Update code comments referencing API contract
    +--> Task 7.2: Update CLAUDE.md Talaria section with compliance notes
```

---

## Detailed TODOs

### Phase 1: NetworkTypes Compliance (Foundation)

#### Task 1.1: Add RFC 9457 ProblemDetails Model
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift`
**Description**: Add a Codable struct representing RFC 9457 Problem Details format used by all Talaria HTTP error responses. Scoped to TalariaService consumption (not a shared protocol).
**Changes**:
- Add `ProblemDetails` struct with fields: `success` (Bool), `type` (String), `title` (String), `status` (Int), `detail` (String), `code` (String), `retryable` (Bool), `retryAfterMs` (Int?, from spec), `instance` (String?), `metadata` (optional dict)
- Add `NetworkError.apiError(ProblemDetails)` case to replace opaque `.serverError(Int)` for parsed errors
- Keep `.serverError(Int)` as fallback for when response body cannot be parsed
**Acceptance Criteria**:
- `ProblemDetails` struct conforms to `Codable` and `Sendable`
- Can decode: `{"success":false,"type":"https://api.oooefam.net/errors/rate-limit-exceeded","title":"Rate Limit Exceeded","status":429,"detail":"Too many requests","code":"RATE_LIMIT_EXCEEDED","retryable":true,"retryAfterMs":60000,"metadata":{"timestamp":"...","requestId":"..."}}`
- `NetworkError.apiError` case exposes `retryable` flag and `retryAfterMs`

#### Task 1.2: Add Status Enums
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift`
**Description**: Add typed enums for the three status contexts to resolve Known Issue #3.
**Changes**:
- Add `JobStatus` enum: `initialized`, `processing`, `completed`, `failed`, `canceled`
- Add `ScanStage` enum: `analyzingImage`, `identifyingBooks`, `enrichingMetadata`, `complete`
- Add `EnrichmentStatus` enum: `pending`, `success`, `notFound`, `error`, `circuitOpen`, `reviewNeeded`
- All conform to `String`, `Codable`, `Sendable` with CodingKeys mapping snake_case
**Acceptance Criteria**:
- All three enums decode from their respective snake_case JSON strings
- `EnrichmentStatus.reviewNeeded` correctly maps to `"review_needed"`

#### Task 1.3: Update SSEEvent Enum
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift`
**Description**: Extend SSEEvent to support inline books, enrichment degradation, and pings.
**Changes**:
- Modify `.complete(resultsUrl: String?)` to `.complete(resultsUrl: String?, books: [BookMetadata]?)`
- Add `.enrichmentDegraded(EnrichmentDegradedInfo)` case
- Add `.ping` case
- Add `EnrichmentDegradedInfo` struct matching actual API format: `jobId: String?`, `isbn: String?`, `title: String?`, `reason: String?`, `fallbackSource: String?`, `timestamp: String?`
**Acceptance Criteria**:
- `.complete` carries optional inline `books` array
- `.enrichmentDegraded` carries structured info matching API spec format
- `.ping` has no associated value
- All new types conform to `Sendable`
**Note**: The original plan incorrectly used `{ affectedSources, fallbackUsed, message }` for `EnrichmentDegradedInfo`. The actual API uses `{ type, jobId, isbn, title, reason, fallbackSource, timestamp }` per the API Integration Guide. This has been corrected.

#### Task 1.4: Update SSEError with Richer Context
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift`
**Description**: Extend SSE error event representation to capture full backend error context.
**Changes**:
- Add `SSEErrorInfo` struct: `message: String`, `code: String?`, `retryable: Bool?`, `jobId: String?`
- Modify `.error(String)` to `.error(SSEErrorInfo)` on SSEEvent
**Acceptance Criteria**:
- SSEErrorInfo decodes from `{"type":"error","jobId":"abc-123","code":"NO_TEXT_DETECTED","message":"fail","retryable":false}`
- Backward compatible: if only `message` present, other fields are nil
**Risk**: This changes the SSEEvent.error associated type. ALL consumers must be updated simultaneously. See Task 6.4 for full blast radius.

**Blast Radius for SSEEvent.error type change:**
- `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift` -- switch on SSEEvent
- `/Users/juju/dev_repos/swiftwing/swiftwingTests/TalariaIntegrationTests.swift` -- line 109
- `/Users/juju/dev_repos/swiftwing/swiftwingTests/TalariaServiceTests.swift` -- line 151
- `/Users/juju/dev_repos/swiftwing/swiftwingTests/MockURLSession.swift` -- lines 13, 37 (type signature)
- `/Users/juju/dev_repos/swiftwing/swiftwingTests/SimpleURLSessionMock.swift` -- lines 8, 9, 17, 50 (type signature)
- `/Users/juju/dev_repos/swiftwing/swiftwingTests/SwiftWingComprehensiveTests.swift` -- lines 123-131 (`.error("Test error")` construction)

#### Task 1.5: Add enrichmentStatus to BookMetadata
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift`
**Description**: Add enrichment status tracking to BookMetadata.
**Changes**:
- Add `enrichmentStatus: EnrichmentStatus?` property to `BookMetadata`
**Acceptance Criteria**:
- Decodes `enrichmentStatus` from JSON when present
- Nil when absent (backward compatible)

### Phase 2: TalariaService Compliance (Core Logic) ✅ COMPLETE

All tasks (2.1-2.7) implemented. Build successful: 0 errors, 0 warnings.

#### Task 2.1: Add RFC 9457 Error Parsing to uploadScan ✅
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift`
**Description**: Parse error response bodies as ProblemDetails before throwing NetworkError.
**Changes**:
- In `uploadScan`, for status codes 400, 413, 429, 500-599: attempt to decode response body as `ProblemDetails`
- If decodable: throw `NetworkError.apiError(problemDetails)`
- If not decodable: fall back to existing behavior
- For 429: extract `retryAfterMs` from ProblemDetails (new field) in addition to Retry-After header
**Acceptance Criteria**:
- 400 response with RFC 9457 body throws `.apiError(...)` with `retryable: false`
- 429 response with RFC 9457 body throws `.apiError(...)` with `retryable: true` and `retryAfterMs` extractable
- Malformed error body falls back to `.serverError(statusCode)`

#### Task 2.2: Add RFC 9457 Error Parsing to cleanup and fetchResults
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift`
**Description**: Apply same RFC 9457 parsing pattern to cleanup and fetchResults methods.
**Changes**:
- In `cleanup`: parse error responses as ProblemDetails for 400, 500+ status codes
- In `fetchResults`: parse error responses as ProblemDetails for non-200 status codes
**Acceptance Criteria**:
- Error responses from cleanup and fetchResults include structured ProblemDetails when available

#### Task 2.3: Update parseSSEEvent for New Event Types
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift`
**Description**: Handle completed event with inline books, enrichment_degraded, and ping events.
**Changes**:
- `complete`/`completed` case: after extracting `resultsUrl`, also attempt to decode `books` array from the same JSON. Return `.complete(resultsUrl: url, books: inlineBooks)`
- Add `enrichment_degraded` case: decode `EnrichmentDegradedInfo` from JSON matching actual API format `{ type, jobId, isbn, title, reason, fallbackSource, timestamp }` and return `.enrichmentDegraded(...)`
- Add `ping` case: return `.ping` (no data parsing needed)
- Update `default` case: silently ignore unknown events (return nil or add a dedicated silent-ignore path) instead of throwing
**Acceptance Criteria**:
- SSE data `{"type":"complete","resultsUrl":"/v3/jobs/...","books":[{"title":"Test","author":"Auth","isbn":"123"}]}` returns `.complete` with both resultsUrl and books
- SSE data `{"type":"complete","resultsUrl":"/v3/jobs/..."}` returns `.complete` with books=nil
- `enrichment_degraded` event with `{"type":"enrichment_degraded","jobId":"abc","isbn":"123","title":"Book","reason":"isbndb_circuit_open","fallbackSource":"raw","timestamp":"..."}` parsed correctly
- `ping` event silently consumed (no error log)
- Unknown events silently ignored (no error log, no `.error` yielded)

#### Task 2.4: Add Last-Event-ID to SSE Reconnection
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift`
**Description**: Track `id:` field from SSE events and send `Last-Event-ID` header on reconnection.
**Changes**:
- Add `lastEventId` variable inside `streamEvents` closure
- Parse `id:` lines from SSE stream (alongside `event:` and `data:`)
- On reconnection (retry loop), set `Last-Event-ID` header on the request
**Acceptance Criteria**:
- If SSE event contains `id: 1738419600000-progress`, `lastEventId` is set to `"1738419600000-progress"`
- On retry, request includes `Last-Event-ID: 1738419600000-progress` header
- If no `id:` received, no `Last-Event-ID` header is sent

#### Task 2.5: Fix fetchResults Response Format and Add ?format=lite
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift`
**Description**: Align fetchResults with actual API response format and ensure lite format is requested.
**Changes**:
- Update internal `ResultsResponse` struct to match: `{ success: Bool, data: ResultsData }` where `ResultsData` has `results: [BookMetadata]` (Note: API returns `data.results`, NOT `data.books`)
- When constructing URL, append `?format=lite` query parameter if not already present
- Decode using new struct; extract `data.results` instead of top-level `results`
**Acceptance Criteria**:
- Decodes `{"success":true,"data":{"jobId":"abc","status":"completed","results":[...]}}` correctly
- URL includes `?format=lite` query parameter
- Returns array of BookMetadata from `data.results`

#### Task 2.6: Add X-Device-ID to fetchResults
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift`
**Description**: Include X-Device-ID header on results fetch request.
**Changes**:
- Add `request.addValue(self.deviceId, forHTTPHeaderField: "X-Device-ID")` to fetchResults
**Acceptance Criteria**:
- fetchResults HTTP request includes X-Device-ID header

#### Task 2.7: Update SSE Error Event Parsing
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift`
**Description**: Extract full error context from SSE error events.
**Changes**:
- In `parseSSEEvent` case `"error"`: decode full `SSEErrorInfo` struct (message, code, retryable, jobId)
- Return `.error(SSEErrorInfo(...))` instead of `.error(message)`
**Acceptance Criteria**:
- SSE error data `{"type":"error","jobId":"abc-123","code":"ANALYSIS_SERVICE_UNAVAILABLE","message":"Gemini Vision API timeout after 30s","retryable":true}` produces `.error(SSEErrorInfo(message:"Gemini Vision API timeout after 30s", code:"ANALYSIS_SERVICE_UNAVAILABLE", retryable:true, jobId:"abc-123"))`

#### Task 2.8: Extract SSEEventParser Struct for Testability (NEW)
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/SSEEventParser.swift` (NEW)
**Also modifies**: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift`
**Description**: Extract `parseSSEEvent(event:data:)` logic from TalariaService into a standalone `SSEEventParser` struct with `internal` access level. This resolves the testability blocker where the method is currently `nonisolated private` (line 486 of TalariaService.swift) and cannot be tested from the test target.
**Changes**:
- Create new file `SSEEventParser.swift` with struct `SSEEventParser`
- Move all SSE event parsing logic from `TalariaService.parseSSEEvent` into `SSEEventParser.parse(event:data:) throws -> SSEEvent`
- Give the struct and its `parse` method `internal` access (default in Swift)
- In TalariaService: replace `self.parseSSEEvent(event:, data:)` call with `SSEEventParser().parse(event:, data:)`
- TalariaService.parseSSEEvent can either be removed or become a thin wrapper calling SSEEventParser
**Acceptance Criteria**:
- `SSEEventParser` is a standalone struct, not part of the actor
- `SSEEventParser.parse(event:data:)` has `internal` access
- All existing SSE parsing behavior preserved
- Test target can `@testable import swiftwing` and directly test `SSEEventParser`
- No actor isolation issues (struct is `Sendable`, method is synchronous)

### Phase 3: CameraViewModel Compliance (Integration)

#### Task 3.1: Handle Inline Books from SSE Completed Event
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`
**Description**: When SSE completed event contains inline books, use them directly instead of fetching.
**Changes**:
- Update `.complete` switch case to check for inline `books` array
- If `books` is non-nil and non-empty: process inline books directly via `handleBookResult`
- If `books` is nil or empty: fall back to `fetchResults` as current behavior
- Mark processing item as `.done` after handling inline books
**Acceptance Criteria**:
- When SSE completed contains inline books: no HTTP call to /results, books processed directly
- When SSE completed lacks inline books: fetchResults called as before
- Queue item transitions to `.done` in both paths

#### Task 3.2: Implement Persistent Device ID
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`
**Description**: Use a persistent device ID stored in UserDefaults instead of generating new UUIDs.
**Injection Strategy**: The device ID will be injected via `CameraViewModel.init(deviceId:)` parameter with a default value from UserDefaults. This enables:
  - Production: `CameraViewModel()` uses persistent UserDefaults value
  - Testing: `CameraViewModel(deviceId: "test-device-id")` for deterministic tests
**Changes**:
- Add `DeviceIdentifier` utility (small struct with static method) that reads from `UserDefaults.standard` key `"com.swiftwing.deviceId"`
- If not present, generate UUID v4, store it, return it
- Add `deviceId: String` parameter to `CameraViewModel.init` with default `DeviceIdentifier.current`
- Store as `private let deviceId: String` property
- Replace `UUID().uuidString` on line 307 with `self.deviceId`
- Pass persistent device ID to TalariaService and all API calls
**Acceptance Criteria**:
- Same device ID used across all API calls within a session
- Same device ID persists across app launches
- Device ID is valid UUID v4 format
- CameraViewModel can be initialized with custom deviceId for testing

#### Task 3.3: Surface enrichment_degraded to User
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`
**Description**: Show non-intrusive notification when enrichment sources are degraded.
**Changes**:
- Add `.enrichmentDegraded` case to SSE event switch in `processCaptureWithImageData`
- Show a brief toast/banner: "Some book details may be limited (enrichment service degraded)"
- Do NOT treat as error - processing continues normally
**Acceptance Criteria**:
- enrichment_degraded event shows temporary info banner (not error)
- Processing continues uninterrupted
- Banner auto-dismisses after 5 seconds

#### Task 3.4: Use retryable Flag from Errors
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`
**Description**: Use the `retryable` flag from both HTTP and SSE errors to decide retry behavior.
**Changes**:
- For SSE `.error(SSEErrorInfo)`: check `retryable` flag
  - If retryable: auto-retry once (with backoff) before showing error to user
  - If not retryable: show permanent error immediately
- For HTTP `NetworkError.apiError(ProblemDetails)`: check `retryable` flag for same logic
- Update error handling in `processCaptureWithImageData` outer catch block
**Acceptance Criteria**:
- Retryable SSE errors trigger one automatic retry before failing
- Non-retryable errors immediately show to user
- Existing rate limit handling is preserved (rate limit errors still queue)

### Phase 4: Book Model Update

#### Task 4.1: Add enrichmentStatus to Book @Model
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/Models/Book.swift`
**Description**: Add enrichment status tracking to the SwiftData Book model.
**Changes**:
- Add `var enrichmentStatus: String?` property (stores EnrichmentStatus rawValue)
- Add to `init` with default `nil`
- Add computed `needsEnrichmentReview: Bool` property: true when enrichmentStatus is "review_needed" or "not_found"
**Acceptance Criteria**:
- New property persists in SwiftData
- Existing data migrates without issue (new optional field defaults to nil)
- `needsEnrichmentReview` returns correct value for each status

#### Task 4.2: Map enrichmentStatus During Book Creation
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`
**Description**: Pass enrichmentStatus from BookMetadata to Book model during library addition.
**Changes**:
- In `addBookToLibrary`: set `enrichmentStatus: metadata.enrichmentStatus?.rawValue`
**Acceptance Criteria**:
- Books created with enrichmentStatus from API response
- Books without enrichmentStatus (older API) get nil

### Phase 5: OpenAPI Spec Update

#### Task 5.1: Update talaria-openapi.yaml
**File**: `/Users/juju/dev_repos/swiftwing/swiftwing/OpenAPI/talaria-openapi.yaml`
**Description**: Update committed spec to reflect actual v3 API contract including all documented features.
**Changes**:
- Add `ping` event type to SSE stream documentation
- Add `enrichment_degraded` event schema
- Update `SSECompleteEvent` to include optional `books[]` array and `resultsUrl`
- Add `enrichmentStatus` field to `BookMetadata` schema
- Replace `ErrorResponse` with RFC 9457 `ProblemDetails` schema
- Add `?format=lite` query parameter to results endpoint
- Add `Last-Event-ID` header to SSE stream endpoint
- Add `Authorization: Bearer` header to SSE and results endpoints
- **Fix WebSocket/SSE terminology**: The existing spec references "WebSocket" in places where the actual implementation uses SSE (Server-Sent Events). Update descriptions to accurately reflect SSE usage. WebSocket is only used server-side for Durable Object communication, not client-facing.
- Bump version to 3.1.0
**Acceptance Criteria**:
- Valid OpenAPI 3.1.0 YAML (passes linting)
- All 14 gaps reflected in spec
- WebSocket references corrected to SSE where appropriate
- SHA256 checksum updated

### Phase 6: Testing

#### Task 6.1: Unit Tests for RFC 9457 ProblemDetails
**File**: `/Users/juju/dev_repos/swiftwing/swiftwingTests/TalariaComplianceTests.swift` (NEW)
**Description**: Test ProblemDetails decoding for various error scenarios.
**Test Cases**:
- Decode complete ProblemDetails JSON with all fields
- Decode ProblemDetails with minimal required fields (no optional instance, retryAfterMs)
- Decode ProblemDetails with metadata containing timestamp and requestId
- Verify `retryable` flag propagation through NetworkError.apiError
- Decode ProblemDetails with retryAfterMs field
**Acceptance Criteria**: All test cases pass

#### Task 6.2: Unit Tests for SSEEventParser (Extracted Parsing Logic)
**File**: `/Users/juju/dev_repos/swiftwing/swiftwingTests/TalariaComplianceTests.swift`
**Description**: Test the extracted SSEEventParser struct directly (enabled by Task 2.8).
**Test Cases**:
- Parse `completed` event with inline books array
- Parse `completed` event without inline books (only resultsUrl)
- Parse `completed` event with neither (legacy format)
- Parse `enrichment_degraded` event with full API fields (jobId, isbn, title, reason, fallbackSource, timestamp)
- Parse `ping` event
- Parse `error` event with full SSEErrorInfo fields (type, jobId, code, message, retryable)
- Parse unknown event type (should not throw, should return nil or be silently ignored)
- Parse `progress` event with scan stage status
- Parse `result` event with BookMetadata
**Acceptance Criteria**: All test cases pass. Tests use `@testable import swiftwing` and directly construct `SSEEventParser()`.

#### Task 6.3: Unit Tests for Last-Event-ID
**File**: `/Users/juju/dev_repos/swiftwing/swiftwingTests/TalariaComplianceTests.swift`
**Description**: Test that Last-Event-ID is tracked and sent on reconnection.
**Test Cases**:
- Verify `id:` field is extracted from SSE lines
- Verify `Last-Event-ID` header is set on retry request when ID was received
- Verify no `Last-Event-ID` header when no ID was received
**Acceptance Criteria**: All test cases pass

#### Task 6.4: Update ALL Existing Test Files for Type Changes (EXPANDED SCOPE)
**Description**: Update ALL existing test files that reference SSEEvent types to match the new signatures. This is the full blast radius of the type changes in Phase 1.

**Files to update (6 files total):**

1. **`/Users/juju/dev_repos/swiftwing/swiftwingTests/TalariaIntegrationTests.swift`**
   - Line 88: `streamEvents(streamUrl:)` called without `deviceId` -- add `deviceId: testDeviceId` parameter
   - Line 104: `.complete` now has `(resultsUrl:books:)` -- update pattern match
   - Line 109: `.error(let message)` now `.error(let errorInfo)` -- update to extract `errorInfo.message`
   - Lines 167, 277, 305: Same `streamEvents` signature fix (add deviceId)

2. **`/Users/juju/dev_repos/swiftwing/swiftwingTests/TalariaServiceTests.swift`**
   - Line 95: `.complete` in mock events array -- update to `.complete(resultsUrl: nil, books: nil)`
   - Line 110: `.complete` pattern -- update to `.complete(resultsUrl: _, books: _)` or similar
   - Line 151: `.error("Recognition failed...")` -- update to `.error(SSEErrorInfo(message: "Recognition failed...", code: nil, retryable: nil, jobId: nil))`
   - Line 299: Mock events array -- update `.complete` construction

3. **`/Users/juju/dev_repos/swiftwing/swiftwingTests/MockURLSession.swift`**
   - Line 13: `[String: [NetworkTypes.SSEEvent]]` type -- no change needed (generic type)
   - Line 37: `func mockStreamEvents(_ events: [NetworkTypes.SSEEvent]...)` -- no change needed (generic type)
   - Note: MockURLSession stores SSEEvent values but doesn't construct them, so changes are minimal here. However, verify any switch/pattern matching on SSEEvent still compiles.

4. **`/Users/juju/dev_repos/swiftwing/swiftwingTests/SimpleURLSessionMock.swift`**
   - Lines 8, 9, 17, 50: All reference `NetworkTypes.SSEEvent` as a type parameter -- no structural change needed
   - Verify: stream emission logic doesn't pattern-match on SSEEvent internals

5. **`/Users/juju/dev_repos/swiftwing/swiftwingTests/SwiftWingComprehensiveTests.swift`**
   - Line 113-121: `testSSEEventComplete()` -- `.complete` now requires `(resultsUrl:books:)`, update to `.complete(resultsUrl: nil, books: nil)` or equivalent
   - Lines 123-131: `testSSEEventError()` -- `.error("Test error")` must become `.error(SSEErrorInfo(message: "Test error", code: nil, retryable: nil, jobId: nil))`; pattern match updated from `.error(let message)` to `.error(let errorInfo)` then check `errorInfo.message`

6. **`/Users/juju/dev_repos/swiftwing/swiftwingTests/TalariaIntegrationTests.swift`** (re-listed for completeness)
   - Add `?format=lite` test for fetchResults
   - Update `testUploadReturnsValidJobIdAndStreamUrl` to destructure authToken from response

**Acceptance Criteria**: All existing tests compile and pass with updated types. Zero regressions.

#### Task 6.5: Build Verification
**Command**: `xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift`
**Acceptance Criteria**: 0 errors, 0 warnings

### Phase 7: Documentation

#### Task 7.1: Update Code Comments
**Files**: All modified files
**Description**: Update doc comments to reference API compliance, spec version, known issues.
**Acceptance Criteria**: All public methods have updated doc comments

#### Task 7.2: Update CLAUDE.md
**File**: `/Users/juju/dev_repos/swiftwing/CLAUDE.md`
**Description**: Update the Talaria Backend Integration section with compliance notes.
**Changes**:
- Document the 5 known inconsistencies and how they're handled
- Update SSE Events section with new event types (ping, enrichment_degraded)
- Add note about RFC 9457 error handling
- Update endpoint documentation
- Reference external Talaria docs location for future spec updates
**Acceptance Criteria**: CLAUDE.md reflects current implementation accurately

---

## Commit Strategy

```
Commit 1: "feat(network): Add RFC 9457 ProblemDetails and status enums to NetworkTypes"
  Files: NetworkTypes.swift
  Phase: 1 (Tasks 1.1, 1.2, 1.3, 1.4, 1.5)

Commit 2: "refactor(talaria): Extract SSEEventParser for testability"
  Files: SSEEventParser.swift (NEW), TalariaService.swift
  Phase: 2 (Task 2.8)

Commit 3: "feat(talaria): Update TalariaService for API v3 compliance"
  Files: TalariaService.swift
  Phase: 2 (Tasks 2.1-2.7)

Commit 4: "feat(camera): Update CameraViewModel for inline books and persistent device ID"
  Files: CameraViewModel.swift
  Phase: 3 (Tasks 3.1-3.4)

Commit 5: "feat(model): Add enrichmentStatus to Book model"
  Files: Book.swift, CameraViewModel.swift (addBookToLibrary mapping)
  Phase: 4 (Tasks 4.1-4.2)

Commit 6: "chore(api): Update OpenAPI spec to v3.1.0"
  Files: talaria-openapi.yaml, .sha256
  Phase: 5 (Task 5.1)

Commit 7: "test: Add Talaria API compliance test suite and update existing tests"
  Files: TalariaComplianceTests.swift (NEW), TalariaIntegrationTests.swift,
         TalariaServiceTests.swift, SwiftWingComprehensiveTests.swift,
         MockURLSession.swift, SimpleURLSessionMock.swift
  Phase: 6 (Tasks 6.1-6.5)

Commit 8: "docs: Update Talaria integration documentation"
  Files: CLAUDE.md, code comments
  Phase: 7 (Tasks 7.1-7.2)
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SSEEvent.error type change breaks 6 test files | High | Medium | Task 6.4 explicitly lists all 6 files. Phase 1 + Phase 6 must be done atomically in same build cycle |
| SSEEvent.complete type change breaks CameraViewModel + 3 test files | High | Medium | Phase 2.3 and Phase 3.1 and Task 6.4 must be done atomically |
| SwiftData migration for enrichmentStatus | Low | Low | New optional field, nil default, no migration needed |
| fetchResults struct change causes runtime failures | Medium | High | Unit test with mock JSON before deploying; note `data.results` not `data.books` |
| Last-Event-ID server doesn't support it | Low | Low | Graceful degradation - server ignores unknown headers; spec confirms support |
| Actor isolation issues with persistent device ID | Low | Medium | DeviceIdentifier is a static method on a struct, not actor state. CameraViewModel injects via init parameter |
| Concurrent SSE reconnection race condition | Medium | High | Last-Event-ID tracked per-stream (local variable), not shared state |
| SSEEventParser extraction introduces regression | Low | Medium | Exact same logic extracted; comprehensive unit tests in Task 6.2 |
| Integration tests have wrong `streamEvents` signature | High | Low | Task 6.4 adds missing `deviceId` parameter to all 4 call sites |

---

## Success Criteria

1. **All 14 compliance gaps addressed** (verified by gap-by-gap checklist)
2. **Build: 0 errors, 0 warnings** via xcodebuild + xcsift
3. **All tests pass**: existing tests (updated) + new compliance unit tests + SSEEventParser tests
4. **No data races**: verified by Swift 6.2 strict concurrency checking
5. **Backward compatible**: app works correctly with both old and new API response formats
6. **OpenAPI spec updated**: v3.1.0 with SHA256 checksum, WebSocket/SSE terminology corrected
7. **Documentation current**: CLAUDE.md and code comments reflect implementation
8. **SSEEventParser testable**: extracted struct with `internal` access, directly testable from test target

---

## Estimated Complexity

- **Total Tasks**: 25 (was 23, added Task 2.8 and expanded Task 6.4)
- **Files Modified**: 11 (NetworkTypes.swift, TalariaService.swift, CameraViewModel.swift, Book.swift, talaria-openapi.yaml, TalariaIntegrationTests.swift, TalariaServiceTests.swift, MockURLSession.swift, SimpleURLSessionMock.swift, SwiftWingComprehensiveTests.swift, CLAUDE.md)
- **Files Created**: 2 (SSEEventParser.swift, TalariaComplianceTests.swift)
- **Estimated Effort**: HIGH (cross-cutting changes to types propagate through all consumers; 6 test files affected by SSEEvent type changes)
- **Critical Path**: Phase 1 -> Phase 2 (including 2.8) -> Phase 3 + Phase 6 (type changes cascade)

---

## Revision History

| Rev | Date | Changes | Reviewer |
|-----|------|---------|----------|
| 1 | 2026-02-01 | Initial plan from planner interview + research | Planner (Opus) |
| 2 | 2026-02-01 | Critic feedback: Source of Truth appendix, SSEEventParser extraction, expanded blast radius, enrichment_degraded format fix, device ID injection strategy, integration test signature fixes, Known Issue #5 exclusion, WebSocket/SSE terminology, `data.results` vs `data.books` clarification | Critic (Opus) |

---

## Phase 3 Execution Summary (2026-02-02)

**Status**: ✅ COMPLETE
**Build Result**: 0 errors / 0 warnings
**Executor**: oh-my-claudecode:executor (a3874fb)

### Completed Tasks

#### Task 3.1: Handle Inline Books from SSE ✅
- Verified existing implementation (lines 372-427) already handles inline books correctly
- Inline books: direct processing via handleBookResult (no HTTP round-trip)
- Missing books: fallback to fetchResults with authToken
- Queue item marked `.done` in both paths

#### Task 3.2: Persistent Device ID ✅
**Files Created**:
- `DeviceIdentifier.swift` - UserDefaults-backed persistent UUID v4

**Files Modified**:
- `CameraViewModel.swift`:
  - Line 79: Added `private let deviceId: String`
  - Line 85: Init with `deviceId: String = DeviceIdentifier.current` parameter
  - Line 309: Upload uses `self.deviceId` (persistent across sessions)
  - Line 334: SSE stream uses same `self.deviceId`

**Acceptance**: ✅ All criteria met
- Device ID persists across app launches (UserDefaults)
- Same ID used for upload + SSE within session
- Injectable for testing: `CameraViewModel(deviceId: "test-id")`

#### Task 3.3: Enrichment Degraded Banner ✅
**Files Modified**:
- `CameraViewModel.swift`:
  - Lines 25-26: Added `enrichmentDegradedMessage`, `showEnrichmentDegradedBanner` state
  - Lines 484-492: enrichment_degraded case handler calls banner method
  - Lines 757-771: `showEnrichmentDegradedBanner` method (5s auto-dismiss)

**Behavior**:
- Non-blocking info banner: "Some book details may be limited (enrichment service degraded): {reason}"
- Processing continues uninterrupted
- Auto-dismiss after 5 seconds

**Acceptance**: ✅ All criteria met

#### Task 3.4: Retryable Error Handling ✅
**Files Modified**:
- `CameraViewModel.swift`:
  - Lines 440-492: SSE `.error(SSEErrorInfo)` handler
  - Checks `errorInfo.retryable == true` (unwrapped from optional)
  - Retryable: logs, updates "Retrying...", 2s delay, retries with new UUID
  - Non-retryable: immediate error display, haptic, cleanup
  - Edge case: missing originalImageData treated as permanent error

**Behavior**:
- Retryable errors: 1 automatic retry before user sees error
- Non-retryable errors: immediate display with haptic
- Rate limit errors: separate path preserved (queued for later)

**Acceptance**: ✅ All criteria met

### Build Verification
```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift
```

**Result**: ✅ SUCCESS (0 errors / 0 warnings)

### Changes Summary
**Files Modified**: 1 (CameraViewModel.swift)
**Files Created**: 1 (DeviceIdentifier.swift)
**Lines Changed**: ~120 (added state properties, enrichment banner, retryable error logic, persistent device ID)

**Xcode Project Update**: DeviceIdentifier.swift added to target via ruby xcodeproj gem

### Next Steps
Phase 4 (Book Model) and Phase 5 (OpenAPI Spec) can now proceed with CameraViewModel integration complete.

---
