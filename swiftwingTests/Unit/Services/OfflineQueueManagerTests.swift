import Foundation
import Testing
@testable import swiftwing

@Suite("OfflineQueueManager")
struct OfflineQueueManagerTests {
    // Create isolated temp directory per test
    private func createTestQueueDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("OfflineQueueTest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        return testDir
    }

    // Clean up temp directory after test
    private func cleanupTestDirectory(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    @Test
    func queueScanRoundTripsImageDataAndMetadata() async throws {
        let testQueueDir = createTestQueueDirectory()
        defer { try? cleanupTestDirectory(testQueueDir) }

        let manager = OfflineQueueManager(queueDirectory: testQueueDir)
        let imageData = Data("offline-image".utf8)

        let scanId = try await manager.queueScan(imageData: imageData, preScannedISBN: "9780306406157")

        var streamedScans: [(metadata: OfflineQueueManager.QueuedScanMetadata, imageData: Data)] = []
        for try await scan in manager.streamQueuedScans() {
            streamedScans.append(scan)
        }

        #expect(streamedScans.count == 1)

        let queuedScan = try #require(streamedScans.first)
        #expect(queuedScan.metadata.id == scanId)
        #expect(queuedScan.metadata.preScannedISBN == "9780306406157")
        #expect(queuedScan.imageData == imageData)
        #expect(try await manager.getQueuedScanCount() == 1)

        try await manager.removeQueuedScan(scanId: scanId)
        #expect(try await manager.getQueuedScanCount() == 0)
    }

    @Test
    func streamQueuedScansSkipsEntriesWithMissingImages() async throws {
        let testQueueDir = createTestQueueDirectory()
        defer { try? cleanupTestDirectory(testQueueDir) }

        let manager = OfflineQueueManager(queueDirectory: testQueueDir)
        let goodId = try await manager.queueScan(imageData: Data("good".utf8), preScannedISBN: "9780000000001")
        let brokenId = try await manager.queueScan(imageData: Data("broken".utf8), preScannedISBN: "9780000000002")

        let missingImageURL = testQueueDir
            .appendingPathComponent("\(brokenId.uuidString).jpg")
        try FileManager.default.removeItem(at: missingImageURL)

        var streamedScans: [(metadata: OfflineQueueManager.QueuedScanMetadata, imageData: Data)] = []
        for try await scan in manager.streamQueuedScans() {
            streamedScans.append(scan)
        }

        #expect(streamedScans.count == 1)
        #expect(streamedScans.first?.metadata.id == goodId)
        #expect(try await manager.getQueuedScanCount() == 2)

        try await manager.removeQueuedScan(scanId: goodId)
        try await manager.removeQueuedScan(scanId: brokenId)
        #expect(try await manager.getQueuedScanCount() == 0)
    }
}
