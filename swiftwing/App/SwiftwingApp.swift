import SwiftUI
import SwiftData
import OSLog

@main
struct SwiftwingApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: BookSchemaV2.self)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: BookMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            Logger(subsystem: "com.ooheynerds.swiftwing", category: "app-init")
                .fault("Could not create ModelContainer: \(error)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        configureForUITesting()
        Task(priority: .background) {
            await Self.cleanupOrphanedTempPhotos()
        }

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

    /// True when the one-hour sweep will consider this file. The sweep lists only
    /// the top of the temp directory, so a JPEG in a subdirectory is left alone.
    nonisolated static func tempSweepWouldDelete(
        _ url: URL,
        tempDirectory: URL = FileManager.default.temporaryDirectory
    ) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "jpg" || ext == "jpeg" else { return false }
        return url.deletingLastPathComponent().standardizedFileURL
            == tempDirectory.standardizedFileURL
    }

    /// Remove orphaned JPEG temp files older than 1 hour from the top of the temp directory.
    /// Does not enter subdirectories. Rate-limit retries live in `SwiftWingRateLimit` and stay
    /// for the session. Handles crash/force-quit scenarios where normal cleanup didn't run.
    private nonisolated static func cleanupOrphanedTempPhotos() async {
        let tempDir = FileManager.default.temporaryDirectory
        let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "app-init")
        let oneHourAgo = Date().addingTimeInterval(-3600)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
        ) else { return }

        var cleaned = 0
        for file in files where tempSweepWouldDelete(file, tempDirectory: tempDir) {
            guard let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
                  let created = attrs.creationDate,
                  created < oneHourAgo else { continue }
            do {
                try FileManager.default.removeItem(at: file)
                cleaned += 1
            } catch {
                logger.warning("Failed to clean orphaned temp photo: \(error.localizedDescription)")
            }
        }
        if cleaned > 0 {
            logger.info("Cleaned up \(cleaned) orphaned temp photo(s)")
        }
    }

    /// Configures app state based on launch arguments for UI testing
    private func configureForUITesting() {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("FORCE_ONBOARDING") {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }

        if arguments.contains("FORCE_CAMERA_GUIDANCE") {
            UserDefaults.standard.set(false, forKey: "hasSeenCameraGuidance")
        }

        guard arguments.contains("UI_TESTING") else { return }

        // Skip onboarding for test determinism
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        // Suppress the first-run camera coach unless a test explicitly asks for it
        // (FORCE_CAMERA_GUIDANCE); otherwise it covers the camera tab for every test.
        if !arguments.contains("FORCE_CAMERA_GUIDANCE") {
            UserDefaults.standard.set(true, forKey: "hasSeenCameraGuidance")
        }
        // Reset review filter to off for deterministic state
        UserDefaults.standard.set(false, forKey: "show_review_needed")

        let context = sharedModelContainer.mainContext

        if arguments.contains("CLEAR_DATA") {
            // Delete all books for clean-slate testing
            do {
                try context.delete(model: Book.self)
                try context.save()
            } catch {
                Logger(subsystem: "com.ooheynerds.swiftwing", category: "app-init")
                    .error("UI_TESTING: Failed to clear data: \(error.localizedDescription, privacy: .public)")
            }
        }

        #if DEBUG
        if arguments.contains("SEED_LIBRARY") {
            // Clear first to ensure deterministic seed count
            do {
                try context.delete(model: Book.self)
                try context.save()
            } catch {
                Logger(subsystem: "com.ooheynerds.swiftwing", category: "app-init")
                    .error("UI_TESTING: Failed to clear before seed: \(error.localizedDescription, privacy: .public)")
            }
            DataSeeder.seedLibrary(context: context)
        }
        #endif
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
