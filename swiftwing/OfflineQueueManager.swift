import Foundation

/// Manages offline scan queue persistence using FileManager
/// Thread-safe actor for storing and retrieving queued scan images
actor OfflineQueueManager {

    // MARK: - Properties

    /// Directory for storing offline queued scans
    private let queueDirectory: URL

    /// Metadata structure for each queued scan
    struct QueuedScanMetadata: Codable {
        let id: UUID
        let captureDate: Date
        let imageFileName: String
    }

    // MARK: - Initialization

    init(queueDirectory: URL? = nil) {
        if let queueDirectory = queueDirectory {
            self.queueDirectory = queueDirectory
        } else {
            // Create offline queue directory in app's documents folder
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.queueDirectory = documentsDir.appendingPathComponent("OfflineQueue", isDirectory: true)
        }

        // Create directory if it doesn't exist (non-blocking)
        Task {
            try? await createQueueDirectoryIfNeeded()
        }
    }

    // MARK: - Public API

    /// Queue a scan for offline upload later
    /// - Parameter imageData: Full-size JPEG image data to queue
    /// - Returns: UUID of the queued item
    func queueScan(imageData: Data) async throws -> UUID {
        // Create queue directory if needed
        try await createQueueDirectoryIfNeeded()

        // Generate unique ID and filename
        let scanId = UUID()
        let imageFileName = "\(scanId.uuidString).jpg"
        let imageURL = queueDirectory.appendingPathComponent(imageFileName)

        // Save image data to file
        try imageData.write(to: imageURL)

        // Create and save metadata
        let metadata = QueuedScanMetadata(
            id: scanId,
            captureDate: Date(),
            imageFileName: imageFileName
        )
        let metadataFileName = "\(scanId.uuidString).json"
        let metadataURL = queueDirectory.appendingPathComponent(metadataFileName)
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL)

        print("💾 Queued offline scan: \(scanId)")
        return scanId
    }

    /// Retrieve all queued scans with their metadata
    /// - Returns: Array of (metadata, imageData) tuples
    func getAllQueuedScans() async throws -> [(metadata: QueuedScanMetadata, imageData: Data)] {
        // Check if directory exists
        guard FileManager.default.fileExists(atPath: queueDirectory.path) else {
            return []
        }

        // Read all metadata files
        let contents = try FileManager.default.contentsOfDirectory(
            at: queueDirectory,
            includingPropertiesForKeys: nil
        )

        let metadataFiles = contents.filter { $0.pathExtension == "json" }

        print("🔄 Loading \(metadataFiles.count) queued scans in parallel...")

        // Capture queueDirectory to avoid actor isolation issues inside TaskGroup
        let queueDir = self.queueDirectory

        return await withTaskGroup(of: (QueuedScanMetadata, Data)?.self) { group in
            for metadataFile in metadataFiles {
                group.addTask {
                    do {
                        return try await self.loadScan(metadataFile: metadataFile, queueDirectory: queueDir)
                    } catch {
                        print("⚠️ Failed to load queued scan from \(metadataFile.lastPathComponent): \(error)")
                        return nil
                    }
                }
            }

            var results: [(metadata: QueuedScanMetadata, imageData: Data)] = []
            for await result in group {
                if let result = result {
                    results.append(result)
                }
            }

            // Sort by capture date (oldest first)
            results.sort { $0.metadata.captureDate < $1.metadata.captureDate }

            print("📂 Found \(results.count) queued offline scans")
            return results
        }
    }

    /// Remove a queued scan after successful upload
    /// - Parameter scanId: UUID of the scan to remove
    func removeQueuedScan(scanId: UUID) async throws {
        let imageFileName = "\(scanId.uuidString).jpg"
        let metadataFileName = "\(scanId.uuidString).json"

        let imageURL = queueDirectory.appendingPathComponent(imageFileName)
        let metadataURL = queueDirectory.appendingPathComponent(metadataFileName)

        // Remove both files (ignore errors if already deleted)
        try? FileManager.default.removeItem(at: imageURL)
        try? FileManager.default.removeItem(at: metadataURL)

        print("🗑️ Removed queued scan: \(scanId)")
    }

    /// Get count of queued scans
    func getQueuedScanCount() async throws -> Int {
        guard FileManager.default.fileExists(atPath: queueDirectory.path) else {
            return 0
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: queueDirectory,
            includingPropertiesForKeys: nil
        )

        // Count metadata files (one per scan)
        let count = contents.filter { $0.pathExtension == "json" }.count
        return count
    }

    // MARK: - Private Helpers

    /// Create queue directory if it doesn't exist
    private func createQueueDirectoryIfNeeded() async throws {
        if !FileManager.default.fileExists(atPath: queueDirectory.path) {
            try FileManager.default.createDirectory(
                at: queueDirectory,
                withIntermediateDirectories: true
            )
            print("📁 Created offline queue directory")
        }
    }

    /// Loads scan data asynchronously and safely off the main actor
    /// - Parameters:
    ///   - metadataFile: URL to the metadata JSON file
    ///   - queueDirectory: The base directory for queued files
    /// - Returns: Tuple containing metadata and image data
    nonisolated func loadScan(metadataFile: URL, queueDirectory: URL) async throws -> (QueuedScanMetadata, Data) {
        // Use URLSession for async non-blocking file I/O
        let (metadataData, _) = try await URLSession.shared.data(from: metadataFile)
        let metadata = try JSONDecoder().decode(QueuedScanMetadata.self, from: metadataData)

        let imageURL = queueDirectory.appendingPathComponent(metadata.imageFileName)
        let (imageData, _) = try await URLSession.shared.data(from: imageURL)

        return (metadata, imageData)
    }
}
