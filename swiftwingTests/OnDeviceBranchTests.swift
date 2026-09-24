import Foundation
import Testing
@testable import swiftwing

private struct StubSpineExtractor: BookSpineExtracting {
    var outcome: OnDeviceScanOutcome

    func extract(_ imageData: Data) async throws -> OnDeviceScanOutcome {
        outcome
    }
}

@MainActor
@Suite("On-device capture branch")
struct OnDeviceBranchTests {
    private func makeViewModel(
        mode: ScanMode,
        extractor: any BookSpineExtracting = OnDeviceScanner()
    ) -> (CameraViewModel, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftwing-on-device-\(UUID().uuidString)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "OnDeviceBranchTests-\(UUID().uuidString)")!
        let settings = ScanModeSettings(defaults: defaults)
        settings.mode = mode
        let viewModel = CameraViewModel(
            scanModeSettings: settings,
            spineExtractor: extractor,
            offlineQueueManager: OfflineQueueManager(queueDirectory: directory)
        )
        viewModel.queueRemovalDelay = 0
        let monitor = NetworkMonitor(startsMonitoring: false)
        monitor.setConnected(false)
        viewModel.networkMonitor = monitor
        return (viewModel, directory)
    }

    @Test func onDeviceWhileOfflineReviewsWithoutQueueing() async throws {
        let outcome = OnDeviceScanOutcome(
            metadata: BookMetadata(
                title: "Local Title",
                author: "Local Author",
                confidence: nil,
                enrichmentStatus: .success
            ),
            ocrText: "Local Title\nLocal Author"
        )
        let (viewModel, directory) = makeViewModel(
            mode: .onDevice,
            extractor: StubSpineExtractor(outcome: outcome)
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let context = try makeSwiftDataContext()
        let finished = await viewModel.processCaptureWithImageData(
            itemId: UUID(),
            imageData: Data("jpeg".utf8),
            modelContext: context
        )

        #expect(finished)
        #expect(viewModel.queueStateManager.offlineQueuedCount == 0)
        let pending = try #require(viewModel.reviewQueueManager.pendingReviewBooks.first)
        #expect(viewModel.reviewQueueManager.pendingReviewBooks.count == 1)
        #expect(pending.metadata.title == "Local Title")
        #expect(pending.metadata.confidence == nil)
        #expect(pending.metadata.enrichmentStatus == .success)
        #expect(pending.rawJSON == "Local Title\nLocal Author")
    }

    @Test func talariaWhileOfflineStillQueues() async throws {
        let (viewModel, directory) = makeViewModel(mode: .talaria)
        defer { try? FileManager.default.removeItem(at: directory) }

        let context = try makeSwiftDataContext()
        let finished = await viewModel.processCaptureWithImageData(
            itemId: UUID(),
            imageData: Data("jpeg".utf8),
            modelContext: context
        )

        #expect(finished)
        #expect(viewModel.queueStateManager.offlineQueuedCount == 1)
        #expect(viewModel.queueStateManager.processingQueue.contains { $0.state == .offline })
    }
}
