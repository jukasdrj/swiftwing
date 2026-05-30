import Testing
@testable import swiftwing

@Suite("QueueStateManager")
@MainActor
struct QueueStateManagerTests {
    @Test
    func restartingCountdownCancelsPreviousTimer() async throws {
        let manager = QueueStateManager()

        manager.startRateLimitCountdown(duration: 3)
        try await Task.sleep(for: .seconds(1.1))

        manager.startRateLimitCountdown(duration: 3)
        try await Task.sleep(for: .milliseconds(200))

        #expect(manager.isRateLimited)
        #expect(manager.rateLimitCountdown >= 2)

        manager.clearRateLimit()
    }

    @Test
    func countdownExpiresAndClearsRateLimit() async throws {
        let manager = QueueStateManager()

        manager.startRateLimitCountdown(duration: 1)
        try await Task.sleep(for: .seconds(1.2))

        #expect(manager.isRateLimited == false)
        #expect(manager.rateLimitCountdown == 0)
    }
}
