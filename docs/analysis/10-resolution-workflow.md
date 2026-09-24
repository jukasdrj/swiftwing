# Resolution workflow

Date: 2026-09-24. This is the order for closing ledger rows. It does not change app behavior by itself.

Source of truth for what is still open: `00-ledger.md`. Findings stay in `01-` through `09-`. Do not rewrite those files into the fixed state. Append a **Resolved** section with the date, the ledger id, and the test that now locks the behavior.

## Closeout for every slice

Do these in one slice, before starting the next slice in the same wave:

1. Add or adjust a test that fails on the current code. Unit test when the bug is a pure function or a decoded payload. UI test only for a gate the simulator can reach.
2. Make the smallest code change that turns that test green.
3. Build: `xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' build 2>&1 | xcsift` with 0 errors and 0 warnings. If the slice touches the test target, run `build-for-testing` the same way.
4. Append **Resolved** to the findings file named in the slice. Include the ledger id.
5. Set that ledger row to `done` and name the findings file. Do not delete the row.
6. If `CLAUDE.md`, `AGENTS.md`, `START-HERE.md`, or `.claude/rules/` still describes the old behavior, change that sentence in the same slice. Leave historical plans and `docs/architecture/DESIGN-DECISION.md` alone unless the slice is W6.
7. Device-only checks go in `docs/testing/TESTING-CHECKLIST.md` as a checkbox. Do not claim them done from the simulator.

T7 stays deferred. No store-reset UI unless that is requested on its own.

## Waves

Waves A through D can run in any order. E waits on a real JPEG. F waits on a one-line product choice. G is last because it deletes code E might still be reading.

### W1 — Permission gate (T1, T2, T6)

`RootView` must record a denial. The primer binding can only write `.authorized` today, so Cancel leaves the status at `.notDetermined` and Continue calls `requestAccess` again. Also re-read `AVCaptureDevice.authorizationStatus` when the scene becomes active, so a grant made in Settings replaces the primer with the tabs.

Test: a unit-level check is awkward because the gate is a view. Add a UI test that launches with camera denied if the runner can set that, and extend `OnboardingUITests` so a pass requires `permission_continue` when the status is not authorized. Do not keep the assertion that accepts either the primer or the Library tab.

Docs: pass `01-`. No API doc change.

### W2 — Review save tells the truth (T17, T18)

Two separate bugs.

A `review_needed` result with a null title or author is rejected in `validateBookMetadata` and never becomes a card, so the user cannot edit it or look it up. Let that result into `pendingReviewBooks`. Keep `addBookToLibrary` refusing an empty title and author. Show manual lookup for `.reviewNeeded` as well as `.notFound` and `.circuitOpen`. `.error` stays without that button until a payload shows it is recoverable.

`addBookToLibrary` must surface `DataSyncActor.save`'s false. `approveBook` must not remove the card when nothing was written. The duplicate check before the alert must use title and author when the ISBN is missing or `UNKNOWN-`, which is the same pair `save` already uses.

Tests: extend `ReviewQueueManagerTests` and `DataSyncActorTests`. One case for a null-author `review_needed` row remaining in the queue. One case for a title+author duplicate with an `UNKNOWN-` ISBN leaving the card in place and skipping the insert.

Docs: pass `06-` and `07-`. `CLAUDE.md` already says to persist `resolvedMetadata`. Add one sentence that a refused save leaves the card on screen.

### W3 — Shutter versus session start (T13)

`CameraViewModel.setupCamera` marks the camera ready before `AVCaptureSession.startRunning()` has finished, because `startSession` returns as soon as the work is queued. Keep the shutter disabled until the session is running, or await a started state before clearing `isLoading`.

Test: this needs a device or a session double. A device checkbox in `docs/testing/TESTING-CHECKLIST.md` is the honest lock. A unit test can still assert the view model does not report ready before the manager reports running, if that flag is injectable.

Docs: pass `02-`.

### W4 — User-Agent and the dead launch view (T5, T15)

Set the session `User-Agent` to the shipping OS, `SwiftWing/1.0 iOS/27.0`. Remove `LaunchScreenView` from the target. The generated launch screen is the one that runs. Do not add `JetBrainsMono-Bold` for a view nothing presents.

Test: a contract-style test that the upload request is hard from `TalariaService` unless the header is injectable. If it is not, cover the string from a small visible constant the service already uses, and add that constant if the header is inline. No new test for a deleted view.

Docs: pass `01-` and `04-`.

### W5 — Image prep, only the double encode (T14)

Do not invent a new rotation. The aspect check above 2.0 does not match a shelf photo, and changing it changes what Talaria sees. Leave it, and say so in the **Resolved** note as an intentional keep.

Do stop the second JPEG pass when the capture is already within the upload edge and is already JPEG. `CameraManager` already asks for dimensions near 1024×768, then `preprocess` writes JPEG 0.85 and `resizeAndCompress` writes JPEG 0.85 again with a 1920 ceiling that does not shrink that capture.

Test: `ImagePreprocessor` tests do not exist yet. Add one that a JPEG whose long edge is under 1920 is not expanded, and one that records whether a second encode ran. Use a generated bitmap in the test, not `test_book_stack.jpg` (that file is HTML).

Docs: pass `03-`.

### W6 — Bounding boxes (T8 follow-through, T16)

Blocked until one real shelf JPEG exists. `test_book_stack.jpg` is HTML and the API returned 400 Invalid image format. Replace that file with a real JPEG, or point the check at another path. Then:

1. `POST /v3/jobs/scans` with one photo and `X-Device-ID`.
2. Poll until `completed`.
3. Save the `format=lite` body and the `format=full` body next to each other under `swiftwingTests/Fixtures/`. Record whether `boundingBox` is present and whether each number is in 0...1 or above 1.
4. Append that record to pass `04-` and pass `05-` before changing the client.

If full boxes are fractions in 0...1, switch `fetchPollingResults` to `format=full`. `BoundingBox.toCGRect(in:)` already multiplies by the fitted photo size. Update the pixel-scale fixtures (`x: 120.5` and the rest) so they match the saved payload. Add a test that a 0.5 by 0.25 box in a 200 by 100 fit becomes a 100 by 25 rect, and a test that a decoded lite payload has a nil box while the saved full payload does not.

If full boxes are pixels, do not switch yet. Change `toCGRect` only after the saved payload is in the repo, and add the fixture as the test input.

Then delete the live overlay path. It cannot be repaired against the poll API. The server used to push an annotated JPEG on the SSE `segmented` event. Polling never returns that image, and `streamAndProcess` never calls `onSegmented`. Remove `SegmentedPreviewOverlay`, `updateQueueItemSegmented`, and the `onSegmented` callback. Keep `BoundingBoxOverlay` as the after-scan overlay. The review card already shows it only when `metadata.boundingBox` and `originalPhotoURL` are both set. After the format switch, that gate opens.

The temp photo is still deleted on approve, on reject, and after 30 minutes. The overlay only has to work while the card is on screen. Say that in pass `05-`.

Docs: `CLAUDE.md` and `START-HERE.md` currently say the client fetches `format=lite`. Update them in the same slice that changes the query. `AGENTS.md` has the same sentence.

Device check: one shelf photo, open the review card, tap the magnifying glass, confirm the rectangle sits on the book.

### W7 — Library label (T19)

Do not silently widen the predicate. The library control filters `spineConfidence < 0.8`. The review queue is enrichment status. Pick one and record it in the ledger decisions table:

- Rename the library control so it says low confidence, and leave the predicate, or
- Include `enrichmentStatus` of `review_needed` and `not_found` as well as low confidence, and rename nothing.

Test: `LibraryUITests` already toggles the filter. Add a model-level test on `LibraryViewModel.fetch` behavior for a high-confidence `not_found` book so the chosen predicate is locked. The fetch is private today. Test through `updateFilteredBooks` on an in-memory container.

Docs: pass `08-`.

### W8 — Rate limit and the poll cap (T20)

Two edits, no new queue.

Rate-limit files are temp JPEGs named like every other temp JPEG, and the one-hour sweep deletes those. The URL list is also in memory, so a relaunch already drops the queue. Move the rate-limit files to a subdirectory of temp that `cleanupOrphanedTempPhotos` does not scan, or teach that sweep to skip the prefix `RateLimitState` writes. Document them as session-only in pass `09-`. Do not fold them into Documents `/OfflineQueue`. That queue means "offline until the network returns," which is a different event.

`StreamManager` releases its slot when `uploadScan` returns, before `pollScanStatus`. The shutter counter of 5 already covers the whole `processCapture`, including the poll. Do not hold the stream slot through the poll. Correct the `StreamManager` comment so it says the cap is in-flight uploads. The poll bound stays the shutter counter.

Tests: `OfflineQueueManagerTests` stays on Documents. Add a rate-limit test that a queued file is not inside the directory the sweep deletes, or that the sweep's filter skips it. `StreamManagerTests` stays on the slot cap. No new poll-cap test unless the shutter counter moves.

Docs: pass `09-`. T3 stays open until W9 changes the onboarding sentence.

### W9 — Copy, dead client, and stale docs (T3, T9, T10, T11)

Onboarding slide 2 says photos are never stored. Say that a photo is kept on the phone until the scan is uploaded, and that an offline scan stays in the library queue until then. Match the primer, which already says images are processed and then deleted.

Delete the six empty directories under `Services/` (`Data`, `Image`, `Network`, `Offline`, `Monitoring`, `Shared`) if they are still empty. Remove the unused `NetworkService` type and drop `OpenAPIRuntime` and `OpenAPIURLSession` from the app target. No Swift file imports them. The committed YAML stays. The copy-spec build phase stays.

`AGENTS.md` still describes a flat source tree. Point it at `swiftwing/App`, `Features`, `Services`, and `Models`. In `DESIGN-DECISION.md`, `docs/superpowers/plans/2026-06-09-readiness.md`, and `swiftwing/OpenAPI/README.md`, add a single line at the top that the current target is iOS 27 and Swift 6.4, and that the body is historical. Do not rewrite those bodies.

Test: none for deleted empty directories. `build-for-testing` must stay 0 warnings after the package products are removed.

Docs: pass `01-` for the slide sentence. Ledger T3 done in that same slice.

## Suggested order

W1, W2, and W4 first. They are user-visible and they do not wait on a photograph. W6 next, as soon as a real JPEG is available, because that is the bounding-box failure. W3 and W5 with a device nearby. W7 after the rename choice. W8 and W9 last.

## Done means

Every row in `00-ledger.md` is `done` or still `deferred` (T7 only). Each `01-` through `09-` file has a **Resolved** section or an explicit "kept on purpose" sentence. `CLAUDE.md` describes `format=full` only after W6 lands. The simulator build is 0 errors and 0 warnings.
