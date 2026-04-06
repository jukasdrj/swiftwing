# Plan: Parallel Agent Execution for Swift Pro Audit Findings

## Context

Four Swift Pro skill audits identified 23 actionable findings across SwiftUI, SwiftData, Concurrency, and Testing. The goal is to maximize concurrent agent work by grouping findings into non-overlapping file sets that can be executed in parallel without merge conflicts.

## Dependency Analysis

Findings touch these file groups:

| Group | Files | Findings |
|-------|-------|----------|
| **A: Theme + Deprecated APIs** | Theme.swift, all 27 files with `foregroundColor`, all 15 files with `.cornerRadius` | SwiftUI #7, #8, #10 (animation bug, foregroundStyle, clipShape, Task.sleep) |
| **B: RootView + Tab API** | RootView.swift | SwiftUI #9, #13, #14 (Tab API, enum tabs, Binding) |
| **C: LibraryView + ViewModel** | LibraryView.swift, LibraryViewModel.swift, LibraryGridView.swift | SwiftUI #5, #12, #15, #16, #17 (filteredBooks perf, ContentUnavailableView, NavigationLink, localizedStandardContains, onTapGesture→Button) |
| **D: Onboarding** | OnboardingView.swift | SwiftUI #6 (hardcoded fonts → Dynamic Type) |
| **E: ReviewQueue** | ReviewQueueView.swift, ReviewCardView.swift | SwiftUI #2, #4 (onTapGesture→Button, icon-only edit button) |
| **F: Camera Concurrency** | TalariaService.swift, CameraManager.swift, NetworkMonitor.swift, ScanJobCoordinator.swift | Concurrency #1, #3, #4, #5, #6 (makeStream, cancellation, withDiscardingTaskGroup) |
| **G: SwiftData** | Book.swift, SwiftwingApp.swift, DuplicateDetection.swift | SwiftData #1, #2, #5, #6 (versioned schema, ReadingStatus enum, index, fetchLimit) |
| **H: Tests** | swiftwingTests/*.swift (new files) | Testing #1-#6 (migrate to Swift Testing, add SSE/dedup/service tests) |

## Conflict Matrix

Groups that touch overlapping files:
- **A** touches Theme.swift + scattered files (modifier changes only, no logic overlap)
- **B** is isolated (RootView.swift only)
- **C** is isolated (Library feature only)
- **D** is isolated (Onboarding only)
- **E** is isolated (ReviewQueue only)
- **F** is isolated (Services + Camera concurrency only)
- **G** touches Book.swift + SwiftwingApp.swift (no overlap with other groups)
- **H** creates new files only (zero conflict)

**All 8 groups are independent** — no two groups modify the same file.

## Execution Plan: 4 Waves

### Wave 1 — Maximum parallelism (8 agents)

All groups can run simultaneously since they touch non-overlapping files.

| Agent | Group | Scope | Model | Est. Files |
|-------|-------|-------|-------|------------|
| **Agent 1: Theme + Deprecated APIs** | A | Fix `swissSpring()` UUID bug in Theme.swift:188. Replace `.cornerRadius()` → `.clipShape(.rect(cornerRadius:))` in Theme.swift (3 modifiers). Replace `Task.sleep(nanoseconds:)` → `Task.sleep(for:)` in all 6 files (19 occurrences). | sonnet | ~10 files |
| **Agent 2: foregroundStyle migration** | A (subset) | Replace all 166 `foregroundColor()` → `foregroundStyle()` across 27 files. Mechanical find-replace, no logic changes. | sonnet | 27 files |
| **Agent 3: RootView modernization** | B | Convert `.tabItem()` → modern `Tab` API. Convert `Int` tab selection → `AppTab` enum. Remove `Binding(get:set:)` → callback pattern. | sonnet | 1 file |
| **Agent 4: Library improvements** | C | Cache `filteredBooks()` call in body (call once, use let). Replace empty states with `ContentUnavailableView`. Replace `onTapGesture` → `Button` in LibraryGridView. Replace `NavigationLink(destination:)` → `navigationDestination(for:)`. Replace `.lowercased().contains()` → `localizedStandardContains()` in LibraryViewModel. | sonnet | 3 files |
| **Agent 5: Onboarding + ReviewQueue** | D+E | Replace hardcoded `.font(.system(size:))` → semantic Dynamic Type in OnboardingView (6 locations). Replace `onTapGesture` → `Button` in ReviewQueueView and ReviewCardView. Add text label to icon-only edit button. | sonnet | 4 files |
| **Agent 6: Concurrency modernization** | F | Convert `AsyncThrowingStream` closure → `makeStream()` in TalariaService. Convert `AsyncStream` closure → `makeStream()` in CameraManager (eliminates IUO). Convert `AsyncStream` closure → `makeStream()` in NetworkMonitor. Replace unstructured tasks in loop → `withDiscardingTaskGroup` in ScanJobCoordinator. Replace `DispatchQueue.main.async` → `Task { @MainActor in }` in CameraPreviewView. | sonnet | 5 files |
| **Agent 7: SwiftData hardening** | G | Add `VersionedSchema` + `SchemaMigrationPlan` in new file. Convert `readingStatus: String?` → `ReadingStatus?` in Book.swift. Add `#Index` on isbn + addedDate. Add `fetchLimit: 1` in DuplicateDetection. Wire migration plan in SwiftwingApp.swift. | sonnet | 4 files |
| **Agent 8: Test migration + new tests** | H | Migrate BookModelTests to Swift Testing (struct, @Test, #expect, parameterized). Create SSEEventParserTests.swift with Swift Testing. Create DuplicateDetectionTests.swift with Swift Testing + in-memory SwiftData container. | sonnet | 3-4 files |

### Wave 2 — Build verification (1 agent)

After all Wave 1 agents complete:

| Agent | Scope |
|-------|-------|
| **Agent 9: Build + verify** | Run `xcodebuild ... \| xcsift` to verify 0 errors, 0 warnings. Fix any compilation issues from Wave 1 changes. Run unit tests to verify migrations pass. |

### Wave 3 — Fix-up (as needed)

If Wave 2 reveals issues, targeted fix agents for specific files.

### Wave 4 — Final verification

Clean build + full test run to confirm everything is green.

## Key Constraints

1. **Always pipe xcodebuild through xcsift** — never call raw xcodebuild
2. **Zero warnings policy** — any warning is a build failure
3. **foregroundStyle migration** is mechanical but must preserve `.opacity()` modifiers (e.g., `.foregroundColor(.swissText.opacity(0.8))` → `.foregroundStyle(.swissText.opacity(0.8))`)
4. **Tab API migration** requires checking if `CameraViewModel.requestedTab` uses Int — must update to enum there too
5. **SwiftData migration** — the `ReadingStatus` enum change requires updating all code that sets `readingStatus` as a raw string
6. **AsyncStream `makeStream`** — verify bufferingPolicy is preserved (CameraManager uses `.bufferingNewest(1)`)
7. **Test files** — create new Swift Testing files, don't modify UI test files (they must stay XCTest)

## Verification

After all waves:
```bash
# Build
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  clean build 2>&1 | xcsift
# Expected: errors: 0, warnings: 0

# Unit tests
xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:swiftwingTests \
  2>&1 | xcsift
# Expected: all tests pass
```

## Files Modified Summary

| Wave | Agent | New Files | Modified Files |
|------|-------|-----------|---------------|
| 1 | Agent 1 | 0 | ~10 (Theme + sleep) |
| 1 | Agent 2 | 0 | 27 (foregroundStyle) |
| 1 | Agent 3 | 0 | 1 (RootView) |
| 1 | Agent 4 | 0 | 3 (Library) |
| 1 | Agent 5 | 0 | 4 (Onboarding + Review) |
| 1 | Agent 6 | 0 | 5 (Concurrency) |
| 1 | Agent 7 | 1 (BookSchema.swift) | 3 (Book, DuplicateDetection, SwiftwingApp) |
| 1 | Agent 8 | 2-3 (test files) | 1 (BookModelTests) |
| **Total** | | **3-4 new** | **~54 modified** |
