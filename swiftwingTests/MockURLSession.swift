import XCTest
import Foundation
@testable import swiftwing

/// Mock URLSession for testing without hitting real API
/// Enables deterministic, fast tests without network dependencies
actor MockURLSession: URLSession {
    
    // MARK: - Responses
    
    private var mockResponses: [String: Result<Data, Error>] = [:]
    private var mockErrors: [String: Error] = [:]
    private var mockStreamEvents: [String: [NetworkTypes.SSEEvent]] = [:]
    
    // MARK: - Response Recording
    
    private(set) var lastRequestURL: URL?
    private(set) var lastRequestBody: Data?
    private(set) var lastRequestHeaders: [String: String]?
    private(set) var lastRequestMethod: String?
    
    // MARK: - Configuration
    
    var uploadDelay: TimeInterval = 0.01  // Simulate network latency (10ms)
    var streamDelay: TimeInterval = 0.01
    
    // MARK: - Mock Setup
    
    func mockUploadResponse(data: Data, for endpoint: String) {
        mockResponses[endpoint] = .success(data)
    }
    
    func mockUploadError(_ error: Error, for endpoint: String) {
        mockErrors[endpoint] = error
    }
    
    func mockStreamEvents(_ events: [NetworkTypes.SSEEvent], for streamURL: String) {
        mockStreamEvents[streamURL] = events
    }
    
    func clearMocks() {
        mockResponses.removeAll()
        mockErrors.removeAll()
        mockStreamEvents.removeAll()
        lastRequestURL = nil
        lastRequestBody = nil
        lastRequestHeaders = nil
        lastRequestMethod = nil
    }
    
    // MARK: - URLSession Override
    
    override func dataTask(
        with request: URLRequest,
        completionHandler: @Sendable @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        
        // Record request details for verification
        lastRequestURL = request.url
        lastRequestBody = request.httpBody
        lastRequestHeaders = request.allHTTPHeaderFields as? [String: String]
        lastRequestMethod = request.httpMethod
        
        let url = request.url?.absoluteString ?? ""
        
        // Simulate network latency
        Task {
            try? await Task.sleep(nanoseconds: UInt64(uploadDelay * 1_000_000_000))
            
            // Check for mock error
            if let error = mockErrors[url] {
                completionHandler(nil, nil, error)
                return
            }
            
            // Check for mock data response
            if let data = mockResponses[url] {
                let httpResponse = HTTPURLResponse(
                    url: request.url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "application/json"
                    ]
                )
                completionHandler(data, httpResponse, nil)
                return
            }
            
            // Default: simulate successful upload
            let mockResponse = """
            {
                "success": true,
                "data": {
                    "jobId": "test-job-\\(UUID().uuidString)",
                    "sseUrl": "https://api.oooefam.net/v3/jobs/scans/test-job-\\(UUID().uuidString)/stream",
                    "statusUrl": "https://api.oooefam.net/v3/jobs/scans/test-job-\\(UUID().uuidString)/status",
                    "authToken": "test-token"
                }
            }
            """.data(using: .utf8)!
            
            let httpResponse = HTTPURLResponse(
                url: request.url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json"
                ]
            )
            
            completionHandler(mockResponse, httpResponse, nil)
        }
        
        // Return a mock task
        return MockURLSessionDataTask()
    }
}

// MARK: - Mock Data Task

final class MockURLSessionDataTask: URLSessionDataTask {
    private var resumeHandler: (() -> Void)?
    
    func resume() {
        resumeHandler?()
    }
}
