import Foundation
import os

private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "offline-queue")

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
        let preScannedISBN: String?
    }

    // MARK: - Initialization

    init() {
        // Create offline queue directory in app's documents folder
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.queueDirectory = documentsDir.appendingPathComponent("OfflineQueue", isDirectory: true)

        // Create directory if it doesn't exist (non-blocking)
        Task {
            await ensureInitialized()
        }
    }

    // MARK: - Initialization Guard

    /// Ensures the queue directory exists before any queue operation.
    /// Logs errors instead of silently swallowing them.
    func ensureInitialized() async {
        do {
            try await createQueueDirectoryIfNeeded()
        } catch {
            logger.error("Failed to create queue directory: \(error)")
        }
    }

    // MARK: - Public API

    /// Queue a scan for offline upload later
    /// - Parameters:
    ///   - imageData: Full-size JPEG image data to queue
    ///   - preScannedISBN: Vision-detected ISBN from barcode scanner
    /// - Returns: UUID of the queued item
    func queueScan(imageData: Data, preScannedISBN: String? = nil) async throws -> UUID {
        // Ensure queue directory exists before writing
        await ensureInitialized()

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
            imageFileName: imageFileName,
            preScannedISBN: preScannedISBN
        )
        let metadataFileName = "\(scanId.uuidString).json"
        let metadataURL = queueDirectory.appendingPathComponent(metadataFileName)
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL)

        logger.info("Queued offline scan: \(scanId)")
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

        var results: [(metadata: QueuedScanMetadata, imageData: Data)] = []

        for metadataFile in metadataFiles {
            do {
                // Load metadata
                let metadataData = try Data(contentsOf: metadataFile)
                let metadata = try JSONDecoder().decode(QueuedScanMetadata.self, from: metadataData)

                // Load corresponding image
                let imageURL = queueDirectory.appendingPathComponent(metadata.imageFileName)
                let imageData = try Data(contentsOf: imageURL)

                results.append((metadata: metadata, imageData: imageData))
            } catch {
                logger.warning("Failed to load queued scan from \(metadataFile.lastPathComponent): \(error)")
                // Continue with other scans even if one fails
            }
        }

        // Sort by capture date (oldest first)
        results.sort { $0.metadata.captureDate < $1.metadata.captureDate }

        logger.info("Found \(results.count) queued offline scans")
        return results
    }

    /// Stream queued scans one at a time from oldest to newest
    /// - Returns: AsyncThrowingStream of (metadata, imageData) tuples
    func streamQueuedScans() -> AsyncThrowingStream<(metadata: QueuedScanMetadata, imageData: Data), Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Check if directory exists
                    guard FileManager.default.fileExists(atPath: queueDirectory.path) else {
                        continuation.finish()
                        return
                    }

                    // Read all metadata files
                    let contents = try FileManager.default.contentsOfDirectory(
                        at: queueDirectory,
                        includingPropertiesForKeys: nil
                    )

                    let metadataFiles = contents.filter { $0.pathExtension == "json" }

                    // Load and decode all metadata first to sort by date
                    var metadataList: [QueuedScanMetadata] = []
                    for metadataFile in metadataFiles {
                        do {
                            let metadataData = try Data(contentsOf: metadataFile)
                            let metadata = try JSONDecoder().decode(QueuedScanMetadata.self, from: metadataData)
                            metadataList.append(metadata)
                        } catch {
                            logger.warning("Failed to load metadata from \(metadataFile.lastPathComponent): \(error)")
                        }
                    }

                    // Sort by capture date (oldest first)
                    let sorted = metadataList.sorted { $0.captureDate < $1.captureDate }

                    // Stream each scan one at a time
                    for metadata in sorted {
                        let imageURL = queueDirectory.appendingPathComponent(metadata.imageFileName)
                        if let imageData = try? Data(contentsOf: imageURL) {
                            continuation.yield((metadata: metadata, imageData: imageData))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
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

        logger.info("Removed queued scan: \(scanId)")
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
            logger.info("Created offline queue directory")
        }
    }
}
