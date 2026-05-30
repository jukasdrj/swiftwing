import Foundation
import Testing
@testable import swiftwing

@Suite("OfflineQueueManager")
struct OfflineQueueManagerTests {
    private func queueDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineQueue", isDirectory: true)
    }

    private func resetQueueDirectory() throws {
        let directory = queueDirectory()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    @Test
    func queueScanRoundTripsImageDataAndMetadata() async throws {
        try resetQueueDirectory()
        let manager = OfflineQueueManager()
        let imageData = Data("offline-image".utf8)

        let scanId = try await manager.queueScan(imageData: imageData, preScannedISBN: "9780306406157")
        let queuedScans = try await manager.getAllQueuedScans()

        #expect(queuedScans.count == 1)

        let queuedScan = try #require(queuedScans.first)
        #expect(queuedScan.metadata.id == scanId)
        #expect(queuedScan.metadata.preScannedISBN == "9780306406157")
        #expect(queuedScan.imageData == imageData)
        #expect(try await manager.getQueuedScanCount() == 1)

        try await manager.removeQueuedScan(scanId: scanId)
        #expect(try await manager.getQueuedScanCount() == 0)
    }

    @Test
    func getAllQueuedScansSkipsEntriesWithMissingImages() async throws {
        try resetQueueDirectory()
        let manager = OfflineQueueManager()
        let goodId = try await manager.queueScan(imageData: Data("good".utf8), preScannedISBN: "9780000000001")
        let brokenId = try await manager.queueScan(imageData: Data("broken".utf8), preScannedISBN: "9780000000002")

        let missingImageURL = queueDirectory()
            .appendingPathComponent("\(brokenId.uuidString).jpg")
        try FileManager.default.removeItem(at: missingImageURL)

        let queuedScans = try await manager.getAllQueuedScans()

        #expect(queuedScans.count == 1)
        #expect(queuedScans.first?.metadata.id == goodId)
        #expect(try await manager.getQueuedScanCount() == 2)

        try await manager.removeQueuedScan(scanId: goodId)
        try await manager.removeQueuedScan(scanId: brokenId)
        #expect(try await manager.getQueuedScanCount() == 0)
    }
}
