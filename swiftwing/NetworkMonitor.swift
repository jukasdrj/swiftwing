import Foundation
import Network

/// Monitors network connectivity using NWPathMonitor
/// Thread-safe actor that publishes network status changes
@Observable
final class NetworkMonitor: @unchecked Sendable {

    // MARK: - Published State

    /// Current network availability status
    /// Observed by UI to show offline indicator and handle queued scans
    private(set) var isConnected: Bool = true

    // MARK: - Private Properties

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    // MARK: - Initialization

    init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.ooheynerds.swiftwing.networkmonitor")

        // Start monitoring
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let wasConnected = self.isConnected
            let nowConnected = path.status == .satisfied

            // Update state on main thread for UI observation
            Task { @MainActor in
                self.isConnected = nowConnected

                // Log status changes
                if wasConnected != nowConnected {
                    if nowConnected {
                        print("📡 Network connected - ready to upload queued scans")
                    } else {
                        print("📡 Network disconnected - offline mode active")
                    }
                }
            }
        }

        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
