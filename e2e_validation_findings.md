# Findings: End-to-End SwiftWing → Talaria API Validation

## Investigation Date: 2026-01-25

## Root Cause: API Contract Mismatch

### Critical Discovery: Field Name Discrepancy

**Talaria API Expects:**
```typescript
// /Users/juju/dev_repos/talaria/src/api-v3/jobs/scans.ts:264
const photos = formData.getAll('photos[]')
```

**SwiftWing Sends:**
```swift
// /Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift:102
body.append("Content-Disposition: form-data; name=\"image\"; filename=\"spine.jpg\"\r\n".data(using: .utf8)!)
```

**Impact:** API receives request with `image` field, looks for `photos[]` field, finds none → returns 500 error

---

## Talaria Backend Investigation (Agent a90352c)

### Endpoint Details
- **Location:** `/Users/juju/dev_repos/talaria/src/api-v3/jobs/scans.ts`
- **Lines:** 232-472
- **Method:** POST /v3/jobs/scans
- **Expected Format:** multipart/form-data with `photos[]` field (1-5 images)

### Request Flow
1. Middleware: requestContext → deviceAuth → globalRateLimit → deviceRateLimit
2. Validate X-Device-ID header (UUID v4 format)
3. Parse formData
4. Extract `photos[]` field (getAll to support batch uploads)
5. Validate 1-5 images
6. Validate image magic bytes (JPEG/PNG)
7. Generate jobId and authToken
8. Initialize JobStateManagerDO
9. Store authToken in WebSocketConnectionDO
10. Upload images to R2 (bucket: BOOKSHELF_IMAGES)
11. Send initial SSE progress event
12. Schedule bookshelf scan (DO alarm)
13. Return 202 Accepted with jobId and streamUrl

### Error Handling Analysis

**500 Error Paths:**
1. **formData parsing failure** (line 258) - Most likely cause
2. R2 binding missing (lines 292-301) - Has logging
3. Durable Objects initialization failure (lines 404-411) - Caught
4. Image validation throwing exception (lines 348-362) - Should return 400
5. R2 upload failures (lines 418-425) - Caught
6. DO alarm scheduling failure (line 437) - Could propagate

**Why Current Request Fails:**
```
SwiftWing sends: { "image": <file> }
API expects: { "photos[]": <file> }
  ↓
formData.getAll('photos[]') returns empty array
  ↓
Validation at line 269 fails: photos.length === 0
  ↓
Should return 400 Bad Request, but...
  ↓
Something throws exception before validation
  ↓
Caught at line 462 → returns 500
```

---

## SwiftWing Client Investigation

### Current Implementation
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift`

**Upload Method (lines 80-148):**
```swift
func uploadScan(image: Data, deviceId: String) async throws -> (jobId: String, streamUrl: URL)
```

**Issues Found:**
1. **Line 102:** Field name is `image` (should be `photos[]`)
2. **Line 91:** Correctly sets `X-Device-ID` header ✅
3. **Line 104:** Single image upload (API supports batch 1-5)

**Already Fixed:**
- ✅ Device ID moved from form field to X-Device-ID header (done earlier today)
- ✅ Actor isolation fixed (streamEvents and parseSSEEvent now nonisolated)

---

## OpenAPI Spec Analysis

**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/OpenAPI/talaria-openapi.yaml`

**Discrepancies Found:**

| OpenAPI Spec Says | Actual API Behavior | Status |
|-------------------|---------------------|--------|
| `deviceId` form field (line 39-42) | `X-Device-ID` header required | ❌ Spec outdated |
| Field name: `image` | Field name: `photos[]` | ❌ Spec wrong |
| Single file upload | Supports batch 1-5 files | ⚠️ Spec incomplete |

**Recommendation:** Update OpenAPI spec to match deployed API

---

## Test Results Summary

### TalariaIntegrationTests (6 tests total)

**Passing (1/6):**
- ✅ `testErrorHandlingForNetworkFailures()` - Tests invalid data handling

**Failing (5/6):** All fail fast (~0.3-1.0 seconds)
- ❌ `testUploadReturnsValidJobIdAndStreamUrl()` - 0.326s
- ❌ `testSSEStreamReceivesAllEventTypes()` - 0.331s
- ❌ `testCleanupSucceedsAndIsIdempotent()` - 1.074s
- ❌ `testConcurrentUploadsCompleteSuccessfully()` - 0.552s
- ❌ `testTypesDeserializeCorrectly()` - 0.269s

**Failure Pattern:**
- Fast failures indicate immediate rejection by API
- All tests that upload images fail
- Error handling test passes (doesn't upload)

---

## Talaria Backend Architecture (From Agent Investigation)

### Key Components

1. **R2 Storage:**
   - Binding: `BOOKSHELF_IMAGES`
   - Bucket: `bookshelf-images`
   - Path pattern: `scans/{deviceId}/{jobId}/{timestamp}-{index}.jpg`

2. **Durable Objects:**
   - JobStateManagerDO: Tracks scan progress, handles alarms
   - WebSocketConnectionDO: Stores auth tokens for SSE streams

3. **Middleware Chain:**
   - requestContext: Adds X-Request-ID
   - deviceAuth: Validates X-Device-ID header (UUID v4)
   - globalRateLimit: 10,000/day
   - deviceRateLimit: 100/hour per device

4. **Response Format:**
   ```typescript
   {
     jobId: string (UUID)
     streamUrl: string (SSE endpoint)
   }
   ```

---

## Cloudflare Deployment Status

**wrangler.jsonc Configuration:**
```json
"r2_buckets": [
  { "binding": "BOOKSHELF_IMAGES", "bucket_name": "bookshelf-images" }
]
```

**Status:** ✅ Binding configured (need to verify deployment)

---

## Performance Benchmarks (From Test Code)

| Metric | Target | Test |
|--------|--------|------|
| Upload latency | < 1000ms | testUploadReturnsValidJobIdAndStreamUrl |
| SSE first event | < 500ms | testSSEStreamReceivesAllEventTypes |
| Concurrent uploads (5x) | < 10s | testConcurrentUploadsCompleteSuccessfully |

---

## Recent Commits Context (From clink investigation)

**SwiftWing:**
- US-509: Added integration tests with real API
- US-508: Removed deprecated NetworkActor (~1000 lines)
- US-510: Enhanced documentation

**Talaria:** (Need to check git log)
- Recent changes to routing (commit 7488870)
- Secrets Store update (commit 6e87246)

---

## Key Insights

1. **API Contract Alignment Needed:**
   - SwiftWing needs to send `photos[]` field, not `image`
   - OpenAPI spec is outdated and misleading

2. **Infrastructure is Healthy:**
   - Talaria error handling is comprehensive
   - R2 bindings configured
   - Durable Objects in place
   - Rate limiting works

3. **Client Code Quality:**
   - TalariaService is well-architected (actor-based)
   - Concurrency patterns correct (Swift 6.2)
   - Just needs field name fix

4. **Fast Path to Resolution:**
   - Single line change in TalariaService.swift (line 102)
   - Update OpenAPI spec for documentation
   - Tests should pass immediately

---

## Questions Answered

**Q: Why are 5/6 tests failing?**
A: ~~API contract mismatch - client sends `image` field, API expects `photos[]`~~
**UPDATE:** Actual root cause is Secrets Store null handling in Gemini provider

**Q: Why does error handling test pass?**
A: It sends intentionally invalid data (empty Data()), doesn't use real upload flow

**Q: Is the Talaria API down?**
A: No - API is running, but Secrets Store retrieval is failing in production

**Q: Is there a backend bug?**
A: **YES** - gemini-provider.ts:161 doesn't handle null from Secrets Store .get()

**Q: Why wasn't this caught earlier?**
A: Local dev uses plain env vars (works), production uses Secrets Store bindings (fails)

---

## UPDATED ROOT CAUSE (Agent aed63e7 Investigation)

### Actual Problem: Secrets Store Null Handling

**Location:** `/Users/juju/dev_repos/talaria/src/providers/gemini-provider.ts:161`

```typescript
apiKey = await geminiApiKey.get()  // ❌ No null check!
```

**Issue:**
- Secrets Store `.get()` returns `Promise<string | null | undefined>`
- Code assigns directly without null check
- If secret retrieval fails → apiKey is null → Gemini API call fails → 500 error

**Why Local Works But Production Fails:**
- **Local dev:** Uses plain string `env.GEMINI_API_KEY` (works ✅)
- **Production:** Uses Secrets Store binding `.get()` method (returns null ❌)

**Evidence:**
- Local dev: Returns 202 with jobId
- Production: Returns 500 INTERNAL_ERROR
- Response time: 1377ms (alarm fired, then failed during Gemini call)

---

## References

- Explore Agent Report: agentId a90352c
- Talaria Endpoint: `/Users/juju/dev_repos/talaria/src/api-v3/jobs/scans.ts:232-472`
- SwiftWing Client: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift:80-148`
- Integration Tests: `/Users/juju/dev_repos/swiftwing/swiftwingTests/TalariaIntegrationTests.swift`
