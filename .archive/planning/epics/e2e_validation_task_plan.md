# Task Plan: End-to-End SwiftWing → Talaria API Validation

## Goal
Complete end-to-end validation of SwiftWing iOS app integration with Talaria API backend before UI/UX validation on device. Ensure all 6 TalariaIntegrationTests pass with the live API.

## Context
- SwiftWing: iOS 26 book scanning app at `/Users/juju/dev_repos/swiftwing`
- Talaria: Backend API at `/Users/juju/dev_repos/talaria`
- Current state: Tests run but 5/6 fail with API returning 500 errors
- One passing test: `testErrorHandlingForNetworkFailures()`
- Failing tests suggest API issue, not client code issue

## Current Status: Phase 1 in Progress

## Phases

### Phase 1: Diagnose Talaria API 500 Errors ⏳ in_progress
**Status:** Exploration complete, root cause identified
**Actions:**
- [x] Explored Talaria backend codebase structure
- [x] Identified POST /v3/jobs/scans endpoint (lines 232-472 in `/src/api-v3/jobs/scans.ts`)
- [x] Found most likely cause: formData field name mismatch
  - API expects: `photos[]` field (line 264)
  - SwiftWing sends: `image` field (TalariaService.swift:102)
- [x] Identified secondary issue: OpenAPI spec outdated (says `deviceId` form field, API needs header)

**Findings:** See findings.md for detailed investigation

**Next:** Fix SwiftWing client to match actual API contract

### Phase 2: Fix SwiftWing API Contract 📋 pending
**Status:** Not started
**Actions:**
- [ ] Update TalariaService.swift uploadScan() to use `photos[]` instead of `image`
- [ ] Verify multipart form structure matches API expectations
- [ ] Update OpenAPI spec to reflect actual API (for documentation)
- [ ] Rebuild SwiftWing tests

**Expected Outcome:** Tests should pass or give more specific errors

### Phase 3: Fix Any Remaining Talaria Backend Issues 📋 pending
**Status:** Not started
**Actions:**
- [ ] If tests still fail, check Talaria logs for specific errors
- [ ] Verify R2 bucket bindings are deployed
- [ ] Verify Durable Objects are initialized correctly
- [ ] Check Cloudflare deployment status

**Expected Outcome:** Backend returns 202 Accepted with jobId/streamUrl

### Phase 4: Verify SSE Streaming Works 📋 pending
**Status:** Not started
**Actions:**
- [ ] Test SSE stream connection
- [ ] Verify progress events arrive
- [ ] Verify result event with BookMetadata
- [ ] Verify complete event arrives
- [ ] Test cleanup endpoint

**Expected Outcome:** All SSE-related tests pass

### Phase 5: Run Full Integration Test Suite 📋 pending
**Status:** Not started
**Actions:**
- [ ] Run all 6 TalariaIntegrationTests
- [ ] Verify 6/6 pass with live API
- [ ] Check performance benchmarks (upload <1s, first event <500ms, concurrent <10s)
- [ ] Document any issues found

**Expected Outcome:** 6/6 tests passing, ready for UI/UX validation

### Phase 6: Document & Handoff 📋 pending
**Status:** Not started
**Actions:**
- [ ] Update CLAUDE.md with lessons learned
- [ ] Document API contract corrections
- [ ] Create summary for user
- [ ] Prepare device for UI/UX testing

**Expected Outcome:** Clear documentation, user can proceed with device testing

## Decisions Log

| Decision | Rationale | Date |
|----------|-----------|------|
| Use Explore agent for Talaria investigation | Need systematic codebase analysis to find root cause | 2026-01-25 |
| Focus on API contract mismatch first | Agent found `photos[]` vs `image` field name issue - fastest fix | 2026-01-25 |
| Don't modify Talaria backend yet | SwiftWing client should match deployed API first | 2026-01-25 |

## Errors Encountered

| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| 5/6 tests failing with fast failures | 1 | Initial diagnosis - suspected API down | ❌ Incomplete |
| API returns 500 on upload | 2 | Curl testing confirmed 500 errors | ✅ Diagnosed |
| Root cause: field name mismatch | 3 | Explore agent found `photos[]` vs `image` discrepancy | ✅ Identified |

## Key Files

| File | Purpose | Status |
|------|---------|--------|
| `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift` | Client API integration | Needs fix (line 102) |
| `/Users/juju/dev_repos/swiftwing/swiftwingTests/TalariaIntegrationTests.swift` | E2E tests | Tests ready, API broken |
| `/Users/juju/dev_repos/talaria/src/api-v3/jobs/scans.ts` | Backend endpoint | Works, expects `photos[]` |
| `/Users/juju/dev_repos/swiftwing/swiftwing/OpenAPI/talaria-openapi.yaml` | API spec | Outdated, needs update |

## Blockers

None currently - have clear path forward.

## Notes

- User has full access to both repos and Cloudflare
- User wants strong PM approach with specialized agents
- Must complete E2E validation before UI/UX device testing
- All infrastructure is in place, just need to align API contracts
