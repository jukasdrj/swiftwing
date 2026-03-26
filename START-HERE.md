# SwiftWing - Start Here

**SwiftWing** is a native iOS 26 book spine scanner app. Point your camera at a bookshelf, tap the shutter, and AI identifies and catalogs your books in real time.

---

## Current State

**Epics 1-5 are complete. Epic 6 (App Store Launch) is in progress.**

| Epic | Focus | Status |
|------|-------|--------|
| 1 | Foundation & Walking Skeleton | Complete (A 95/100) |
| 2 | Camera | Complete (A 98/100) |
| 3 | Library UI | Complete (A 97/100) |
| 4 | Talaria AI Integration | Complete (A 99/100) |
| 5 | Refactoring (MVVM + Actor) | Complete |
| 6 | App Store Launch | In Progress |

The app is production-ready with a working end-to-end flow:
**Capture → Upload → SSE Stream → Review Queue → Library**

---

## Quick Start (New Developer)

### 1. Open the project

```bash
open swiftwing.xcodeproj
```

### 2. Build and verify

```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift
```

Expected: `errors: 0, warnings: 0`

### 3. Run on simulator

Press Cmd+R in Xcode. Use the iPhone 17 Pro Max simulator.

---

## Architecture

```
SwiftUI Views → @Observable ViewModels → Actor Services → SwiftData
```

**Key files:**

| File | Role |
|------|------|
| `swiftwing/App/RootView.swift` | Tab container (Camera / Library) |
| `swiftwing/Features/Camera/CameraView.swift` | Camera UI (~250 lines) |
| `swiftwing/Features/Camera/CameraViewModel.swift` | Camera business logic |
| `swiftwing/Features/Library/LibraryView.swift` | Library grid |
| `swiftwing/Features/Library/LibraryViewModel.swift` | Library business logic (FetchDescriptor-based filtering) |
| `swiftwing/Features/ReviewQueue/ReviewQueueView.swift` | Book review/approve UI |
| `swiftwing/Services/TalariaService.swift` | Network + SSE actor |
| `swiftwing/Services/DataSyncActor.swift` | All SwiftData writes (@MainActor class) |
| `swiftwing/Models/Book.swift` | SwiftData model |

**Concurrency:** Swift 6.2 strict concurrency. Actors for all mutable shared state. No DispatchQueue with async/await.

**Persistence:** SwiftData with `@Attribute(.unique)` on ISBN to prevent duplicates.

---

## Tech Stack

- **Language:** Swift 6.2
- **UI:** SwiftUI (iOS 26.0+ only)
- **Persistence:** SwiftData
- **Camera:** AVFoundation
- **Networking:** URLSession + Server-Sent Events
- **AI Backend:** Talaria (`https://api.oooefam.net`)
- **No external dependencies**

---

## Key Documentation

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Full project guide for AI assistance (build commands, architecture, patterns) |
| `AGENTS.md` | Agent-optimized reference |
| `PRD.md` | Product requirements |
| `docs/` | Architecture, testing, and operations docs |
| `.archive/` | Completed epic summaries, one-time analyses, historical planning |

---

## Build Rules (Non-Negotiable)

- **Always pipe xcodebuild through xcsift** — never call xcodebuild directly
- **0 errors AND 0 warnings** required — warnings are treated as errors
- See `.claude/rules/build-workflow.md` for details

---

## Talaria Integration

The app uploads book spine images to the Talaria backend and streams results via SSE.

**Endpoints:**
- `POST /v3/jobs/scans` — upload image, returns `{ jobId, sseUrl }`
- `GET {sseUrl}` — SSE stream (progress, result, complete, error events)
- `DELETE /v3/jobs/scans/{jobId}/cleanup` — cleanup after completion

**SSE deduplication is critical:** Talaria sends books via both `.result` events and inline in the `.complete` event. The deduplication guard in `CameraViewModel` is mission-critical, not defensive.

See `CLAUDE.md` for the full Talaria integration reference.

---

## Design Language: Swiss Glass Hybrid

60% Swiss Utility + 40% Liquid Glass.

- Black base (`#0D0D0D`) for OLED
- `.ultraThinMaterial` overlays for depth
- International Orange (`#FF4F00`) accent
- JetBrains Mono for data/IDs, SF Pro for UI
- Spring animations, 12px rounded corners

---

## Prerequisites

- **Xcode:** 26+ (iOS 26 SDK)
- **macOS:** Sequoia 15+
- **Swift:** 6.2
- **Simulator:** iPhone 17 Pro Max
- **CLI tool:** `xcsift` (required for all builds)

---

**Bundle ID:** `com.ooheynerds.swiftwing`
**Min Deployment:** iOS 26.0
**Last Updated:** 2026-03-26
