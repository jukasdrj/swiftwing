# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**SwiftWing** is a native iOS 27 book spine scanner app that uses camera + AI (Talaria backend) to automatically identify and catalog books. Built with SwiftUI, SwiftData, Swift 6.4 concurrency, and AVFoundation.

**Bundle ID:** `com.ooheynerds.swiftwing`
**Min Deployment:** iOS 27.0 (current-gen devices only)
**Architecture:** MVVM + Actor-based services (vertical slice epics)

**Epic Status:** Epics 1-5 complete. Epic 6 (App Store Launch) in progress.

## Building & Running

**CRITICAL: ALWAYS pipe xcodebuild through xcsift — never call xcodebuild directly**

```bash
# Build
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  build 2>&1 | xcsift

# Clean build
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
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
| `Features/Camera/CameraFirstRunGuidance.swift` | One-time camera coach overlay (`hasSeenCameraGuidance`) |
| `Features/Library/LibraryView.swift` |
| `Features/Library/LibraryViewModel.swift` | Library business logic |
| `Features/Library/LibraryGridView.swift` | Library grid display |
| `Features/ReviewQueue/ReviewQueueView.swift` | Review queue container (~220 lines) |
| `Features/ReviewQueue/ReviewCardView.swift` | Individual review card |
| `Features/ReviewQueue/ManualLookupSheet.swift` | Manual `/v3/books/search` recovery for failed enrichment |
| `Services/TalariaService.swift` | Network + HTTP polling actor |
| `Models/Book.swift` | SwiftData model |

### Folder Organization

```
swiftwing/
├── App/                  # SwiftwingApp.swift, RootView
├── Features/
│   ├── Camera/           # Camera capture, preview, overlays (18 files)
│   ├── Library/          # Book library grid, search, filtering (9 files)
│   ├── ReviewQueue/      # Book review/approve workflow (6 files)
│   ├── Onboarding/       # First-run onboarding
│   └── Settings/         # Debug feature flags
├── UIComponents/         # Theme, AsyncImageWithLoading, OfflineIndicatorView
├── Services/             # TalariaService, network, caching (10 files)
├── Models/               # SwiftData @Model classes (7 files)
├── Utilities/            # Performance test data
├── OpenAPI/              # Committed Talaria API spec
│   └── talaria-openapi.yaml
├── Generated/            # Auto-generated code (not committed)
├── Fonts/                # JetBrains Mono
└── Assets.xcassets/
```

### Concurrency (Swift 6.4)

- `TalariaService` (actor) — network + HTTP status polling
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

Use file-based planning before any task requiring >4 tool calls. This is non-negotiable. See `.claude/rules/planning-mandatory.md` for the full policy.

### Talaria Backend Integration

**API Contract (Talaria 3.9.0 — July 2026)**

Talaria runs **Cloudflare Workflows + HTTP polling** (SSE, firehose, and cleanup endpoints removed).

**Scan workflow:**
1. `POST /v3/jobs/scans` — multipart `photos[]` (exactly **one** photo), header `X-Device-ID` (UUID v4)
2. `GET /v3/jobs/scans/{jobId}` — poll until `completed` / `failed` / `canceled`
3. `GET /v3/jobs/scans/{jobId}/results?format=lite` — fetch detected books

**Upload Response (POST /v3/jobs/scans → 202):**
```json
{
  "success": true,
  "data": {
    "jobId": "550e8400-e29b-41d4-a716-446655440000",
    "status": "queued"
  }
}
```

// SwiftWing mapping: `(jobId: String, status: JobStatus)`

**Job status values:** `queued` | `processing` | `completed` | `failed` | `canceled`  
(Client also maps legacy `initialized` → `queued`.)

**BookMetadata from results (API contract boundary):**
- **External API:** singular `author: String` (SwiftWing compatibility) + optional `authors[]`
- **Hoisted enrichment fields:** `coverUrl`, `publisher`, `publishedDate`, top-level `enrichmentStatus`
- **SwiftWing strategy:** accept singular or plural authors; resilient optional-field decoding

```swift
// API Contract (external — current format)
{
  "title": "The Great Gatsby",
  "author": "F. Scott Fitzgerald",
  "isbn": "9780743273565",
  "enrichmentStatus": "success",
  "confidence": 0.98,
  "coverUrl": "https://..."
}
```

**EnrichmentStatus Variations:**
- `success` — Full enrichment complete
- `review_needed` — Ambiguous spine; client should prompt review
- `circuit_open` — Enrichment endpoint down; basic metadata may still be present
- `not_found` — Book not in database
- `error` — Enrichment failed
- Unknown values default to `pending` (backward-compatible)

**Enrichment recovery:** `not_found`, `circuit_open`, and `review_needed` open manual lookup in the review queue. `ReviewCardView` shows a "Look up manually" button for those three; `.error` does not. It opens `ManualLookupSheet`, which calls `GET /v3/books/search` and grafts the result onto the pending item via `ReviewQueueManager.applyRecoveredMetadata`. That sets `recoveredMetadata` (the original AI result stays on `metadata` for provenance) and flips status to `success`, so the button disappears on its own. **Read and persist `PendingBookResult.resolvedMetadata`, not `.metadata`** — `resolvedISBN` is the duplicate-detection key, and dedup must see a recovered ISBN. A refused save leaves the card on screen.

**Contract Validation & Testing:**
- Use `TalariaContractFixtures.swift` for CI-safe testing (no live API dependency)
- Contract adherence tests in `TalariaContractAdherenceTests.swift`

**API Endpoints (3.9.0):**
- `POST /v3/jobs/scans` — upload one photo → `{ jobId, status }`
- `GET /v3/jobs/scans/{jobId}` — status poll (`progress` 0.0–1.0; optional `error` on failure)
- `GET /v3/jobs/scans/{jobId}/results?format=lite|full` — results when completed
- `DELETE /v3/jobs/scans/{jobId}` — cancel job
- `GET /v3/books/search?isbn=&title=&author=` — single best-match manual lookup; at least one param required. Backs the review queue's enrichment-recovery sheet (`ManualLookupSheet`). `404` = no match, surfaced as `NetworkError.apiError(status: 404)` — deliberately **not** a new `NetworkError` case, so existing exhaustive switches stay intact.
- ~~SSE / firehose / cleanup~~ — removed (404)

**Deduplication:** still required when processing results arrays (same book may appear once; guard by ISBN/title in `ScanJobCoordinator`).

**Known API quirks (handled automatically):**
1. `Retry-After` header is seconds; response body `retryAfterMs` is milliseconds
2. Problem details use camelCase instead of snake_case
3. Enrichment failures use `enrichmentStatus` (`circuit_open` / etc.) rather than hard fail
4. Literal ISBN `"unknown"` is normalized to `nil` in the client decoder

**API references:**
- OpenAPI spec: `swiftwing/OpenAPI/talaria-openapi.yaml` (committed, 3.9.0)
- Live contract: `https://api.oooefam.net/v3/openapi.json` (Swagger: `/v3/docs`)
- Contract fixtures: `swiftwingTests/Fixtures/TalariaContractFixtures.swift`
- Contract adherence tests: `swiftwingTests/Unit/Services/TalariaContractAdherenceTests.swift`

**OpenAPI spec update:**
```bash
./Scripts/update-api-spec.sh          # fetch /v3/openapi.json → YAML + checksum
./Scripts/update-api-spec.sh --force  # no confirmation
git diff swiftwing/OpenAPI/talaria-openapi.yaml  # review before committing
```
Rollback: `git checkout swiftwing/OpenAPI/` to restore committed spec.

### Performance Targets

| Metric | Target |
|--------|--------|
| Camera cold start | < 0.5s |
| UI frame rate | > 55 FPS |
| Image processing | < 500ms |
| Status poll round-trip | < 200ms P95 |

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

### Camera controls (Phase 9)

`CameraOverlayView` owns the capture chrome: a **zoom slider** bound to
`cameraManager.setZoom`/`currentZoomFactor` (the same pair the pinch gesture drives, so
they stay in sync), and an **AE/AF lock** (`toggleExposureFocusLock`). The numeric zoom
readout lives once, in `statusOverlays` — the slider is the control, not a second display.
The slider hides while a scan-complete banner or segmented preview occupies the same
bottom strip. Tapping the preview to refocus clears the lock, but only *after* the device
accepts the new mode, so the flag can't desync from hardware.

**Neither actuates in the Simulator** — `videoDevice` is nil, so `setZoom` and the lock
both return early. UI tests assert the controls render and are hittable; real behaviour is
a device check, tracked in `docs/testing/TESTING-CHECKLIST.md`.

`CameraFirstRunGuidance` is modal and keyed on `hasSeenCameraGuidance`, separate from
`hasCompletedOnboarding`. `UI_TESTING` presets that key so the overlay does not cover the
camera tab for every other test; `FORCE_CAMERA_GUIDANCE` opts a test back in (mirrors
`FORCE_ONBOARDING`).

### Error Handling (RFC 9457)

```swift
do {
    let (jobId, status) = try await talariaService.uploadScan(image: imageData, deviceId: deviceId)
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
- **Never ignore Swift 6.4 concurrency warnings** — all warnings are errors in this project
- **Build before reviews** — never run code review on code that hasn't built cleanly

## Testing

**UI Tests:** Always use `-parallel-testing-enabled NO` (without it, simulator clone fails).

```bash
xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -only-testing:swiftwingUITests \
  -parallel-testing-enabled NO \
  2>&1 | xcsift
```

See `docs/testing/TESTING-CHECKLIST.md` for regression checklist.

## Skills & Tools

Skills live in `.claude/skills/<name>/SKILL.md`. Grok and OpenCode both load that layout. Flat markdown files in `.claude/skills/` are not skills.

| Skill | Purpose | Trigger |
|-------|---------|---------|
| `swiftui-pro` | SwiftUI review against current APIs | SwiftUI view changes |
| `swiftdata-pro` | SwiftData patterns and queries | Model or data changes |
| `swift-testing-pro` | Swift Testing, including Swift 6.4 XCTest interop | Test file changes |
| `swift-concurrency-pro` | Swift 6.4 concurrency review | Actor or async changes |
| `new-feature-slice` | Scaffold a View, ViewModel, and Swift Testing suite | New feature slice |
| `run-contract-tests` | Talaria contract adherence tests only | OpenAPI or Talaria decoding |

**Commands** (`.claude/commands/`, loaded by Grok; stock OpenCode does not read this directory):

- `/build-sim` — simulator build, iPhone 18 Pro Max unless another name is given
- `/update-api` — refresh the committed OpenAPI spec

**Agents** (`.claude/agents/`, loaded by Grok; stock OpenCode reads `.opencode/agents/`):

- `swift-concurrency-reviewer`
- `talaria-contract-reviewer`

## Key Documentation

| File | Purpose |
|------|---------|
| `START-HERE.md` | Orientation for new contributors |
| `AGENTS.md` | Agent-optimized architecture reference + skills catalog |
| `PRD.md` | Full product requirements |
| `docs/` | Architecture, testing docs |
| `.claude/rules/` | Build workflow, Swift conventions, planning policy |
| `.claude/skills/` | Skills both Grok and OpenCode load (`<name>/SKILL.md`) |
| `.claude/agents/` | Grok project agents |
| `.archive/` | Completed epic summaries, historical planning |

---

**Last Updated:** 2026-09-24
