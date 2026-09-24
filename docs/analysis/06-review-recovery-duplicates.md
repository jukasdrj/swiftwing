# Pass 6 — Review, edit, manual recovery, duplicates

Date: 2026-09-24. Read only. Depends on pass 4. Boxes are absent (pass 5).

Files: `swiftwing/Features/ReviewQueue/ReviewQueueManager.swift`, `swiftwing/Features/ReviewQueue/ReviewQueueView.swift`, `swiftwing/Features/ReviewQueue/ReviewCardView.swift`, `swiftwing/Features/ReviewQueue/ReviewEditForm.swift`, `swiftwing/Features/ReviewQueue/ManualLookupSheet.swift`, `swiftwing/Features/ReviewQueue/DuplicateBookAlert.swift`, `swiftwing/Models/DuplicateDetection.swift`, `swiftwing/Models/PendingBookResult.swift`, `swiftwingTests/ReviewQueueManagerTests.swift`, `swiftwingTests/Unit/Services/BookSearchTests.swift`, `swiftwingTests/DuplicateDetectionTests.swift`.

Do not change yet.

## 1. What starts it, and who owns it

`ReviewQueueManager` (`@MainActor`) owns the in-memory list `pendingReviewBooks`. `handleBookResult` is the entry from the scan callbacks. The Review tab’s `ReviewQueueView` reads that list off the shared `CameraViewModel`. The list is not SwiftData. Killing the app drops it.

`handleBookResult` rejects an empty title or an empty author, suppresses a recent duplicate, and either auto-approves or appends a `PendingBookResult`. Auto-approve runs only when `AutoApproveSettings.isEnabled` and `confidence` is at least the threshold. Otherwise the card waits.

## 2. Inputs and outputs

| Action | Input | Output |
|---|---|---|
| Queue insert | `BookMetadata`, raw JSON, thumbnail, photo URL | `PendingBookResult` with `metadata` immutable |
| Edit | title and author strings | `editedTitle`, `editedAuthor` |
| Manual lookup | `BookSearchResult` from `GET /v3/books/search` | `recoveredMetadata`, edits cleared, status `.success` |
| Approve | `resolvedTitle`, `resolvedAuthor`, `resolvedMetadata` | `DataSyncActor.save`, then the card is removed |
| Reject | the pending id | card removed, temp photo deleted |
| Duplicate alert | `DuplicateDetection.findDuplicate(isbn:)` | `DuplicateBookAlert` with cancel, add anyway, view existing |

`resolvedMetadata` is `recoveredMetadata ?? metadata`. `resolvedTitle` and `resolvedAuthor` prefer the edits, then that metadata. `resolvedISBN` is the recovered or original ISBN, then `preScannedISBN`, then `UNKNOWN-<uuid>`.

`needsRecovery` is true only for `.notFound` and `.circuitOpen` on `resolvedMetadata`. After a successful lookup the status is `.success` and the button goes away. `.error` and `.reviewNeeded` never open the sheet. Pass 4: a `review_needed` or `not_found` row with a null author never reaches a card at all.

In-queue dedup matches a non-empty ISBN, or title and author, and only if the existing card is less than 60 seconds old. The coordinator already deduped within one job. This second check covers a second photo of the same book.

`ManualLookupSheet` calls `talariaService.searchBook`. A 404 stays `NetworkError.apiError`. `applyRecoveredMetadata` keeps the original `metadata` for provenance and copies the lookup onto `recoveredMetadata`, including the original `boundingBox` (absent on lite).

## 3. Failures

Handled:

- Empty title or author: error overlay, book dropped.
- Duplicate at approve time, when `findDuplicate(isbn:)` returns a row: alert, card stays.
- Lookup 404: the sheet surfaces the API error. The card stays `not_found` or `circuit_open`.
- `addBookToLibrary` refuses an empty resolved title or author and logs.

Logged or dropped:

- `addBookToLibrary` ignores the `Bool` from `DataSyncActor.save`. A `false` (duplicate skipped inside the actor) still logs "Book added" and the caller still removes the card.
- `approveBook`’s pre-check calls `findDuplicate(isbn:)` with empty title and author. An ISBN of `UNKNOWN-…` skips the ISBN query and then skips the title+author query because both strings are empty. The alert does not appear. `save` later does the title+author check and returns false. The card is gone and the library is unchanged.
- Bulk approve uses the same ISBN-only pre-check, silently.

## 4. What is tested

`ReviewQueueManagerTests` covers queue insert, recovery (`resolvedMetadata` becomes `.success`, original `metadata` stays `.notFound`), and approve behavior on fixtures. `BookSearchTests` covers the search decoder and the 404 mapping. `DuplicateDetectionTests` covers ISBN and title+author matching. No UI test drives the lookup sheet or the duplicate alert. The silent `UNKNOWN-` drop is not asserted.

## 5. Structural risk

Approving a book that has no real ISBN removes the card even when `save` refuses it as a title+author duplicate. The duplicate alert only runs for an ISBN that is not an `UNKNOWN-` placeholder.

## Do not change yet

Leave validation, the recovery button’s two statuses, and the approve path alone until pass 7’s save notes are read with this one.

## Resolved

2026-09-24. T17, T18.

A `review_needed` result with a null title or author stays in `pendingReviewBooks`. Other statuses with an empty title or author are still dropped. `addBookToLibrary` still refuses an empty resolved title or author. `EnrichmentStatus.offersManualLookup` is true for `.reviewNeeded`, `.notFound`, and `.circuitOpen`. `.error` does not offer the button.

`approveBook` calls `findDuplicate` with the resolved title and author, so an `UNKNOWN-` ISBN uses the same pair as `DataSyncActor.save`. The duplicate alert shows, the card stays, and nothing is inserted. If `save` returns false, the card stays. Bulk approve removes only the cards that were written.

Tests: `handleBookResult_reviewNeededNilAuthor_staysInQueue`, `reviewNeededOffersManualLookup`, `approveBook_unknownISBNTitleAuthorDuplicate_leavesCardAndSkipsInsert` in `ReviewQueueManagerTests`, and `saveSkipsUnknownISBNTitleAuthorDuplicate` in `DataSyncActorTests`. `ReviewQueueManagerTests` and `DataSyncActorTests` passed, 0 warnings.
