# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**SwiftWing** is a native iOS 26 book spine scanner app that uses camera + AI (Talaria backend) to automatically identify and catalog books. Built with SwiftUI, SwiftData, Swift 6.2 concurrency, and AVFoundation.

**Bundle ID:** `com.ooheynerds.swiftwing`
**Min Deployment:** iOS 26.0 (current-gen devices only)
**Architecture:** MVVM + Actor-based services (vertical slice epics)

## Building & Running

### Xcode Commands

**CRITICAL: ALWAYS use xcsift, NEVER call xcodebuild directly**

```bash
# Open project
open swiftwing.xcodeproj

# Build for simulator (Cmd+B in Xcode)
# Run on simulator (Cmd+R in Xcode)

# Build from command line - ONLY METHOD TO USE
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift

# Clean build
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' clean build 2>&1 | xcsift

# NEVER USE: xcodebuild without piping to xcsift
# NEVER USE: xcsift build (command doesn't exist - xcsift is a formatter only)
```

**Why xcsift?**
- Formats xcodebuild output to structured JSON
- Makes errors parseable and actionable
- Essential for automated diagnosis

### Ralph-TUI Task Management
Epic-based development workflow using ralph-tui:

```bash
# Load current epic
ralph-tui load epic-1.json  # Or epic-2.json, etc.

# Check progress
ralph-tui status

# Load next epic when ready
ralph-tui load epic-2.json
```

**Epic sequence:** 1 (Foundation) → 2 (Camera) → 3 (Library) → 4 (AI) → 5 (Polish) → 6 (Launch)

## Architecture

### High-Level Structure

```
SwiftUI Views
    ↓
@Observable ViewModels
    ↓
Actor Services (CameraActor, NetworkActor, DataSyncActor)
    ↓
SwiftData Models (Book @Model)
```

**Key Pattern:** Feature-based vertical slices. Each epic delivers ONE complete feature across all layers (UI → Logic → Data → Network).

### Folder Organization

```
swiftwing/
├── App/                  # SwiftwingApp.swift (entry point)
├── Features/             # Feature modules (camera, library, etc.)
├── Models/               # SwiftData @Model classes
│   └── Book.swift        # Core data model
├── Services/             # NetworkService, actors (future)
├── OpenAPI/              # Committed API specifications
│   └── talaria-openapi.yaml  # Talaria backend spec
├── Generated/            # Auto-generated code (not committed)
├── Theme.swift           # Swiss Glass design system
└── Assets.xcassets/      # Colors, images, app icon
```

### Concurrency Model (Swift 6.2)

**Use Actors for Isolated State:**
- `CameraActor` - Manages AVCaptureSession (prevents data races)
- `NetworkActor` - Handles uploads and SSE streams
- `DataSyncActor` - Coordinates SwiftData writes

**Pattern:**
```swift
actor CameraManager {
    private var session: AVCaptureSession
    private var isRunning: Bool = false

    func startSession() async throws {
        // Thread-safe operations
    }
}
```

**Critical Rules:**
- Only use actors when you have **mutable instance properties** to protect
- Avoid `DispatchSemaphore`/`DispatchGroup` with async/await (deadlock risk)
- Don't use detached tasks unless necessary (breaks priority inheritance)
- Use structured concurrency (Task groups, async let)

### SwiftData Schema

**Book Model** (`Models/Book.swift`):
```swift
@Model
final class Book {
    @Attribute(.unique) var isbn: String  // Prevents duplicates
    var id: UUID
    var title: String
    var author: String
    // Future: coverUrl, format, spineConfidence (Epic 3)
}
```

**Usage in Views:**
```swift
@Query(sort: \Book.title) var books: [Book]
@Environment(\.modelContext) private var modelContext
```

**Epic 1:** Minimal schema (id, title, author, isbn)
**Epic 3:** Full schema (add coverUrl, format, confidence, etc.)

### Design Language: Swiss Glass Hybrid

**60% Swiss Utility + 40% Liquid Glass** (iOS 26 platform convention)

**Theme Constants** (`Theme.swift`):
```swift
// Colors
Color.swissBackground  // Black (#0D0D0D)
Color.swissText        // White
Color.internationalOrange  // #FF4F00 (accent)

// Typography
Font.jetBrainsMono     // For data/IDs (brand identity)
Font.system()          // San Francisco Pro for UI (native)

// ViewModifiers
.swissGlassCard()      // Black bg + .ultraThinMaterial + rounded corners
```

**Guidelines:**
- Black base for OLED optimization (Swiss)
- `.ultraThinMaterial` overlays for depth (Liquid Glass)
- Rounded corners (12px) with white borders (hybrid)
- Spring animations (`.spring(duration: 0.2)`) for fluidity

## AI Collaboration Workflow

### 🚨 MANDATORY: Planning-with-Files for Complex Tasks

**ABSOLUTE REQUIREMENT: Use planning-with-files skill for tasks requiring >4 tool calls**

**You MUST invoke this skill BEFORE starting:**
```bash
/planning-with-files
```

**This is NON-NEGOTIABLE for:**
- ✅ Build failures requiring diagnosis (like the @Environment(\.modelContainer) issue)
- ✅ Multi-step features (Epic 2+ camera integration)
- ✅ Architecture decisions (actor design, concurrency patterns)
- ✅ Performance optimization (profiling + fixes)
- ✅ Integration work (Talaria SSE streaming setup)
- ✅ Code review findings with multiple fixes
- ✅ **Any task where you'll use >4 tools or make >3 decisions**
- ✅ **Any time you find yourself going in circles or repeating fixes**

**Why This is Mandatory:**
- **Persistent Memory:** Context doesn't evaporate - stops circular debugging
- **Error Tracking:** Log what failed to avoid repeating same mistakes
- **Decision History:** Document why approaches were chosen/rejected
- **Structured Thinking:** Forces systematic problem-solving instead of random attempts

**Planning Files You MUST Create:**
- `{task_name}_task_plan.md` - Phases, progress tracking, decision log, error attempts
- `{task_name}_findings.md` - Research discoveries, API insights, patterns, expert advice
- `{task_name}_progress.md` - Session log, test results, errors encountered (optional)

**Real Example from This Project:**
- Issue: Build failures after code review fixes
- Without planning: 8+ circular attempts fixing same issues
- With planning-with-files + PAL thinkdeep: Root cause identified in 3 steps
- Result: BUILD SUCCESSFUL after systematic diagnosis

**Only Skip Planning For:**
- ❌ Single-file edits (< 10 lines)
- ❌ Quick bug fixes (obvious one-line changes)
- ❌ Simple questions
- ❌ Trivial refactors (rename, format)

**If User Says "I keep failing" or You're Repeating Fixes:**
→ STOP immediately
→ Invoke /planning-with-files
→ Use PAL tools for expert help
→ Document everything systematically

### Epic-Based Vertical Slices

**Current Epic:** Check `epic-X.json` files or ralph-tui status.

**Epic 1 (Foundation):**
- Minimal skeleton: UI → Data → Network
- Dummy data, test endpoints
- **Goal:** Prove all layers connect

**Epic 2 (Camera):**
- AVFoundation camera preview
- Non-blocking shutter + image processing
- Processing queue UI
- **Goal:** Working scanner (no AI yet)

**Epic 3 (Library):**
- Library grid with LazyVGrid
- Full-text search
- Book detail sheets
- **Goal:** Browsable collection

**Epic 4 (Talaria Integration):**
- Multipart upload + SSE streaming
- Real-time AI enrichment
- Offline queue
- **Goal:** Full AI-powered scanning

**Epic 5-6:** Polish + Launch

### Talaria Backend Integration

**API Endpoints:**
- `POST /v3/jobs/scans` - Upload image, returns `{ jobId, sseUrl, authToken }`
- `GET {sseUrl}` - SSE stream for real-time progress (auth required if token provided)
- `DELETE /v3/jobs/scans/{jobId}/cleanup` - Cleanup after completion

**SSE Event Types:**
```swift
// Server-Sent Events (RFC 9457 compliant error handling)
event: progress       // {"stage": "analyzing_image", "progress": 25}
event: result         // {"book": {...}, "enrichmentStatus": "success"}
event: ping           // Keep-alive heartbeat (no data)
event: enrichment_degraded  // Graceful degradation (circuit breaker open)
event: complete       // Job finished successfully
event: error          // {"code": "...", "detail": "...", "retryable": true}
```

**Known API Inconsistencies (Documented):**

SwiftWing handles 5 known inconsistencies in Talaria API:

1. **Status Format Mismatch**: SSE events use `ScanStage` enum but status endpoint returns `JobStatus`. Always check both.
2. **Retry Field Names**: `Retry-After` header uses seconds but response body has `retryAfterMs` (milliseconds). Handler converts automatically.
3. **Field Naming**: Problem details use camelCase (non-standard) instead of snake_case.
4. **Enrichment Errors**: When enrichment endpoints fail, API returns `circuitOpen` status rather than error (graceful degradation).
5. **Error Metadata**: Not all error codes documented in OpenAPI spec. Check Talaria docs for authoritative list.

**Implementation Pattern (TalariaService):**
```swift
actor TalariaService {
    /// Upload a book spine image to Talaria for AI processing
    /// - Parameter image: JPEG image data
    /// - Returns: Tuple of (jobId, sseUrl) for monitoring progress
    /// - Throws: NetworkError.apiError with RFC 9457 problem details
    func uploadScan(_ image: Data) async throws -> (jobId: String, sseUrl: URL)

    /// Stream real-time progress and results via Server-Sent Events
    /// - Parameter sseUrl: URL from uploadScan response
    /// - Returns: AsyncThrowingStream<SSEEvent, Error> for progress monitoring
    /// - Yields: .progress(stage), .result(metadata), .ping, .complete, .error(details)
    func streamEvents(from sseUrl: URL) -> AsyncThrowingStream<SSEEvent, Error>

    /// Cleanup job and release server resources
    /// - Parameter jobId: ID from uploadScan response
    /// - Note: Called automatically on completion or error
    func cleanup(jobId: String) async throws
}
```

**Error Handling (RFC 9457):**
```swift
do {
    let (jobId, sseUrl) = try await talariaService.uploadScan(imageData)
} catch NetworkError.rateLimited(let retryAfter) {
    // API returned 429 - respect Retry-After header or body
    let delay = retryAfter ?? 60.0
    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
} catch NetworkError.apiError(let problem) {
    // RFC 9457 structured error
    if problem.retryable {
        // Automatic retry with exponential backoff
        let delayMs = problem.retryAfterMs ?? 60_000
        try await Task.sleep(nanoseconds: UInt64(delayMs * 1_000_000))
    } else {
        // Non-retryable error - show to user
        print("API Error: \(problem.code) - \(problem.detail)")
    }
}
```

**External Documentation Reference:**

For comprehensive Talaria API documentation beyond this file:
- **Talaria OpenAPI Spec:** `swiftwing/OpenAPI/talaria-openapi.yaml` (committed to repo)
- **Talaria API Documentation:** Available at https://api.oooefam.net/docs (external, requires access)
- **RFC 9457 Problem Details:** https://tools.ietf.org/html/rfc9457 (error format standard)
- **SwiftWing Integration Tests:** `swiftwingTests/TalariaIntegrationTests.swift` (real API examples)

For details on the 5 known API inconsistencies and workarounds:
- See `Services/NetworkTypes.swift` doc comments on `ProblemDetails` and error enums
- See `Services/TalariaService.swift` implementation comments on status mapping

**OpenAPI Specification Management:**

The Talaria OpenAPI spec is **committed to the repository** for deterministic, offline-capable builds.

**Location:**
```
swiftwing/OpenAPI/talaria-openapi.yaml  # Committed spec
swiftwing/OpenAPI/.talaria-openapi.yaml.sha256  # Checksum verification
```

**Update Workflow:**
```bash
# Fetch latest spec from Talaria server
scripts/update-api-spec.sh

# Review changes before committing
git diff swiftwing/OpenAPI/talaria-openapi.yaml

# Commit if changes are intentional
git add swiftwing/OpenAPI/
git commit -m "chore: Update Talaria OpenAPI spec"

# Rebuild to regenerate client code
xcodebuild ... | xcsift
```

**Script Features:**
- `--force` flag required to overwrite existing spec (safety)
- SHA256 checksum verification for integrity
- Shows diff preview before updating
- Requires confirmation unless `--force` is used

**Build Process:**
- Build phase runs `Scripts/copy-openapi-spec.sh`
- Copies committed spec to `swiftwing/Generated/openapi.yaml`
- Swift OpenAPI Generator creates client code from Generated/
- **No network calls during build** (offline-capable)

**Why Committed Spec:**
- ✅ Deterministic builds (same input = same output)
- ✅ Offline builds (no internet required)
- ✅ API changes go through code review
- ✅ Version control history of API evolution
- ✅ CI/CD reliability (no external dependencies)
- ✅ Security: Prevents supply chain attacks (no runtime fetching)
- ✅ Audit trail: All API changes reviewed and version-controlled

### Performance Targets

| Metric | Target | Where |
|--------|--------|-------|
| Camera cold start | < 0.5s | Epic 2 |
| UI frame rate | > 55 FPS | All epics |
| Image processing | < 500ms | Epic 2 |
| SSE connection | < 200ms | Epic 4 |

**Instrumentation:**
```swift
let start = CFAbsoluteTimeGetCurrent()
// ... operation ...
let duration = CFAbsoluteTimeGetCurrent() - start
print("Duration: \(duration)s")
```

## Swift OpenAPI Generator Integration

### Overview

SwiftWing uses **swift-openapi-generator** for type-safe API client generation. The project uses a **manual implementation approach** (TalariaService) while maintaining the OpenAPI spec for future automated generation.

**Current Architecture:**
- ✅ OpenAPI spec committed to repository
- ✅ Manual TalariaService implementation (actor-based)
- ⏭️ Future: Enable build plugin for auto-generated client

**Why Manual Implementation:**
- **Swift 6.2 Compatibility:** Full control over actor isolation
- **Custom Error Handling:** Domain-specific NetworkError types
- **SSE Streaming:** Custom AsyncThrowingStream implementation
- **Rapid Development:** Avoid Xcode build plugin configuration complexity
- **Type Safety:** Still based on committed OpenAPI spec

### swift-openapi-generator Package

**Installation:** (Already configured in Package.swift)
```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0")
]
```

**Target Dependencies:**
```swift
.target(
    name: "swiftwing",
    dependencies: [
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
        .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
    ]
)
```

### Using the Generator (Future)

**When to Enable:**
- After Epic 5-6 completion (post-MVP)
- When team wants automated client maintenance
- When API evolves frequently

**Steps to Enable Build Plugin:**

1. **Open Xcode Project**
   ```bash
   open swiftwing.xcodeproj
   ```

2. **Configure Build Plugin**
   - Select `swiftwing` target
   - Navigate to **Build Phases** tab
   - Add **Run Build Tool Plug-ins**
   - Select **OpenAPIGenerator** from list
   - Move plugin phase BEFORE "Compile Sources"

3. **Create openapi-generator-config.yaml**
   ```yaml
   # swiftwing/openapi-generator-config.yaml
   generate:
     - types
     - client
   accessModifier: internal
   ```

4. **Update openapi.yaml Location**
   Ensure `swiftwing/Generated/openapi.yaml` exists (build script creates this)

5. **Rebuild Project**
   ```bash
   xcodebuild -project swiftwing.xcodeproj -scheme swiftwing clean build 2>&1 | xcsift
   ```

6. **Verify Generated Code**
   Check `swiftwing/Generated/` for:
   - `Types.swift` - Schema types
   - `Client.swift` - API client

### TalariaService Actor Architecture

**Design Pattern:** Actor-isolated network service with domain model translation

**Architecture Diagram:**
```
┌─────────────────────────────────────────────────────────────┐
│                      SwiftUI Views                           │
│                    (CameraView, etc.)                        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ async/await calls
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   TalariaService (actor)                     │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Actor-Isolated State:                                │  │
│  │  - urlSession: URLSession                             │  │
│  │  - deviceId: String                                   │  │
│  │  - baseURL: String                                    │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  Public API (async methods):                                │
│  ┌──────────────────────────────────────────────┐           │
│  │ uploadScan(image:deviceId:)                  │           │
│  │   → (jobId: String, streamUrl: URL)          │           │
│  └──────────────────────────────────────────────┘           │
│                         │                                    │
│                         ├─→ Multipart/form-data construction│
│                         ├─→ POST /v3/jobs/scans             │
│                         └─→ Decode UploadResponse           │
│                                                              │
│  ┌──────────────────────────────────────────────┐           │
│  │ streamEvents(streamUrl:)                     │           │
│  │   → AsyncThrowingStream<SSEEvent, Error>    │           │
│  └──────────────────────────────────────────────┘           │
│                         │                                    │
│                         ├─→ Connect to SSE endpoint          │
│                         ├─→ Parse event stream               │
│                         └─→ Yield domain events              │
│                                                              │
│  ┌──────────────────────────────────────────────┐           │
│  │ cleanup(jobId:)                              │           │
│  │   → Void                                     │           │
│  └──────────────────────────────────────────────┘           │
│                         │                                    │
│                         └─→ DELETE cleanup endpoint          │
│                                                              │
│  Private Helpers:                                           │
│  - parseSSEEvent(event:data:) → SSEEvent                   │
│    ├─→ "progress" → .progress(String)                      │
│    ├─→ "result" → .result(BookMetadata)                    │
│    ├─→ "complete" → .complete                              │
│    └─→ "error" → .error(String)                            │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ Network I/O
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Talaria API (https://api.oooefam.net)           │
│  - POST /v3/jobs/scans                                      │
│  - GET {streamUrl} (SSE)                                    │
│  - DELETE /v3/jobs/scans/:jobId/cleanup                     │
└─────────────────────────────────────────────────────────────┘
```

**Actor Isolation Benefits:**
- **Data Race Prevention:** URLSession instance protected by actor
- **Thread Safety:** All network state mutations isolated
- **Swift 6.2 Compliance:** No `@unchecked Sendable` hacks
- **Async/Await Native:** No DispatchQueue/DispatchGroup (deadlock avoidance)

**Domain Model Translation:**

The actor translates OpenAPI types to SwiftWing domain models:

| OpenAPI Schema | TalariaService Type | Domain Model |
|----------------|---------------------|--------------|
| UploadResponse | UploadResponse struct | Internal |
| BookMetadata | BookMetadata struct | Exposed to app |
| SSE events (text) | SSEEvent enum | Domain events |

**Example Translation (in parseSSEEvent):**
```swift
// Raw SSE: event: result, data: {"title":"...", "author":"..."}
case "result":
    let metadata = try decoder.decode(BookMetadata.self, from: jsonData)
    return .result(metadata)  // Domain event
```

**Performance Characteristics (US-509 Benchmarks):**
- Upload latency: < 1000ms ✅
- SSE first event: < 500ms ✅
- 5 concurrent uploads: < 10s ✅
- SSE parsing CPU: < 15% main thread ✅ (manual profiling)
- Memory: Zero leaks in 10-minute session ✅ (Instruments validation)

**Error Handling Strategy:**
```swift
enum NetworkError: Error {
    case noConnection          // Network unreachable
    case timeout               // Request timeout
    case rateLimited(retryAfter: TimeInterval?)  // 429 with Retry-After
    case serverError(Int)      // 5xx errors
    case invalidResponse       // Malformed data
}
```

**Integration Testing:**
- Real API tests in `swiftwingTests/TalariaIntegrationTests.swift`
- 7 test methods covering all endpoints
- See `TalariaIntegrationTests_README.md` for details

### Rollback Procedures

**Scenario 1: Bad API Spec Update**

If `update-api-spec.sh` fetches a breaking spec:

1. **Verify Git Status**
   ```bash
   git status
   # Should show modified: swiftwing/OpenAPI/talaria-openapi.yaml
   ```

2. **Review Changes**
   ```bash
   git diff swiftwing/OpenAPI/talaria-openapi.yaml
   ```

3. **Rollback Spec**
   ```bash
   git checkout swiftwing/OpenAPI/talaria-openapi.yaml
   git checkout swiftwing/OpenAPI/.talaria-openapi.yaml.sha256
   ```

4. **Rebuild**
   ```bash
   xcodebuild -project swiftwing.xcodeproj -scheme swiftwing clean build 2>&1 | xcsift
   ```

**Scenario 2: Need Previous Spec Version**

1. **Check Git History**
   ```bash
   git log --oneline swiftwing/OpenAPI/talaria-openapi.yaml
   ```

2. **View Specific Version**
   ```bash
   git show <commit-hash>:swiftwing/OpenAPI/talaria-openapi.yaml > /tmp/old-spec.yaml
   ```

3. **Restore Old Version**
   ```bash
   git checkout <commit-hash> -- swiftwing/OpenAPI/talaria-openapi.yaml
   git checkout <commit-hash> -- swiftwing/OpenAPI/.talaria-openapi.yaml.sha256
   ```

4. **Commit Rollback**
   ```bash
   git add swiftwing/OpenAPI/
   git commit -m "chore: Rollback OpenAPI spec to <commit-hash> due to breaking changes"
   ```

**Scenario 3: Corrupted Spec File**

If checksum verification fails:

1. **Verify Corruption**
   ```bash
   cd swiftwing/OpenAPI
   shasum -a 256 talaria-openapi.yaml
   cat .talaria-openapi.yaml.sha256
   # Compare - if different, file is corrupted
   ```

2. **Re-fetch from Server**
   ```bash
   ../../Scripts/update-api-spec.sh --force
   ```

3. **Or Restore from Git**
   ```bash
   git checkout HEAD -- swiftwing/OpenAPI/
   ```

### Troubleshooting OpenAPI Build Errors

#### Error: "No such file or directory: openapi.yaml"

**Cause:** Build script didn't copy spec to Generated/

**Solution:**
```bash
# Manually run copy script
bash Scripts/copy-openapi-spec.sh

# Verify file exists
ls -la swiftwing/Generated/openapi.yaml

# Rebuild
xcodebuild ... | xcsift
```

#### Error: "OpenAPIGenerator plugin not found"

**Cause:** Build plugin not enabled in Xcode target

**Solution:**
- This is expected (we're not using the plugin yet)
- If you want to enable it, see "Steps to Enable Build Plugin" above
- For now, TalariaService works without generated code

#### Error: "Cannot find type 'Components' in scope"

**Cause:** Trying to use generated types that don't exist

**Solution:**
```swift
// ❌ Don't use generated types (not generated yet)
let metadata: Components.Schemas.BookMetadata

// ✅ Use manual types
let metadata: BookMetadata  // From NetworkTypes.swift
```

#### Error: "Failed to parse OpenAPI spec"

**Cause:** Invalid YAML syntax in committed spec

**Solution:**
```bash
# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('swiftwing/OpenAPI/talaria-openapi.yaml'))"

# If invalid, check diff
git diff swiftwing/OpenAPI/talaria-openapi.yaml

# Rollback if necessary (see Rollback Procedures above)
```

#### Error: "Network error: The certificate for this server is invalid"

**Cause:** HTTPS certificate issue (usually in Simulator)

**Solution:**
```swift
// ⚠️ DEVELOPMENT ONLY - Never ship this
#if DEBUG
let configuration = URLSessionConfiguration.default
configuration.urlCache = nil
configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
#endif
```

**For Production:**
- Ensure Talaria API has valid HTTPS certificate
- Add certificate pinning for security

#### Error: "Rate limited (429)"

**Cause:** Too many requests to Talaria API

**Solution:**
```swift
// In TalariaService.uploadScan:
case 429:
    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
        .flatMap { TimeInterval($0) }
    throw NetworkError.rateLimited(retryAfter: retryAfter)

// In calling code:
do {
    let (jobId, streamUrl) = try await service.uploadScan(...)
} catch NetworkError.rateLimited(let retryAfter) {
    print("Rate limited. Retry after \(retryAfter ?? 60) seconds")
    // Show user-friendly message
}
```

#### Warning: "Uncommitted changes in OpenAPI spec"

**Cause:** Modified talaria-openapi.yaml not committed

**Solution:**
```bash
# Review changes
git diff swiftwing/OpenAPI/talaria-openapi.yaml

# If intentional, commit
git add swiftwing/OpenAPI/
git commit -m "chore: Update Talaria OpenAPI spec"

# If accidental, rollback
git checkout swiftwing/OpenAPI/
```

## Critical Patterns

### Defer Complexity

**Bad (Over-engineering in Epic 1):**
```swift
// Don't build full offline-first network layer yet
class NetworkManager {
    func upload(retryCount: Int, backoff: ExponentialBackoff) async throws
}
```

**Good (Minimal in Epic 1, enhance in Epic 4):**
```swift
// Simple test fetch in Epic 1
func fetchTestData() async throws -> TestPost {
    let url = URL(string: "https://jsonplaceholder.typicode.com/posts/1")!
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(TestPost.self, from: data)
}
```

### Camera Integration (Epic 2)

**AVFoundation Bridge:**
```swift
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}
```

**Performance:**
- Use 30 FPS preset (battery efficiency)
- Pixel format: `kCVPixelBufferPixelFormatType_420YpCbCr8BiPlanarVideoRange`
- Process images with `Task.detached` (`.userInitiated` priority)

### Non-Blocking UI Pattern

**Critical:** Shutter button must never block user interaction.

```swift
Button("Capture") {
    // Fire and forget - don't await
    Task.detached(priority: .userInitiated) {
        await captureAndProcess()
    }
}
```

## Documentation References

**Planning Docs:**
- `PRD.md` - Full product requirements
- `EPIC-1-STORIES.md` - Current implementation guide
- `VERTICAL-SLICES.md` - Feature-based development strategy
- `findings.md` - iOS 26 APIs and architecture decisions

**Epic JSONs:**
- `epic-1.json` through `epic-6.json` - Ralph-TUI configurations

**If stuck:** Check `START-HERE.md` for orientation.

## Info.plist Requirements

```xml
<!-- Camera permission (required for Epic 2+) -->
<key>NSCameraUsageDescription</key>
<string>SwiftWing uses your camera to scan book spines for automatic identification.</string>

<!-- Custom fonts -->
<key>UIAppFonts</key>
<array>
    <string>JetBrainsMono-Regular.ttf</string>
</array>
```

## Common Pitfalls

### ❌ NEVER Call xcodebuild Directly
**ABSOLUTE RULE: ALWAYS pipe xcodebuild through xcsift**

```bash
# ✅ CORRECT - Always use this pattern
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift

# ❌ WRONG - Never call xcodebuild without xcsift
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing build

# ❌ WRONG - xcsift is not a build command (it's a formatter)
xcsift build
```

**Why This Matters:**
- xcsift parses xcodebuild output into structured JSON
- Makes errors machine-readable for diagnosis
- Essential for automated problem-solving
- Without xcsift, you're flying blind on build errors

### ❌ Don't Skip planning-with-files for Complex Tasks
If a task requires >4 tool calls or you're debugging build failures, you MUST use `/planning-with-files` first. No exceptions. Circular debugging wastes time and frustrates users.

### ❌ Don't Build Full Features in Epic 1
Epic 1 is a **Walking Skeleton** - minimal code to prove architecture works. Defer design systems, offline logic, and complex state management to later epics.

### ❌ Don't Use Horizontal Slicing
Build features vertically (UI → Logic → Data → Network in one epic), not layers horizontally (all models, then all services, then all UI).

### ❌ Don't Fight Swift 6.2 Concurrency
Compiler errors about data races are helping you. Use actors, don't bypass with `@unchecked Sendable`.

### ✅ Do Verify Builds BEFORE Code Reviews
**Critical Workflow: Build → Review → Fix → Build**

**ABSOLUTE REQUIREMENT: ZERO WARNINGS**

Never run code reviews on code that doesn't build cleanly. Always:
1. First: `xcodebuild ... | xcsift` to verify **0 errors, 0 warnings**
2. Then: Run static analysis / code review
3. Finally: Apply fixes and re-verify **0 errors, 0 warnings**

**Build Success Criteria:**
```json
{
  "summary": {
    "errors": 0,     // ✅ Required
    "warnings": 0    // ✅ Required - NOT NEGOTIABLE
  }
}
```

**If warnings > 0:** Task is NOT complete. Fix all warnings before declaring done.

**Lesson from this project:** Gemini Pro 3 and Grok reviewed code that had missing files and never built. Wasted hours debugging review fixes when the base code was broken. Later, declared build "successful" with 14 warnings - user rightfully rejected.

### ✅ Do Keep Stories Small
Each user story should take 1-2 hours max. If larger, break it down.

### ✅ Do Ship Working Code Every Epic
Each epic should be demoable. Epic 2 = working scanner (no AI). Epic 3 = browsable library. Epic 4 = AI enrichment.

## Testing Strategy

**Epic 1:** Manual verification only (tap buttons, see results)
**Epic 2+:** Add unit tests for:
- Image processing functions
- SwiftData queries
- Network parsing
- SSE stream handling

**Performance Tests:**
- Camera cold start (< 0.5s)
- UI frame rate (> 55 FPS with Instruments)
- Image processing (< 500ms)

## Future Considerations

**Post-Epic 6 (After Launch):**
- iPad version with optimized layout
- Collections/shelves organization
- Loan tracking (who borrowed what)
- Reading progress tracking
- Widgets (home screen library stats)

**Don't plan these now** - ship the MVP first (Epics 1-6).

---

## Claude Code Configuration

### Available Skills

Skills are specialized workflows invoked with `/skill-name` syntax:

**Planning & Development:**
- `/planning-with-files` - Manus-style file-based planning (REQUIRED for >4 tool calls)
- `/feature-dev` - Guided feature development with codebase analysis
- `/gogo` - Quick commit + push workflow (no PR creation)
- `/commit-push-pr` - Full workflow: commit → push → PR (for releases)

**Code Quality:**
- `/review` - Code quality review (leverage PAL MCP tools)

**Full Skill Name (if shorthand fails):**
```bash
# If /commit doesn't work, use:
/commit-commands:commit

# If /planning-with-files doesn't work, use:
/planning-with-files:planning-with-files
```

### PAL MCP Tools

Advanced analysis tools available via Model Context Protocol:

**Deep Investigation:**
- `mcp__pal__debug` - Systematic debugging with hypothesis testing
- `mcp__pal__thinkdeep` - Multi-stage reasoning for complex problems
- `mcp__pal__analyze` - Comprehensive code analysis

**Code Quality:**
- `mcp__pal__codereview` - Architecture and quality review
- `mcp__pal__refactor` - Refactoring opportunity analysis
- `mcp__pal__secaudit` - Security vulnerability assessment

**Planning & Design:**
- `mcp__pal__planner` - Interactive sequential planning
- `mcp__pal__consensus` - Multi-model consensus building
- `mcp__pal__chat` - Collaborative thinking partner

**Specialized:**
- `mcp__pal__tracer` - Code execution flow tracing
- `mcp__pal__testgen` - Comprehensive test suite generation
- `mcp__pal__docgen` - Documentation generation with complexity analysis

**When to Use PAL Tools:**
- Swift 6.2 concurrency debugging (data race investigation)
- AVFoundation camera performance optimization
- SwiftData query performance analysis
- Security review (Info.plist permissions, data handling)
- Architecture decisions (actor design patterns)

### Hooks (Future Configuration)

Claude Code supports automated triggers via `.claude/settings.json`:

**Recommended Hooks for SwiftWing:**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo '📱 SwiftWing iOS 26 | Current Epic: Check ralph-tui status'",
            "timeout": 3000
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/suggest-planning.sh",
            "timeout": 3000
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash(xcodebuild*)",
        "hooks": [
          {
            "type": "command",
            "command": "echo '🔨 Build completed. Consider running tests.'",
            "timeout": 2000
          }
        ]
      }
    ]
  }
}
```

**Hook Ideas:**
- `SessionStart` - Display current epic status
- `UserPromptSubmit` - Auto-detect complex tasks, suggest `/planning-with-files`
- `PostToolUse(Bash)` - Detect `xcodebuild` or `xcsift`, suggest test runs
- `PreToolUse(Bash)` - Validate Xcode project before builds

### Rules Directory (Future)

Create `.claude/rules/` for persistent project constraints:

**Suggested Rules:**

`.claude/rules/swift-concurrency.md`:
```markdown
# Swift 6.2 Concurrency Rules

- ALWAYS use actors for mutable shared state
- NEVER use DispatchQueue/DispatchSemaphore with async/await
- Use structured concurrency (TaskGroup, async let)
- Avoid Task.detached unless absolutely necessary
- MainActor isolation for all SwiftUI view updates
```

`.claude/rules/swiftdata-patterns.md`:
```markdown
# SwiftData Best Practices

- @Model classes must be final
- Use @Attribute(.unique) for identifiers
- Always use @Query for reactive updates
- SwiftData writes must happen on @MainActor
- Use modelContext from @Environment, never store
```

`.claude/rules/ios-design.md`:
```markdown
# Swiss Glass Design System

- Black base (#0D0D0D) for OLED optimization
- .ultraThinMaterial for glass effects
- International Orange (#FF4F00) for accents only
- JetBrains Mono for data/IDs, SF Pro for UI
- Spring animations (.spring(duration: 0.2))
- 12px rounded corners with 1px white borders
```

### Commands (Future)

Custom shell commands for project automation:

`.claude/commands/epic-status.sh`:
```bash
#!/bin/bash
# Show current epic progress
ralph-tui status | head -20
echo ""
echo "📋 Planning files:"
ls -1 task_plan.md findings.md progress.md 2>/dev/null || echo "  None (use /planning-with-files)"
```

`.claude/commands/build-and-test.sh`:
```bash
#!/bin/bash
# Build and run basic validation
echo "🔨 Building SwiftWing..."
xcsift build -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'

if [ $? -eq 0 ]; then
  echo "✅ Build succeeded"
  echo "💡 Run in Xcode (Cmd+R) to test in simulator"
else
  echo "❌ Build failed. Check errors above."
  exit 1
fi
```

### Settings Configuration

Create `.claude/settings.json` for project-specific configuration:

```json
{
  "respectGitignore": true,
  "plansDirectory": ".claude/plans",
  "attribution": {
    "commit": "🤖 Co-Authored-By: Claude Code <noreply@anthropic.com>"
  },
  "fileSuggestion": {
    "type": "command",
    "command": "find swiftwing -type f \\( -name '*.swift' -o -name '*.json' -o -name '*.md' \\) 2>/dev/null"
  },
  "permissions": {
    "Bash": "*",
    "Read": "*",
    "Write": "*",
    "Edit": "*",
    "Glob": "*",
    "Grep": "*",
    "Task": "*",
    "Skill(planning-with-files)": "*",
    "Skill(commit)": "*",
    "mcp__pal__debug": "*",
    "mcp__pal__codereview": "*"
  }
}
```

---

## Quick Reference

### When Starting a New Task

1. **Is it complex? (>4 tool calls expected)**
   - ✅ Yes → `/planning-with-files` first
   - ❌ No → Proceed directly

2. **Check Current Epic**
   ```bash
   ralph-tui status
   ```

3. **Review Planning Docs**
   - Epic guide: `EPIC-X-STORIES.md`
   - Architecture: `findings.md`
   - Progress: `task_plan.md` (if exists)

4. **Before Major Decisions**
   - Read planning files to refresh context
   - Consider using `mcp__pal__planner` for architecture choices
   - Use `mcp__pal__consensus` for critical tradeoffs

5. **After Completing Work**
   - Update `task_plan.md` phase status
   - Log any errors in `progress.md`
   - Use `/gogo` to commit + push incremental progress

### Troubleshooting

**Swift Concurrency Issues:**
- Use `mcp__pal__debug` with focus on data race patterns
- Check `findings.md` for Swift 6.2 actor patterns

**Performance Problems:**
- Use `mcp__pal__analyze` with `analysis_type: "performance"`
- Instrument with CFAbsoluteTimeGetCurrent()
- Compare against targets in this file

**Build Failures:**
- Check Xcode project structure
- Validate Info.plist configuration
- Ensure Swift 6.2 language mode enabled

---

**Last Updated:** January 22, 2026
**Claude Code Features:** Skills, PAL MCP, Planning-with-Files, Hooks (v2.0.64+)
**Setup Guide:** This file covers configuration; implement `.claude/` directory as needed
