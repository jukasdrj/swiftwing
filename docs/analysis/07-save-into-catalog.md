# Pass 7 — Save into the catalog

Date: 2026-09-24. Read only. Depends on pass 6. Boxes are absent (pass 5).

Files: `swiftwing/Services/DataSyncActor.swift`, `swiftwing/Models/Book.swift`, `swiftwing/Models/PendingBookResult.swift` (`resolvedMetadata`, `resolvedISBN`), `swiftwing/Models/DuplicateDetection.swift`, `swiftwing/Features/ReviewQueue/ReviewQueueManager.swift` (`addBookToLibrary`), `swiftwingTests/Unit/Services/DataSyncActorTests.swift`, `swiftwingTests/BookModelTests.swift`.

Do not change yet.

## 1. What starts it, and who owns it

`DataSyncActor` (`@MainActor` class, not an actor) is the writer the review path uses. `addBookToLibrary` builds a synthetic `PendingBookResult` and calls `DataSyncActor.shared.save`. The synthetic metadata is already flattened: title, author, and the other fields come from the `BookMetadata` argument the caller passed. On approve, that argument is `pendingBook.resolvedMetadata`, so a manual lookup’s title, author, ISBN, cover, and publisher are copied in before `save`. `save` itself does not read `recoveredMetadata` or `editedTitle`. A caller that handed it the original pending item would persist the AI metadata and ignore the recovery. Production approve does not do that. It flattens first.

Library delete does not use `DataSyncActor`. `LibraryViewModel.deleteBook` calls `modelContext.delete` directly. SwiftData autosave is on, so the delete still reaches the store.

## 2. Inputs and outputs

`save(book:in:)` returns `Bool`. False means a duplicate was skipped. True means `context.insert` and `context.save` ran.

`makeBook` writes:

| `Book` field | Source on the synthetic item |
|---|---|
| `title`, `author`, `isbn` | `resolvedTitle`, `resolvedAuthor`, `resolvedISBN` |
| `coverUrl`, `format`, `publisher`, `publishedDate`, `pageCount`, `spineConfidence`, `enrichmentStatus` | `metadata` (the flattened copy) |
| `addedDate` | `Date()` at save time |
| `rawJSON` | the pending item’s raw JSON |

`isbn` is `@Attribute(.unique)`. A missing ISBN becomes `UNKNOWN-<pending uuid>`, which is unique per card, so the unique constraint does not collapse two unknown books. `DuplicateDetection.findDuplicate(isbn:title:author:)` does that instead: an `UNKNOWN-` prefix skips the ISBN query and compares normalized title and author across every `Book`.

`Book.author` is one `String`. The API’s `authors[]` array is joined before this point, in `BookMetadata`’s decoder and in `BookSearchResult.joinedAuthors`. The schema comment in older docs that says `authors: [String]` does not match `Book.swift`.

## 3. Failures

Handled:

- Duplicate: log and return false. No insert.
- `context.save` throws. `addBookToLibrary` logs "Failed to save book" and does not remove the card only if the throw happens before the caller continues. Approve removes the card after `addBookToLibrary` returns, and that method catches the error. A thrown save leaves the card in the queue. A false return does not.

Logged or dropped:

- The `Bool` is discarded. See pass 6.
- `enrichmentStatus` is stored as the raw string. Unknown future values were already coerced to `.pending` at decode time, so the store never sees the original unknown token.

## 4. What is tested

`DataSyncActorTests` saves a success fixture and expects the enrichment raw value on `Book`. `BookModelTests` covers the model fields and `needsReview` (`spineConfidence < 0.8`). Neither test asserts that `save`’s false is honored by `addBookToLibrary`, or that a recovered cover survives a save of an unflattened `PendingBookResult`.

## 5. Structural risk

`save` can refuse the write and report that only through a `Bool` the review path ignores. The unique ISBN constraint does not save an `UNKNOWN-` pair that shares a title and author. Only the title+author scan inside `save` does, and the UI treats that refusal as success.

## Do not change yet

Leave `makeBook` and the `UNKNOWN-` ISBN until a change is planned for the approve path in pass 6.

## Resolved

2026-09-24. T18.

`DataSyncActor.save` already returned false for a title-and-author match when the ISBN is `UNKNOWN-`, and it did not insert a second row. `addBookToLibrary` now returns that bool. `approveBook` does not remove the card when the bool is false. The pre-check uses the same title and author, so the duplicate alert appears instead of a silent drop.

Test: `saveSkipsUnknownISBNTitleAuthorDuplicate` in `DataSyncActorTests`. The approve-path lock is `approveBook_unknownISBNTitleAuthorDuplicate_leavesCardAndSkipsInsert` in `ReviewQueueManagerTests`. Both suites passed, 0 warnings.
