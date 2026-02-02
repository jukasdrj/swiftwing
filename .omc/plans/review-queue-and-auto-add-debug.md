# Work Plan: Review Queue UI + Auto-Add Library Debug

**Plan ID:** review-queue-and-auto-add-debug
**Created:** 2026-02-01
**Revised:** 2026-02-01 (Iteration 2 -- Critic review applied)
**Status:** PENDING
**Complexity:** HIGH (2 parallel workstreams, new UI surface, bug investigation)

---

## Context

### Original Request
User scanned books via camera. Talaria SSE completed successfully with 7 `result` events logged in console. However, books did NOT appear in the library. Additionally, the user wants ALL scans to go through a manual review step before being added to the library, replacing the current auto-add behavior.

### Interview Summary
- **Default behavior change:** ALL scans require manual review before library insertion (no auto-add)
- **Priority:** Parallel workstreams -- Phase 1 debug first, Phase 2 review queue implementation
- **UI placement:** Dedicated "Review" tab in main TabView (3 tabs: Library, Review, Camera)
- **Debug scope:** Database layer accessible for verification (save vs. display issue)
- **Workflow optimization:** Deferred to a later iteration

### Research Findings (Codebase Analysis)

**SSE Flow (Current):**
1. `CameraView.swift:208` -- modelContext injected via `.task { viewModel.modelContext = modelContext }`
2. `CameraViewModel.swift:180-183` -- capture fires `processCapture(itemId:)` in a Task
3. `CameraViewModel.swift:187-201` -- `processCapture` reads `self.modelContext` (optional), calls `processCaptureWithImageData`
4. `CameraViewModel.swift:301-326` -- SSE `.result` event triggers `handleBookResult(metadata:rawJSON:modelContext:)`
5. `CameraViewModel.swift:645-666` -- `handleBookResult` checks duplicates, then calls `addBookToLibrary`
6. `CameraViewModel.swift:668-703` -- `addBookToLibrary` does `modelContext.insert(newBook)` + `try modelContext.save()`

**Bug Hypothesis (HIGH confidence):**
The `modelContext` is injected at line 66 as `var modelContext: ModelContext?` and set at line 208 via `.task { viewModel.modelContext = modelContext }`. The `.task` modifier runs asynchronously. If `captureImage()` is called before `.task` completes (unlikely but possible), OR if the modelContext from CameraView is a different instance than expected, the save might succeed locally but the `@Query` in LibraryView/RootView may be observing a different context.

**More likely root cause candidates:**
1. **ISBN uniqueness constraint violation** -- `@Attribute(.unique) var isbn: String` on Book model. If `metadata.isbn` is `nil`, it becomes `"Unknown"` (line 680). Multiple books with isbn="Unknown" would violate the unique constraint. The `save()` catch at line 700-702 only prints the error -- it does NOT propagate or show UI feedback.
2. **Silent SwiftData save failure** -- `modelContext.save()` may throw but the error is only printed to console (`print("Failed to save book: \(error)")`). If 7 results all have isbn="Unknown" or duplicate ISBNs, only the first would save; the rest would silently fail.
3. **ModelContext isolation** -- CameraViewModel creates a new `TalariaService()` per capture (line 210). The modelContext passed through the chain is the one from CameraView's `@Environment(\.modelContext)`. This should be the main context, so `@Query` in LibraryView should observe it. But if there is a timing issue with `.task` injection, modelContext could be nil, causing the fatalError at line 195-196.

**Key files:**
- `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift` (814 lines) -- All scan logic
- `/Users/juju/dev_repos/swiftwing/swiftwing/CameraView.swift` (293 lines) -- View + context injection
- `/Users/juju/dev_repos/swiftwing/swiftwing/RootView.swift` (95 lines) -- TabView with 2 tabs
- `/Users/juju/dev_repos/swiftwing/swiftwing/Models/Book.swift` (83 lines) -- @Model with @Attribute(.unique) isbn
- `/Users/juju/dev_repos/swiftwing/swiftwing/ProcessingItem.swift` (85 lines) -- Queue item model
- `/Users/juju/dev_repos/swiftwing/swiftwing/ProcessingQueueView.swift` (159 lines) -- Camera queue UI
- `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift` (95 lines) -- BookMetadata, SSEEvent
- `/Users/juju/dev_repos/swiftwing/swiftwing/SwiftwingApp.swift` (51 lines) -- ModelContainer setup
- `/Users/juju/dev_repos/swiftwing/swiftwing/Theme.swift` (~180 lines) -- Swiss Glass design system

---

## Work Objectives

### Core Objective
1. Diagnose and fix why scanned books are not appearing in the library
2. Implement a review queue system where ALL scans land in a "pending review" state
3. Add a dedicated "Review" tab in the main TabView

### Deliverables
1. Root cause identification and fix for the auto-add library failure
2. `PendingBookResult` model (in-memory) for holding scan results pre-review
3. `ReviewQueueView` -- new tab showing pending books awaiting user approval
4. Modified `CameraViewModel` -- scans go to review queue instead of auto-adding to library
5. Updated `RootView.MainTabView` -- 3 tabs (Library, Review, Camera)

### Definition of Done
- [ ] Bug root cause documented with evidence
- [ ] Books from SSE results appear in review queue
- [ ] User can approve (add to library) or reject (discard) each pending book
- [ ] Review tab shows badge count of pending items
- [ ] Library tab only shows explicitly approved books
- [ ] Zero build warnings, zero build errors
- [ ] Swiss Glass design system applied consistently

---

## Guardrails

### MUST Have
- All scans go to review queue by default (no auto-add to library)
- Pending books survive within the current session (in-memory is acceptable for v1)
- Review tab is a top-level tab in MainTabView
- Approve action inserts book into SwiftData (library)
- Reject action removes book from review queue
- Badge on Review tab showing count of pending items
- Existing library functionality unchanged
- Build succeeds with 0 errors, 0 warnings

### MUST NOT Have
- Auto-add to library (explicitly removed)
- Complex workflow features (batch approve, swipe gestures, filters) -- deferred
- SwiftData persistence for pending reviews (in-memory is fine for v1)
- Changes to Talaria SSE protocol or TalariaService
- Changes to Book model schema (no migration needed)

---

## Task Flow and Dependencies

```
Phase 1: Debug Auto-Add Failure
  |-- TODO 1.1: Add diagnostic logging to addBookToLibrary() [INDEPENDENT]
  |-- TODO 1.2: Investigate ISBN uniqueness constraint violations [INDEPENDENT]
  |-- TODO 1.3: Verify ModelContext identity between CameraView and LibraryView [INDEPENDENT]
  +-- TODO 1.4: Fix root cause (ISBN fallback in addBookToLibrary) [DEPENDS ON 1.1-1.3]

Phase 2: Review Queue Implementation (can start in parallel with Phase 1)
  |-- TODO 2.1: Create PendingBookResult model [INDEPENDENT]
  |-- TODO 2.2: Create ReviewQueueView (with @Environment modelContext) [DEPENDS ON 2.1]
  |-- TODO 2.3: Modify CameraViewModel to route to review queue [DEPENDS ON 2.1]
  |-- TODO 2.4: Add Review tab to MainTabView + lift viewModel + update CameraView init + fix previews [DEPENDS ON 2.2]
  |-- TODO 2.5: Wire approve/reject actions with duplicate detection [DEPENDS ON 2.2, 2.3]
  |-- TODO 2.6: Move DuplicateBookAlert from CameraView to ReviewQueueView [DEPENDS ON 2.4, 2.5]
  +-- TODO 2.7: Add badge count to Review tab [DEPENDS ON 2.4, 2.5]

Phase 3: Integration & Verification
  |-- TODO 3.1: Build verification (0/0) [DEPENDS ON all above]
  |-- TODO 3.2: Camera stop/restart on tab switch verification [DEPENDS ON 3.1]
  +-- TODO 3.3: End-to-end flow validation [DEPENDS ON 3.1, 3.2]
```

---

## Phase 1: Debug Auto-Add Library Failure

### TODO 1.1: Add Diagnostic Logging to Save Path

**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`
**Lines:** 668-703 (`addBookToLibrary`)

**Problem:** The current error handling at line 700-702 only prints to console. If the `@Attribute(.unique)` constraint on `isbn` causes a save failure, we get a silent failure with no UI feedback.

**Diagnostic Steps:**
1. Add pre-save logging: print the isbn value, Book count in context before insert
2. Add post-save verification: fetch the book back immediately after save to confirm it persisted
3. Add detailed error logging: capture the full error type, not just `error` description
4. Check if `modelContext` is the main context (same container as LibraryView)

**Code to inspect/modify:**
```swift
// CameraViewModel.swift:668-703
func addBookToLibrary(metadata: BookMetadata, rawJSON: String?, modelContext: ModelContext) {
    // ADD: Pre-save diagnostic
    print("DEBUG: Attempting to save book - ISBN: '\(metadata.isbn ?? "nil")', Title: '\(metadata.title)'")
    print("DEBUG: ModelContext container: \(ObjectIdentifier(modelContext.container))")

    // ... existing book creation ...

    modelContext.insert(newBook)

    do {
        try modelContext.save()
        print("Book added to library: \(metadata.title)")

        // ADD: Post-save verification
        let verifyDescriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.isbn == newBook.isbn })
        let found = try? modelContext.fetch(verifyDescriptor)
        print("DEBUG: Post-save verification - found \(found?.count ?? 0) books with ISBN '\(newBook.isbn)'")

    } catch {
        // CHANGE: More detailed error logging
        print("Failed to save book: \(error)")
        print("Error type: \(type(of: error))")
        print("ISBN was: '\(metadata.isbn ?? "nil")' -> '\(newBook.isbn)'")
    }
}
```

**Acceptance Criteria:**
- Console output clearly shows whether save succeeded or failed for each of 7 results
- If ISBN constraint is the issue, error message will show "UNIQUE constraint failed"

---

### TODO 1.2: Investigate ISBN Uniqueness Constraint

**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/Models/Book.swift`
**Lines:** 14 (`@Attribute(.unique) var isbn: String`)

**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`
**Line:** 680 (`isbn: metadata.isbn ?? "Unknown"`)

**Investigation:**
The `isbn` field has a `@Attribute(.unique)` constraint. When `metadata.isbn` is `nil`, the fallback is `"Unknown"` (line 680). If multiple books in a single scan have `nil` ISBNs, all would get isbn="Unknown", and only the first insert would succeed. Subsequent inserts would violate the unique constraint.

**Root Cause Probability:** HIGH (70%)

This is the most likely explanation for why 7 `result` events were received but 0 books appeared:
- If ALL 7 books had the same ISBN (e.g., from scanning the same spine multiple times), or
- If ALL 7 books had `nil` ISBNs (common for spine-only recognition where barcode is not visible)

**Fix Options:**
1. **Generate unique fallback ISBN:** Use `"UNKNOWN-\(UUID().uuidString)"` instead of `"Unknown"` to avoid collisions
2. **Make isbn non-unique:** Remove `@Attribute(.unique)` -- requires SwiftData migration consideration
3. **Use composite uniqueness:** Combine isbn + title + author for uniqueness check

**Recommended Fix:** Option 1 -- generate unique fallback ISBN. Simplest, no schema migration, preserves uniqueness for real ISBNs.

**Acceptance Criteria:**
- Books with nil ISBNs get unique fallback identifiers
- Multiple books from single scan all save successfully
- Duplicate detection still works for books with real ISBNs

---

### TODO 1.3: Verify ModelContext Identity

**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraView.swift`
**Line:** 208 (`viewModel.modelContext = modelContext`)

**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/SwiftwingApp.swift`
**Line:** 38 (`.modelContainer(sharedModelContainer)`)

**Investigation:**
- CameraView gets `modelContext` from `@Environment(\.modelContext)` (line 8)
- This is injected via `.task { viewModel.modelContext = modelContext }` (line 207-209)
- LibraryView gets `modelContext` from `@Environment(\.modelContext)` (line 39 of LibraryView.swift)
- Both should be the SAME context (main context from `sharedModelContainer`)

**Diagnostic:** Add an assertion or log comparing container identities:
```swift
// In CameraView .task:
print("DEBUG: CameraView modelContext container: \(ObjectIdentifier(modelContext.container))")
```

**Acceptance Criteria:**
- Confirmed that CameraView and LibraryView share the same ModelContainer
- If different, root cause identified and documented

---

### TODO 1.4: Apply Fix for Root Cause

**Depends on:** TODO 1.1, 1.2, 1.3

**Most Likely Fix (ISBN Uniqueness):**

**CRITICAL: The ISBN fallback fix MUST be applied in `addBookToLibrary` (line 680) INDEPENDENTLY, regardless of what happens to `handleBookResult` in Phase 2.** This is because `addBookToLibrary` is the single method that creates Book objects, and it is called from multiple paths: `handleBookResult`, `approveBook`, `addDuplicateAnyway`, and `retryFailedItem`.

**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`
**Line:** 680 (inside `addBookToLibrary`)

**Change in `addBookToLibrary` (line 680):**
```swift
// BEFORE (line 680):
isbn: metadata.isbn ?? "Unknown",

// AFTER:
isbn: metadata.isbn ?? "UNKNOWN-\(UUID().uuidString)",
```

This fix is in the ONLY method that creates Book objects (`addBookToLibrary`), so it covers all callers. Even when Phase 2 replaces `handleBookResult`, the fix remains effective because `approveBook` calls `addBookToLibrary`.

**Also update `handleBookResult` (line 646) for duplicate detection consistency:**
```swift
// BEFORE (line 646):
let isbn = metadata.isbn ?? "Unknown"

// AFTER:
let isbn = metadata.isbn ?? "UNKNOWN-\(UUID().uuidString)"
```

**Note:** In Phase 2, `handleBookResult` is replaced entirely (routes to review queue instead of library). The duplicate detection logic that uses isbn moves to `approveBook`. The fix in `addBookToLibrary` at line 680 is the durable fix that survives Phase 2.

**Acceptance Criteria:**
- 7 scanned books all successfully save to library (pre-Phase 2 verification)
- Console shows "Book added to library" for each result
- LibraryView displays all saved books
- No SwiftData constraint violation errors

---

## Phase 2: Review Queue Implementation

### TODO 2.1: Create PendingBookResult Model

**New File:** `/Users/juju/dev_repos/swiftwing/swiftwing/PendingBookResult.swift`

**Design:** In-memory model (NOT SwiftData @Model). This is a transient holding area for scan results before user approval. Survives within the current app session.

```swift
import Foundation

/// Represents a book scan result awaiting user review
/// In-memory only -- does not persist across app launches
/// Used by ReviewQueueView for approve/reject workflow
struct PendingBookResult: Identifiable, Equatable {
    let id: UUID
    let metadata: BookMetadata
    let rawJSON: String?
    let thumbnailData: Data?   // From ProcessingItem for visual reference
    let scannedDate: Date
    let confidence: Double?

    init(metadata: BookMetadata, rawJSON: String?, thumbnailData: Data? = nil) {
        self.id = UUID()
        self.metadata = metadata
        self.rawJSON = rawJSON
        self.thumbnailData = thumbnailData
        self.scannedDate = Date()
        self.confidence = metadata.confidence
    }

    static func == (lhs: PendingBookResult, rhs: PendingBookResult) -> Bool {
        lhs.id == rhs.id
    }
}
```

**Note:** `BookMetadata` (from NetworkTypes.swift:51-61) is already `Codable, Sendable`, so it can be stored directly.

**Acceptance Criteria:**
- Model compiles without warnings
- Contains all metadata needed for display and library insertion
- Equatable for SwiftUI list diffing

---

### TODO 2.2: Create ReviewQueueView

**New File:** `/Users/juju/dev_repos/swiftwing/swiftwing/ReviewQueueView.swift`

**Design:** Swiss Glass styled view showing pending book results as cards. Each card has book metadata + approve/reject buttons.

**CRITICAL: ModelContext plumbing resolved.** ReviewQueueView owns its own `@Environment(\.modelContext)` and receives the viewModel directly. It calls `viewModel.approveBook(book, modelContext: modelContext)` with its own environment context.

**View signature:**
```swift
struct ReviewQueueView: View {
    @Environment(\.modelContext) private var modelContext
    var viewModel: CameraViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.pendingReviewBooks.isEmpty {
                    // Empty state
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.pendingReviewBooks) { book in
                            ReviewCardView(
                                book: book,
                                onApprove: {
                                    viewModel.approveBook(book, modelContext: modelContext)
                                },
                                onReject: {
                                    viewModel.rejectBook(book)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .background(Color.swissBackground.ignoresSafeArea())
            .navigationTitle("Review Queue")
            .toolbar {
                if !viewModel.pendingReviewBooks.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Approve All") {
                            viewModel.approveAllBooks(modelContext: modelContext)
                        }
                        .foregroundColor(.internationalOrange)
                    }
                }
            }
        }
    }
}
```

**Note:** `viewModel` is a plain `var` (not `@Bindable`), because CameraViewModel is `@Observable` and ReviewQueueView only reads properties and calls methods -- it never uses `$viewModel.property` two-way binding syntax.

**Key Components:**
1. **ReviewQueueView** -- main view with `@Environment(\.modelContext)` and viewModel reference
2. **ReviewCardView** -- individual book card with metadata display and action closures
3. **Empty state** -- message when no books pending review

**Design System Compliance:**
- Background: `Color.swissBackground`
- Cards: `.swissGlassCard()` modifier
- Approve button: `.internationalOrange` background, white text
- Reject button: transparent with white border
- Typography: SF Pro for labels, JetBrains Mono for ISBN/data
- Animations: `.swissSpring` for card removal

**Acceptance Criteria:**
- Shows list of pending books with all metadata
- Approve button present and styled
- Reject button present and styled
- Empty state shown when queue is empty
- Swiss Glass design system applied
- Accessibility labels on all interactive elements

---

### TODO 2.3: Modify CameraViewModel to Route to Review Queue

**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`

**Changes Required:**

1. **Add pending review state (after line 31):**
```swift
// MARK: - Review Queue State
var pendingReviewBooks: [PendingBookResult] = []
```

2. **Replace `handleBookResult` (lines 645-666) to route to review queue instead of library:**

The existing `handleBookResult` signature is:
```swift
func handleBookResult(metadata: BookMetadata, rawJSON: String?, modelContext: ModelContext)
```

Replace with:
```swift
func handleBookResult(metadata: BookMetadata, rawJSON: String?, modelContext: ModelContext) {
    // Route ALL results to review queue (no auto-add)
    let pendingBook = PendingBookResult(
        metadata: metadata,
        rawJSON: rawJSON,
        thumbnailData: nil  // Could capture from ProcessingItem in future iteration
    )

    withAnimation(.swissSpring) {
        pendingReviewBooks.append(pendingBook)
    }

    print("Book added to review queue: \(metadata.title) (pending: \(pendingReviewBooks.count))")

    // Haptic feedback for new review item
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(.success)
}
```

**Note:** The `modelContext` parameter is retained in the signature even though the new implementation does not use it. This avoids changing all call sites in `processCaptureWithImageData` (line 326). The parameter will be removed in a future cleanup.

3. **Add approve/reject methods:**
```swift
// MARK: - Review Queue Actions
func approveBook(_ pendingBook: PendingBookResult, modelContext: ModelContext) {
    let isbn = pendingBook.metadata.isbn ?? "UNKNOWN-\(UUID().uuidString)"

    // Duplicate detection at approve time
    do {
        if let duplicate = try DuplicateDetection.findDuplicate(isbn: isbn, in: modelContext) {
            // Stash pending book reference for "Add Anyway" flow
            pendingBookBeingApproved = pendingBook
            pendingBookMetadata = pendingBook.metadata
            pendingRawJSON = pendingBook.rawJSON
            duplicateBook = duplicate
            withAnimation(.swissSpring) {
                showDuplicateAlert = true
            }
            return
        }
    } catch {
        // Proceed with add on detection failure
    }

    addBookToLibrary(metadata: pendingBook.metadata, rawJSON: pendingBook.rawJSON, modelContext: modelContext)

    withAnimation(.swissSpring) {
        pendingReviewBooks.removeAll { $0.id == pendingBook.id }
    }

    print("Book approved and added to library: \(pendingBook.metadata.title)")
}

func rejectBook(_ pendingBook: PendingBookResult) {
    withAnimation(.swissSpring) {
        pendingReviewBooks.removeAll { $0.id == pendingBook.id }
    }

    print("Book rejected from review queue: \(pendingBook.metadata.title)")
}

func approveAllBooks(modelContext: ModelContext) {
    let count = pendingReviewBooks.count
    for book in pendingReviewBooks {
        addBookToLibrary(metadata: book.metadata, rawJSON: book.rawJSON, modelContext: modelContext)
    }

    withAnimation(.swissSpring) {
        pendingReviewBooks.removeAll()
    }

    print("All \(count) books approved and added to library")
}
```

**Note on `approveAllBooks`:** The count is captured BEFORE `.removeAll()` so the log message is correct. (Critic issue #5 fixed.)

4. **Add new state property for tracking which pending book is being approved (for duplicate alert flow):**
```swift
// After line 31 (alongside other duplicate detection state):
var pendingBookBeingApproved: PendingBookResult?
```

5. **Update `addDuplicateAnyway` (line 714) to also remove from review queue:**
```swift
func addDuplicateAnyway(modelContext: ModelContext) {
    withAnimation(.swissSpring) {
        showDuplicateAlert = false
        if let metadata = pendingBookMetadata {
            addBookToLibrary(metadata: metadata, rawJSON: pendingRawJSON, modelContext: modelContext)
        }
        // Remove from review queue if it was an approve-time duplicate
        if let pending = pendingBookBeingApproved {
            pendingReviewBooks.removeAll { $0.id == pending.id }
        }
        duplicateBook = nil
        pendingBookMetadata = nil
        pendingRawJSON = nil
        pendingBookBeingApproved = nil
    }
}
```

6. **Update `dismissDuplicateAlert` (line 705) to also clear the pending book reference:**
```swift
func dismissDuplicateAlert() {
    withAnimation(.swissSpring) {
        showDuplicateAlert = false
        duplicateBook = nil
        pendingBookMetadata = nil
        pendingRawJSON = nil
        pendingBookBeingApproved = nil
    }
}
```

**Acceptance Criteria:**
- SSE `.result` events add to `pendingReviewBooks` instead of library
- `addBookToLibrary` is only called from `approveBook`, `approveAllBooks`, and `addDuplicateAnyway`
- Duplicate detection occurs at approve time (not scan time)
- `approveAllBooks` logs correct count before clearing
- Console logs confirm review queue routing

---

### TODO 2.4: Add Review Tab to MainTabView + Lift ViewModel + Fix CameraView + Fix Previews

**Files Modified:**
- `/Users/juju/dev_repos/swiftwing/swiftwing/RootView.swift` (lines 60-95)
- `/Users/juju/dev_repos/swiftwing/swiftwing/CameraView.swift` (lines 7-9, 290-293)

#### ModelContext Plumbing Architecture (CRITICAL -- Critic Issue #1)

**Chosen approach:** Each view that needs ModelContext gets it from `@Environment(\.modelContext)`. The viewModel is passed as a plain reference. No closures needed for ModelContext plumbing.

**Exact wiring for all three views:**

| View | Gets ModelContext From | Gets ViewModel From | How It Uses Them |
|------|----------------------|---------------------|------------------|
| **MainTabView** | Not needed (no SwiftData operations) | `@State private var viewModel = CameraViewModel()` (owns lifecycle) | Passes `viewModel` to ReviewQueueView and CameraView; reads `viewModel.pendingReviewBooks.count` for badge |
| **ReviewQueueView** | `@Environment(\.modelContext)` (from SwiftwingApp's `.modelContainer`) | `var viewModel: CameraViewModel` (plain property, NOT @Bindable) | Calls `viewModel.approveBook(book, modelContext: modelContext)` |
| **CameraView** | `@Environment(\.modelContext)` (from SwiftwingApp's `.modelContainer`) | `var viewModel: CameraViewModel` (plain property, NOT @Bindable) | Injects `viewModel.modelContext = modelContext` in `.task {}` |

**Why NOT @Bindable (Critic Issue #3):** CameraView does not use `$viewModel.property` two-way binding syntax anywhere in its body. It only reads `viewModel.someProperty` and calls `viewModel.someMethod()`. Since CameraViewModel is `@Observable`, SwiftUI automatically tracks property access for re-rendering. `@Bindable` is only needed when a view needs to create `Binding<T>` values from the observed object (e.g., `TextField("", text: $viewModel.name)`). Neither CameraView nor ReviewQueueView need this.

#### RootView.swift Changes (lines 60-89)

```swift
struct MainTabView: View {
    let bookCount: Int
    @State private var viewModel = CameraViewModel()

    var body: some View {
        TabView {
            // Library Tab
            Group {
                if bookCount > 0 {
                    LibraryView()
                        .badge(bookCount)
                } else {
                    LibraryView()
                }
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }

            // Review Tab (NEW)
            ReviewQueueView(viewModel: viewModel)
                .tabItem {
                    Label("Review", systemImage: "checklist")
                }
                .badge(viewModel.pendingReviewBooks.count > 0 ? viewModel.pendingReviewBooks.count : 0)

            // Camera Tab
            CameraView(viewModel: viewModel)
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }
        }
        .tint(.internationalOrange)
    }
}
```

#### CameraView.swift Changes (lines 7-9, 290-293)

**Line 9 change -- remove @State, accept viewModel as parameter:**
```swift
// BEFORE (line 9):
@State private var viewModel = CameraViewModel()

// AFTER:
var viewModel: CameraViewModel
```

**CRITICAL: Preview fix (Critic Issue #2).** The `#Preview` at lines 290-293 currently calls `CameraView()` with no arguments. After the init change, this will fail to compile. Update to:

```swift
// BEFORE (lines 290-293):
#Preview {
    CameraView()
        .preferredColorScheme(.dark)
}

// AFTER:
#Preview {
    CameraView(viewModel: CameraViewModel())
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
```

**Note:** `.modelContainer(for: Book.self, inMemory: true)` is added because CameraView uses `@Environment(\.modelContext)`, and without a container in the preview environment, it would crash. The RootView preview already has this pattern (line 93).

#### RootView.swift Preview (line 91-95)

The existing `RootView` preview does not need changes -- it calls `RootView()` which internally creates `MainTabView`, which now creates `CameraViewModel` via `@State`. No compilation issue.

**Acceptance Criteria:**
- 3 tabs visible: Library, Review, Camera
- Review tab has "checklist" SF Symbol icon
- Tab bar uses `.internationalOrange` tint
- CameraViewModel shared between Camera and Review tabs
- No duplicate ViewModel instances
- `CameraView` #Preview compiles and renders (0 errors, 0 warnings)
- No use of `@Bindable` on viewModel references

---

### TODO 2.5: Wire Approve/Reject Actions with Duplicate Detection

**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/ReviewQueueView.swift`

**ModelContext Access:** ReviewQueueView has `@Environment(\.modelContext)` (specified in TODO 2.2). It passes this directly to viewModel methods.

**Approve Flow:**
1. User taps "Approve" on ReviewCardView
2. ReviewQueueView closure calls `viewModel.approveBook(book, modelContext: modelContext)`
3. `approveBook` checks for duplicate ISBN via `DuplicateDetection.findDuplicate`
4. If no duplicate: calls `addBookToLibrary` (which has the ISBN fallback fix from Phase 1, line 680), removes from review queue
5. If duplicate found: sets `showDuplicateAlert = true` (handled by TODO 2.6)
6. Book appears in library, badge count decrements

**Reject Flow:**
1. User taps "Reject" on ReviewCardView
2. ReviewQueueView closure calls `viewModel.rejectBook(book)`
3. Book removed from `pendingReviewBooks` with `.swissSpring` animation
4. Badge count decrements

**ISBN Fix Survival (Critic Issue #4):** The ISBN fallback `metadata.isbn ?? "UNKNOWN-\(UUID().uuidString)"` is applied in TWO independent locations:
1. `addBookToLibrary` line 680 -- the durable fix (covers ALL callers including `approveBook`, `approveAllBooks`, `addDuplicateAnyway`)
2. `approveBook` -- for duplicate detection query (generates fallback for the `DuplicateDetection.findDuplicate` call)

These are independent. Even if `approveBook` generates a fallback ISBN for detection, `addBookToLibrary` independently generates its own fallback for the Book object. This means the ISBN used for detection and the ISBN stored on the Book will be DIFFERENT UUIDs. This is acceptable because:
- Real ISBNs (non-nil) are passed through unchanged -- duplicate detection works correctly
- Fallback ISBNs (nil -> UNKNOWN-UUID) will never match each other by design -- which is correct behavior since two unknown-ISBN books should NOT be considered duplicates

**Acceptance Criteria:**
- Approve adds book to library via SwiftData
- Reject removes book from review queue
- Duplicate detection occurs at approve time using ISBN from metadata
- DuplicateBookAlert shown when approving a book with duplicate real ISBN
- Books with nil ISBNs always pass duplicate check (correct -- no false positives)
- Smooth animations on card removal
- ISBN fallback fix in `addBookToLibrary` line 680 is never bypassed

---

### TODO 2.6: Move DuplicateBookAlert from CameraView to ReviewQueueView

**(Critic Issue #6)**

**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraView.swift` (lines 188-203)
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/ReviewQueueView.swift`

**Problem:** Currently the `DuplicateBookAlert` overlay is in CameraView (lines 188-203). After Phase 2, duplicate detection no longer happens during camera scanning -- it happens at approve time in ReviewQueueView. The alert overlay must move.

**Changes:**

1. **Remove DuplicateBookAlert from CameraView** (lines 188-203):
Delete the entire block:
```swift
// REMOVE from CameraView:
// US-405: Duplicate book detection alert with full metadata
if viewModel.showDuplicateAlert, let duplicate = viewModel.duplicateBook {
    DuplicateBookAlert(
        duplicateBook: duplicate,
        onCancel: { ... },
        onAddAnyway: { ... },
        onViewExisting: { ... }
    )
}
```

2. **Add DuplicateBookAlert to ReviewQueueView:**
```swift
// Add as ZStack overlay in ReviewQueueView body:
.overlay {
    if viewModel.showDuplicateAlert, let duplicate = viewModel.duplicateBook {
        DuplicateBookAlert(
            duplicateBook: duplicate,
            onCancel: {
                viewModel.dismissDuplicateAlert()
            },
            onAddAnyway: {
                viewModel.addDuplicateAnyway(modelContext: modelContext)
            },
            onViewExisting: {
                viewModel.dismissDuplicateAlert()
            }
        )
    }
}
```

**Acceptance Criteria:**
- DuplicateBookAlert no longer appears in CameraView
- DuplicateBookAlert appears in ReviewQueueView when approving a duplicate
- "Add Anyway" action correctly adds book to library AND removes from review queue
- "Cancel" dismisses alert, book remains in review queue for retry

---

### TODO 2.7: Add Badge Count to Review Tab

**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/RootView.swift`

**Implementation:** Already covered in TODO 2.4 via `.badge()` modifier. This task is about ensuring reactivity.

**Reactivity Chain:**
1. SSE result received -> `pendingReviewBooks.append(...)` in CameraViewModel
2. CameraViewModel is `@Observable` -> SwiftUI automatically observes `pendingReviewBooks`
3. MainTabView reads `viewModel.pendingReviewBooks.count` for badge
4. Badge updates automatically via observation

**Acceptance Criteria:**
- Badge shows count of pending review items
- Badge updates in real-time as items are added (from camera) or removed (approve/reject)
- Badge hidden when count is 0

---

## Phase 3: Integration & Verification

### TODO 3.1: Build Verification

**Command:**
```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift
```

**Success Criteria:**
```json
{
  "summary": {
    "errors": 0,
    "warnings": 0
  }
}
```

**Specific Build Risks to Check:**
- CameraView `#Preview` compiles (Critic Issue #2)
- `PendingBookResult.swift` added to Xcode project target
- `ReviewQueueView.swift` added to Xcode project target
- No unused `@Bindable` imports or annotations (Critic Issue #3)

**Acceptance Criteria:**
- 0 errors
- 0 warnings (non-negotiable per project rules)
- All new files added to Xcode project

---

### TODO 3.2: Camera Stop/Restart on Tab Switch Verification

**(Critic Issue #7)**

**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraView.swift`
**Lines:** 206-213 (`.task` and `.onDisappear`)

**Concern:** After lifting CameraViewModel to MainTabView, the camera session lifecycle must still work correctly when switching tabs. Currently:
- `.task { await viewModel.setupCamera() }` starts camera when CameraView appears
- `.onDisappear { viewModel.stopCamera() }` stops camera when leaving tab

**Verification Steps:**
1. Switch to Camera tab -> camera preview visible, session running
2. Switch to Library tab -> camera stops (verify console log)
3. Switch back to Camera tab -> camera restarts (verify console log)
4. Switch to Review tab -> camera stops
5. Switch back to Camera tab -> camera restarts

**Key Question:** Does SwiftUI's TabView call `.onDisappear` when switching tabs? Answer: Yes, TabView with default behavior does trigger `.onDisappear` and `.task` re-execution when switching tabs. The `.task` modifier runs its async block when the view appears and cancels it when the view disappears.

**Potential Issue:** Since CameraViewModel is now owned by MainTabView (not CameraView), the ViewModel persists across tab switches. This is correct -- we WANT it to persist (for review queue state). But `setupCamera()` and `stopCamera()` are idempotent, so calling them on each tab switch is safe.

**Acceptance Criteria:**
- Camera starts when Camera tab is selected
- Camera stops when switching away from Camera tab
- No crash or hang on rapid tab switching
- Camera state does not affect Review or Library tabs
- Console logs confirm start/stop pattern

---

### TODO 3.3: End-to-End Flow Validation

**Validation Steps:**
1. Launch app -> 3 tabs visible (Library, Review, Camera)
2. Camera tab -> capture image -> SSE stream completes
3. Review tab badge increments for each `.result` event
4. Switch to Review tab -> see pending books with metadata
5. Approve a book -> appears in Library tab, removed from review queue
6. Reject a book -> removed from review queue, not in library
7. Approve a duplicate ISBN -> DuplicateBookAlert appears in ReviewQueueView
8. "Add Anyway" on duplicate -> book added to library, removed from review queue
9. Verify library count matches approved book count
10. Verify DuplicateBookAlert does NOT appear in CameraView

**Acceptance Criteria:**
- Complete flow works without crashes
- No console errors (except intentional debug logging)
- Haptic feedback on approve action
- Smooth animations throughout
- DuplicateBookAlert only appears in ReviewQueueView context

---

## Risk Identification

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **ISBN uniqueness causing silent save failures** | HIGH | HIGH | Fix in `addBookToLibrary` line 680 (durable, covers all callers) |
| **CameraViewModel lifecycle when lifting to MainTabView** | MEDIUM | MEDIUM | Use `@State` in MainTabView to own lifecycle; test camera start/stop on tab switches (TODO 3.2) |
| **Camera session restart on tab switch** | MEDIUM | LOW | CameraView has `.onDisappear { viewModel.stopCamera() }` and `.task { await viewModel.setupCamera() }` -- explicit verification in TODO 3.2 |
| **CameraView #Preview build break** | HIGH | HIGH | Explicit preview update in TODO 2.4 with viewModel parameter and modelContainer |
| **SwiftData schema migration** | LOW | HIGH | No schema changes planned; PendingBookResult is in-memory only |
| **Review queue lost on app termination** | EXPECTED | LOW | Acceptable for v1; user knows pending items are session-scoped |
| **Large review queue memory pressure** | LOW | LOW | BookMetadata is lightweight; thumbnailData optional; 100+ items would be unusual |
| **DuplicateBookAlert in wrong view** | MEDIUM | MEDIUM | Explicitly moved from CameraView to ReviewQueueView in TODO 2.6 |

---

## Commit Strategy

### Commit 1: Debug diagnostics (Phase 1)
```
fix: Add diagnostic logging to book save path

Investigate why SSE result events don't persist to library.
Add pre/post save verification and ISBN uniqueness analysis.
```
**Files:** `CameraViewModel.swift`

### Commit 2: ISBN uniqueness fix (Phase 1)
```
fix: Generate unique fallback ISBN for books without ISBN

Books with nil ISBN from Talaria were all getting isbn="Unknown",
violating the @Attribute(.unique) constraint and silently failing.
Generate UUID-based fallback in addBookToLibrary to prevent
constraint violations regardless of caller.
```
**Files:** `CameraViewModel.swift`

### Commit 3: PendingBookResult model (Phase 2)
```
feat: Add PendingBookResult model for review queue

In-memory model for holding scan results before user approval.
Stores BookMetadata, rawJSON, thumbnail, and scan date.
```
**Files:** `PendingBookResult.swift`

### Commit 4: ReviewQueueView + tab integration (Phase 2)
```
feat: Add Review tab with pending book queue

- New ReviewQueueView with approve/reject per book
- ReviewQueueView owns @Environment(\.modelContext) for SwiftData ops
- Third tab in MainTabView (Library, Review, Camera)
- Badge count for pending items on Review tab
- CameraViewModel lifted to MainTabView, shared with Camera and Review
- CameraView accepts viewModel parameter (plain var, not @Bindable)
- CameraView #Preview updated with viewModel and modelContainer
- All scans now route to review queue (no auto-add)
- Duplicate detection moved from scan-time to approve-time
- DuplicateBookAlert moved from CameraView to ReviewQueueView
- approveAllBooks logs count before clearing array
```
**Files:** `ReviewQueueView.swift`, `RootView.swift`, `CameraView.swift`, `CameraViewModel.swift`

### Commit 5: Cleanup debug logging (Phase 3)
```
chore: Remove temporary debug logging from save path

Clean up diagnostic prints added during investigation.
Keep essential logging (success/error only).
```
**Files:** `CameraViewModel.swift`

---

## Success Criteria

| Criterion | Measurement | Target |
|-----------|-------------|--------|
| Bug identified | Root cause documented | Documented with evidence |
| Bug fixed | Books save successfully | 7/7 SSE results persist |
| Review queue functional | Approve adds to library | 100% of approved books appear |
| Review queue functional | Reject removes from queue | 100% removed with animation |
| Tab integration | 3 tabs visible | Library + Review + Camera |
| Badge accuracy | Count matches pending items | Real-time accuracy |
| Build quality | xcsift output | 0 errors, 0 warnings |
| Design compliance | Swiss Glass system | Cards, colors, typography consistent |
| Preview compilation | CameraView #Preview | Compiles without error |
| Camera tab switching | Start/stop on switch | No crashes, no hangs |
| DuplicateBookAlert location | Only in ReviewQueueView | Not in CameraView |

---

## Critic Issue Resolution Tracker

| Issue # | Type | Description | Resolution | TODO |
|---------|------|-------------|------------|------|
| 1 | CRITICAL | ModelContext plumbing unresolved (`/* need context */`) | ReviewQueueView owns `@Environment(\.modelContext)`, passes to viewModel methods directly. MainTabView has no ModelContext. Full wiring table in TODO 2.4. | 2.4 |
| 2 | CRITICAL | CameraView #Preview build break | Preview updated to `CameraView(viewModel: CameraViewModel()).modelContainer(for: Book.self, inMemory: true)` | 2.4 |
| 3 | CRITICAL | @Bindable usage incorrect | Changed to plain `var viewModel: CameraViewModel`. Justification: no `$viewModel.property` binding syntax used. | 2.4 |
| 4 | CRITICAL | ISBN fix lost in Phase 2 | Fix applied independently in `addBookToLibrary` line 680 (durable). `approveBook` generates separate fallback for duplicate detection only. Both are independent and correct. | 1.4, 2.5 |
| 5 | MINOR | `approveAllBooks` prints count after removeAll | Count captured before removeAll: `let count = pendingReviewBooks.count` then log `count` | 2.3 |
| 6 | MINOR | DuplicateBookAlert orphaned in CameraView | New TODO 2.6 explicitly moves alert from CameraView to ReviewQueueView | 2.6 |
| 7 | MINOR | Camera stop/restart on tab switch unverified | New TODO 3.2 with explicit 5-step verification protocol | 3.2 |
| 8 | MINOR | File line counts incorrect | Fixed: CameraView 293 lines, CameraViewModel 814 lines | Context |

---

## File Change Summary

| File | Action | Changes |
|------|--------|---------|
| `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift` (814 lines) | MODIFY | Add `pendingReviewBooks`, `pendingBookBeingApproved` state; replace `handleBookResult`; add `approveBook`, `rejectBook`, `approveAllBooks`; update `addDuplicateAnyway`, `dismissDuplicateAlert`; fix ISBN fallback at line 680 |
| `/Users/juju/dev_repos/swiftwing/swiftwing/RootView.swift` (95 lines) | MODIFY | MainTabView: add `@State viewModel`, add Review tab with badge, pass viewModel to CameraView and ReviewQueueView |
| `/Users/juju/dev_repos/swiftwing/swiftwing/CameraView.swift` (293 lines) | MODIFY | Line 9: `@State private var viewModel` -> `var viewModel: CameraViewModel`; remove DuplicateBookAlert (lines 188-203); update #Preview (lines 290-293) |
| `/Users/juju/dev_repos/swiftwing/swiftwing/PendingBookResult.swift` | CREATE | ~30 lines |
| `/Users/juju/dev_repos/swiftwing/swiftwing/ReviewQueueView.swift` | CREATE | ~200 lines (ReviewQueueView + ReviewCardView + empty state + DuplicateBookAlert overlay) |
