# SwiftData Patterns (iOS 26 / Swift 6.2)

## Environment Access Patterns

### ✅ CORRECT: modelContext is the Environment Key

```swift
struct MyView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        // Access container through modelContext
        let container = modelContext.container

        // Use modelContext for data operations
        modelContext.insert(newBook)
        try? modelContext.save()
    }
}
```

### ❌ WRONG: modelContainer is NOT an Environment Key

```swift
// THIS DOES NOT EXIST IN SWIFTDATA
@Environment(\.modelContainer) private var modelContainer  // ❌ COMPILER ERROR
```

**Error you'll see:**
```
cannot infer key path type from context
cannot convert KeyPath<Root, Value> to ModelContainer.Type
```

## Why This Design?

**Apple's Rationale:**
- `ModelContext`: Lightweight, thread-confined, designed for views
- `ModelContainer`: Heavy, foundational, manages persistence layer
- Views should use ModelContext for transactions
- Container access only needed for background tasks

## Background Task Pattern

**When you need ModelContainer for background work:**

```swift
@MainActor
static func backgroundTask(container: ModelContainer) async {
    await Task.detached(priority: .userInitiated) {
        let context = ModelContext(container)
        context.autosaveEnabled = false  // Optimization

        // Do work...
        try? context.save()
    }.value
}

// In view:
Task {
    await MyService.backgroundTask(container: modelContext.container)
}
```

## SwiftData Environment Setup

**In App:**
```swift
@main
struct SwiftwingApp: App {
    var sharedModelContainer: ModelContainer = {
        // Setup container
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)  // ← Sets up environment
    }
}
```

**The `.modelContainer()` modifier:**
- Puts ModelContext in environment (accessible via `\.modelContext`)
- Does NOT put ModelContainer in environment
- Container accessible through `modelContext.container`

## Common Mistakes

### ❌ Mistake 1: Trying to Access Container Directly
```swift
@Environment(\.modelContainer) var container  // ❌ Doesn't exist
```

**Fix:**
```swift
@Environment(\.modelContext) var modelContext
// Use: modelContext.container when needed
```

### ❌ Mistake 2: Storing ModelContainer in @State
```swift
@State private var container: ModelContainer  // ❌ Heavy, not designed for this
```

**Fix:**
```swift
@Environment(\.modelContext) var modelContext  // ✅ Lightweight, designed for views
```

### ❌ Mistake 3: Creating ModelContext Without Container
```swift
let context = ModelContext()  // ❌ Needs container
```

**Fix:**
```swift
let context = ModelContext(modelContext.container)  // ✅ From existing context
```

## Real Example from This Project

**Problem:**
```swift
// LibraryView.swift:40
@Environment(\.modelContainer) private var modelContainer: ModelContainer  // ❌

private func generatePerformanceTestData(count: Int) {
    Task {
        await PerformanceTestData.generateTestDataset(
            count: count,
            container: modelContainer,  // ❌ Not available
            includeCovers: true
        )
    }
}
```

**Solution:**
```swift
// Remove invalid environment line
@Environment(\.modelContext) private var modelContext  // ✅

private func generatePerformanceTestData(count: Int) {
    Task {
        await PerformanceTestData.generateTestDataset(
            count: count,
            container: modelContext.container,  // ✅ Access via modelContext
            includeCovers: true
        )
    }
}
```

## Quick Reference

| Need | Use |
|------|-----|
| Insert/delete/query in view | `@Environment(\.modelContext)` |
| Access container for background task | `modelContext.container` |
| Create new context | `ModelContext(container)` |
| Save changes | `try modelContext.save()` |
| Batch operations | Background context with `autosaveEnabled = false` |

## Verification

**If you see this error:**
```
cannot infer key path type from context
```

**You're trying to use:**
```swift
@Environment(\.something)
```

**Where `\.something` doesn't exist as an EnvironmentKey.**

**For SwiftData, only `\.modelContext` is provided.**
