import Foundation

/// Mock network monitor for testing online/offline scenarios.
final class MockNetworkMonitor: Sendable {
    private let lock = NSLock()
    private var _isOnline: Bool = true
    
    var isOnline: Bool {
        lock.withLock { _isOnline }
    }
    
    var statusPublisher: AsyncStream<Bool> {
        AsyncStream { continuation in
            // Immediately emit current status
            continuation.yield(_isOnline)
        }
    }
    
    // MARK: - Configuration
    
    func setOnline(_ online: Bool) {
        lock.withLock { _isOnline = online }
    }
    
    func simulateNetworkDown() {
        setOnline(false)
    }
    
    func simulateNetworkRecovery() {
        setOnline(true)
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() async {
        // Mock monitoring is a no-op
    }
}
