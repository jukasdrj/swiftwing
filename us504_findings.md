# US-504: Generate Type-Safe Talaria Client Code - Findings

## OpenAPI Spec Structure

### Endpoints Defined
1. **POST /v3/jobs/scans** (`createScanJob`)
   - Multipart upload: image (binary) + deviceId (UUID)
   - Returns: `{ jobId: UUID, streamUrl: URL }`
   - Error responses: 400, 413, 429, 500

2. **GET /v3/jobs/scans/{jobId}/stream** (`streamScanProgress`)
   - SSE streaming endpoint (text/event-stream)
   - Path parameter: jobId (UUID)
   - Stream event types: progress, result, complete, error
   - Error responses: 404, 410

3. **DELETE /v3/jobs/scans/{jobId}/cleanup** (`cleanupScanJob`)
   - Resource cleanup endpoint
   - Path parameter: jobId (UUID)
   - Returns: 204 (no content)
   - Error responses: 404, 500

### Schema Types Defined

**Core Response Types:**
- `ScanJobResponse` - Initial upload response
- `BookMetadata` - Book identification result
- `ErrorResponse` - Standard error format
- `RateLimitErrorResponse` - Rate limit specific errors

**SSE Event Types:**
- `SSEProgressEvent` - Progress messages (enum: "Looking...", "Reading...", etc.)
- `SSEResultEvent` - Book metadata result
- `SSECompleteEvent` - Empty completion marker
- `SSEErrorEvent` - Error with message and optional code enum

**Enums Generated:**
- Book format: hardcover, paperback, ebook, audiobook
- Error codes: NO_TEXT_DETECTED, MULTIPLE_BOOKS_DETECTED, etc.
- Progress messages: Looking, Reading, Enriching, Finalizing

## Generator Configuration

**File:** `openapi-generator-config.yaml`

**Key Settings:**
- `generate: [types, client]` - Generate both types and client code
- `accessModifier: public` - Make generated code public
- `apiNamespace: TalariaAPI` - Namespace for generated code
- `featureFlags: [SendableTypes, StrictConcurrency]` - Swift 6.2 compatibility
- `multipartFormDataEnabled: true` - For image upload
- `eventStreamEnabled: true` - For SSE support

**Additional Imports:**
- Foundation
- OpenAPIRuntime
- OpenAPIURLSession

## Build Plugin Investigation

### Package Dependencies Resolved
```
swift-openapi-generator: 1.10.4
swift-openapi-runtime: 1.9.0
swift-openapi-urlsession: 1.2.0
```

### Target Configuration Found
- Target: swiftwing
- Package products: OpenAPIRuntime, OpenAPIURLSession
- Missing: Build plugin reference to swift-openapi-generator

### Expected Behavior
According to swift-openapi-generator documentation:
1. Add package as plugin dependency to target
2. Place `openapi.yaml` in target directory
3. Place `openapi-generator-config.yaml` in target directory
4. Build automatically triggers code generation
5. Generated code appears in DerivedData

### Current State
- ✅ Files in correct location (`swiftwing/openapi.yaml`, `swiftwing/openapi-generator-config.yaml`)
- ❌ Build plugin not configured in target
- ❌ No generated code in DerivedData after build

## Talaria Server Status
- Base URL: https://api.oooefam.net
- Status: HTTP 522 (Connection timeout) as of 2026-01-24
- Workaround: Using local OpenAPI spec for development

## Swift 6.2 Concurrency Requirements
- Generated types must conform to Sendable
- Strict concurrency checking enabled
- All async operations should use structured concurrency
- Actor isolation for shared mutable state

## File Locations

| File | Location | Purpose |
|------|----------|---------|
| OpenAPI Spec (source) | `swiftwing/Generated/openapi.yaml` | Fetched by build script |
| OpenAPI Spec (generator input) | `swiftwing/openapi.yaml` | Read by build plugin |
| Generator Config | `swiftwing/openapi-generator-config.yaml` | Controls code generation |
| Fetch Script | `Scripts/fetch-openapi-spec.sh` | Downloads spec from server |
| Generated Code | `DerivedData/.../GeneratedSources/openapi/` | Expected output location |

## References
- swift-openapi-generator docs: https://github.com/apple/swift-openapi-generator
- Epic 5 JSON: `/Users/juju/dev_repos/swiftwing/epic-5.json`
- CLAUDE.md Talaria section: Lines 238-252
