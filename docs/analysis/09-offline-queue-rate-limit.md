# Pass 9 — Offline queue and rate limit

Date: 2026-09-24. Read only. Crosses passes 2, 4, and 6.

Files: `swiftwing/Services/OfflineQueueManager.swift`, `swiftwing/Features/Camera/RateLimitState.swift`, `swiftwing/Features/Camera/StreamManager.swift`, `swiftwing/Features/Camera/CameraViewModel.swift` (`captureImage` cap, `uploadToTalaria`, `handleRateLimitError`, `checkAndUploadQueuedScans`, `uploadQueuedScans`, `handleNetworkChange`), `swiftwing/App/SwiftwingApp.swift` (`cleanupOrphanedTempPhotos`), `swiftwingTests/Unit/Services/OfflineQueueManagerTests.swift`, `swiftwingTests/StreamManagerTests.swift`.

Do not change yet.

## 1. What starts it, and who owns it

Three separate limits sit on one shutter tap.

Offline. `processCaptureWithImageData` checks `networkMonitor.isConnected` before preprocessing. When it is false, `OfflineQueueManager.queueScan` writes the raw capture bytes. The manager is an actor. Files live in Documents `/OfflineQueue/<uuid>.jpg` plus a sibling `<uuid>.json` (`QueuedScanMetadata`: id, date, file name, optional `preScannedISBN`). `CameraView`’s `.task` calls `checkAndUploadQueuedScans`. `handleNetworkChange` calls `uploadQueuedScans` when connectivity returns. Replay is serial: each `processCaptureWithImageData` is awaited, and the file is removed only when that call returns true.

Rate limit. A `NetworkError.rateLimited` in the processing catch calls `RateLimitState.queueScan` with the capture bytes, removes the processing-queue row, and starts a countdown from `retryAfter` or 60 seconds. The actor writes `temporaryDirectory/<uuid>.jpg` and keeps the URL in memory. When the countdown hits zero, `dequeueAllScans` reads the files, deletes them, and re-enters `processCaptureWithImageData`.

Concurrency. `captureImage` allows 5 `processCapture` tasks, and that counter stays up through the poll. `StreamManager` also allows 5, but `uploadToTalaria` releases the slot as soon as `uploadScan` returns, before `streamAndProcess` polls. The comment on `StreamManager` says it limits poll jobs. The call site limits in-flight uploads.

## 2. Inputs and outputs

| Path | Bytes stored | Where | Survives relaunch |
|---|---|---|---|
| Offline, before preprocess | original capture `Data` | Documents `/OfflineQueue` | yes |
| Upload pipeline | second JPEG | temp `<uuid>.jpg` | no; 30-minute detached delete, and the one-hour temp sweep |
| Rate limit | the `imageData` argument of `handleRateLimitError`, which is the original capture | temp `<uuid>.jpg` | no; the URL list is in memory |

`uploadQueuedScans` refuses to start a second drain (`isUploadingOfflineScans`). It requires `modelContext`. It clears `.offline` rows from the on-screen queue, then streams disk items oldest first. A false return from processing leaves the disk item in place. A true return deletes it. If the remove fails, the next launch uploads it again.

Pass 1 asked whether the one-hour temp sweep deletes an offline scan. It does not. Offline files are not in the temp directory. The sweep does match rate-limit files (`*.jpg` in the temp directory, older than one hour) and the upload temp files from pass 3. A rate-limit wait is usually about a minute, so the sweep matters when the countdown is long or the process sits idle with files still queued.

Onboarding slide 2 says photos are never stored. Offline queue stores them in Documents until a successful upload. Temp JPEGs exist for the in-flight upload and for the rate-limit queue. The sentence is false. Ledger T3 stays open as a copy bug. Ledger T4 is answered: the offline file is safe from that sweep.

## 3. Failures

Handled:

- `queueScan` ensures the directory exists and throws if the write fails. The view model has already put an `.offline` row on screen before the write. A throw leaves that row without a matching disk file, and the function returns false, so the caller’s success path is the catch.
- Rate-limit file write failure logs and drops that capture. The countdown still runs.
- `dequeueAllScans` skips a file it cannot read, and still deletes the ones it can.
- Offline replay of a failed scan keeps the Documents file.
- `StreamManager.acquireStreamSlot` queues past 5 uploads and wakes waiters on release. Cancellation removes the waiter.

Logged or dropped:

- Rate-limit state and its file list die with the process. The JPEG can remain until the one-hour sweep.
- `StreamManager` does not bound the number of polls. Five uploads can finish and leave five polls running, and the shutter cap is the only poll bound.
- Offline replay sends the original capture back through preprocess and upload. It does not skip prep. That is consistent. It does mean a photo queued offline is filtered on the way out, not on the way in.

## 4. What is tested

`OfflineQueueManagerTests` uses the injected directory initializer and covers queue, stream order, and removal. `StreamManagerTests` covers the slot cap and wakeups. No test runs the view-model replay, the rate-limit temp files, or the interaction with `cleanupOrphanedTempPhotos`. A device on airplane mode, then back online, is the check for the Documents queue. A 429 is the check for the countdown.

## 5. Structural risk

The durable queue and the rate-limit queue are different mechanisms that the shutter treats as one "try again later." Only the Documents queue survives a relaunch. The rate-limit queue looks queued, lives in temp, and is gone if the process dies or the one-hour sweep runs first. `StreamManager`’s cap ends at upload, so it does not limit the polls the comment says it limits.

## Do not change yet

Leave both queues, the shutter cap, and the slot release where they are. T3 and T4 are recorded. No copy or cleanup change in this pass.

## Resolved

2026-09-24. T20.

Rate-limit retries stay session-only. The files are JPEGs under `temporaryDirectory/SwiftWingRateLimit`. The one-hour sweep lists only the top of the temp directory, so it does not delete them. A relaunch still drops the queue, because the URL list is in memory. They are not copied into Documents `/OfflineQueue`.

`StreamManager` still releases its slot when `uploadScan` returns. Its comment now says the cap is in-flight uploads. The shutter counter of 5 still covers the poll. The slot is not held through the poll.

Test: `queuedFileSitsOutsideTheOneHourSweep` in `RateLimitStateTests`. `OfflineQueueManagerTests` and `StreamManagerTests` are unchanged.
