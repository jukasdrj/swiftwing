# Swift Pro Audit Fixes — Concurrent Team Execution Plan
**Revised after Gemini planner review + 4 Swift Pro agent approvals**

## Overview
Implement 64 findings from 4 Swift Pro skill audits (SwiftUI, SwiftData, Concurrency, Testing) using phased parallel execution. Gemini review identified a CameraManager file conflict, CVPixelBuffer retention risk, and destructive schema migration — all addressed below.

## Phased Execution

### Phase 1: Foundation (Sequential — Unblocks Everything)
**Why sequential:** These 3 tasks create dependencies for all other lanes. Must land first.

| Task | Severity | File | Fix | Notes |
|------|----------|------|-----|-------|
| 1A. VisionService data race | HIGH | VisionService.swift | Convert to actor (preferred) or protect with `Mutex` | Makes `processFrame` async — CameraManager callers must add `await` |
| 2A. Fix schema versioning | CRITICAL | BookSchemaVersioning.swift, Book.swift | Create frozen `BookV1` inside `BookSchemaV1` with snapshot of current fields. Nest live `Book` inside `BookSchemaV2`. Add `MigrationStage.lightweight` from V1→V2 | **Gemini flag:** Book must be nested inside the schema enum for proper versioning |
| 2D. Type readingStatus as enum | HIGH | Book.swift | Change `String?` to `ReadingStatus?` in `BookSchemaV2`. Implement `MigrationStage.custom` with explicit rawValue→enum mapping | **Gemini flag:** Destructive without custom migration — existing user data would be lost |

**Estimated effort:** 4-6 hours
**Build gate:** `xcodebuild ... | xcsift` → 0 errors, 0 warnings

---

### Phase 2: Parallel Services (3 Lanes Concurrent)

#### Lane 1: Concurrency Safety
**Owner:** concurrency-executor
**Files:** StreamManager.swift, TalariaService.swift, CameraViewModel.swift, ImagePreprocessor.swift
**Depends on:** Phase 1 (1A complete)

| Task | Severity | File | Fix |
|------|----------|------|-----|
| 1C. StreamManager cancellation hang | HIGH | StreamManager.swift:71-83 | Wrap with `withTaskCancellationHandler`, add `cancelPendingScan` to remove pending entry and resume continuation |
| 1D. SSE stream not cancellable | MEDIUM | TalariaService.swift:204-207 | Add `continuation.onTermination = { _ in task.cancel() }` to bridge stream termination to task cancellation |
| 1E. CancellationError shown to users | MEDIUM | CameraViewModel.swift:352 | Add `catch is CancellationError { logger.debug("cancelled"); return }` before generic catch |
| 1F. Double image preprocessing | MEDIUM | ImagePreprocessor.swift:299-304 | Remove redundant `preprocess()` call inside `processImageForUpload` — caller already preprocesses |
| 1G. Defer fire-and-forget slot release | MEDIUM | CameraViewModel.swift:450-455 | Replace `defer { Task { ... } }` with `await releaseStreamSlot` in normal control flow |
| 1H. Loading indicator race | MEDIUM | CameraViewModel.swift:122-128 | Store delayed Task handle, cancel on setup success |

**Estimated effort:** 6-8 hours
**Build gate:** Required after all sub-tasks

#### Lane 2: SwiftData Modernization
**Owner:** swiftdata-executor
**Files:** PerformanceTestData.swift, LibraryViewModel.swift, LibraryView.swift, RootView.swift, DataSeeder.swift
**Depends on:** Phase 1 (2A, 2D complete)

| Task | Severity | File | Fix |
|------|----------|------|-----|
| 2B. Replace Task.detached in test data | CRITICAL | PerformanceTestData.swift:94,180 | Use `@ModelActor` pattern: create `BackgroundDataWorker` actor for background writes |
| 2C. Fix silent save failures | HIGH | LibraryViewModel.swift:192,204,260,316; LibraryView.swift:459 | Replace **6x** `try? context.save()` with `do { try context.save() } catch { logger.error(...) }` — **Amendment:** Agent review found 6 sites, not 5 |
| 2E. Use fetchCount for badge | HIGH | RootView.swift:93 | Replace `@Query var books: [Book]` with `modelContext.fetchCount(FetchDescriptor<Book>())` |
| 2F. Add missing indexes | MEDIUM | Book.swift:14 | Extend `#Index<Book>` to include `[\.title], [\.author]` |
| 2G. Add @MainActor to DataSeeder | LOW | DataSeeder.swift:17 | Add `@MainActor` annotation to struct |

**Estimated effort:** 6-8 hours
**Build gate:** Required — test with existing data to verify migration

#### Lane 4: Test Coverage
**Owner:** testing-executor
**Files:** swiftwingTests/ only (new + existing test files)
**Depends on:** None (test-only files, no production code conflicts)

| Task | Severity | File | Fix |
|------|----------|------|-----|
| 4A. SSE parser: 3 missing event tests | HIGH | SSEEventParserTests.swift | Add tests for `segmented`, `book_progress`, `enrichment_degraded` |
| 4B. SSE parser: error path tests | HIGH | SSEEventParserTests.swift | Test malformed JSON for `result`, `segmented`, `book_progress` — verify `SSEError.invalidEventFormat` thrown |
| 4C. Fix silent pass in OnboardingUITests | HIGH | OnboardingUITests.swift:21,40 | Replace `guard...return` with `try XCTSkipUnless(...)` |
| 4D. Add BookMetadata Codable tests | HIGH | NEW: BookMetadataTests.swift | Test: `author` string, `authors` array, `publicationYear` int/string, missing optionals, malformed coverUrl |
| 4E. Add ReviewQueueManager unit tests | HIGH | NEW: ReviewQueueManagerTests.swift | Test `handleBookResult`, `validateBookMetadata`, `isDuplicateResult` (60s window) |
| 4F. Use #require in DuplicateDetectionTests | MEDIUM | DuplicateDetectionTests.swift:27-28,37-38,50-53 | Replace `#expect(!=nil)` + optional chain with `try #require()` across all 3 test functions — **Amendment:** Pattern scattered across multiple functions, not contiguous block |
| 4G. Extract SSE enum verification helpers | MEDIUM | SSEEventParserTests.swift | Create `requireProgress()`, `requireResult()` etc. with `SourceLocation` pass-through |
| 4H. ~~Fix OnboardingUITests base class~~ **REMOVED** | ~~MEDIUM~~ | OnboardingUITests.swift | **Amendment:** Agent review found OnboardingUITests intentionally skips `UI_TESTING` launch arg. Inheriting `SwiftwingUITestCase` would inject it and break the test. Extract shared setup (continueAfterFailure, app init) into a minimal base class WITHOUT launch args, or leave as-is |
| 4I. Replace sleep(2) in IntegrationUITests | MEDIUM | IntegrationUITests.swift:39 | Use `waitForExistence(timeout: 10)` instead of hard sleep |
| 4J. Migrate testLazyFilterCorrectness | MEDIUM | ReviewQueueManagerPerformanceTests.swift:31-42 | Extract to Swift Testing struct with `@Test` + `#expect` — **Amendment:** Line range is 31-42 |

**Estimated effort:** 6-8 hours
**Build gate:** Full test suite pass

---

### Phase 3: Parallel UI (SwiftUI — Excluding CameraManager)
**Owner:** swiftui-executor
**Files:** Theme.swift, LaunchScreenView.swift, CameraOverlayView.swift, CameraView.swift, ReviewQueueView.swift, OnboardingView.swift, LibraryGridView.swift, DuplicateBookAlert.swift, ConfidenceBadge.swift
**Depends on:** None (can start in parallel with Phase 2, but listed as Phase 3 for clarity)

| Task | Severity | File | Fix |
|------|----------|------|-----|
| 3A. Adopt Liquid Glass | HIGH | Theme.swift:110-116 | Replace `.ultraThinMaterial` + `.background(.black)` with `.glassEffect()` in `SwissGlassCard`, `SwissGlassOverlay`, `SwissGlassButton` |
| 3B. Fix LaunchScreen double font | HIGH | LaunchScreenView.swift:15-16 | Remove line 16, replace line 15 with `.font(.jetBrainsMono(size: 48))` |
| 3D. Extract CameraOverlay sub-views | MEDIUM | CameraOverlayView.swift | Split 244-line body into `CameraStatusOverlays`, `CameraFeedbackOverlays`, `CameraBannerOverlays` |
| 3E. Replace Task.sleep(nanoseconds:) | MEDIUM | ReviewQueueView.swift:111 | `try? await Task.sleep(for: .milliseconds(100))` |
| 3F. Use scenePhase | MEDIUM | CameraView.swift:161-165 | Replace `onReceive(NotificationCenter)` with `@Environment(\.scenePhase)` + `.onChange(of:)` |
| 3G. DuplicateBookAlert accessibility | MEDIUM | DuplicateBookAlert.swift | Add `.accessibilityAddTraits(.isModal)`, VoiceOver focus trap |
| 3H. Hide decorative VoiceOver elements | LOW | OnboardingView.swift:101-128 | Add `.accessibilityHidden(true)` to decorative shapes |
| 3I. Fix ConfidenceBadge Float→Double | LOW | ConfidenceBadge.swift:4 | Change `Float` to `Double` for consistency |
| 3J. Pre-computed stats to LibraryStatsHeader | MEDIUM | LibraryGridView.swift:100-113 | Change init to accept `(bookCount:uniqueAuthorsCount:mostCommonFormatText:)` |

**Estimated effort:** 6-8 hours
**Build gate:** Required + visual verification of Liquid Glass

---

### Phase 4: Integration — Camera Layer Modernization
**Why isolated:** CameraManager.swift is touched by both concurrency and SwiftUI lanes. Gemini flagged this as a guaranteed merge conflict. Consolidating into one phase eliminates the risk.

**Owner:** camera-integration-executor
**Files:** CameraManager.swift (+ callers if signatures change)
**Depends on:** Phase 1 (1A — VisionService is now an actor), Phase 2 Lane 1 complete

| Task | Severity | File | Fix | Safeguard |
|------|----------|------|-----|-----------|
| 1B. Vision processing off MainActor | HIGH | CameraManager.swift:141-168 (`startVisionTask()`) | Move `processFrame` to background task, hop results back to MainActor | **Gemini flag:** CVPixelBuffer is recycled by AVFoundation. Must `CVPixelBufferRetain`/copy before sending off-thread. Add `Task.checkCancellation()` in vision loop. **Amendment:** Code refactored into `startVisionTask()` at lines 141-168 |
| 3C. Migrate to @Observable | HIGH | CameraManager.swift:17-34 | Replace `@Published` with plain stored properties, remove `ObservableObject` conformance, update all callers from `@ObservedObject`/`@StateObject` to direct reference | Must integrate with 1B's async `processFrame` calls |

**Estimated effort:** 4-6 hours
**Build gate:** Required — verify camera preview, vision overlays, and frame rate

---

### Phase 5: Final Validation
**Depends on:** All phases complete

| Check | Command / Tool | Pass Criteria |
|-------|----------------|---------------|
| Clean build | `xcodebuild ... build 2>&1 \| xcsift` | 0 errors, 0 warnings |
| Unit tests | `xcodebuild ... test -only-testing:swiftwingTests 2>&1 \| xcsift` | All pass |
| UI tests | `xcodebuild ... test -only-testing:swiftwingUITests -parallel-testing-enabled NO 2>&1 \| xcsift` | All pass |
| Camera regression | Manual: cold start < 0.5s, capture works, SSE streams, review queue populates | No regressions |
| Library regression | Manual: CRUD, search, sort, filter, export CSV | No regressions |
| Schema migration | Install old build → update to new build → verify data preserved | ReadingStatus migrated, no data loss |
| Memory leaks | Instruments: Leaks template on camera capture flow | No new leaks |

---

## Execution Diagram

```
PHASE 1: FOUNDATION (sequential)
├── 1A: VisionService → Actor
├── 2A: VersionedSchema + frozen BookV1
└── 2D: ReadingStatus enum + custom migration
        │
        ▼
PHASE 2 + 3: PARALLEL (4 lanes)
┌────────────────┬────────────────┬────────────────┬────────────────┐
│  Lane 1        │  Lane 2        │  Lane 3        │  Lane 4        │
│  Concurrency   │  SwiftData     │  SwiftUI       │  Testing       │
│  1C-1H         │  2B,2C,2E-2G   │  3A-3B,3D-3J   │  4A-4J         │
│  (6-8h)        │  (6-8h)        │  (6-8h)        │  (6-8h)        │
└───────┬────────┴────────────────┴────────────────┴────────────────┘
        │
        ▼
PHASE 4: CAMERA INTEGRATION (sequential)
├── 1B: Vision offload (CVPixelBuffer retain!)
└── 3C: @Observable migration
        │
        ▼
PHASE 5: FINAL VALIDATION
├── Build: 0/0
├── Tests: all pass
├── Schema migration: data preserved
└── Manual regression: camera + library
```

## Risk Register (from Gemini review)

| Risk | Severity | Mitigation |
|------|----------|------------|
| CameraManager merge conflict (1B + 3C) | HIGH | Consolidated into Phase 4 — single executor, sequential |
| CVPixelBuffer recycled by AVFoundation | HIGH | Retain buffer before background dispatch; release after processing |
| ReadingStatus migration destroys data | CRITICAL | `MigrationStage.custom` with explicit rawValue→enum mapping; test with seeded data |
| VisionService→actor breaks sync callers | MEDIUM | Phase 1 lands first; all callers updated to `await` before Phase 2 starts |
| Effort underestimate | MEDIUM | Revised from 4-6h to 6-8h per lane (Gemini recommended 12-16h — split difference) |

## Success Criteria
- All 2 CRITICAL issues resolved (schema versioning, Task.detached)
- All 14 HIGH issues resolved
- All 28 MEDIUM issues resolved or documented as deferred
- Build: 0 errors, 0 warnings at every gate
- Existing + new tests pass
- No regressions in camera capture, SSE streaming, library CRUD
- Schema migration verified with seeded data
