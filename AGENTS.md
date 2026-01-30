# SwiftWing: AI Agent Reference & Architecture

**Last Updated:** January 30, 2026
**Status:** Epic 5 Phase 2A-2E Complete (Refactoring)
**Branch:** `main` / `refactor/camera-view-decomposition`
**Build:** ✅ SUCCESS (0 errors, 1 warning) | **iOS 26.0+ | Swift 6.2**

---

## Quick Navigation

- **First Time?** → Read [START-HERE.md](./START-HERE.md) (orientation guide)
- **Building/Running?** → See [CLAUDE.md](./CLAUDE.md) (section: Building & Running)
- **Need to Fix Something?** → See [CURRENT-STATUS.md](./CURRENT-STATUS.md) (status & next steps)
- **Writing Code?** → Read `.claude/rules/` (project conventions)
- **Planning Major Task?** → Use `/planning-with-files` (MANDATORY for >4 tool calls)

---

## Project Overview

**SwiftWing** is a native iOS 26 book spine scanner application that uses AVFoundation camera capture and Talaria AI backend to automatically identify and catalog books. Built with SwiftUI, SwiftData, Swift 6.2 structured concurrency, and actor-based services.

**Core Identity:**
- **Platform:** iOS 26.0+ only (current-gen Apple devices)
- **Architecture:** MVVM with Actor-based isolated services
- **Design:** Swiss Glass hybrid (60% utility + 40% liquid glass)
- **Language:** Swift 6.2 with strict concurrency enabled
- **Data:** SwiftData with actor-coordinated writes

**Bundle ID:** `com.ooheynerds.swiftwing`
**GitHub:** Private repository with 6 epics (foundation → launch)

---

## Directory Structure

```
swiftwing/
├── 📱 CORE APPLICATION
│   ├── SwiftwingApp.swift              # Entry point & model container setup
│   ├── RootView.swift                  # Navigation root
│   ├── ContentView.swift                # Main content coordinator
│   ├── LaunchScreenView.swift           # Launch screen UI
│   └── OnboardingView.swift             # 3-slide onboarding flow
│
├── 🎥 CAMERA & VISION
│   ├── CameraView.swift                 # Main camera UI (250 lines, refactored)
│   ├── CameraViewModel.swift            # Camera business logic (727 lines)
│   ├── CameraManager.swift              # AVFoundation abstraction (actor)
│   ├── CameraPermissionPrimerView.swift # Camera permission request
│   └── CameraPreviewView.swift          # Metal/AVFoundation preview bridge
│
├── 📚 LIBRARY & BROWSING
│   ├── LibraryView.swift                # Library grid (47KB, optimized)
│   ├── LibraryPerformanceOptimizations.swift  # Query strategies
│   └── LibraryPrefetchCoordinator.swift # Image prefetching logic
│
├── 🔧 SERVICES & NETWORK
│   ├── Services/
│   │   ├── TalariaService.swift         # AI backend (22KB, actor-based)
│   │   ├── NetworkTypes.swift           # Domain models (2.6KB)
│   │   ├── NetworkMonitor.swift         # Network status tracking
│   │   ├── OfflineQueueManager.swift    # Offline sync queue
│   │   ├── RateLimitState.swift         # Rate limit tracking
│   │   └── StreamManager.swift          # SSE stream coordination
│   │
│   ├── NetworkService.swift             # Legacy stub (for migration)
│   └── ProcessingQueue UI components
│       ├── ProcessingQueueView.swift    # Queue display (159 lines)
│       ├── ProcessingItem.swift         # Queue item model (3.4KB)
│       ├── ProcessingThumbnailView.swift# Item thumbnail (embedded)
│       ├── RateLimitOverlay.swift       # Rate limit countdown (78 lines)
│       ├── OfflineIndicatorView.swift   # Offline badge (44 lines)
│       ├── DuplicateBookAlert.swift     # Duplicate modal (120 lines)
│       └── RateLimitState.swift         # Rate limit state mgmt
│
├── 💾 DATA & MODELS
│   ├── Models/
│   │   └── Book.swift                   # SwiftData @Model (core entity)
│   │
│   └── DuplicateDetection.swift         # ISBN uniqueness checking
│
├── 🎨 DESIGN & THEME
│   ├── Theme.swift                      # Swiss Glass design system
│   ├── AsyncImageWithLoading.swift      # Async image + skeleton (6.8KB)
│   ├── OfflineIndicatorView.swift       # Network status badge
│   └── RateLimitOverlay.swift           # Rate limit UI
│
├── 🚀 PERFORMANCE & MONITORING
│   ├── PerformanceLogger.swift          # Instrumentation (8KB)
│   ├── PerformanceTestData.swift        # Test data generation (8.3KB)
│   └── StreamManager.swift              # Concurrent stream limits
│
├── 🌍 LOCALIZATION & ASSETS
│   ├── Assets.xcassets/                 # App icons, colors, images
│   ├── Fonts/                           # JetBrains Mono (brand)
│   ├── Preview Content/                 # SwiftUI preview fixtures
│   └── Info.plist                       # App config (camera permission)
│
├── 📡 API SPECIFICATION
│   ├── OpenAPI/
│   │   ├── talaria-openapi.yaml         # Committed API spec (deterministic builds)
│   │   └── .talaria-openapi.yaml.sha256 # Integrity checksum
│   │
│   ├── Generated/                       # Auto-generated by build (not committed)
│   │   └── openapi.yaml                 # Copy for generator
│   │
│   └── openapi-generator-config.yaml    # Generator config (future use)
│
└── 🛠️ BUILD & CONFIGURATION
    └── (Xcode project handles most)
```

**Total iOS App:** ~620KB source code (after Epic 5 refactoring)

---

## Root-Level Documentation Files

### 📋 Core Documentation

| File | Purpose | Audience |
|------|---------|----------|
| **CLAUDE.md** | ⭐ AI collaboration guide (CRITICAL) | AI Agents, Developers |
| **CURRENT-STATUS.md** | Real-time project status & next steps | Everyone |
| **START-HERE.md** | Orientation guide for new team members | New contributors |
| **PRD.md** | Product requirements & feature specs | Product, Developers |
| **US-swift.md** | User stories (Epic 1-6, 50+ stories) | Project planning |

### 📊 Planning & Progress

| File | Purpose |
|------|---------|
| **task_plan.md** | Active task phases & decision log |
| **findings.md** | iOS 26 research & technical discoveries |
| **progress.md** | Session log & test results |
| **README-PLANNING.md** | Planning methodology documentation |
| **EPIC-1-STORIES.md** | Foundation epic details (completed Jan 22) |
| **EPIC-5-REVIEW-SUMMARY.md** | Code review findings (Phase 2A) |

### 🏢 Corporate Documentation

| File | Purpose |
|------|---------|
| **PRIVACY.md** | Privacy policy (user data handling) |
| **TERMS.md** | Terms of service (legal agreement) |
| **APP_STORE_PRIVACY.md** | App Store privacy manifest (required for iOS 26) |

---

## For AI Agents: Critical Rules & Patterns

### 🔴 MANDATORY: Read CLAUDE.md FIRST

**Every AI agent working on SwiftWing MUST:**

1. **Read CLAUDE.md completely** - It contains:
   - Building & running commands (xcodebuild + xcsift pattern)
   - Swift 6.2 concurrency rules (actors, @MainActor, structured concurrency)
   - Concurrency pitfalls to avoid (DispatchQueue, Task.detached)
   - Architecture patterns (MVVM, vertical slices)
   - OpenAPI spec management (committed, deterministic builds)

2. **Check `.claude/rules/` directory** - Project-specific conventions:
   - `swift-conventions.md` - Actor patterns, concurrency requirements
   - `build-workflow.md` - xcodebuild + xcsift (NEVER omit xcsift)
   - `planning-mandatory.md` - Planning-with-files requirement (>4 tool calls)
   - `planning-workflow.md` - Specialist agent coordination
   - `swiftdata-patterns.md` - SwiftData best practices (@Model, queries)

3. **Understand Build Requirements:**
   - ✅ ALWAYS: `xcodebuild ... 2>&1 | xcsift`
   - ✅ ALWAYS: 0 errors, 0 warnings (non-negotiable)
   - ❌ NEVER: Raw xcodebuild output (unparseable)
   - ❌ NEVER: xcsift as build command (it's a formatter only)

### 🟡 MANDATORY: Planning-with-Files

**Trigger:** Any task requiring >4 tool calls (>4 decisions)

**What to do:**
```bash
/planning-with-files
```

**Creates:**
- `{task_name}_task_plan.md` - Phases, progress, decisions, errors table
- `{task_name}_findings.md` - Root causes, expert advice, solutions
- `{task_name}_progress.md` - Session log, test results (optional)

**This prevents circular debugging.** Without planning:
- ❌ Repeat same fixes
- ❌ Lose context
- ❌ Waste hours

With planning:
- ✅ Systematic diagnosis
- ✅ Error tracking table
- ✅ Fast resolution

**Real example from this project:** Build failure required 8+ circular attempts without planning, 20 minutes WITH planning. Planning saved hours.

### 🟢 Swift 6.2 Concurrency Rules

**STRICT ENFORCEMENT - Compiler treats warnings as errors**

#### ✅ DO:
```swift
// Use actors for mutable state
actor TalariaService {
    private var session: URLSession
    func upload() async throws { ... }
}

// Use @MainActor for UI updates
@MainActor class CameraViewModel { ... }

// Use structured concurrency
async let result1 = fetch()
async let result2 = upload()
let (r1, r2) = await (result1, result2)

// Use TaskGroup for parallel work
try await withThrowingTaskGroup(of: Book.self) { group in
    for isbn in isbns {
        group.addTask { await fetchBook(isbn) }
    }
}
```

#### ❌ DON'T:
```swift
// DON'T mix DispatchQueue with async/await (DEADLOCK)
DispatchQueue.main.async {
    await someAsyncFunction()  // 🔥 DEADLOCK
}

// DON'T use Task.detached (breaks actor isolation)
Task.detached {
    await actorMethod()  // 🔥 Data race risk
}

// DON'T use DispatchSemaphore (antique pattern)
let sem = DispatchSemaphore(value: 1)
sem.wait()  // 🔥 Blocks with async/await

// DON'T suppress data race warnings
@unchecked Sendable  // 🔥 Bypasses safety checks
```

### 🟢 SwiftData Patterns

**Key Rule:** Only `\.modelContext` is an environment key, NOT `\.modelContainer`

```swift
// ✅ CORRECT
@Environment(\.modelContext) var modelContext
let container = modelContext.container  // Access via modelContext

// ❌ WRONG - Doesn't exist
@Environment(\.modelContainer) var container  // ERROR!
```

See `.claude/rules/swiftdata-patterns.md` for details.

### 🟢 OpenAPI Spec Management

**The Talaria spec is COMMITTED to the repository** (not fetched during build):

```
swiftwing/OpenAPI/talaria-openapi.yaml  # Committed spec
swiftwing/OpenAPI/.talaria-openapi.yaml.sha256  # Integrity
```

**Why?**
- ✅ Offline builds (no internet required)
- ✅ Reproducible builds (same input = same output)
- ✅ Version control of API evolution
- ✅ Supply chain security (no runtime fetching)

**Update workflow:**
```bash
Scripts/update-api-spec.sh         # Normal update
Scripts/update-api-spec.sh --force # Force override
```

---

## Architecture Overview

### High-Level Data Flow

```
┌──────────────────────────────────────────────────────────────┐
│                      SwiftUI Views                           │
│  (CameraView, LibraryView, ProcessingQueueView, etc.)        │
└──────────────────┬───────────────────────────────────────────┘
                   │
                   │ Bind to viewModel state
                   ▼
┌──────────────────────────────────────────────────────────────┐
│                   ViewModels (@Observable)                   │
│  (CameraViewModel, LibraryViewModel, etc.)                   │
│                                                               │
│  Responsibilities:                                            │
│  - Coordinate business logic                                  │
│  - Call actor services                                        │
│  - Update view state reactively                              │
└──────────────────┬───────────────────────────────────────────┘
                   │
                   │ async/await calls
                   ▼
┌──────────────────────────────────────────────────────────────┐
│            Actor Services (Thread-Safe)                       │
│                                                               │
│  TalariaService (actor)        - Network + SSE streaming      │
│  CameraManager (actor)         - AVFoundation isolation       │
│  NetworkMonitor (class)        - Network status tracking      │
│  OfflineQueueManager (actor)   - Offline sync                │
│  DataSyncActor (future)        - SwiftData writes             │
└──────────────────┬───────────────────────────────────────────┘
                   │
                   │ File I/O, Network, Device APIs
                   ▼
┌──────────────────────────────────────────────────────────────┐
│            Frameworks & External Services                     │
│                                                               │
│  SwiftData         - Local persistent storage (Books)        │
│  AVFoundation      - Camera capture                           │
│  URLSession        - Network requests                         │
│  Talaria API       - AI backend (book identification)         │
└──────────────────────────────────────────────────────────────┘
```

### MVVM Pattern Details

**View Layer:**
- Pure presentation logic
- Reads: Bindings to `@Observable` ViewModel
- Writes: Calls ViewModel methods
- No async logic or side effects

**ViewModel Layer:**
- `@Observable @MainActor` for reactive updates
- Coordinates multiple actors
- Handles app logic (camera → process → save)
- ModelContext injection via view lifecycle

**Service Layer (Actors):**
- `TalariaService` - Network calls, SSE streaming, rate limiting
- `CameraManager` - AVFoundation session management
- `NetworkMonitor` - Network status tracking
- Isolated mutable state (prevents data races)

**Data Layer:**
- `@Model` classes with `@Attribute(.unique)` constraints
- SwiftData for local persistence
- Actor-coordinated writes (future)

### Vertical Slice Development (Epic-Based)

Each epic delivers a **complete feature** across all layers:

```
Epic 1 (Foundation) → Epic 2 (Camera) → Epic 3 (Library) →
Epic 4 (AI) → Epic 5 (Refactor) → Epic 6 (Launch)
```

**Example:** Epic 2 (Camera)
- **UI:** CameraView with preview + shutter button
- **Logic:** CameraViewModel with capture pipeline
- **Service:** CameraManager actor for AVFoundation
- **Data:** None (cameras don't persist)
- **Network:** None (Epic 4 adds this)

---

## Current Status: Epic 5 Refactoring

### What's Complete (As of Jan 30, 2026)

| Epic | Status | Date | Grade |
|------|--------|------|-------|
| **Epic 1: Foundation** | ✅ Complete | Jan 22 | A (95/100) |
| **Epic 2: Camera** | ✅ Complete | Jan 23 | A (98/100) |
| **Epic 3: Library** | ✅ Complete | Jan 24 | A (97/100) |
| **Epic 4: AI Integration** | ✅ Complete | Jan 25 | A (99/100) |
| **Epic 5: Refactoring** | 🔄 Phase 2A-2E | Jan 26-30 | (In Progress) |
| **Epic 6: App Store** | ⚪ Pending | TBD | - |

### Epic 5 Progress: Code Quality

**Goal:** Improve maintainability through MVVM refactoring

**Completed Phases:**
- ✅ Phase 2A: Extract CameraViewModel (830 line reduction)
- ✅ Phase 2B: Extract ProcessingQueueView (159 lines)
- ✅ Phase 2C: Extract RateLimitOverlay (78 lines)
- ✅ Phase 2D: Extract OfflineIndicatorView (44 lines)
- ✅ Phase 2E: Extract DuplicateBookAlert (120 lines)

**Result:** CameraView reduced from 1,098 → 250 lines (**77% reduction**)

**Next Steps:**
1. Complete simulator testing (verify all features work)
2. Phase 3A: Add XCTest infrastructure (70%+ coverage)
3. Phase 3B: Performance optimization (Instruments profiling)
4. Epic 6: App Store preparation

---

## Key Files for AI Agents

### Essential Reference

| File | Purpose | Read When |
|------|---------|-----------|
| CLAUDE.md | Build instructions, concurrency rules | Starting any work |
| .claude/rules/swift-conventions.md | Actor patterns, @MainActor usage | Writing Swift code |
| .claude/rules/swiftdata-patterns.md | @Environment keys, modelContext | Working with data |
| .claude/rules/planning-mandatory.md | Planning requirement | Task > 4 tool calls |
| CURRENT-STATUS.md | Real-time status, next steps | Need context |

### Code Structure Reference

| File | Role | Size |
|------|------|------|
| CameraView.swift | Main camera UI | 250 lines |
| CameraViewModel.swift | Camera business logic | 727 lines |
| TalariaService.swift | Network + SSE (actor) | 22KB |
| LibraryView.swift | Library grid | 47KB |
| Services/ | Actor-isolated services | 56KB |

### Planning & Investigation

| File | When to Use |
|------|------------|
| task_plan.md | Track complex task phases |
| findings.md | Document research & discoveries |
| progress.md | Log session work & errors |

---

## Dependencies & Requirements

### Runtime Requirements

- **Platform:** iOS 26.0+ (current-gen devices only)
- **Swift:** 6.2 with strict concurrency enabled
- **Frameworks:**
  - SwiftUI (declarative UI)
  - SwiftData (local storage)
  - AVFoundation (camera access)
  - Foundation (networking, concurrency)

### Build Tools

- **Xcode:** 16.0+ (with Swift 6.2 compiler)
- **xcsift:** Required for build output parsing
- **ralph-tui:** Epic task tracking

### Network Requirements

- **Talaria API:** `https://api.oooefam.net/v3/jobs/scans`
- **OpenAPI Spec:** `swiftwing/OpenAPI/talaria-openapi.yaml` (committed)
- **SSE Streaming:** Server-Sent Events for real-time progress

### Performance Targets

| Metric | Target | Epic |
|--------|--------|------|
| Cold start | < 1.5s | Epic 1 |
| Camera start | < 0.5s | Epic 2 |
| UI frame rate | > 55 FPS | All |
| Image processing | < 500ms | Epic 2 |
| Network request | < 200ms P95 | Epic 4 |

---

## Common Workflows for AI Agents

### Starting a Coding Task

```
1. Read CLAUDE.md (building & architecture)
2. Check .claude/rules/ (project conventions)
3. Review CURRENT-STATUS.md (context)
4. Check if task > 4 tool calls:
   - YES → /planning-with-files first
   - NO → Proceed directly
5. Execute with xcodebuild | xcsift
6. Verify: 0 errors, 0 warnings
```

### Building & Testing

```bash
# Build for simulator
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift

# Expected output: {"summary": {"errors": 0, "warnings": 0}}
```

### Managing Complex Tasks

```
1. Run /planning-with-files
2. Create {task}_task_plan.md (phases, decisions, errors)
3. Create {task}_findings.md (research, expert advice)
4. Launch specialist agent tasks (parallel when possible)
5. Use PAL MCP tools (thinkdeep, codereview, debug)
6. Document discoveries in planning files
7. Execute implementation
8. Verify with xcodebuild | xcsift
9. Update planning files with completion status
```

### Debugging Build Failures

```
1. /planning-with-files (mandatory)
2. Run xcodebuild ... | xcsift (get structured errors)
3. Use mcp__pal__debug with error output
4. Document root cause in *_findings.md
5. Apply systematic fix
6. Verify: xcodebuild ... | xcsift (0/0)
```

---

## Specialist Agent Roles

When using Task agents for parallel work, assign these roles:

| Role | Best For | Model |
|------|----------|-------|
| **Explorer** | Codebase mapping, file location | haiku |
| **Architect** | Design decisions, architecture review | opus |
| **Executor** | Implementation, code changes | sonnet |
| **Code Reviewer** | Quality, standards, patterns | opus |
| **Vision** | UI/UX review, design analysis | sonnet |
| **Scientist** | Data analysis, performance profiling | sonnet |
| **Security** | Security review, vulnerability scanning | opus |

---

## Known Limitations & Workarounds

### iOS 26 Specifics

- ❌ iOS < 26.0 not supported (app requires current generation)
- ✅ SwiftUI native controls (no UIKit bridge needed)
- ✅ Swift 6.2 concurrency (full native support)

### Swiftdata Quirks

- ✅ Only `\.modelContext` is an EnvironmentKey
- ❌ `\.modelContainer` does not exist (common mistake)
- ✅ Access container via `modelContext.container`

### Build Warnings

**Current:** 1 warning in TalariaService.swift (SSE async expression)
- Non-blocking
- Can be addressed in future cleanup
- Does not prevent shipping

---

## Critical Success Criteria

### Before Every Commit

- [ ] 0 errors
- [ ] 0 warnings (**non-negotiable**)
- [ ] Builds successfully with xcodebuild | xcsift
- [ ] All changes documented in planning files

### Before Code Reviews

- [ ] Build verified (0/0)
- [ ] Manual testing completed (or checklist)
- [ ] Performance targets met
- [ ] No circular debugging (use planning)

### Before Major Releases

- [ ] All epics complete
- [ ] 70%+ test coverage
- [ ] Zero critical issues
- [ ] Documentation up-to-date
- [ ] App Store requirements met

---

## Getting Help

### For Build Issues
- Check CLAUDE.md section "Building & Running"
- Run diagnostic: `xcodebuild ... | xcsift`
- Consult `.claude/rules/build-workflow.md`

### For Concurrency Issues
- Read `.claude/rules/swift-conventions.md` (actor patterns)
- Check `.claude/rules/swiftdata-patterns.md` (data handling)
- Review CURRENT-STATUS.md for context

### For Architecture Questions
- Read CLAUDE.md section "Architecture"
- Check CURRENT-STATUS.md (decision log)
- Review `.claude/rules/` (all conventions)

### For Complex Debugging
- Always use `/planning-with-files`
- Use PAL MCP tools (mcp__pal__debug, mcp__pal__thinkdeep)
- Document error attempts in planning files

---

## File Manifest (Quick Reference)

### Root Directory

```
AGENTS.md                       ← You are here
CLAUDE.md                       ← AI collaboration guide (CRITICAL)
CURRENT-STATUS.md              ← Real-time status
START-HERE.md                  ← Orientation guide
PRD.md                          ← Product requirements
US-swift.md                     ← User stories (50+)
README-PLANNING.md             ← Planning methodology
EPIC-1-STORIES.md              ← Foundation epic
EPIC-5-REVIEW-SUMMARY.md       ← Code review findings
task_plan.md                   ← Active task phases
findings.md                    ← Technical research
progress.md                    ← Session log
PRIVACY.md                     ← Privacy policy
TERMS.md                       ← Terms of service
APP_STORE_PRIVACY.md           ← App Store manifest
```

### Configuration & Rules

```
.claude/
├── README.md                  ← Claude Code setup
├── VALIDATION-CHECKLIST.md    ← Build verification
├── rules/
│   ├── swift-conventions.md   ← Actor patterns, concurrency
│   ├── build-workflow.md      ← xcodebuild + xcsift
│   ├── planning-mandatory.md  ← Planning requirement
│   ├── planning-workflow.md   ← Agent coordination
│   └── swiftdata-patterns.md  ← Data layer patterns
├── hooks/
│   ├── enforce-planning.sh    ← Complexity detection
│   └── (other automation)
└── (other configuration)
```

### Source Code

```
swiftwing/                      ← iOS app source (620KB total)
├── CameraView.swift           ← Main camera UI (250 lines)
├── CameraViewModel.swift      ← Business logic (727 lines)
├── Services/
│   ├── TalariaService.swift   ← Network + SSE (actor)
│   ├── NetworkMonitor.swift   ← Network status
│   └── (other services)
├── Models/Book.swift          ← SwiftData entity
├── LibraryView.swift          ← Library grid (47KB)
└── (UI components, assets, etc.)
```

### Testing & Documentation

```
swiftwingTests/                 ← Unit test suites
docs/                           ← API docs, guides
.archive/                       ← Completed planning files
```

---

## Last Updated

**January 30, 2026, 11:53 AM UTC**
By: Claude Code (AI Agent Orchestration)

**Next Review:** After Epic 5 Phase 3A completion (XCTest infrastructure)

---

**Remember:** This is a reference guide for AI agents. Always start by reading CLAUDE.md for AI collaboration details and build instructions.
