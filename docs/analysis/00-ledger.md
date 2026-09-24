# Analysis ledger

Open items only. When an item is done, strike it here and point at the commit or the findings file. Do not delete the row.

Status values: `open`, `deferred`, `done`.

## Todos

| ID | Status | From | Item |
|---|---|---|---|
| T1 | done | pass 1 | ~~After the user denies the system camera prompt, `RootView.cameraPermissionStatus` stays `.notDetermined`.~~ Resolved 2026-09-24 in `01-launch-onboarding-permission.md`. |
| T2 | done | pass 1 | ~~Granting camera access in Settings and returning to the primer does not re-read authorization.~~ Resolved 2026-09-24 in `01-launch-onboarding-permission.md`. |
| T3 | done | pass 1, confirmed pass 9 | ~~Slide 2 says photos are never stored.~~ Resolved 2026-09-24 in `01-launch-onboarding-permission.md`. |
| T4 | done | pass 1, answered pass 9 | The one-hour temp sweep does not delete offline scans. Those files are in Documents `/OfflineQueue`, not the temp directory. Rate-limit JPEGs are in the temp directory and are eligible for the sweep. See T20. |
| T5 | done | pass 1 | ~~`LaunchScreenView` is compiled and never presented.~~ Resolved 2026-09-24 in `01-launch-onboarding-permission.md`. |
| T6 | done | pass 1 | ~~`OnboardingUITests` accepts either the permission primer or the Library tab.~~ Resolved 2026-09-24 in `01-launch-onboarding-permission.md`. |
| T7 | deferred | pass 1 | `SwiftwingApp` calls `fatalError` if `ModelContainer` cannot be created. No recovery UI. Leave it unless a store-reset path is requested. |
| T8 | done | pass 4 | The client requests `format=lite`. Committed OpenAPI says lite omits `boundingBox`, and full boxes are normalized 0–1. Fixtures still use pixel-scale boxes (120.5). Live diff did not run: `test_book_stack.jpg` is HTML and the API returned 400 Invalid image format. Pass 5 treats boxes as absent. |
| T9 | done | org review | ~~`Services/` contains six empty directories.~~ Resolved 2026-09-24 in `01-launch-onboarding-permission.md`. |
| T10 | done | org review | ~~`OpenAPIRuntime` and `OpenAPIURLSession` are linked.~~ Resolved 2026-09-24 in `01-launch-onboarding-permission.md`. |
| T11 | done | toolchain | ~~Historical docs still say iOS 26 / Swift 6.2, and AGENTS.md describes a flat tree.~~ Resolved 2026-09-24 in `01-launch-onboarding-permission.md`. |
| T12 | done | toolchain | Test targets are Swift 6.4. UI test classes are `@MainActor`. `setUpWithError()` cannot be `@MainActor` (XCTest declares it nonisolated), so `app` is `nonisolated(unsafe)` and setup builds the `XCUIApplication` inside `MainActor.assumeIsolated` without capturing `self`. App `build` and `build-for-testing` are 0 errors / 0 warnings on iPhone 18 Pro Max. Test targets still set `SWIFT_APPROACHABLE_CONCURRENCY` and `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`; the app target sets neither. Leave those flags until a pass shows they change behavior. |
| T13 | open | pass 2 | `startSession()` returns before `startRunning()` finishes, and the shutter is already enabled. An early tap fails inside the photo delegate. |
| T14 | open | pass 3 | Shelf prep double-encodes JPEG at 0.85 and only rotates when height/width > 2. A shelf photo does not take that path. |
| T15 | done | pass 4 | ~~`User-Agent` is still `SwiftWing/1.0 iOS/26.0` after the iOS 27 retarget.~~ Resolved 2026-09-24 in `04-shelf-to-books.md`. |
| T16 | done | pass 5 | ~~Shelf UI cannot point at a detected book. Lite omits `boundingBox`.~~ Resolved 2026-09-24 in `04-shelf-to-books.md` and `05-draw-detected-books.md`. Full boxes are 0...1. |
| T17 | done | pass 6 | ~~`validateBookMetadata` drops a result with an empty title or author, so a `review_needed` row with null fields never reaches a card.~~ Resolved 2026-09-24 in `06-review-recovery-duplicates.md`. |
| T18 | done | pass 6, pass 7 | ~~`addBookToLibrary` ignores `DataSyncActor.save`'s false. An `UNKNOWN-` ISBN skips the duplicate alert.~~ Resolved 2026-09-24 in `06-review-recovery-duplicates.md` and `07-save-into-catalog.md`. |
| T19 | done | pass 8 | ~~Library "review needed" is `spineConfidence < 0.8` while the review queue keys off enrichment status.~~ Resolved 2026-09-24 in `08-library-browse.md`. The control is labeled low confidence. The predicate is unchanged. |
| T20 | done | pass 9 | ~~Rate-limit retries sit where the one-hour temp sweep can delete them, and the stream-manager comment says it caps polls.~~ Resolved 2026-09-24 in `09-offline-queue-rate-limit.md`. |

## Decisions

| Date | Decision |
|---|---|
| 2026-09-24 | Learnings live in `docs/analysis/NN-*.md`. Todos live in this ledger. Root-level `*_task_plan.md` files are not used for this review. |
| 2026-09-24 | Deployment target is iOS 27.0 on the project and on all three targets. Swift language mode is 6.4 on all three targets. Xcode 27.0 (27A266a) is the toolchain. Simulator destination for builds is iPhone 18 Pro Max, because iPhone 17 Pro Max is not installed. |
| 2026-09-24 | Passes 2–9 are recorded and do not change behavior. Production results are `format=lite`, so bounding boxes are treated as absent until a real `format=full` payload shows the unit. |
| 2026-09-24 | Shelf job `e37676d1-7738-4f54-bac3-8eca5711ca79`: lite omits `boundingBox`. Full box is 0.027, 0.04, 0.191, 0.834, all in 0...1. The client requests `format=full`. |
| 2026-09-24 | Fixes follow `10-resolution-workflow.md`. A slice is done only when the test, the findings note, the ledger row, and any live doc sentence land together. |
| 2026-09-24 | W7: the library control stays `spineConfidence < 0.8` and is renamed low confidence. It does not also include `review_needed` or `not_found`. |
| 2026-09-24 | W3 (T13) and W5 (T14) were skipped on request. Those rows stay open. |
