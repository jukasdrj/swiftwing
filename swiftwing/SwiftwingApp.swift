import SwiftUI
import SwiftData

@main
struct SwiftwingApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Book.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        #if DEBUG
        // OPTIONAL: Uncomment to auto-seed library on first launch
        // Useful for rapid development iteration without manual button taps
        //
        // Usage:
        // 1. Uncomment the line below
        // 2. Run app - library will seed on first launch
        // 3. To re-seed: Delete app from simulator and run again
        //
        // autoSeedLibraryIfNeeded()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
    }

    #if DEBUG
    /// Auto-seeds library on first launch (development only)
    ///
    /// Checks if library is empty and seeds with diverse book collection.
    /// Safe to call multiple times - will only seed once.
    private func autoSeedLibraryIfNeeded() {
        let context = sharedModelContainer.mainContext
        DataSeeder.seedLibrary(context: context)
    }
    #endif
}
