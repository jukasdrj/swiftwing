import Foundation

/// Sample SSE events for testing stream parsing and event handling.
enum SampleSSEEvents {
    
    // MARK: - Individual Events
    
    static let progressEvent = SSEEvent(
        type: "progress",
        data: """
        {
          "message": "Processing page 1 of 5",
          "progress": 0.2,
          "processedCount": 1,
          "totalCount": 5
        }
        """
    )
    
    static let bookResultEvent1 = SSEEvent(
        type: "result",
        data: """
        {
          "title": "The Swift Programming Language",
          "authors": ["Apple Inc."],
          "isbn": "978-1491927281",
          "confidence": 0.95,
          "processingStage": "enrichment"
        }
        """
    )
    
    static let bookResultEvent2 = SSEEvent(
        type: "result",
        data: """
        {
          "title": "Clean Code",
          "authors": ["Robert C. Martin"],
          "isbn": "978-0132350884",
          "confidence": 0.87,
          "processingStage": "enrichment"
        }
        """
    )
    
    static let completionEvent = SSEEvent(
        type: "completed",
        data: """
        {
          "totalDetected": 2,
          "books": [
            {
              "title": "The Swift Programming Language",
              "authors": ["Apple Inc."],
              "isbn": "978-1491927281",
              "confidence": 0.95,
              "processingStage": "enrichment"
            },
            {
              "title": "Clean Code",
              "authors": ["Robert C. Martin"],
              "isbn": "978-0132350884",
              "confidence": 0.87,
              "processingStage": "enrichment"
            }
          ],
          "duration": {
            "totalMs": 2500,
            "uploadMs": 400,
            "processingMs": 2100
          }
        }
        """
    )
    
    static let enrichmentDegradedEvent = SSEEvent(
        type: "enrichment_degraded",
        data: """
        {
          "message": "Enrichment service degraded",
          "status": "circuitOpen"
        }
        """
    )
    
    static let errorEvent = SSEEvent(
        type: "error",
        data: """
        {
          "error": "Processing timeout",
          "code": "PROCESSING_TIMEOUT",
          "retryable": true,
          "retryAfterMs": 5000
        }
        """
    )
    
    // MARK: - Event Sequences
    
    /// Standard happy path: progress → result × 2 → completion
    static let happyPathSequence: [SSEEvent] = [
        progressEvent,
        bookResultEvent1,
        bookResultEvent2,
        completionEvent
    ]
    
    /// With enrichment degradation
    static let degradedSequence: [SSEEvent] = [
        progressEvent,
        bookResultEvent1,
        enrichmentDegradedEvent,
        completionEvent
    ]
    
    /// With recoverable error
    static let errorRecoverySequence: [SSEEvent] = [
        progressEvent,
        errorEvent
        // In real scenario, would retry and continue
    ]
    
    /// Empty result (no books detected)
    static let emptyResultSequence: [SSEEvent] = [
        SSEEvent(
            type: "completed",
            data: """
            {
              "totalDetected": 0,
              "books": [],
              "duration": {
                "totalMs": 1200,
                "uploadMs": 300,
                "processingMs": 900
              }
            }
            """
        )
    ]
}
