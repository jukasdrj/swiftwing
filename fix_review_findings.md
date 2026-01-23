# Findings: Gemini Pro 3 Implementation Plan

## Date: 2026-01-23

## Summary
Gemini Pro 3 provided comprehensive implementation plan for fixing 5 critical issues in LibraryPrefetchCoordinator and PerformanceTestData.

---

## Finding #1: Data Race - Missing @MainActor

**Issue:** `@Observable` class modifies state from background tasks without actor isolation.

**Fix:** Add `@MainActor` annotation to class declaration.

**Code Change:**
```swift
@MainActor  // <-- ADD THIS
@Observable
class LibraryPrefetchCoordinator {
```

**Integration:** None (annotation only)

**Testing:**
- Enable Strict Concurrency Checking
- Build and verify no warnings
- Run app and scroll library

---

## Finding #2 & #4: Architecture Redundancy + Performance Killer

**Issue:** Duplicate logic + UIImage(data:) decoding causes CPU spikes.

**Fix:** Delegate to ImageCacheManager, remove prefetchImage method.

**Code Removed:**
- `private var prefetchTasks: [URL: Task<Void, Never>] = [:]`
- Entire `prefetchImage(url:)` method
- Manual network code in `prefetchUpcoming`

**Code Added:**
```swift
func prefetchUpcoming(books: [Book], maxCount: Int = 20) {
    let urlsToPrefetch = books
        .prefix(maxCount)
        .compactMap { $0.coverUrl }
        .filter { !prefetchedURLs.contains($0) }

    guard !urlsToPrefetch.isEmpty else { return }

    urlsToPrefetch.forEach { prefetchedURLs.insert($0) }

    Task {
        await ImageCacheManager.shared.prefetchImages(urls: Array(urlsToPrefetch))
    }
}

func cancelAll() {
    Task {
        await ImageCacheManager.shared.cancelAllPrefetches()
    }
}
```

**Testing:**
- Scroll through 100+ items
- Verify cache hits in logs
- Check CPU usage is lower

---

## Finding #3: UI Freeze - Synchronous generateTestDataset

**Issue:** Blocking main thread for several seconds generating 1000 books.

**Fix:** Make async, use background ModelContext via ModelContainer.

**Signature Change:**
```swift
// OLD
static func generateTestDataset(count: Int, context: ModelContext, includeCovers: Bool)

// NEW
@MainActor
static func generateTestDataset(count: Int, container: ModelContainer, includeCovers: Bool) async
```

**Key Changes:**
- Wrap in `Task.detached(priority: .userInitiated)`
- Create background `ModelContext` from container
- Set `context.autosaveEnabled = false` for performance
- Preserve all existing book generation logic

**Integration Changes:**
- LibraryView: Add `@Environment(\.modelContainer)`
- Update calls: `Task { await PerformanceTestData.generateTestDataset(..., container: modelContainer) }`

**Testing:**
- Tap generate button
- Verify UI stays responsive
- Verify books appear after completion

---

## Finding #5: Batch Delete Inefficiency

**Issue:** Fetches all objects into memory before deleting (O(N) memory).

**Fix:** Use SwiftData batch delete.

**Signature Change:**
```swift
// OLD
static func clearTestData(context: ModelContext)

// NEW
@MainActor
static func clearTestData(container: ModelContainer) async
```

**Implementation:**
```swift
@MainActor
static func clearTestData(container: ModelContainer) async {
    print("🧹 Clearing test data...")

    await Task.detached {
        let context = ModelContext(container)
        do {
            try context.delete(model: Book.self)
            print("✅ Cleared all books")
        } catch {
            print("⚠️ Failed to clear test data: \(error)")
        }
    }.value
}
```

**Integration:** Same as Finding #3 (use modelContainer)

**Testing:**
- Generate 1000 books
- Clear all
- Verify near-instant (<1s)

---

## Implementation Order

1. Finding #1 (simple annotation)
2. Finding #2 & #4 (architectural cleanup)
3. Finding #3 (async generation)
4. Finding #5 (batch delete)
5. Update LibraryView integration points
6. Build and test

---

## Risks Identified

| Risk | Mitigation |
|------|------------|
| Deadlock with @MainActor | Unlikely - called from SwiftUI (already MainActor) |
| Missing images if ImageCacheManager fails | CachedAsyncImage loads on demand as fallback |
| UI not refreshing after background saves | @Query observes persistent store, should auto-update |
| Query update delay | Better UX than freeze anyway |

---

## Files to Modify

1. `LibraryPrefetchCoordinator.swift` - Findings #1, #2, #4
2. `PerformanceTestData.swift` - Findings #3, #5
3. `LibraryView.swift` - Integration updates for #3, #5
