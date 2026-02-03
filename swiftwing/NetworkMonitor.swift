import Foundation
import Network

/// Monitors network connectivity using NWPathMonitor
/// Adaptable to Swift Concurrency via AsyncStream
@MainActor
@Observable
final class NetworkMonitor: Sendable {

    // MARK: - Published State

    /// Current network availability status
    /// Observed by UI to show offline indicator and handle queued scans
    private(set) var isConnected: Bool = true

    // MARK: - Private Properties

    private let monitor = NWPathMonitor()

    // MARK: - Initialization

    init() {
        // Start monitoring immediately upon init
        startMonitoring()
    }

    private func startMonitoring() {
        // Create an AsyncStream to bridge the callback-based NWPathMonitor
        let statusStream = AsyncStream<Bool> { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            // Use a dedicated serial queue for the monitor as required by NWPathMonitor
            let queue = DispatchQueue(label: "com.ooheynerds.swiftwing.networkmonitor")
            monitor.start(queue: queue)

            // Handle termination if needed (stream cancellation)
            continuation.onTermination = { [weak monitor] _ in
                monitor?.cancel()
            }
        }

        // Consume the stream
        Task {
            for await status in statusStream {
                updateStatus(status)
            }
        }
    }

    private func updateStatus(_ nowConnected: Bool) {
        let wasConnected = self.isConnected
        self.isConnected = nowConnected

        if wasConnected != nowConnected {
            if nowConnected {
                print("📡 Network connected - ready to upload queued scans")
            } else {
                print("📡 Network disconnected - offline mode active")
            }
        }
    }

    deinit {
        monitor.cancel()
    }
}
