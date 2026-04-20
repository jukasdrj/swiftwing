import Foundation

/// Mock Talaria service for testing SSE streams and API interactions.
/// Allows configurable responses, delays, and simulated errors.
actor MockTalariaService: Sendable {
    private var uploadDelay: Duration = .milliseconds(0)
    private var shouldFailUpload: Bool = false
    private var uploadError: NetworkError?
    private var sseEvents: [SSEEvent] = []
    private var eventDelay: Duration = .milliseconds(100)
    
    nonisolated let deviceId: String
    
    init(deviceId: String = "test-device-001") {
        self.deviceId = deviceId
    }
    
    // MARK: - Configuration
    
    func setUploadDelay(_ duration: Duration) {
        self.uploadDelay = duration
    }
    
    func setUploadFailure(_ error: NetworkError) {
        self.shouldFailUpload = true
        self.uploadError = error
    }
    
    func setShouldSucceedUpload() {
        self.shouldFailUpload = false
        self.uploadError = nil
    }
    
    func setSSEEvents(_ events: [SSEEvent]) {
        self.sseEvents = events
    }
    
    func setEventDelay(_ duration: Duration) {
        self.eventDelay = duration
    }
    
    // MARK: - API Simulation
    
    func uploadScan(imageData: Data, filename: String) async throws -> (jobId: String, sseUrl: String, authToken: String) {
        if uploadDelay.components.attoseconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(uploadDelay.components.attoseconds / 1_000_000_000))
        }
        
        if shouldFailUpload {
            throw uploadError ?? NetworkError.apiError(ProblemDetails(
                type: "http://example.com/errors/upload-failed",
                title: "Upload Failed",
                status: 500,
                detail: "Mock upload failure"
            ))
        }
        
        let jobId = "test-job-\(UUID().uuidString.prefix(8))"
        let sseUrl = "http://localhost:8080/sse/\(jobId)"
        let authToken = "test-token-\(UUID().uuidString.prefix(16))"
        
        return (jobId, sseUrl, authToken)
    }
    
    func streamEvents(from sseUrl: String, authToken: String, callbacks: ScanJobCallbacks) async throws {
        for event in sseEvents {
            if eventDelay.components.attoseconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(eventDelay.components.attoseconds / 1_000_000_000))
            }
            
            switch event.type {
            case "progress":
                if let progress = try? JSONDecoder().decode(ProgressInfo.self, from: event.data.data(using: .utf8) ?? Data()) {
                    await callbacks.onProgress?(progress)
                }
            case "result":
                if let book = try? JSONDecoder().decode(BookMetadata.self, from: event.data.data(using: .utf8) ?? Data()) {
                    await callbacks.onBookResult?(book)
                }
            case "completed":
                if let summary = try? JSONDecoder().decode(ScanSummary.self, from: event.data.data(using: .utf8) ?? Data()) {
                    await callbacks.onComplete?(summary)
                }
            case "error":
                if let errorInfo = try? JSONDecoder().decode(SSEErrorInfo.self, from: event.data.data(using: .utf8) ?? Data()) {
                    await callbacks.onError?(SSEError(errorInfo: errorInfo))
                }
            default:
                break
            }
        }
    }
    
    func cleanup(jobId: String) async throws {
        // Mock cleanup is a no-op
    }
}
