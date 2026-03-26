import Foundation
import Testing
@testable import swiftwing

// MARK: - Test Error

private enum SSETestError: Error {
    case unexpectedEvent
}

@Suite("SSEEventParser")
struct SSEEventParserTests {
    let parser = SSEEventParser()

    // MARK: - Enum Extraction Helpers (4G)

    private func requireProgress(_ event: SSEEvent, sourceLocation: SourceLocation = #_sourceLocation) throws -> ProgressInfo {
        guard case .progress(let info) = event else {
            Issue.record("Expected progress event, got \(event)", sourceLocation: sourceLocation)
            throw SSETestError.unexpectedEvent
        }
        return info
    }

    private func requireResult(_ event: SSEEvent, sourceLocation: SourceLocation = #_sourceLocation) throws -> BookMetadata {
        guard case .result(let metadata) = event else {
            Issue.record("Expected result event, got \(event)", sourceLocation: sourceLocation)
            throw SSETestError.unexpectedEvent
        }
        return metadata
    }

    private func requireBookProgress(_ event: SSEEvent, sourceLocation: SourceLocation = #_sourceLocation) throws -> BookProgressInfo {
        guard case .bookProgress(let info) = event else {
            Issue.record("Expected bookProgress event, got \(event)", sourceLocation: sourceLocation)
            throw SSETestError.unexpectedEvent
        }
        return info
    }

    private func requireEnrichmentDegraded(_ event: SSEEvent, sourceLocation: SourceLocation = #_sourceLocation) throws -> EnrichmentDegradedInfo {
        guard case .enrichmentDegraded(let info) = event else {
            Issue.record("Expected enrichmentDegraded event, got \(event)", sourceLocation: sourceLocation)
            throw SSETestError.unexpectedEvent
        }
        return info
    }

    private func requireSegmented(_ event: SSEEvent, sourceLocation: SourceLocation = #_sourceLocation) throws -> SegmentedPreview {
        guard case .segmented(let preview) = event else {
            Issue.record("Expected segmented event, got \(event)", sourceLocation: sourceLocation)
            throw SSETestError.unexpectedEvent
        }
        return preview
    }

    // MARK: - Existing Event Tests

    @Test func parseProgressEvent() throws {
        let data = """
        {"message": "Analyzing spine...", "progress": 0.35, "processedCount": 1, "totalCount": 3}
        """
        let event = try parser.parse(event: "progress", data: data)
        let info = try requireProgress(event)
        #expect(info.message == "Analyzing spine...")
        #expect(info.progress == 0.35)
        #expect(info.processedCount == 1)
        #expect(info.totalCount == 3)
    }

    @Test func parsePingEvent() throws {
        let event = try parser.parse(event: "ping", data: "{}")
        guard case .ping = event else {
            Issue.record("Expected ping event")
            return
        }
    }

    @Test func parseResultEvent() throws {
        let data = """
        {"title": "The Swift Programming Language", "author": "Apple Inc.", "isbn": "9781234567890"}
        """
        let event = try parser.parse(event: "result", data: data)
        let metadata = try requireResult(event)
        #expect(metadata.resolvedTitle == "The Swift Programming Language")
        #expect(metadata.author == "Apple Inc.")
        #expect(metadata.isbn == "9781234567890")
    }

    @Test func parseResultEventNestedBookFormat() throws {
        let data = """
        {"book": {"title": "Clean Code", "author": "Robert C. Martin", "isbn": "9780132350884"}}
        """
        let event = try parser.parse(event: "result", data: data)
        let metadata = try requireResult(event)
        #expect(metadata.resolvedTitle == "Clean Code")
    }

    @Test func parseCompletedEvent() throws {
        let data = """
        {"totalDetected": 3, "totalUnique": 3, "books": []}
        """
        let event = try parser.parse(event: "completed", data: data)
        guard case .complete = event else {
            Issue.record("Expected complete event")
            return
        }
    }

    @Test func parseCompleteEventAlias() throws {
        let data = """
        {"totalDetected": 1, "totalUnique": 1, "books": []}
        """
        let event = try parser.parse(event: "complete", data: data)
        guard case .complete = event else {
            Issue.record("Expected complete event")
            return
        }
    }

    @Test func parseErrorEvent() throws {
        let data = """
        {"message": "Processing failed", "code": "INTERNAL_ERROR", "retryable": false}
        """
        let event = try parser.parse(event: "error", data: data)
        guard case .error(let errorInfo) = event else {
            Issue.record("Expected error event")
            return
        }
        #expect(errorInfo.message == "Processing failed")
        #expect(errorInfo.code == "INTERNAL_ERROR")
        #expect(errorInfo.retryable == false)
    }

    @Test func parseFailedEventAlias() throws {
        let data = """
        {"message": "Job terminated", "code": "TIMEOUT", "retryable": true}
        """
        let event = try parser.parse(event: "failed", data: data)
        guard case .error(let errorInfo) = event else {
            Issue.record("Expected error event for 'failed' event type")
            return
        }
        #expect(errorInfo.message == "Job terminated")
        #expect(errorInfo.retryable == true)
    }

    @Test func parseCanceledEvent() throws {
        let event = try parser.parse(event: "canceled", data: "{}")
        guard case .canceled = event else {
            Issue.record("Expected canceled event")
            return
        }
    }

    @Test func unknownEventThrowsUnknownEvent() {
        #expect(throws: SSEError.unknownEvent("unknown_future_event")) {
            try parser.parse(event: "unknown_future_event", data: "{}")
        }
    }

    // MARK: - 4A: Missing Event Type Tests (segmented, book_progress, enrichment_degraded)

    @Test func parseSegmentedEvent() throws {
        let imageBytes = Data([0xFF, 0xD8, 0xFF, 0xE0]) // Minimal JPEG header bytes
        let base64Image = imageBytes.base64EncodedString()
        let data = """
        {"image": "\(base64Image)", "totalBooks": 5}
        """
        let event = try parser.parse(event: "segmented", data: data)
        let preview = try requireSegmented(event)
        #expect(preview.imageData == imageBytes)
        #expect(preview.totalBooks == 5)
    }

    @Test func parseBookProgressEvent() throws {
        let data = """
        {"current": 2, "total": 7, "stage": "enriching"}
        """
        let event = try parser.parse(event: "book_progress", data: data)
        let info = try requireBookProgress(event)
        #expect(info.current == 2)
        #expect(info.total == 7)
        #expect(info.stage == "enriching")
    }

    @Test func parseBookProgressEventWithoutStage() throws {
        let data = """
        {"current": 1, "total": 3}
        """
        let event = try parser.parse(event: "book_progress", data: data)
        let info = try requireBookProgress(event)
        #expect(info.current == 1)
        #expect(info.total == 3)
        #expect(info.stage == nil)
    }

    @Test func parseEnrichmentDegradedEvent() throws {
        let data = """
        {"jobId": "job-123", "isbn": "9780132350884", "title": "Clean Code", "reason": "circuit_open", "fallbackSource": "openlibrary", "timestamp": "2026-03-17T10:00:00Z"}
        """
        let event = try parser.parse(event: "enrichment_degraded", data: data)
        let info = try requireEnrichmentDegraded(event)
        #expect(info.jobId == "job-123")
        #expect(info.isbn == "9780132350884")
        #expect(info.title == "Clean Code")
        #expect(info.reason == "circuit_open")
        #expect(info.fallbackSource == "openlibrary")
        #expect(info.timestamp == "2026-03-17T10:00:00Z")
    }

    @Test func parseEnrichmentDegradedEventWithMinimalFields() throws {
        let data = """
        {"reason": "timeout"}
        """
        let event = try parser.parse(event: "enrichment_degraded", data: data)
        let info = try requireEnrichmentDegraded(event)
        #expect(info.jobId == nil)
        #expect(info.isbn == nil)
        #expect(info.reason == "timeout")
    }

    // MARK: - 4B: Error Path Tests

    @Test func parseResultEventMalformedJSONThrows() {
        #expect(throws: SSEError.invalidEventFormat) {
            try parser.parse(event: "result", data: "not json {{{")
        }
    }

    @Test func parseSegmentedEventMissingImageThrows() {
        // Missing required "image" field
        #expect(throws: SSEError.invalidEventFormat) {
            try parser.parse(event: "segmented", data: #"{"totalBooks": 3}"#)
        }
    }

    @Test func parseSegmentedEventInvalidBase64Throws() {
        // image field is not valid base64
        #expect(throws: SSEError.invalidEventFormat) {
            try parser.parse(event: "segmented", data: #"{"image": "not!!valid##base64", "totalBooks": 2}"#)
        }
    }

    @Test func parseSegmentedEventMissingTotalBooksThrows() {
        let base64Image = Data([0x00]).base64EncodedString()
        #expect(throws: SSEError.invalidEventFormat) {
            try parser.parse(event: "segmented", data: #"{"image": "\#(base64Image)"}"#)
        }
    }

    @Test func parseSegmentedEventMalformedJSONThrows() {
        #expect(throws: SSEError.invalidEventFormat) {
            try parser.parse(event: "segmented", data: "not json")
        }
    }

    @Test func parseBookProgressEventMissingCurrentThrows() {
        #expect(throws: SSEError.invalidEventFormat) {
            try parser.parse(event: "book_progress", data: #"{"total": 5}"#)
        }
    }

    @Test func parseBookProgressEventMissingTotalThrows() {
        #expect(throws: SSEError.invalidEventFormat) {
            try parser.parse(event: "book_progress", data: #"{"current": 1}"#)
        }
    }

    @Test func parseBookProgressEventMalformedJSONThrows() {
        #expect(throws: SSEError.invalidEventFormat) {
            try parser.parse(event: "book_progress", data: "not json")
        }
    }

    @Test func parseEnrichmentDegradedEventMalformedJSONThrows() {
        #expect(throws: SSEError.invalidEventFormat) {
            try parser.parse(event: "enrichment_degraded", data: "not json {{{")
        }
    }

    // MARK: - 4C: Rate Limit Error Path Test

    @Test func parseErrorEventRateLimitPath() throws {
        // Test error path: rate limit (429) with retry information
        let data = """
        {"message": "Too many requests", "code": "RATE_LIMITED", "retryable": true, "retryAfterMs": 5000}
        """
        let event = try parser.parse(event: "error", data: data)
        guard case .error(let errorInfo) = event else {
            Issue.record("Expected error event with rate limit info")
            return
        }
        #expect(errorInfo.message == "Too many requests")
        #expect(errorInfo.code == "RATE_LIMITED")
        #expect(errorInfo.retryable == true)
    }
}
