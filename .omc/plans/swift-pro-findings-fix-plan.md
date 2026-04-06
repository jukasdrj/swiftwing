# Swift Pro Findings Fix Plan
**Created:** 2026-03-26
**Scope:** 21 findings from 4-domain Swift Pro review (SwiftUI, SwiftData, Concurrency, Testing)
**Build target:** 0 errors, 0 warnings post-fix

---

## Requirements Summary

Resolve all 21 prioritized findings from the Swift Pro code review across four domains. Work is organized into parallel waves based on dependency topology. Each wave must build-verify (xcodebuild | xcsift → 0/0) before advancing.

---

## Acceptance Criteria

- [ ] `DataSyncActor.swift` exists at `swiftwing/Services/DataSyncActor.swift` with `save(book:in:)` and `saveAll(books:in:)` functions
- [ ] All `@MainActor`-isolated DB writes in `ReviewQueueManager` and `LibraryViewModel` route through `DataSyncActor`
- [ ] `LibraryViewModel.filteredBooks(from:)` replaced with `FetchDescriptor` + `#Predicate` — no O(n) in-memory filter
- [ ] `Book.swift` `#Index` includes `[\.dateScanned]` and `[\.title]` (verify existing index is correct per review H6)
- [ ] `StreamManagerTests.swift` exists with ≥ 8 test cases covering: normal acquire/release, concurrent acquire, underflow guard, cancellation
- [ ] `CancellationError` is NOT caught in `TalariaService.swift:349` catch-all — rethrown
- [ ] `NetworkMonitor` unstructured `Task` stored in a `@discardableResult` property and cancelled in `deinit`
- [ ] `ImagePreprocessor.preprocess(_:)` wraps synchronous CIFilter work in `Task.detached` or offloads to a continuation; actor executor not blocked
- [ ] Offline retry loop in `CameraViewModel.swift:666` uses `withThrowingTaskGroup` for parallel uploads
- [ ] `@MainActor @Sendable` annotation added to `CameraManager` photo capture closure
- [ ] `loadingTask` in `LibraryViewModel` is cancelled in `onDisappear` handler
- [ ] All `onChange(of:)` calls use two-argument closure form `{ old, new in }`
- [ ] All `onAppear { Task { } }` patterns replaced with `.task { }` modifier
- [ ] `CameraOverlayView` labels support Dynamic Type (`.dynamicTypeSize` or `scaledFont`)
- [ ] `ReviewCardView` shadow extracted to a `let` constant outside view body
- [ ] `LibraryView` and `ProcessingQueueView` `.accessibilityIdentifier` moved from container to leaf elements
- [ ] `statusBarHidden` replaced with `.toolbar(.hidden, for: .statusBar)` / `toolbarVisibility` equivalent
- [ ] Redundant `modelContext.save()` calls removed (where auto-save handles it)
- [ ] `#if DEBUG` integration log block extracted / consolidated (Q1 already done; verify no stragglers)
- [ ] Test files use `@Suite` grouping with at least one suite annotation each
- [ ] Error-path tests use `#expect(throws:)` for at least the top 3 error cases
- [ ] Build: `xcodebuild | xcsift` → errors: 0, warnings: 0

---

## Execution Plan

### Wave 1 — Foundation & Critical (parallel, no inter-wave deps)

**Agent A — C1: DataSyncActor implementation**
- Create `swiftwing/Services/DataSyncActor.swift`
  - `actor DataSyncActor`
  - `func save(book: PendingBookResult, in context: ModelContext) async throws`
  - `func saveAll(books: [PendingBookResult], in context: ModelContext) async throws`
  - Handles `DuplicateDetection.findDuplicate` guard internally
- Refactor `ReviewQueueManager.swift:317` — route `addBookToLibrary` through `DataSyncActor`
- Refactor `LibraryViewModel.swift` — any direct `modelContext.insert` / `modelContext.save` routed through `DataSyncActor`
- Add `DataSyncActor.swift` to Xcode project (`swiftwing.xcodeproj/project.pbxproj`)
- **Verify:** Build 0/0

**Agent B — H4 + H5: Concurrency correctness fixes**
- `TalariaService.swift:349` — restructure catch to rethrow `CancellationError` before generic handler:
  ```swift
  } catch is CancellationError {
      throw CancellationError()
  } catch {
      // existing handler
  }
  ```
- `NetworkMonitor.swift:44` — store the monitoring `Task` in `private var monitoringTask: Task<Void, Never>?`; cancel in `deinit { monitoringTask?.cancel() }`
- **Verify:** Build 0/0

**Agent C — H1 + H6: SwiftData query performance**
- `LibraryViewModel.swift:114` — replace `filteredBooks(from:)` in-memory filter with `FetchDescriptor<Book>` + `#Predicate` for search text and filter state; use `modelContext.fetch(descriptor)`
- `Models/Book.swift` — confirm `#Index` covers `[\.dateScanned]` and `[\.title]` (explorer reports it does; verify and annotate if already correct — no-op if H6 is satisfied)
- **Verify:** Build 0/0

---

### Wave 2 — High findings (parallel, after Wave 1 build passes)

**Agent D — H2: ImagePreprocessor actor blocking**
- `ImagePreprocessor.swift:51` — wrap synchronous CIFilter pipeline in `await Task.detached(priority: .userInitiated) { ... }.value` to release the actor executor during CPU-bound work
- Ensure result is passed back to actor context correctly (Sendable types only)
- **Verify:** Build 0/0

**Agent E — H3 + M1: Parallel offline uploads + closure annotation**
- `CameraViewModel.swift:666` — replace serial `for book in queue` upload loop with:
  ```swift
  try await withThrowingTaskGroup(of: Void.self) { group in
      for book in pendingUploads {
          group.addTask { try await self.uploadOfflineBook(book) }
      }
      try await group.waitForAll()
  }
  ```
- `CameraManager.swift` — add `@MainActor @Sendable` annotation to photo capture completion closure
- **Verify:** Build 0/0

**Agent F — C2: StreamManager tests**
- Create `swiftwingTests/StreamManagerTests.swift`
- Test cases:
  1. `acquireStreamSlot` succeeds when slots available
  2. `acquireStreamSlot` waits when at capacity
  3. `releaseStreamSlot` decrements correctly
  4. Underflow guard: `releaseStreamSlot` with 0 active doesn't go negative
  5. Concurrent acquire + release (TaskGroup stress test)
  6. `cancelAllJobs` releases all slots
  7. Slot count matches `maxConcurrentStreams` constant
  8. Re-acquire after release succeeds
- Add to `swiftwing.xcodeproj` test target
- **Verify:** Tests pass

---

### Wave 3 — Medium findings (parallel, after Wave 2 build passes)

**Agent G — M2 + M3 + M4: SwiftUI lifecycle & API modernization**
- `LibraryViewModel.swift` — store `Task` in `private var loadingTask: Task<Void, Never>?`; in `onDisappear` call `loadingTask?.cancel()`
- All `onChange(of:perform:)` (1-arg) → `onChange(of:) { old, new in }` (2-arg) across all views
- All `onAppear { Task { } }` → `.task { }` modifier across all views
- Files to touch: `LibraryView.swift`, `ReviewQueueView.swift`, `CameraView.swift`, any others with the pattern
- **Verify:** Build 0/0

**Agent H — M5 + M6 + M7 + M8 + L1: SwiftUI polish**
- `CameraOverlayView.swift` — add `.dynamicTypeSize(.xSmall ... .accessibility3)` or use `@ScaledMetric` for font sizes in overlay labels
- `ReviewCardView.swift` — extract shadow params to `private let shadowColor = Color.black.opacity(0.15)` etc., outside `body`
- `LibraryView.swift` — move `.accessibilityIdentifier` from container `VStack`/`ZStack` to leaf `Text`/`Button` elements
- `ProcessingQueueView.swift` — same accessibility identifier fix
- All views using `statusBarHidden` → replace with `.toolbar(.hidden, for: .statusBar)` or `toolbarVisibility(.hidden, for: .statusBar)`
- **Verify:** Build 0/0

---

### Wave 4 — Low findings + Testing quality (parallel, after Wave 3 build passes)

**Agent I — L2 + L3: Cleanup**
- Audit `modelContext.save()` calls: remove redundant saves where SwiftData autosave is guaranteed (no explicit transaction boundary needed)
- Verify `#if DEBUG` integration log is fully consolidated in `IntegrationTestLogger.swift` (Q1 fix) — remove any remaining duplicate `#if DEBUG func integrationLog` blocks
- **Verify:** Build 0/0

**Agent J — L4 + L5: Test quality**
- Add `@Suite("ReviewQueueManager")`, `@Suite("DuplicateDetection")`, `@Suite("SSEEventParser")`, `@Suite("BookModel")` annotations to respective test files
- Add `#expect(throws:)` coverage for at least:
  - `TalariaService` rate limit error path
  - `DuplicateDetection` collision path
  - `ReviewQueueManager` invalid state path
- **Verify:** Tests pass

---

### Wave 5 — Final build verification

**Single agent: Full clean build + test run**
```bash
cd /Users/juju/dev_repos/swiftwing
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  clean build 2>&1 | xcsift
```
- Must report: errors: 0, warnings: 0
- If any warnings remain, fix before declaring done

---

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `DataSyncActor` may need ModelContainer (not MainActor context) | Pass `ModelContext` as parameter; create `ModelContext(container)` in actor init if needed |
| `FetchDescriptor` `#Predicate` closures have strict Sendable requirements | Keep predicate lambdas simple; avoid capturing non-Sendable types |
| `Task.detached` in `ImagePreprocessor` breaks actor isolation rules | Only detach CPU work; actor state updates go back through `self` with `await` |
| `withThrowingTaskGroup` offline upload may change error semantics | Collect partial failures; don't abort group on first error unless all errors are fatal |
| Adding `DataSyncActor.swift` to pbxproj manually is error-prone | Use Xcode `addFile` script or verify UUID format matches existing entries |
| `@Suite` annotation may conflict with existing test structure | `@Suite` is additive; existing `@Test` functions are unaffected |

---

## Dependency Graph

```
Wave 1 (A, B, C) ─── independent, fully parallel
      │
      ▼
Wave 2 (D, E, F) ─── parallel, depends on Wave 1 build passing
      │
      ▼
Wave 3 (G, H) ────── parallel, depends on Wave 2 build passing
      │
      ▼
Wave 4 (I, J) ────── parallel, depends on Wave 3 build passing
      │
      ▼
Wave 5 ──────────── clean build verification
```

---

## Team Composition

| Wave | Agents | Model | Rationale |
|------|--------|-------|-----------|
| 1 | A (DataSyncActor), B (concurrency), C (SwiftData) | sonnet | Architecture-adjacent; needs concurrency correctness |
| 2 | D (ImagePreprocessor), E (uploads+closure), F (tests) | sonnet | Implementation + new test file |
| 3 | G (SwiftUI lifecycle), H (SwiftUI polish) | sonnet | Broad but mechanical SwiftUI changes |
| 4 | I (cleanup), J (test quality) | haiku | Mechanical cleanup and annotations |
| 5 | Build verifier | sonnet | Final gate |

---

## File Reference Index

| Finding | File | Lines |
|---------|------|-------|
| C1 | `swiftwing/Services/DataSyncActor.swift` (new) | — |
| C1 | `swiftwing/Features/ReviewQueue/ReviewQueueManager.swift` | ~317 |
| C1 | `swiftwing/Features/Library/LibraryViewModel.swift` | multiple |
| C2 | `swiftwingTests/StreamManagerTests.swift` (new) | — |
| H1 | `swiftwing/Features/Library/LibraryViewModel.swift` | 114 |
| H2 | `swiftwing/Services/ImagePreprocessor.swift` | 51 |
| H3 | `swiftwing/Features/Camera/CameraViewModel.swift` | 666 |
| H4 | `swiftwing/Services/TalariaService.swift` | ~349 |
| H5 | `swiftwing/Services/NetworkMonitor.swift` | 44 |
| H6 | `swiftwing/Models/Book.swift` | 14 |
| M1 | `swiftwing/Features/Camera/CameraManager.swift` | — |
| M2 | `swiftwing/Features/Library/LibraryViewModel.swift` | — |
| M3 | Multiple views | — |
| M4 | Multiple views | — |
| M5 | `swiftwing/Features/Camera/CameraOverlayView.swift` | — |
| M6 | `swiftwing/Features/ReviewQueue/ReviewCardView.swift` | — |
| M7 | `swiftwing/Features/Library/LibraryView.swift` | — |
| M8 | `swiftwing/Features/ReviewQueue/ProcessingQueueView.swift` | — |
| L1 | Multiple views | — |
| L2 | Multiple | — |
| L3 | Multiple | — |
| L4 | `swiftwingTests/*.swift` | — |
| L5 | `swiftwingTests/*.swift` | — |

---

## Verification Steps

1. After each wave: `xcodebuild ... | xcsift` → errors: 0, warnings: 0
2. After Wave 2: `xcodebuild test ... -only-testing:swiftwingTests -parallel-testing-enabled NO | xcsift` → all pass
3. After Wave 4: same test command includes `StreamManagerTests` and `@Suite`-annotated tests
4. Wave 5: clean build (no incremental cache) must pass 0/0
5. Manual smoke: Library search filters correctly; camera scan completes end-to-end

---

## ADR — Architecture Decision Record

**Decision:** Implement `DataSyncActor` as a new actor service; route all SwiftData writes through it.

**Drivers:**
1. All DB writes currently on `@MainActor` block the UI thread during bulk operations
2. Swift 6.2 strict concurrency requires explicit actor isolation for shared mutable state
3. SwiftData `ModelContext` is not `Sendable` — requires actor isolation for safe concurrent access

**Alternatives Considered:**
- **A: Keep @MainActor writes, add `Task.detached`** — rejected: `Task.detached` breaks actor isolation and priority inheritance
- **B: Background ModelContext created per-call** — rejected: multiple contexts create merge conflicts; no single source of truth
- **C: DataSyncActor with its own ModelContainer** — viable but heavy; passing `ModelContext` as parameter is lighter and consistent with existing `DataSyncActor` usage in `swift-conventions.md`

**Why Chosen:** Option C-lite (actor + context parameter) matches the project's documented `DataSyncActor` pattern in `.claude/rules/swift-conventions.md`, requires minimal structural change, and satisfies Swift 6.2 actor isolation rules.

**Consequences:**
- `ReviewQueueManager` and `LibraryViewModel` lose direct `modelContext` write access for inserts
- All call sites become `async` where they weren't already
- Test coverage for DataSyncActor needed (follow-up)

**Follow-ups:**
- Add `DataSyncActorTests.swift` in a subsequent pass
- Consider `DataSyncActor` owning a dedicated `ModelContext` (created from container) rather than accepting one as parameter — better isolation but requires architectural alignment

---

*Plan saved: `.omc/plans/swift-pro-findings-fix-plan.md`*
