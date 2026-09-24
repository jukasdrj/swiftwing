# Pass 8 — Library browse

Date: 2026-09-24. Read only. Can run after pass 7. Boxes are absent and do not affect this screen.

Files: `swiftwing/Features/Library/LibraryView.swift`, `swiftwing/Features/Library/LibraryViewModel.swift`, `swiftwing/Features/Library/LibraryGridView.swift`, `swiftwing/Features/Library/LibraryExporter.swift`, `swiftwing/Services/ImageCacheManager.swift`, `swiftwing/Features/Library/LibraryPrefetchCoordinator.swift`, `swiftwingUITests/LibraryUITests.swift`, `swiftwingTests/LibraryExporterTests.swift`.

Do not change yet.

## 1. What starts it, and who owns it

The Library tab is the default tab. `LibraryView` owns an `@Query` of `Book` and a `LibraryViewModel`. The grid shows `viewModel.filteredBooks(from: books)`. Search text, the review-needed toggle, and the sort option are `@AppStorage` (`library_sort_option`, `show_review_needed`). Changing any of them calls `updateFilteredBooks`, which runs a `FetchDescriptor` and stores `cachedFilteredBooks`.

`ImageCacheManager.shared` is an actor with a `URLSession` whose cache is 50 MB memory and 200 MB disk, policy `.returnCacheDataElseLoad`. `LibraryPrefetchCoordinator` asks it to prefetch the next covers as the grid scrolls.

Export builds a Hardcover CSV through `LibraryExporter` and presents a share sheet.

## 2. Inputs and outputs

Sort options: newest, oldest, title A–Z, author A–Z. The descriptor and `sortedBooks(from:)` implement the same four orders.

Search matches `title` or `author` with `localizedStandardContains`. ISBN is not searched.

The review-needed filter is `(spineConfidence ?? 1.0) < 0.8`. A nil confidence is treated as 1.0 and does not match. This is not `enrichmentStatus`. A `not_found` book saved with confidence 0.9 stays out of the filter. A successful book at 0.7 is included. `Book.needsEnrichmentReview` (`review_needed` or `not_found`) is a different predicate and the library screen does not use it.

`filteredBooks(from:)` returns `sortedBooks(from: books)` when the cache is empty, the search box is empty, the filter is off, and `@Query` has rows. Otherwise it returns the cache, including an empty cache after a fetch error. The first frame can therefore be the `@Query` order while later frames are the descriptor order.

`generateCSV` writes Hardcover’s header exactly, then one row per book. ISBN-13 and ISBN-10 are split by length. `UNKNOWN-` values go through `classifyISBN` and will not land in a clean ISBN column if they fail that classifier. Status comes from `readingStatus`. Most Hardcover columns are empty strings.

Delete and bulk delete call `modelContext.delete` and do not call `context.save` or `DataSyncActor`.

`performRefresh` sets `isRefreshing`, sleeps one second, and clears the flag. It does not refetch.

## 3. Failures

Handled:

- Fetch failure: log, cache becomes `[]`. With an active search or filter the grid goes empty.
- Export of an empty list: `showEmptyLibraryAlert`.
- Image prefetch failures stay inside `ImageCacheManager` and do not surface on the card. `AsyncImageWithLoading` shows its own placeholder.

Logged or dropped:

- A delete that autosave has not flushed yet is invisible to this view model.
- The review-needed count on the stats header uses the same confidence threshold, so it disagrees with the review queue’s enrichment statuses.

## 4. What is tested

`LibraryUITests` covers the empty state, a seeded library, search, the sort menu, the review filter, the detail sheet, selection, and export, under `UI_TESTING` and `SEED_LIBRARY`. `LibraryExporterTests` checks the Hardcover header and row shape. No test checks that the review filter excludes a high-confidence `not_found` row, or that pull-to-refresh reloads anything.

## 5. Structural risk

The library’s "review needed" control filters `spineConfidence < 0.8`. The review queue filters enrichment status and confidence at arrival. The same words describe two different sets of books.

## Do not change yet

Leave the filter predicate, the cache shortcut, and the direct `modelContext.delete` until a library change is explicitly requested.
