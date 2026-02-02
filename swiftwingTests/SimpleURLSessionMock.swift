import XCTest
import Foundation

/// Simple mock for network responses without complex protocol conformance
/// Enables fast, reliable unit testing of services
actor SimpleURLSessionMock {
    private var nextResponse: Result<Data, Error>?
    private var nextStreamEvent: NetworkTypes.SSEEvent?
    private var responseQueue: [NetworkTypes.SSEEvent] = []
    private var eventIndex = 0
    private var latency: TimeInterval = 0.01

    func setResponse(_ response: Result<Data, Error>) {
        nextResponse = response
    }

    func setStreamEvents(_ events: [NetworkTypes.SSEEvent]) {
        responseQueue = events
        eventIndex = 0
    }

    func setLatency(_ seconds: TimeInterval) {
        latency = seconds
    }

    func uploadScan(image: Data, deviceId: String) async throws -> (jobId: String, streamUrl: URL) {
        // Simulate latency
        try await Task.sleep(nanoseconds: UInt64(latency * 1_000_000_000))

        // Return mock response or throw error
        switch nextResponse {
        case .success(let data):
            // Parse mock JSON response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = json["data"] as? [String: Any],
               let jobId = dataDict["jobId"] as? String,
               let sseUrlStr = dataDict["sseUrl"] as? String,
               let sseUrl = URL(string: sseUrlStr) {
                return (jobId, sseUrl)
            }
            throw URLError(.badServerResponse)
        case .failure(let error):
            throw error
        case .none:
            // Default successful mock
            return ("test-job-\(UUID().uuidString)", URL(string: "https://api.oooefam.net/stream/\(UUID().uuidString)")!)
        }
    }

    func streamEvents(from streamUrl: URL) -> AsyncThrowingStream<NetworkTypes.SSEEvent, Error> {
        return AsyncThrowingStream { continuation in
            // Simulate stream events with delay
            Task {
                for _ in 0..<responseQueue.count {
                    try await Task.sleep(nanoseconds: UInt64(latency * 500_000_000)) // 0.5s between events

                    if eventIndex < responseQueue.count {
                        continuation.yield(responseQueue[eventIndex])
                        eventIndex += 1
                    } else {
                        // End of stream
                        continuation.finish()
                    }
                }
            }
        }
    }

    func cleanup(jobId: String) async throws {
        // Mock cleanup - just sleep a bit
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
    }
}
