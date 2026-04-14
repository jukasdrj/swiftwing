import SwiftData
@testable import swiftwing

/// A single shared in-memory `ModelContainer` for the entire test session.
///
/// **Why this exists:**
/// Creating a new `ModelContainer` per test causes SwiftData to accumulate global
/// schema registrations. On iOS 26 / Swift 6.2, this triggers an `EXC_BREAKPOINT`
/// assertion inside SwiftData during `context.fetch` after a certain number of
/// containers have been created and destroyed within the same process. All affected
/// test suites (`DuplicateDetectionTests`, `ReviewQueueManagerTests`) use this
/// container instead of creating their own.
///
/// **Test isolation:**
/// Tests are still isolated — each call to `makeSwiftDataContext()` deletes all
/// `Book` records before returning a clean context. Since all SwiftData tests are
/// `@MainActor` they run serially on the main thread, so the shared context is
/// never accessed concurrently.
///
/// - Note: `force-try` is intentional. If the container can't be created,
///   the test process is unusable and we want an immediate, obvious crash
///   rather than silent nil propagation through every test.
let sharedTestModelContainer: ModelContainer = {
    let schema = Schema(versionedSchema: BookSchemaV2.self)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    return try! ModelContainer(
        for: schema,
        migrationPlan: BookMigrationPlan.self,
        configurations: [config]
    )
}()

/// Returns the shared context with all `Book` records deleted.
///
/// Call this at the start of every test that needs a SwiftData context instead
/// of creating a new `ModelContainer` each time.
@MainActor
func makeSwiftDataContext() throws -> ModelContext {
    let context = sharedTestModelContainer.mainContext
    let existing = try context.fetch(FetchDescriptor<Book>())
    existing.forEach { context.delete($0) }
    if !existing.isEmpty {
        try context.save()
    }
    return context
}
