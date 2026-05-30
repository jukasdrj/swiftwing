# GitHub Copilot Instructions - SwiftWing

**Project:** SwiftWing iOS App (SwiftUI + SwiftData + AVFoundation)
**Stack:** Swift 6.2, SwiftUI, SwiftData, AVFoundation, URLSession
**Backend:** Talaria API (`https://api.oooefam.net`)

---

## Architecture Overview

### MVVM + Actor-Based Services
- **Views:** Pure SwiftUI presentation logic, bindings to `@Observable` ViewModel
- **ViewModels:** `@Observable @MainActor` for reactive state, coordinates actors
- **Services:** Actor-isolated (thread-safe) — `TalariaService`, `CameraManager`, `OfflineQueueManager`
- **Data:** SwiftData `@Model` classes, all writes through `DataSyncActor` (@MainActor class)

### Vertical Slice Epics
Each epic delivers a complete feature across all layers:
```
Epic 1 (Foundation) → Epic 2 (Camera) → Epic 3 (Library) →
Epic 4 (AI Integration) → Epic 5 (Refactor) → Epic 6 (App Store)
```

---

## Code Style

### Swift 6.2 Concurrency (Strict)
```swift
// ✅ CORRECT: Use actors for mutable state
actor TalariaService {
    private var session: URLSession
    func upload() async throws { ... }
}

// ✅ CORRECT: @MainActor for UI updates
@MainActor class CameraViewModel: ObservableObject { ... }

// ✅ CORRECT: Structured concurrency
async let result1 = fetch()
async let result2 = upload()
let (r1, r2) = await (result1, result2)

// ❌ FORBIDDEN: DispatchQueue with async/await (DEADLOCK)
DispatchQueue.main.async { await someAsyncFunction() }

// ❌ FORBIDDEN: Task.detached (breaks actor isolation)
Task.detached { await actorMethod() }

// ❌ FORBIDDEN: @unchecked Sendable
@unchecked Sendable // Bypasses safety checks
```

### SwiftData Patterns
```swift
// ✅ CORRECT: Only \.modelContext exists
@Environment(\.modelContext) private var modelContext
let container = modelContext.container

// ❌ FORBIDDEN: \.modelContainer does not exist
@Environment(\.modelContainer) private var modelContainer // ERROR!
```

### Build Commands
```bash
# ✅ CORRECT: Always pipe xcodebuild through xcsift
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift

# Expected: {"summary": {"errors": 0, "warnings": 0}}

# ❌ FORBIDDEN: Never call xcodebuild directly (unparseable)
xcodebuild -project swiftwing.xcodeproj build
```

---

## Available Skills

This repo includes specialized AI skills in `.claude/skills/`:

| Skill | Purpose | Location |
|-------|---------|----------|
| `swiftui-pro` | SwiftUI best practices | `.claude/skills/swiftui-pro/SKILL.md` |
| `swiftdata-pro` | SwiftData patterns | `.claude/skills/swiftdata-pro/SKILL.md` |
| `swift-testing-pro` | Modern Swift Testing | `.claude/skills/swift-testing-pro/SKILL.md` |
| `swift-concurrency-pro` | Concurrency correctness | `.claude/skills/swift-concurrency-pro/SKILL.md` |
| `new-feature-slice` | Vertical slice development | `.claude/skills/new-feature-slice.md` |
| `run-contract-tests` | OpenAPI contract validation | `.claude/skills/run-contract-tests.md` |

**Manifest:** `skills/available.json` (machine-readable catalog)

When working on SwiftUI views, load `swiftui-pro` skill first.  
When working on data models, load `swiftdata-pro` skill first.  
When working with async/await or actors, load `swift-concurrency-pro` skill first.

---

## Key Files

| File | Role | Size |
|------|------|------|
| `swiftwing/CameraView.swift` | Main camera UI | 250 lines |
| `swiftwing/CameraViewModel.swift` | Camera business logic | ~727 lines |
| `swiftwing/Services/TalariaService.swift` | Network + SSE (actor) | 22KB |
| `swiftwing/LibraryView.swift` | Library grid | 47KB |
| `swiftwing/Models/Book.swift` | SwiftData @Model | Core entity |
| `swiftwing/OpenAPI/talaria-openapi.yaml` | Committed API spec | Deterministic builds |

---

## Planning Requirements

**Any task requiring >4 tool calls MUST use `/planning-with-files`:**
- Creates `{task}_task_plan.md` — phases, decisions, error log
- Creates `{task}_findings.md` — root causes, expert advice
- Prevents circular debugging, saves hours

---

## Cross-Platform Agent Guide

- **Claude Code:** See `CLAUDE.md` + `.claude/rules/`
- **Jules (PR Review):** See `.github/JULES_GUIDE.md`
- **Opencode:** See `AGENTS.md`

**Skills Manifest:** `skills/available.json`

---

**Last Updated:** May 2026
**Version:** 1.0.0
**Maintained By:** Talaria Team (@jukasdrj)
