# SwiftWing Repository Optimization Summary
**Date**: 2026-01-27
**Claude Code Version**: 2.1.20+

## ✅ Implemented Optimizations

### 1. Enhanced Settings (`.claude/settings.json`)
SwiftWing already had excellent configuration:
- ✅ Automated planning enforcement hook (>3 tool calls → mandatory `/planning-with-files`)
- ✅ PM epic review workflow hook
- ✅ Session start reminder
- ✅ PAL MCP tool permissions (debug, codereview, analyze, thinkdeep, chat, consensus)
- ✅ Custom file suggestion (Swift + JSON + MD files)
- ✅ Attribution configured

### 2. Quick Commands (`.claude/commands/`)
Created 3 iOS-specific quick commands:

#### `/build-sim [device]`
- Build for iOS Simulator (default: iPhone 17 Pro Max)
- **CRITICAL**: Always pipes through `xcsift` for readable output
- Shows available devices
- Build requirements: 0 errors, 0 warnings

#### `/update-api [--force]`
- Update Talaria OpenAPI spec from production
- SHA256 checksum verification
- Force flag for breaking changes
- Spec committed to repo (offline builds)

#### `/epic-status [epic-number]`
- Show status for specific epic (default: 5)
- Lists all 6 epics with completion status
- Current phase tracking
- Links to EPIC-ROADMAP.md

### 3. Rules System (`.claude/rules/`)

#### `swift-conventions.md` (comprehensive iOS guide)
Documented all critical Swift 6.2 and iOS 26 conventions:

**Swift 6.2 & Concurrency**:
- Strict concurrency enabled
- Actor-based architecture patterns
- Never mix DispatchQueue with async/await
- Structured concurrency only
- Complete concurrency checking

**Architecture**:
- MVVM with Actors pattern
- Vertical slice development (epic-based)
- SwiftData with actor isolation
- Service layer with actors

**UI/UX Design**:
- Swiss Glass theme (60% utility + 40% glass)
- Typography hierarchy
- Performance targets (>55 FPS)
- Zero-lag camera preview

**Camera Implementation**:
- AVFoundation best practices
- Non-blocking capture
- Image processing pipeline
- Performance targets (<0.5s cold start)

**Network Integration**:
- Talaria Service actor pattern
- SSE streaming for progress
- Offline queue management
- Rate limiting (10 scans / 20 min)

**Build & Testing**:
- **CRITICAL**: Always use `xcsift` with xcodebuild
- 0 errors, 0 warnings requirement
- XCTest coverage targets (70%+)
- Performance instrumentation

**OpenAPI Management**:
- Committed spec pattern (no build-time fetch)
- SHA256 checksum verification
- Offline-capable builds

**What NOT to Do**:
- ❌ Don't mix DispatchQueue + async/await (deadlocks)
- ❌ Don't use Task.detached (breaks isolation)
- ❌ Don't ignore Swift 6.2 warnings (data races)
- ❌ Don't add unnecessary dependencies

**Epic Status**:
- Epic 1-4: ✅ Complete (Grades: A 95-99/100)
- Epic 5: 🔄 In Progress (Phase 2A-2E done)
- Epic 6: ⚪ Pending (App Store launch)

**Epic 5 Achievement**:
- CameraView: 1,098 → 250 lines (77% reduction)
- CameraViewModel: 727 lines extracted
- MVVM pattern established

## 🎯 Key Capabilities

### Already Excellent
SwiftWing had world-class Claude Code setup:
- ✅ Automated planning enforcement (prevents circular debugging)
- ✅ PM workflow integration
- ✅ PAL MCP tools for code review/analysis
- ✅ Comprehensive permissions
- ✅ Session reminders

### New Enhancements
- ✅ Quick commands for iOS workflows (build, API update, epic status)
- ✅ Swift 6.2 conventions documented
- ✅ Actor-based architecture patterns
- ✅ xcsift build requirement emphasized
- ✅ OpenAPI committed spec pattern documented

## 📊 Project Status

**Platform**: iOS 26+ (Swift 6.2, SwiftUI, SwiftData)
**Architecture**: MVVM + Actors
**Build Status**: ✅ 0 errors, 1 minor warning
**Epic Progress**: 4 of 6 complete (Epic 5 in progress)
**Recent Work**: CameraView refactor (77% size reduction)

**Epics**:
- Epic 1: ✅ Foundation (Complete - Jan 22, A 95/100)
- Epic 2: ✅ Camera (Complete - Jan 23, A 98/100)
- Epic 3: ✅ Library (Complete - Jan 24, A 97/100)
- Epic 4: ✅ AI Integration (Complete - Jan 25, A 99/100)
- Epic 5: 🔄 Refactoring (Phase 2A-2E done)
- Epic 6: ⚪ App Store Launch (Pending)

## 🚀 Usage Examples

```bash
# Build for simulator
/build-sim

# Build for specific device
/build-sim "iPad Pro (14-inch)"

# Update Talaria API spec
/update-api

# Force update API (breaking changes)
/update-api --force

# Check current epic status
/epic-status

# Check specific epic
/epic-status 4
```

## 📝 Critical Requirements

### Build Command (MANDATORY)
```bash
# ALWAYS use xcsift - never call xcodebuild directly
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift
```

**Why?**
- Xcodebuild output is unstructured
- xcsift formats for human readability
- Required for CI/CD validation

### Concurrency Rules (MANDATORY)
- ✅ Use `actor` for mutable shared state
- ✅ Use `@MainActor` for all UI updates
- ✅ Use structured concurrency (`Task`, `TaskGroup`, `async let`)
- ❌ NEVER use `DispatchQueue` with async/await (deadlock risk)
- ❌ NEVER use `Task.detached` (breaks actor isolation)
- ❌ NEVER ignore Swift 6.2 concurrency warnings

### Planning Enforcement (AUTOMATIC)
The `enforce-planning.sh` hook automatically:
- Analyzes user prompts for complexity
- Blocks tasks scoring ≥5 (>3 tool calls equivalent)
- Forces `/planning-with-files` for complex work
- Prevents circular debugging with persistent memory

**Complexity Scoring**:
- File modifications: +2 per file
- New features: +3
- Refactoring: +3
- Bug fixes: +2
- Multiple components: +2
- Network/persistence: +2

**Threshold**: ≥5 points → Planning mandatory

## 🔗 Related Repositories

### Integration with Talaria
- **API**: https://api.oooefam.net
- **OpenAPI Spec**: Committed to `swiftwing/OpenAPI/talaria-openapi.yaml`
- **Update Script**: `./Scripts/update-api-spec.sh`
- **SSE Streaming**: Real-time scan progress
- **Rate Limiting**: 10 scans / 20 minutes

### Architecture
```
SwiftWing (iOS App)
    ↓
TalariaService (Actor)
    ↓
Talaria API (Cloudflare Workers)
    ↓
Gemini Vision AI (Spine Recognition)
    ↓
ISBNdb API (Metadata Enrichment)
```

## 📚 Documentation

### Key Files
- `CLAUDE.md` (37KB) - Comprehensive AI collaboration guide
- `EPIC-ROADMAP.md` - All 6 epics overview
- `START-HERE.md` - Quick orientation
- `PRD.md` - Product requirements
- `CURRENT-STATUS.md` - Latest progress
- `TESTING-CHECKLIST.md` - Full test matrix

### Planning Files
- `task_plan.md` - Phase tracking
- `progress.md` - Session logs
- `findings.md` - Technical research
- `epic-1.json` through `epic-6.json` - Ralph-TUI configs

## 🎓 Best Practices

### When to Use Planning Mode
The hook automatically enforces planning for:
- ✅ Multi-file changes (>2 files)
- ✅ New features or major refactors
- ✅ Network/persistence changes
- ✅ Complex bug fixes
- ✅ Tasks estimated >3 tool calls

### When Planning Not Required
- ❌ Single-file typo fixes
- ❌ Documentation updates
- ❌ Build command execution
- ❌ Epic status checks
- ❌ Simple queries

### Swift 6.2 Patterns
```swift
// ✅ GOOD: Actor for shared state
actor TalariaService {
    private var jobs: [UUID: ScanJob] = [:]

    func addJob(_ job: ScanJob) {
        jobs[job.id] = job
    }
}

// ✅ GOOD: MainActor for UI
@MainActor
func updateProgressBar(_ progress: Double) {
    progressValue = progress
}

// ❌ BAD: DispatchQueue + async/await
DispatchQueue.main.async {
    await someAsyncFunction()  // DEADLOCK RISK
}

// ❌ BAD: Task.detached
Task.detached {
    await actorMethod()  // ISOLATION BROKEN
}
```

## 🚨 Common Pitfalls

### Build Issues
- ❌ Calling `xcodebuild` without `xcsift` → unreadable output
- ❌ Ignoring concurrency warnings → data races
- ❌ Not checking for 0 warnings → tech debt accumulation

### Concurrency Issues
- ❌ Mixing DispatchQueue with async/await → deadlocks
- ❌ Using Task.detached → broken actor isolation
- ❌ Forgetting @MainActor → UI updates on background thread

### Architecture Issues
- ❌ Horizontal layering → untestable, unshippable epics
- ❌ Direct SwiftData writes from views → data races
- ❌ Synchronous network calls → UI blocking

---

**Implementation Complete**: SwiftWing repository enhanced with iOS-specific quick commands and comprehensive Swift 6.2 conventions.

**Next Actions**:
1. Test quick commands: `/build-sim`, `/update-api`, `/epic-status`
2. Review Swift conventions in `.claude/rules/swift-conventions.md`
3. Continue Epic 5 refactoring with planning enforcement active
4. Prepare for Epic 6 App Store launch
