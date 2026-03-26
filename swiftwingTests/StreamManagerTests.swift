import Foundation
import Testing
@testable import swiftwing

// MARK: - StreamManager Tests

@Suite("StreamManager")
struct StreamManagerTests {

    // MARK: - Helpers

    private func makeManager(maxStreams: Int = 3) -> StreamManager {
        StreamManager(config: StreamManagerConfig(maxConcurrentStreams: maxStreams))
    }

    // MARK: - 1. acquireStreamSlot succeeds when slots available

    @Test func acquireStreamSlot_whenSlotsAvailable_incrementsActiveCount() async {
        let manager = makeManager(maxStreams: 3)
        let id = UUID()

        await manager.acquireStreamSlot(scanId: id)

        let count = await manager.getActiveStreamCount()
        #expect(count == 1)
    }

    // MARK: - 2. acquireStreamSlot queues when at capacity

    @Test func acquireStreamSlot_whenAtCapacity_queuesAdditionalScans() async {
        let manager = makeManager(maxStreams: 2)

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        // Fill capacity
        await manager.acquireStreamSlot(scanId: id1)
        await manager.acquireStreamSlot(scanId: id2)

        // Third acquire should queue — start it in a background task and verify queue depth
        let task = Task {
            await manager.acquireStreamSlot(scanId: id3)
        }

        // Give the task a moment to reach the waiting point
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let activeCount = await manager.getActiveStreamCount()
        let queueDepth = await manager.getQueueDepth()

        #expect(activeCount == 2)
        #expect(queueDepth == 1)

        // Unblock: release one slot so id3 can proceed, then clean up
        await manager.releaseStreamSlot(scanId: id1)
        await task.value
        await manager.releaseStreamSlot(scanId: id2)
        await manager.releaseStreamSlot(scanId: id3)
    }

    // MARK: - 3. releaseStreamSlot decrements correctly

    @Test func releaseStreamSlot_afterAcquire_decrementsActiveCount() async {
        let manager = makeManager(maxStreams: 3)
        let id = UUID()

        await manager.acquireStreamSlot(scanId: id)
        let countAfterAcquire = await manager.getActiveStreamCount()
        #expect(countAfterAcquire == 1)

        await manager.releaseStreamSlot(scanId: id)
        let countAfterRelease = await manager.getActiveStreamCount()
        #expect(countAfterRelease == 0)
    }

    @Test func releaseStreamSlot_multipleAcquires_decrementsEachTime() async {
        let manager = makeManager(maxStreams: 5)
        let ids = (0..<3).map { _ in UUID() }

        for id in ids {
            await manager.acquireStreamSlot(scanId: id)
        }
        #expect(await manager.getActiveStreamCount() == 3)

        await manager.releaseStreamSlot(scanId: ids[0])
        #expect(await manager.getActiveStreamCount() == 2)

        await manager.releaseStreamSlot(scanId: ids[1])
        #expect(await manager.getActiveStreamCount() == 1)

        await manager.releaseStreamSlot(scanId: ids[2])
        #expect(await manager.getActiveStreamCount() == 0)
    }

    // MARK: - 4. Underflow guard: release with 0 active doesn't go negative

    @Test func releaseStreamSlot_withZeroActive_doesNotGoNegative() async {
        let manager = makeManager(maxStreams: 3)
        let id = UUID()

        // Release without acquire — should be a no-op (underflow guard)
        await manager.releaseStreamSlot(scanId: id)

        let count = await manager.getActiveStreamCount()
        #expect(count == 0)
    }

    // MARK: - 5. Concurrent acquire + release stress test

    @Test func concurrentAcquireAndRelease_stressTest_neverExceedsMax() async {
        let maxStreams = 3
        let manager = makeManager(maxStreams: maxStreams)
        let scanCount = 12

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<scanCount {
                group.addTask {
                    let id = UUID()
                    await manager.acquireStreamSlot(scanId: id)
                    // Simulate brief work
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    await manager.releaseStreamSlot(scanId: id)
                }
            }
        }

        // After all tasks complete, active count must be 0
        let finalCount = await manager.getActiveStreamCount()
        #expect(finalCount == 0)

        // Queue must be empty
        let finalQueue = await manager.getQueueDepth()
        #expect(finalQueue == 0)
    }

    // MARK: - 6. Slot count matches maxConcurrentStreams constant

    @Test func defaultConfig_maxConcurrentStreams_isFive() async {
        let manager = StreamManager()

        // Fill all 5 default slots
        let ids = (0..<5).map { _ in UUID() }
        for id in ids {
            await manager.acquireStreamSlot(scanId: id)
        }

        let activeCount = await manager.getActiveStreamCount()
        #expect(activeCount == 5)

        // 6th should queue
        let extraId = UUID()
        let overflowTask = Task {
            await manager.acquireStreamSlot(scanId: extraId)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await manager.getQueueDepth() == 1)

        // Clean up
        await manager.releaseStreamSlot(scanId: ids[0])
        await overflowTask.value
        for id in ids.dropFirst() {
            await manager.releaseStreamSlot(scanId: id)
        }
        await manager.releaseStreamSlot(scanId: extraId)
    }

    // MARK: - 7. Re-acquire after release succeeds

    @Test func reacquire_afterRelease_succeedsImmediately() async {
        let manager = makeManager(maxStreams: 1)
        let id1 = UUID()
        let id2 = UUID()

        await manager.acquireStreamSlot(scanId: id1)
        #expect(await manager.getActiveStreamCount() == 1)

        await manager.releaseStreamSlot(scanId: id1)
        #expect(await manager.getActiveStreamCount() == 0)

        // Re-acquire with a new ID should succeed immediately (slot is free)
        await manager.acquireStreamSlot(scanId: id2)
        #expect(await manager.getActiveStreamCount() == 1)

        await manager.releaseStreamSlot(scanId: id2)
        #expect(await manager.getActiveStreamCount() == 0)
    }

    // MARK: - 8. Queue drains in FIFO order after releases

    @Test func queueDrains_fifoOrder_afterCapacityReleased() async {
        let manager = makeManager(maxStreams: 1)
        let firstId = UUID()

        // Fill the single slot
        await manager.acquireStreamSlot(scanId: firstId)

        // Two scans queue up
        let secondId = UUID()
        let thirdId = UUID()

        let task2 = Task { await manager.acquireStreamSlot(scanId: secondId) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let task3 = Task { await manager.acquireStreamSlot(scanId: thirdId) }
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(await manager.getQueueDepth() == 2)

        // Release first slot — queue should drain one entry
        await manager.releaseStreamSlot(scanId: firstId)
        await task2.value
        #expect(await manager.getActiveStreamCount() == 1)
        #expect(await manager.getQueueDepth() == 1)

        await manager.releaseStreamSlot(scanId: secondId)
        await task3.value
        #expect(await manager.getActiveStreamCount() == 1)
        #expect(await manager.getQueueDepth() == 0)

        await manager.releaseStreamSlot(scanId: thirdId)
        #expect(await manager.getActiveStreamCount() == 0)
    }
}
