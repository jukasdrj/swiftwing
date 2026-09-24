# Pass 1 — Launch, onboarding, camera permission

Date: 2026-09-24. Read only. No behavior change in this pass.

Files: `swiftwing/App/SwiftwingApp.swift`, `swiftwing/App/RootView.swift`, `swiftwing/App/LaunchScreenView.swift`, `swiftwing/Features/Onboarding/OnboardingView.swift`, `swiftwing/Features/Camera/CameraPermissionPrimerView.swift`, `swiftwing/Models/BookSchemaVersioning.swift`, `swiftwing/Models/Book.swift`, `swiftwingUITests/OnboardingUITests.swift`, `swiftwingTests/SharedModelContainer.swift`.

## 1. What starts it, and who owns it

`SwiftwingApp` (`@main`) creates the SwiftData stack as a stored property before the first frame:

- Schema: `BookSchemaV2` (`Schema.Version(2, 0, 0)`), model type `Book`
- Migration: `BookMigrationPlan`, one lightweight stage from `BookSchemaV1` to `BookSchemaV2`
- Store: on disk (`isStoredInMemoryOnly: false`)
- Failure: `Logger` fault, then `fatalError`

`init` then applies UI-test launch arguments and starts `cleanupOrphanedTempPhotos()` on a background-priority task. The scene is a `WindowGroup` of `RootView`, forced dark, with `.modelContainer(sharedModelContainer)`.

`RootView` owns the gate. On appear it sets `showOnboarding` from `@AppStorage("hasCompletedOnboarding")` and reads `AVCaptureDevice.authorizationStatus(for: .video)` into `cameraPermissionStatus`.

The body chooses one child:

1. `showOnboarding` → `OnboardingView`
2. launch argument `UI_TESTING` → `MainTabView` (permission gate skipped)
3. otherwise the permission switch: `.notDetermined` or `.denied` → `CameraPermissionPrimerView`, `.authorized` → `MainTabView`

`MainTabView` owns the single `CameraViewModel` shared by the Library, Review, and Camera tabs. Library is the default tab unless the launch argument is `INJECT_TEST_IMAGE`.

Onboarding does not request camera access. Slide 2 is copy. `completeOnboarding()` sets `hasCompletedOnboarding` and calls `onComplete`, which clears `showOnboarding`. `RootView.onChange(of: showOnboarding)` then re-reads the camera status. The system prompt happens only when the primer's Continue button calls `AVCaptureDevice.requestAccess(for: .video)`.

## 2. Inputs and outputs

| Step | Input | Output |
|---|---|---|
| Container | `BookSchemaV2`, `BookMigrationPlan` | `ModelContainer` or process abort |
| UI-test init | `ProcessInfo` arguments `FORCE_ONBOARDING`, `FORCE_CAMERA_GUIDANCE`, `UI_TESTING`, `CLEAR_DATA`, `SEED_LIBRARY` | `UserDefaults` keys `hasCompletedOnboarding`, `hasSeenCameraGuidance`, `show_review_needed`; optional wipe or `DataSeeder.seedLibrary` |
| Onboarding | `@AppStorage("hasCompletedOnboarding")`, `currentPage` 0...2 | flag set `true`, `onComplete()` |
| Permission | `AVAuthorizationStatus` | `CameraPermissionStatus` (`.notDetermined`, `.denied`, `.authorized`) |
| Primer grant | `requestAccess` callback `granted == true` | binding sets `cameraPermissionStatus = .authorized`, which presents `MainTabView` |
| Tabs | `AppTab` raw values library 0, review 1, camera 2 | `TabView` selection |

`Book` and the frozen `BookSchemaV1.BookV1` both store `author: String` (one string, not an array). V1 stores `readingStatus: String?`. V2 stores `readingStatus: ReadingStatus?` with the same raw strings (`to_read`, `reading`, `completed`, `did_not_finish`). The migration comment matches the models: on-disk representation of the enum is the raw string, and the stage is lightweight. V2 adds `#Index` entries on `title` and `author`. V1 indexed `isbn` and `addedDate` only.

## 3. Failures

Handled:

- Store creation failure aborts the process. Logged first.
- Orphan JPEG deletion failures are logged as warnings and the loop continues.
- `CLEAR_DATA` / `SEED_LIBRARY` save failures are logged. Seeding still runs after a failed clear.
- Denied `requestAccess` presents the "Camera Access Needed" alert with Cancel and Open Settings.
- Previously denied status (read at launch) shows the Open Settings primer instead of Continue.
- `@unknown default` on authorization status is treated as `.notDetermined`.

Logged or dropped:

- A denial does not update `RootView`. See T1 in the ledger.
- Returning from Settings does not re-read status. See T2.
- `cleanupOrphanedTempPhotos` has no link to the offline queue. A file it deletes is gone. See T4.

## 4. What is tested

`OnboardingUITests` launches with `FORCE_ONBOARDING` only (not `UI_TESTING`):

- `testSkipOnboarding` taps `onboarding_skip` and accepts `permission_continue` or the Library tab.
- `testNextThroughAllSlides` taps Next twice, taps `onboarding_get_started`, and accepts the same pair.

Neither test requires the primer. There is no test for an already-authorized skip of the primer, a denial, the Settings button, or a store migration.

`SharedModelContainer` builds one in-memory `ModelContainer` for the unit-test process with `BookSchemaV2` and `BookMigrationPlan`, because creating a container per test hit an `EXC_BREAKPOINT` inside SwiftData on iOS 26 / Swift 6.2. The comment still names that toolchain. Whether iOS 27 still needs the shared container is unproven. Keep the helper.

UI-test arguments that do work, from `SwiftwingApp.configureForUITesting`: `UI_TESTING` marks onboarding and camera guidance complete and clears `show_review_needed`. `FORCE_ONBOARDING` and `FORCE_CAMERA_GUIDANCE` clear those flags and are applied even when `UI_TESTING` is absent. `FORCE_CAMERA_GUIDANCE` together with `UI_TESTING` leaves guidance unseen.

## 5. Structural risk

The permission gate's denied state is write-only from a cold launch. `CameraPermissionPrimerView` reports success through a `Binding<Bool>` whose setter ignores `false`:

```swift
set: { if $0 { cameraPermissionStatus = .authorized } }
```

Deny, cancel the alert, and the primer is still the first-run Continue screen, because status is still `.notDetermined`. iOS will not show the system prompt again. Continue calls `requestAccess`, gets `granted == false` immediately, and shows the alert again. The Open Settings copy exists, and it is reachable on the next launch.

## Other notes, not the structural risk

- `LaunchScreenView` is in the app target and is never referenced. Cold start uses the generated launch screen. See T5.
- Slide 2 says "Your photos are never stored — we only send them to our AI for instant recognition." The primer says images are processed and deleted immediately. Temp-file cleanup proves JPEGs are written. See T3. Pass 9 owns the persistence question.
- Display name in the target is `swiftoooe`. Onboarding copy says SwiftWing. The home-screen name and the in-app name differ.
- `UI_TESTING` skips the permission gate entirely, including when the camera is denied. That is intentional for the other UI tests. Onboarding tests do not pass `UI_TESTING`, so they still hit the real gate.

## Resolved

2026-09-24. T1, T2, T6.

A denial from `requestAccess` sets `RootView.cameraPermissionStatus` to `.denied`. The Open Settings primer replaces Continue in that same session. `RootView` re-reads `AVCaptureDevice.authorizationStatus` when the scene becomes active, so a grant made in Settings replaces the primer once the system reports the new status.

`OnboardingUITests` resets camera authorization and requires `permission_continue`. The Library tab does not count. `testDenyingSystemPromptShowsOpenSettingsPrimer` denies the system prompt and requires the Open Settings primer. `testGrantingCameraInSettingsReplacesPrimerOnNextRead` turns on the Camera switch under Privacy & Security and requires the Library tab on the next launch. This simulator keeps the previous authorization status for the running process, so that test relaunches. The active-scene re-read covers a grant the system reports without a restart.

Tests: `swiftwingUITests/OnboardingUITests`, 4 passed, 0 warnings, iPhone 18 Pro Max.

2026-09-24. T5.

`LaunchScreenView` is removed from the app target and deleted. Cold start uses the generated launch screen (`INFOPLIST_KEY_UILaunchScreen_Generation`). `JetBrainsMono-Bold` was not added. No new test for a deleted view.

2026-09-24. T3, T9, T10, T11.

Slide 2 now says a photo stays on the phone until the scan is uploaded, and that an offline scan stays in the library queue until then.

The six empty directories under `Services/` are gone. `NetworkService` is removed. `OpenAPIRuntime` and `OpenAPIURLSession` are no longer linked. The committed YAML and the copy-spec build phase stay. The virtual Shared group in the Xcode project still holds `BoundingBox+CGRect.swift`.

`AGENTS.md` points at `swiftwing/App`, `Features`, `Services`, and `Models`. `DESIGN-DECISION.md`, `docs/superpowers/plans/2026-06-09-readiness.md`, and `swiftwing/OpenAPI/README.md` each open with one line that the current target is iOS 27 and Swift 6.4 and that the body is historical.
