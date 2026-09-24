# Pass 4 — Shelf photo to book results

Date: 2026-09-24. Read only.

Files: `swiftwing/Features/Camera/ScanJobCoordinator.swift`, `swiftwing/Services/TalariaService.swift` (`uploadScan`, `pollScanStatus`, `fetchPollingResults`), `swiftwing/Services/NetworkTypes.swift` (`JobStatus`, `BookMetadata`, `BoundingBox`, `EnrichmentStatus`), `swiftwing/OpenAPI/talaria-openapi.yaml` (`POST /v3/jobs/scans`, `GET .../results`), `swiftwing/Features/Camera/CameraViewModel.swift` (`buildScanCallbacks`), `swiftwingTests/Fixtures/TalariaContractFixtures.swift`, `swiftwingTests/Unit/Services/TalariaContractAdherenceTests.swift`, `PollScanStatusResilienceTests.swift`, `ScanResultsResponseContractTests.swift`.

Do not change yet.

## 1. What starts it, and who owns it

`CameraViewModel.uploadToTalaria` acquires a `StreamManager` slot and calls `ScanJobCoordinator.uploadScan`. The coordinator calls `TalariaService.uploadScan`. On 200 or 202 it returns `ScanUploadResult.jobId`. The view model then calls `streamAndProcess`, which calls `pollScanStatus` and fans the array out through `ScanJobCallbacks`.

`TalariaService` is an actor. The view model and the review sheet share one instance so the device id stays stable. The status poll sends the actor’s `deviceId`. The upload sends the `deviceId` argument. `CameraViewModel` constructs the service with `DeviceIdentifier.current` and passes that same string into `uploadScan`.

## 2. The five checks

### One JPEG and `X-Device-ID`

`uploadScan` builds one multipart part: `name="photos[]"`, `filename="spine.jpg"`, `Content-Type: image/jpeg`, then the bytes. The header is `X-Device-ID` set to the passed device id. The committed spec says `photos[]` has `minItems: 1` and `maxItems: 1`, and that the header is a required UUID. The client matches that shape. The `User-Agent` on the session is still `SwiftWing/1.0 iOS/26.0`.

### Status values

`pollScanStatus` decodes `JobStatusResponse` and switches:

| Wire value | Client |
|---|---|
| `queued`, `processing` | keep polling |
| `completed` | `fetchPollingResults` |
| `failed` | `NetworkError.scanFailed` |
| `canceled` | `CancellationError` |
| `initialized` | `JobStatus` decoder maps it to `.queued` |

Unknown status strings fail the decode and count as a transient failure (budget 4, then throw). The loop allows 75 attempts with backoff capped at 4 seconds. A 404 or 5xx on the status call is transient. `scanFailed` and cancellation are terminal. Results-fetch failures have their own budget of 4 so a status-200 cannot reset them. Contract tests cover the `initialized` → `queued` map.

### Lite versus full, and bounding boxes

The client always requests `GET /v3/jobs/scans/{jobId}/results?format=lite`.

The committed spec, `talaria-openapi.yaml`, says:

- `format` is `full` (default) or `lite` (described as the App Clip shape).
- Lite excludes `boundingBox`.
- `boundingBox` on `DetectedBook` is normalized, 0.0–1.0, and "Absent in lite format."
- Both formats use the same `JobResultsResponse` schema. The exclusion is prose on the operation and on the property, not a second schema.

`BookMetadata`’s comment agrees that lite omits `boundingBox`. The same comment calls the box "pixel coordinates." `BoundingBox+CGRect.toCGRect(in:)` multiplies by the image size, which is the normalized interpretation. The two comments disagree. The spec and `toCGRect` agree with each other.

`TalariaContractFixtures` is neither lite nor the current full shape. `bookMetadataFullJSON` and the other book fixtures include `boundingBox` values such as `x: 120.5`, `y: 200.3`, `width: 80`, `height: 150`. Those numbers are outside 0–1. One fixture sets `boundingBox` to null. The file header says the fixtures are hand-maintained and CI-safe, not captured responses. `test_decodeBookMetadata_withBoundingBox` expects those pixel-scale numbers.

A live diff was attempted with `test_book_stack.jpg` and a fresh device UUID against `POST https://api.oooefam.net/v3/jobs/scans`. The file is HTML (`<!DOCTYPE html>`), 2.1 KB. The server returned 400 `Invalid image format` (`requestId` `26794e30-92b5-401c-abda-25de9c00cd8d`). There is no other photo in the repo, so there is no completed job to compare. Until a real JPEG is posted, the spec is the source for "lite has no box."

### One `BookMetadata` into the review queue

`streamAndProcess` walks the array:

- Dedup key is `isbn:<trimmed isbn>` when `isbn` is non-empty after the decoder has mapped `""` and `"unknown"` to nil. Otherwise `title-author:<lowercased title>|<lowercased author>` when both are non-empty. Title alone does not dedup. A nil key is delivered anyway.
- Each kept book calls `onBookMetadataReceived`, then `onBookResult`.
- `buildScanCallbacks` ignores the callback’s ISBN and photo arguments and calls `ReviewQueueManager.handleBookResult` with the captured `originalPhotoURL` and `preScannedISBN`. The photo URL does arrive, from that capture, not from the nil arguments.

`handleBookResult` then `validateBookMetadata`: empty title or empty author is rejected and an error overlay is shown. The book never joins `pendingReviewBooks`. A `review_needed` payload with null title and author, which the type comment describes, dies here.

`EnrichmentStatus` is `success`, `review_needed`, `circuit_open`, `not_found`, `error`, and `pending` (also the fallback for an unknown string). `ReviewCardView.needsRecovery` is true only for `.notFound` and `.circuitOpen`. `.error`, `.reviewNeeded`, `.success`, and `.pending` do not show "Look up manually." A `not_found` row with a null author never reaches that button, because validation already dropped it.

`streamAndProcess` does not call `onSegmented`, `onBookProgress`, `onEnrichmentDegraded`, or `onTruncationSuspected`. Those closures exist. The poll path never fires them.

### Where a spine or a cover becomes a book

A spine or a front cover becomes a separate book only as one element of the `results` array Talaria returns for that single photo. The client has no local detector past that boundary.

## 3. Failures

Handled: 400, 413, 429, and 5xx on upload parse `ProblemDetails` when they can. 429 becomes `NetworkError.rateLimited` from `retryAfterMs` (milliseconds) or the `Retry-After` header (seconds). Disconnect and timeout map to `noConnection` and `timeout`. Poll cancellation calls `onCanceled`. Other poll errors call `onError` and return 0. They do not throw to the view model, so `processCaptureWithImageData` still takes its success path unless the queue item was already marked `.error`.

Logged or dropped: a book with no dedup key is not collapsed. A book with an empty title or author is dropped after the server already counted it.

## 4. What is tested

`TalariaContractAdherenceTests`, `PollScanStatusResilienceTests`, and `ScanResultsResponseContractTests` decode fixtures, including `initialized` → `queued`, enrichment statuses, a box, a null box, and `"unknown"` ISBN → nil. They do not perform a live upload, and they do not assert that the URL the client builds contains `format=lite`.

## 5. Structural risk

The client asks for lite. The spec says lite omits `boundingBox`. The review overlay and the segmented preview both need that box, or a segmented image the poll path never delivers. Pass 5 should treat boxes as absent on the production request.

## Do not change yet

Do not switch the results query to `format=full`, and do not retune dedup or validation, until pass 5 records what the shelf UI can actually draw.

## Resolved

2026-09-24. T15.

The session `User-Agent` is `TalariaService.userAgent`, `SwiftWing/1.0 iOS/27.0`. Test: `test_userAgentNamesShippingOS` in `TalariaContractAdherenceTests`.

2026-09-24. Live shelf payload, recorded before the client change. T16.

Source photo: `9FD415F6-EB20-4996-84CF-730315A12738.heic`, 5712×4284. Uploaded as a 1920×1440 JPEG (`sips -Z 1920`). Job `e37676d1-7738-4f54-bac3-8eca5711ca79`, device `56acbe50-d5ae-4eea-b8d4-96ef7cf6bd24`. One book: Bittersweet, Susan Cain.

Bodies: `swiftwingTests/Fixtures/shelf-scan-lite.json` and `shelf-scan-full.json`.

| Format | boundingBox |
|---|---|
| lite | absent |
| full | `x` 0.027, `y` 0.04, `width` 0.191, `height` 0.834 |

Every full-box number is in 0...1. None is above 1.

2026-09-24. T16, client follow-through.

`fetchPollingResults` requests `format=full`. `toCGRect` still multiplies by the fitted photo size. The pixel-scale fixtures now use 0...1 values, and the primary fixture matches this payload. Tests: `test_savedLitePayloadOmitsBoundingBox`, `test_savedFullPayloadBoundingBoxIsNormalized`, `test_toCGRectScalesNormalizedBox`.
