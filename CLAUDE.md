# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**SwiftWing** is a native iOS 26 book spine scanner app that uses camera + AI (Talaria backend) to automatically identify and catalog books. Built with SwiftUI, SwiftData, Swift 6.2 concurrency, and AVFoundation.

**Bundle ID:** `com.ooheynerds.swiftwing`
**Min Deployment:** iOS 26.0 (current-gen devices only)
**Architecture:** MVVM + Actor-based services (vertical slice epics)

**Epic Status:** Epics 1-5 complete. Epic 6 (App Store Launch) in progress.

## Building & Running

**CRITICAL: ALWAYS pipe xcodebuild through xcsift — never call xcodebuild directly**

```bash
# Build
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift

# Clean build
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  clean build 2>&1 | xcsift
```

**Required:** `errors: 0, warnings: 0`. Any warning is a failure. See `.claude/rules/build-workflow.md`.

**Ralph-TUI:** `ralph-tui status` to check current epic. `ralph-tui load epic-6.json` to load epic tasks.

## Architecture

```
SwiftUI Views → @Observable ViewModels → Actor Services → SwiftData
```

**Key files:**

| File | Role |
|------|------|
| `App/RootView.swift` | Tab container (Camera / Library) |
| `Features/Camera/CameraView.swift` | Camera UI (~280 lines) |
| `Features/Camera/CameraViewModel.swift` | Camera business logic |
| `Features/Camera/CameraOverlayView.swift` | Camera overlay composition |
| `Features/Camera/CameraHapticsManager.swift` | Haptic feedback coordinator |
| `Features/Library/LibraryView.swift` |
| `Features/Library/LibraryViewModel.swift` | Library business logic |
| `Features/Library/LibraryGridView.swift` | Library grid display |
| `Features/ReviewQueue/ReviewQueueView.swift` | Review queue container (~220 lines) |
| `Features/ReviewQueue/ReviewCardView.swift` | Individual review card |
| `Services/TalariaService.swift` | Network + SSE actor |
| `Models/Book.swift` | SwiftData model |

### Folder Organization

```
swiftwing/
├── App/                  # SwiftwingApp.swift, RootView, LaunchScreen
├── Features/
│   ├── Camera/           # Camera capture, preview, overlays (14 files)
│   ├── Library/          # Book library grid, search, filtering (8 files)
│   ├── ReviewQueue/      # Book review/approve workflow (5 files)
│   ├── Onboarding/       # First-run onboarding
│   └── Settings/         # Debug feature flags
├── UIComponents/         # Theme, shared views (AsyncImage, ConfidenceBadge)
├── Services/             # TalariaService, network, caching (11 files)
├── Models/               # SwiftData @Model classes (6 files)
├── Utilities/            # Performance test data
├── OpenAPI/              # Committed Talaria API spec
│   └── talaria-openapi.yaml
├── Generated/            # Auto-generated code (not committed)
├── Fonts/                # JetBrains Mono
└── Assets.xcassets/
```

### Concurrency (Swift 6.2)

- `TalariaService` (actor) — network + SSE streams
- `CameraManager` (actor) — AVCaptureSession
- `ImagePreprocessor` (actor) — image processing; CIFilter pipeline offloaded via `Task.detached`
- `DataSyncActor` (@MainActor class) — centralises all SwiftData writes; uses `@MainActor` rather than `actor` because `ModelContext` and `DuplicateDetection` are both `@MainActor`-bound

**Rules:** Use actors only for mutable shared state. No `DispatchSemaphore`/`DispatchGroup` with async/await (deadlock risk). Use structured concurrency (`TaskGroup`, `async let`). `Task.detached` is permitted only for CPU-bound work that must run off the actor (e.g. image processing pipelines); avoid it for general async coordination.

### SwiftData

```swift
@Model final class Book {
    @Attribute(.unique) var isbn: String
    var id: UUID
    var title: String
    var authors: [String]
    // ...
}
```

Use `@Environment(\.modelContext)` — not `\.modelContainer` (does not exist as an environment key). See `.claude/rules/swiftdata-patterns.md`.

### Design Language: Swiss Glass Hybrid

60% Swiss Utility + 40% Liquid Glass. Defined in `Theme.swift`:
- Black base `#0D0D0D` (OLED optimization)
- `.ultraThinMaterial` overlays for depth
- International Orange `#FF4F00` accent
- JetBrains Mono for data/IDs, SF Pro for UI
- Spring animations `.spring(duration: 0.2)`, 12px rounded corners

## AI Collaboration Workflow

### Planning-with-Files (MANDATORY for complex tasks)

Use `/planning-with-files` before any task requiring >4 tool calls. This is non-negotiable. See `.claude/rules/planning-mandatory.md` for the full policy.

### Talaria Backend Integration

**API Contract & Schema Boundaries (CRITICAL UPDATE — April 2026)**

Talaria v3.5.0+ clarifies the schema boundary between the external API contract and internal canonical models:

**Upload Response (POST /v3/jobs/scans):**
```swift
// API Contract (external) — matches JobResponseSchema from Talaria
{
  "success": true,
  "data": {
    "jobId": "550e8400-e29b-41d4-a716-446655440000",    // UUID string
    "status": "initialized",                              // JobStatus enum
    "streamUrl": "https://api.oooefam.net/...",          // SSE endpoint
    "token": "eyJhbGc..."                                // Optional auth token
  }
}

// Swiftwing mapping: (jobId: String, streamUrl: URL, status: JobStatus, token: String?)
```

**BookMetadata from SSE & Results (CRITICAL: API Contract Boundary):**
- **External API contract:** Uses singular `author: String` (for Swiftwing compatibility)
- **Internal canonical model:** Uses plural `authors: [String]` (for future enrichment)
- **Swiftwing strategy:** Accept both formats via custom decoder (forward-compatible)

```swift
// API Contract (external — current format)
{
  "title": "The Great Gatsby",
  "author": "F. Scott Fitzgerald",      // Singular (API contract)
  "isbn": "9780743273565",
  "enrichmentStatus": "success",
  "confidence": 0.98
}

// Future format (already supported)
{
  "title": "The Great Gatsby",
  "authors": ["F. Scott Fitzgerald"],   // Plural (canonical)
  "isbn": "9780743273565",
  "enrichmentStatus": "success"
}

// Swiftwing decoder joins plural authors: "F. Scott Fitzgerald, Co-Author"
// Prefers singular author if both present
```

**EnrichmentStatus Variations:**
- `success` — Full enrichment complete
- `review_needed` — Ambiguous spine; title/author are null; client should prompt review
- `circuit_open` — Enrichment endpoint down; basic metadata present, covers/reviews missing
- `not_found` — Book not in database
- `error` — Enrichment failed; see error details
- Unknown values default to `pending` (backward-compatible)

**Contract Validation & Testing:**
- Use `TalariaContractFixtures.swift` for CI-safe testing (no live API dependency)
- Contract adherence tests in `TalariaContractAdherenceTests.swift`
- Fixtures include edge cases: missing fields, malformed URLs, unexpected types
- Resilient decoding: single field corruption doesn't kill entire book parse

**Handling Missing/Malformed Fields:**
```swift
// Resilient decoding strategy
coverUrl = try? container.decodeIfPresent(URL.self, forKey: .coverUrl)  // Malformed URL silently fails
confidence = try? container.decodeIfPresent(Double.self, forKey: .confidence)  // Type mismatch handled
enrichmentStatus = try? container.decodeIfPresent(EnrichmentStatus.self, forKey: .enrichmentStatus)  // Unknown values default to pending

// Display-safe fallbacks
var resolvedTitle: String { title ?? "Unknown Title" }
var resolvedAuthor: String { author ?? "Unknown Author" }
```

**API Endpoints (Updated April 2026):**
- `POST /v3/jobs/scans` — upload image, returns `{ jobId, status, streamUrl, token }`
- `GET {streamUrl}` — SSE stream for real-time progress
- `DELETE /v3/jobs/scans/{jobId}/cleanup` — no-op since Feb 2026 (images auto-deleted)

**SSE Event Types** (unchanged):
```
event: progress       // {"message": "...", "progress": 0.35, "processedCount": 1, "totalCount": 3}
event: result         // {"book": {title, author, isbn, ...}, "processedCount": 1, "totalCount": 7}
event: completed      // {"totalDetected": 7, "books": [...], "duration": {...}}
event: ping           // Keep-alive heartbeat
event: enrichment_degraded  // Circuit breaker open (graceful degradation)
event: error          // {"error": "...", "code": "...", "retryable": true}
```

**SSE deduplication is critical:** Talaria sends books via both `.result` events and inline in `.complete`. The deduplication guard in `CameraViewModel` is mission-critical.

**Known API quirks (handled automatically):**
1. `Retry-After` header is seconds; response body `retryAfterMs` is milliseconds
2. Problem details use camelCase instead of snake_case
3. Enrichment failures return `circuitOpen` status rather than error
4. UploadResponse now includes `status` field for job state tracking (initialize, processing, etc.)

**API references:**
- OpenAPI spec: `swiftwing/OpenAPI/talaria-openapi.yaml` (committed)
- Contract fixtures: `swiftwingTests/Fixtures/TalariaContractFixtures.swift`
- Contract adherence tests: `swiftwingTests/Unit/Services/TalariaContractAdherenceTests.swift`
- Talaria docs: `https://api.oooefam.net/docs`

**OpenAPI spec update:**
```bash
./Scripts/update-api-spec.sh          # normal (checksum verification)
./Scripts/update-api-spec.sh --force  # bypass checksum
git diff swiftwing/OpenAPI/talaria-openapi.yaml  # review before committing
```
Rollback: `git checkout swiftwing/OpenAPI/` to restore committed spec.

### Performance Targets

| Metric | Target |
|--------|--------|
| Camera cold start | < 0.5s |
| UI frame rate | > 55 FPS |
| Image processing | < 500ms |
| SSE connection | < 200ms |

**Instrumentation:** Use `CFAbsoluteTimeGetCurrent()` for timing. **Logging:** Use OSLog — `print()` does not appear in production device logs.

```swift
import os
private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "camera")
logger.info("Session started")
logger.error("Upload failed: \(error)")
```

## Critical Patterns

### Camera (Non-blocking shutter)

```swift
Button("Capture") {
    Task {  // Fire and forget — never await in button action
        await captureAndProcess()
    }
}
```

### Error Handling (RFC 9457)

```swift
do {
    let (jobId, sseUrl) = try await talariaService.uploadScan(imageData)
} catch NetworkError.rateLimited(let retryAfter) {
    let delay = retryAfter ?? 60.0
    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
} catch NetworkError.apiError(let problem) {
    if problem.retryable {
        let delayMs = problem.retryAfterMs ?? 60_000
        try await Task.sleep(nanoseconds: UInt64(delayMs * 1_000_000))
    }
}
```

## Common Pitfalls

- **Never call xcodebuild without xcsift** — output is unparseable without it
- **Never use `@Environment(\.modelContainer)`** — use `\.modelContext` instead
- **Never mix DispatchQueue with async/await** — deadlock risk; use `@MainActor`
- **Never ignore Swift 6.2 concurrency warnings** — all warnings are errors in this project
- **Build before reviews** — never run code review on code that hasn't built cleanly

## Testing

**UI Tests:** Always use `-parallel-testing-enabled NO` (without it, simulator clone fails).

```bash
xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:swiftwingUITests \
  -parallel-testing-enabled NO \
  2>&1 | xcsift
```

See `docs/testing/TESTING-CHECKLIST.md` for regression checklist.

## Skills & Tools

**Skills:**
- `/planning-with-files` — file-based planning (REQUIRED for >4 tool calls)
- `/gogo` — quick commit + push
- `/commit-push-pr` — commit → push → PR

**PAL MCP Tools:**
- `mcp__pal__debug` — systematic debugging
- `mcp__pal__thinkdeep` — multi-stage reasoning
- `mcp__pal__codereview` — architecture review
- `mcp__pal__analyze` — code analysis
- `mcp__pal__secaudit` — security audit

## Key Documentation

| File | Purpose |
|------|---------|
| `START-HERE.md` | Orientation for new contributors |
| `AGENTS.md` | Agent-optimized architecture reference |
| `PRD.md` | Full product requirements |
| `docs/` | Architecture, testing docs |
| `.claude/rules/` | Build workflow, Swift conventions, planning policy |
| `.archive/` | Completed epic summaries, historical planning |

---

**Last Updated:** April 7, 2026
