import Testing
@testable import swiftwing

struct SSEEventParserTests {
    let parser = SSEEventParser()

    @Test func parseProgressEvent() throws {
        let data = """
        {"message": "Analyzing spine...", "progress": 0.35, "processedCount": 1, "totalCount": 3}
        """
        let event = try parser.parse(event: "progress", data: data)
        guard case .progress(let info) = event else {
            Issue.record("Expected progress event")
            return
        }
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
        guard case .result(let metadata) = event else {
            Issue.record("Expected result event")
            return
        }
        #expect(metadata.resolvedTitle == "The Swift Programming Language")
        #expect(metadata.author == "Apple Inc.")
        #expect(metadata.isbn == "9781234567890")
    }

    @Test func parseResultEventNestedBookFormat() throws {
        let data = """
        {"book": {"title": "Clean Code", "author": "Robert C. Martin", "isbn": "9780132350884"}}
        """
        let event = try parser.parse(event: "result", data: data)
        guard case .result(let metadata) = event else {
            Issue.record("Expected result event")
            return
        }
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
}
