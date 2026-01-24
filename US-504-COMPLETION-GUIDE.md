# US-504: Generate Type-Safe Talaria Client Code - Completion Guide

## Current Status: 80% Complete - Requires Manual Xcode Step

### ✅ What's Been Completed

1. **OpenAPI Specification Created** (`swiftwing/openapi.yaml` - 9.3K)
   - All v3 endpoints defined:
     - ✅ POST /v3/jobs/scans (`createScanJob`)
     - ✅ GET /v3/jobs/scans/{jobId}/stream (`streamScanProgress`)
     - ✅ DELETE /v3/jobs/scans/{jobId}/cleanup (`cleanupScanJob`)
   - All request/response types defined
   - Immutable types (structs)
   - Enums for constants (book format, error codes, progress messages)
   - Multipart upload support
   - SSE streaming support

2. **Generator Configuration** (`swiftwing/openapi-generator-config.yaml`)
   - ✅ Swift 6.2 strict concurrency enabled
   - ✅ Sendable types feature flag
   - ✅ Public access modifier
   - ✅ TalariaAPI namespace
   - ✅ Multipart and event stream enabled

3. **Build Infrastructure**
   - ✅ Fetch script modified to allow local fallback
   - ✅ Package dependencies resolved (swift-openapi-generator 1.10.4)
   - ✅ Runtime packages added to target
   - ✅ Files in correct locations

### ⚠️ Manual Step Required: Configure Build Plugin in Xcode

The OpenAPI generator build plugin **must be added through Xcode's UI**. Follow these steps:

#### Step 1: Open Project in Xcode
```bash
open swiftwing.xcodeproj
```

#### Step 2: Add Build Tool Plugin
1. Select **swiftwing** target in project navigator
2. Go to **Build Phases** tab
3. Click **"+" button** at top left
4. Select **"Run Build Tool Plug-ins"**
5. From the dropdown, select **"OpenAPI Generator"** plugin
6. The plugin should appear in the build phases list

#### Step 3: Add OpenAPI Files to Target
The `openapi.yaml` and `openapi-generator-config.yaml` files need to be recognized by Xcode:

**Option A: Add via Project Navigator (Recommended)**
1. In Project Navigator, locate `swiftwing/openapi.yaml`
2. Right-click → **Get Info** (or press Cmd+Option+1)
3. In **Target Membership**, check ✅ **swiftwing**
4. Repeat for `swiftwing/openapi-generator-config.yaml`

**Option B: Add Files to Project**
1. Right-click `swiftwing` folder in Project Navigator
2. Select **"Add Files to swiftwing..."**
3. Navigate to and select:
   - `swiftwing/openapi.yaml`
   - `swiftwing/openapi-generator-config.yaml`
4. Ensure **"Add to targets: swiftwing"** is checked
5. Click **"Add"**

#### Step 4: Build Project
```bash
# In Xcode: Press Cmd+B
# Or from terminal:
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift
```

#### Step 5: Verify Code Generation

**Check Build Log:**
Look for output like:
```
[OpenAPI Generator] Generating Swift code from OpenAPI document...
[OpenAPI Generator] Generated 8 Swift files
```

**Find Generated Files:**
```bash
find ~/Library/Developer/Xcode/DerivedData/swiftwing-*/SourcePackages/plugins -name "*.swift" | grep -i talaria
```

Expected files:
- `Client.swift` - Main API client with async methods
- `Types.swift` - Request/response models
- `Components+Schemas.swift` - Schema types (BookMetadata, SSEEvent, etc.)
- `Servers.swift` - Server configuration

#### Step 6: Test Autocomplete

Create a test file in Xcode:

```swift
import OpenAPIRuntime
import OpenAPIURLSession
import Foundation

@MainActor
func testTalariaClient() async throws {
    // Xcode should autocomplete these types:
    let client = Client(
        serverURL: try Servers.server1(),
        transport: URLSessionTransport()
    )

    // Test endpoint method autocomplete:
    let response = try await client.createScanJob(/* ... */)

    // Test type autocomplete:
    let jobId = response.jobId  // Should autocomplete
    let streamUrl = response.streamUrl  // Should autocomplete
}
```

If autocomplete works and build succeeds with **0 errors, 0 warnings**, the story is complete! ✅

---

## Acceptance Criteria Status

| Criterion | Status | Notes |
|-----------|--------|-------|
| Generator creates client code in DerivedData during build | ⏸️ Pending | Requires build plugin configuration |
| Generated code includes all v3 endpoints | ✅ Ready | Spec defines all 3 endpoints |
| Generated request/response types match spec exactly | ✅ Ready | OpenAPI 3.1.0 spec is comprehensive |
| All generated types are immutable (struct-based) | ✅ Ready | Generator config ensures this |
| Enums generated for known string constants | ✅ Ready | Spec defines enums for format, errors, progress |
| Generated code compiles with zero errors or warnings | ⏸️ Pending | Verify after plugin configured |
| Xcode autocomplete works for generated types | ⏸️ Pending | Verify after plugin configured |

---

## Files Created/Modified

| File | Action | Purpose |
|------|--------|---------|
| `swiftwing/Generated/openapi.yaml` | Created | OpenAPI 3.1.0 spec (source of truth) |
| `swiftwing/openapi.yaml` | Created | Copy for generator to read |
| `swiftwing/openapi-generator-config.yaml` | Created | Generator configuration |
| `Scripts/fetch-openapi-spec.sh` | Modified | Added local fallback for development |
| `US-504-COMPLETION-GUIDE.md` | Created | This guide |
| `us504_task_plan.md` | Created | Planning file (persistent memory) |
| `us504_findings.md` | Created | Research and discoveries |
| `us504_progress.md` | Created | Session log |

---

## Troubleshooting

### Issue: Build plugin not running
**Symptom:** Build succeeds but no log output about code generation

**Solutions:**
1. Verify plugin appears in Build Phases → Run Build Tool Plug-ins
2. Clean build folder (Cmd+Shift+K in Xcode)
3. Delete DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData/swiftwing-*`
4. Rebuild project

### Issue: Generated code not found
**Symptom:** Build succeeds but can't find generated Swift files

**Check:**
```bash
# Look in these locations:
find ~/Library/Developer/Xcode/DerivedData/swiftwing-* -name "Client.swift" 2>/dev/null
find ~/Library/Developer/Xcode/DerivedData/swiftwing-* -path "*openapi*" -name "*.swift" 2>/dev/null
```

### Issue: Cannot import generated code
**Symptom:** `import TalariaAPI` fails

**Solutions:**
1. Ensure build succeeded (0 errors)
2. Generated code is in target's build output
3. Restart Xcode to refresh code completion index
4. Clean build and rebuild

---

## Next Story: US-505

Once this story is complete (generated code compiling with autocomplete working), proceed to:

**US-505: Create TalariaService Actor Wrapper**
- Wrap generated OpenAPI client in actor
- Translate API types to SwiftWing domain models
- Provide business logic layer

This story (US-504) provides the foundation for US-505's implementation.

---

## Quick Command Reference

```bash
# Build from command line
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift

# Find generated code
find ~/Library/Developer/Xcode/DerivedData/swiftwing-* -name "*.swift" -path "*openapi*" 2>/dev/null

# Verify OpenAPI spec syntax
python3 -c "import yaml, json; json.dump(yaml.safe_load(open('swiftwing/openapi.yaml')), open('/dev/null', 'w'))"

# Clean everything
rm -rf ~/Library/Developer/Xcode/DerivedData/swiftwing-*
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing clean
```
