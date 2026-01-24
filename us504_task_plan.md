# US-504: Generate Type-Safe Talaria Client Code - Task Plan

## Goal
Configure swift-openapi-generator build plugin to automatically generate type-safe Swift client code for all Talaria v3 API endpoints during Xcode builds, with zero errors/warnings and working autocomplete.

## Current Status: Phase 2 - In Progress

## Phases

### Phase 1: OpenAPI Spec Creation ✅ COMPLETE
- [x] Created comprehensive OpenAPI 3.1.0 spec for Talaria v3 API
- [x] Spec includes all required endpoints:
  - POST /v3/jobs/scans (multipart upload)
  - GET /v3/jobs/scans/{jobId}/stream (SSE streaming)
  - DELETE /v3/jobs/scans/{jobId}/cleanup
- [x] Defined all schemas: ScanJobResponse, BookMetadata, SSE events, error types
- [x] Placed spec in `/Users/juju/dev_repos/swiftwing/swiftwing/Generated/openapi.yaml`
- [x] Modified fetch script to allow local fallback when server unavailable
- [x] Copied spec to target directory: `/Users/juju/dev_repos/swiftwing/swiftwing/openapi.yaml`
- [x] Copied generator config to target: `/Users/juju/dev_repos/swiftwing/swiftwing/openapi-generator-config.yaml`

**Files Created:**
- `swiftwing/Generated/openapi.yaml` (9.3K)
- `swiftwing/openapi.yaml` (copy for generator)
- `swiftwing/openapi-generator-config.yaml` (copy for generator)
- Modified: `Scripts/fetch-openapi-spec.sh`

### Phase 2: Configure Build Plugin ⚠️ BLOCKED (Manual Xcode Step Required)
**Status:** Files prepared, requires Xcode UI interaction to complete

**Completed:**
- ✅ OpenAPI spec created and validated (9.3K, comprehensive v3 API)
- ✅ Generator config in place with correct settings
- ✅ Files in target directory (swiftwing/)
- ✅ Package dependencies resolved (generator 1.10.4, runtime 1.9.0)
- ✅ Runtime packages added to target (OpenAPIRuntime, OpenAPIURLSession)

**Requires Manual Steps in Xcode:**
The swift-openapi-generator build plugin MUST be added through Xcode UI:

1. Open `swiftwing.xcodeproj` in Xcode
2. Select swiftwing target → Build Phases
3. Click "+" → "Run Build Tool Plug-ins"
4. Select "OpenAPI Generator" plugin
5. In Project Navigator, add files to target:
   - Right-click `swiftwing/openapi.yaml` → Add to Targets → swiftwing
   - Right-click `swiftwing/openapi-generator-config.yaml` → Add to Targets → swiftwing
6. Build project (Cmd+B)
7. Verify generated code in DerivedData

**Why Manual Step Needed:**
- Xcode pbxproj modification for plugins is complex and error-prone
- Plugin configuration uses Xcode 14+ build tool plugin system
- Files must be recognized by Xcode project navigator
- Automated pbxproj editing risks project corruption

**Alternative:** User can complete this story by opening Xcode and following steps above

### Phase 3: Verify Generated Code ⏸️ PENDING
- [ ] Check DerivedData for generated Swift files
- [ ] Verify all 3 endpoints present (createScanJob, streamScanProgress, cleanupScanJob)
- [ ] Verify generated types match spec
- [ ] Check types are immutable (structs where appropriate)
- [ ] Verify enums for string constants
- [ ] Test import of generated code in existing files

### Phase 4: Test Autocomplete & Compilation ⏸️ PENDING
- [ ] Create test file importing generated client
- [ ] Verify Xcode autocomplete works for:
  - Client initialization
  - Endpoint methods
  - Request/response types
  - Schema types
- [ ] Verify zero build errors
- [ ] Verify zero build warnings

### Phase 5: Quality Checks & Commit ⏸️ PENDING
- [ ] Run full build with zero errors/warnings
- [ ] Document generated code location
- [ ] Commit with message: `feat: US-504 - Generate Type-Safe Talaria Client Code`
- [ ] Signal completion with `<promise>COMPLETE</promise>`

## Decisions Made

| Decision | Rationale | Timestamp |
|----------|-----------|-----------|
| Create local OpenAPI spec when server unavailable | Talaria server returning HTTP 522; need development spec | 2026-01-24 14:49 |
| Modify fetch script for local fallback | Allow development when server down; maintains build-time validation | 2026-01-24 14:50 |
| Copy config files to target directory | swift-openapi-generator expects files in target root per documentation | 2026-01-24 14:51 |

## Errors Encountered

| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| HTTP 522 from api.oooefam.net | 1 | Created local OpenAPI spec based on documentation | ✅ Resolved |
| Build fails - spec fetch error | 2 | Modified fetch script to allow local fallback | ✅ Resolved |
| No generated code in DerivedData | 3 | Need to add build plugin to Xcode target | 🔄 In Progress |

## Open Questions
- Does Xcode build plugin automatically trigger when openapi.yaml present?
- Do we need to manually add plugin in Xcode UI?
- Should generated files be in specific location for import?

## Next Steps
1. Investigate how to add swift-openapi-generator build plugin to Xcode target
2. Check if files need to be added to Xcode project navigator
3. Verify plugin triggers on build
4. Find generated code location
