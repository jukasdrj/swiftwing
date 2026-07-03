import Foundation
import Testing
@testable import swiftwing

/// Serves a scripted sequence of HTTP responses, one per intercepted request.
/// Static state is guarded by a lock and the suite runs `.serialized`, so
/// Swift Testing's default parallelism can't interleave sequences.
final class SequencedURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var responses: [(status: Int, body: Data)] = []
    nonisolated(unsafe) private(set) static var requestCount = 0
    private static let lock = NSLock()

    static func script(_ sequence: [(status: Int, body: Data)]) {
        lock.lock()
        responses = sequence
        requestCount = 0
        lock.unlock()
    }

    static func recordedRequestCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let index = Self.requestCount
        Self.requestCount += 1
        let response = index < Self.responses.count ? Self.responses[index] : Self.responses.last
        Self.lock.unlock()

        guard let response, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let http = HTTPURLResponse(
            url: url,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Pins the poll loop's resilience contract (S3): transient blips are absorbed
/// up to the consecutive-failure budget, results fetches have their own budget
/// (a 200 status must not re-arm it), and terminal outcomes propagate at once.
@Suite(.serialized) struct PollScanStatusResilienceTests {
    private static let jobId = "990e8400-e29b-41d4-a716-446655440004"

    private func makeService() -> TalariaService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SequencedURLProtocol.self]
        return TalariaService(deviceId: "test-device", session: URLSession(configuration: configuration))
    }

    private func statusBody(_ status: String) -> Data {
        Data("""
        {"success": true, "data": {"jobId": "\(Self.jobId)", "status": "\(status)", "progress": 0.5}}
        """.utf8)
    }

    private var resultsBody: Data {
        Data(TalariaContractFixtures.scanResultsTopLevelEnrichmentJSON.utf8)
    }

    @Test func transientBlipsAreAbsorbedAndScanSucceeds() async throws {
        SequencedURLProtocol.script([
            (500, Data()),
            (200, statusBody("processing")),
            (500, Data()),
            (404, Data()),
            (200, statusBody("completed")),
            (200, resultsBody),
        ])
        let books = try await makeService().pollScanStatus(jobId: Self.jobId)
        #expect(books.count == 1)
        #expect(books.first?.title == "The Great Gatsby")
        #expect(SequencedURLProtocol.recordedRequestCount() == 6)
    }

    @Test func fiveConsecutiveTransientFailuresExhaustTheBudget() async {
        SequencedURLProtocol.script([(500, Data())])
        do {
            _ = try await makeService().pollScanStatus(jobId: Self.jobId)
            Issue.record("expected serverError after the transient budget is spent")
        } catch let error as NetworkError {
            guard case .serverError(let code) = error else {
                Issue.record("expected serverError, got \(error)")
                return
            }
            #expect(code == 500)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        // budget of 4 consecutive failures -> the 5th throws
        #expect(SequencedURLProtocol.recordedRequestCount() == 5)
    }

    @Test func failedStatusThrowsScanFailedImmediately() async {
        SequencedURLProtocol.script([
            (200, Data(TalariaContractFixtures.jobStatusFailedWithErrorJSON.utf8))
        ])
        do {
            _ = try await makeService().pollScanStatus(jobId: Self.jobId)
            Issue.record("expected scanFailed")
        } catch let error as NetworkError {
            guard case .scanFailed(let code, _) = error else {
                Issue.record("expected scanFailed, got \(error)")
                return
            }
            #expect(code == "IMAGE_QUALITY_LOW")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        // terminal: exactly one request, no retries
        #expect(SequencedURLProtocol.recordedRequestCount() == 1)
    }

    @Test func resultsFetchFailuresHaveTheirOwnBudget() async {
        // status 200 (completed) alternating with failing results fetches:
        // the 200s must NOT re-arm the results budget (the pre-fix bug burned
        // all 75 poll attempts here and surfaced a misleading .timeout).
        var sequence: [(Int, Data)] = []
        for _ in 0..<5 {
            sequence.append((200, statusBody("completed")))
            sequence.append((500, Data()))
        }
        SequencedURLProtocol.script(sequence)
        do {
            _ = try await makeService().pollScanStatus(jobId: Self.jobId)
            Issue.record("expected invalidResponse from the results fetch")
        } catch let error as NetworkError {
            guard case .invalidResponse = error else {
                Issue.record("expected invalidResponse, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        // 5 status reads + 5 results attempts, then the 5th fetch failure throws
        #expect(SequencedURLProtocol.recordedRequestCount() == 10)
    }
}
