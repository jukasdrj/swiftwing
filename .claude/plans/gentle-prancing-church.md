# Plan: Repository Restructuring + Large File Decomposition

## Context

SwiftWing has 41 of 53 Swift files sitting at the root of `swiftwing/`. The CLAUDE.md describes a Feature-based structure (`Features/Camera/`, `Features/Library/`, etc.) but this was never fully implemented — only 2 debug views live in `Features/`. Additionally, several files have grown into god objects: `LibraryView.swift` (1,286 lines), `CameraViewModel.swift` (949 lines), `ReviewQueueView.swift` (659 lines), and `CameraView.swift` (521 lines).

This plan restructures the repository into strict feature-based grouping and decomposes the largest files. All files stay in the same `swiftwing` module target, so Swift imports and `@testable import swiftwing` tests remain unaffected. The main risk is `project.pbxproj` — we'll update it programmatically after each batch of moves.

## Safety Notes

- **Swift imports are module-level** — moving files within the target doesn't break any imports
- **Tests use `@testable import swiftwing`** — unaffected by internal moves
- **No hardcoded file paths** in build scripts (only `${SRCROOT}` references)
- **Build verification after each phase** via `xcodebuild ... | xcsift`

---

## Phase 1: Directory Creation + File Moves

Create the target directory structure and move existing files. **No code changes yet** — just file relocations + pbxproj updates.

### Target Structure

```
swiftwing/
├── App/
│   ├── SwiftwingApp.swift          (from root)
│   ├── RootView.swift              (from root)
│   └── LaunchScreenView.swift      (from root)
│
├── Features/
│   ├── Camera/
│   │   ├── CameraView.swift
│   │   ├── CameraViewModel.swift
│   │   ├── CameraManager.swift
│   │   ├── CameraPreviewView.swift
│   │   ├── CameraPermissionPrimerView.swift
│   │   ├── ScanJobCoordinator.swift
│   │   ├── StreamManager.swift
│   │   ├── VisionOverlayView.swift
│   │   ├── ObjectBoundingBoxView.swift
│   │   ├── BoundingBoxOverlay.swift
│   │   ├── CaptureGuidanceView.swift
│   │   ├── ProcessingQueueView.swift
│   │   ├── ProcessingFeedbackView.swift  (from Features/Camera/)
│   │   ├── SegmentedPreviewOverlay.swift
│   │   ├── RateLimitOverlay.swift
│   │   ├── RateLimitState.swift
│   │   ├── ProcessingItem.swift
│   │   └── FocusIndicatorView.swift (if exists)
│   │
│   ├── Library/
│   │   ├── LibraryView.swift
│   │   ├── LibraryPerformanceOptimizations.swift
│   │   ├── LibraryPrefetchCoordinator.swift
│   │   └── BookDetailSheetView.swift
│   │
│   ├── ReviewQueue/
│   │   ├── ReviewQueueView.swift
│   │   ├── ReviewQueueManager.swift
│   │   └── DuplicateBookAlert.swift
│   │
│   ├── Onboarding/
│   │   └── OnboardingView.swift
│   │
│   └── Settings/
│       └── FeatureFlagsDebugView.swift  (already here)
│
├── UIComponents/
│   ├── Theme.swift
│   ├── AsyncImageWithLoading.swift
│   ├── ConfidenceBadge.swift
│   └── OfflineIndicatorView.swift
│
├── Services/                        (already exists, add to it)
│   ├── TalariaService.swift         (already here)
│   ├── NetworkTypes.swift           (already here)
│   ├── ImagePreprocessor.swift      (already here)
│   ├── SSEEventParser.swift         (already here)
│   ├── VisionService.swift          (already here)
│   ├── VisionTypes.swift            (already here)
│   ├── BoundingBox+CGRect.swift     (already here)
│   ├── NetworkMonitor.swift         (from root)
│   ├── NetworkService.swift         (from root)
│   ├── ImageCacheManager.swift      (from root)
│   ├── OfflineQueueManager.swift    (from root)
│   └── PerformanceLogger.swift      (from root)
│
├── Models/                          (already exists, add to it)
│   ├── Book.swift                   (already here)
│   ├── DataSeeder.swift             (already here)
│   ├── PendingBookResult.swift      (already here)
│   ├── DuplicateDetection.swift     (from root)
│   ├── AutoApproveSettings.swift    (from root)
│   └── DeviceIdentifier.swift       (from root)
│
├── Utilities/
│   └── PerformanceTestData.swift    (from root)
│
├── OpenAPI/                         (unchanged)
├── Generated/                       (unchanged)
├── Fonts/                           (unchanged)
├── Assets.xcassets/                 (unchanged)
└── Preview Content/                 (unchanged)
```

**Files removed/skipped:**
- `HelloWorldView.swift` — legacy, delete if unused (verify first)
- `Extensions/` — empty directory, remove

### Execution

1. Create directories: `App/`, `Features/Camera/`, `Features/Library/`, `Features/ReviewQueue/`, `Features/Onboarding/`, `UIComponents/`, `Utilities/`
2. Move files in batches (Camera batch, Library batch, etc.) using `mv`
3. Update `project.pbxproj` path references for each moved file
4. **Build verify**: `xcodebuild ... | xcsift` — must be 0 errors, 0 warnings

---

## Phase 2: LibraryView Decomposition (1,286 → ~300 + 400 + subviews)

Extract a `LibraryViewModel` and break the view into sub-views.

### Files to create

| New File | Location | Purpose |
|----------|----------|---------|
| `LibraryViewModel.swift` | `Features/Library/` | `@Observable` class: sorting, filtering, search, bulk selection, stats logic |
| `LibraryGridView.swift` | `Features/Library/` | Grid display sub-view (extracted from LibraryView body) |
| `LibraryToolbar.swift` | `Features/Library/` | Sort/filter toolbar (extracted) |
| `BookCardView.swift` | `Features/Library/` | Individual book card in grid |

### Approach
- Read `LibraryView.swift` fully, identify logical sections
- Extract `@Observable class LibraryViewModel` with: sort state, search text, filter logic, bulk selection, stats computation, performance test data generation
- `LibraryView` becomes a thin shell: toolbar + grid + sheets
- Sub-views receive ViewModel via `@Bindable` or parameters
- **Build verify** after extraction

---

## Phase 3: CameraViewModel Decomposition (949 → ~500 + coordinators)

CameraViewModel manages rate limiting, vision state, haptics, and offline queues. Extract focused coordinators.

### Files to create

| New File | Location | Purpose |
|----------|----------|---------|
| `CameraHapticsManager.swift` | `Features/Camera/` | Haptic feedback logic |
| `CameraVisionCoordinator.swift` | `Features/Camera/` | Vision framework state + bounding box management |

### Approach
- Extract haptics into a small manager (called by ViewModel)
- Extract vision/bounding-box state tracking into a coordinator
- CameraViewModel delegates to these, reducing to ~500 lines
- Rate limiting stays in ViewModel (it's tightly coupled to scan flow)
- **Build verify** after extraction

---

## Phase 4: ReviewQueueView Decomposition (659 → ~250 + subviews)

### Files to create

| New File | Location | Purpose |
|----------|----------|---------|
| `ReviewCardView.swift` | `Features/ReviewQueue/` | Individual review card (extracted from ReviewQueueView) |
| `ReviewEditForm.swift` | `Features/ReviewQueue/` | Book editing form within review |

### Approach
- Extract the per-item card UI into `ReviewCardView`
- Extract editing/detail form into `ReviewEditForm`
- ReviewQueueView becomes a list/scroll container
- **Build verify** after extraction

---

## Phase 5: CameraView Cleanup (521 → ~300)

### Files to create

| New File | Location | Purpose |
|----------|----------|---------|
| `CameraOverlayView.swift` | `Features/Camera/` | Combined overlay logic (guidance + processing + rate limit) |

### Approach
- Extract the complex overlay stacking logic into `CameraOverlayView`
- CameraView becomes: preview + overlay + capture button
- **Build verify** after extraction

---

## Phase 6: Documentation Update

- Update `CLAUDE.md` architecture section to reflect new structure
- Update file table in CLAUDE.md
- Remove stale references to root-level files
- Delete planning files

---

## Verification

After each phase:
```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift
```
**Required: errors: 0, warnings: 0**

After all phases:
- Run unit tests to confirm no regressions
- Verify git diff is clean (only moves + new files + pbxproj updates)

## Execution Strategy

Use a **team of agents** for parallel work:
- Phase 1 is sequential (must complete before code changes)
- Phases 2-5 can be parallelized after Phase 1 (each feature area is independent)
- Phase 6 is sequential (after all code changes)

## Risk Mitigation

- **Commit after Phase 1** before any code decomposition — easy rollback point
- **pbxproj is the main risk** — we'll read it carefully before editing, use unique UUIDs for new file references
- **No module boundary changes** — everything stays in `swiftwing` target
