//
//  SSEEventParser.swift
//  swiftwing
//
//  Created by Claude Code on 2026-02-02.
//

import Foundation

/// Parses Server-Sent Events (SSE) from Talaria API
///
/// Testable, stateless parser for SSE event/data pairs. Decodes JSON payloads
/// into strongly-typed SSEEvent enum cases.
///
/// **Supported Events:**
/// - `progress`: Processing progress messages
/// - `result`: Book metadata (BookMetadata)
/// - `complete`/`completed`: Job completion with optional resultsUrl and books
/// - `error`/`failed`: Rich error information (both treated as terminal error events)
/// - `canceled`: Job cancellation
/// - `segmented`: Segmented image preview
/// - `book_progress`: Per-book processing progress
/// - `ping`: SSE keepalive
/// - `enrichment_degraded`: Enrichment fallback notification
/// - Unknown events: Silently ignored for forward compatibility
///
/// **Example:**
/// ```swift
/// let parser = SSEEventParser()
/// let event = try parser.parse(event: "progress", data: #"{"message":"Reading..."}"#)
/// // event == .progress("Reading...")
/// ```
public struct SSEEventParser: Sendable {
    public init() {}

    /// Parse SSE event and data into SSEEvent
    ///
    /// - Parameters:
    ///   - event: Event type string (e.g., "progress", "result")
    ///   - data: JSON data string
    /// - Returns: Parsed SSEEvent
    /// - Throws: SSEError.invalidEventFormat on parse failures
    public func parse(event: String, data: String) throws -> SSEEvent {
        switch event {
        case "progress":
            // Progress event with optional message field
            if let jsonData = data.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                let message = json["message"] as? String
                    ?? json["stage"] as? String
                    ?? "Processing..."
                return .progress(message)
            } else {
                return .progress("Processing...")
            }

        case "result":
            // Result event with book metadata nested under "book" key
            // Server sends: { jobId, status, message, progress, book: { title, author, isbn, ... } }
            guard let jsonData = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let bookDict = json["book"] as? [String: Any],
                  let bookData = try? JSONSerialization.data(withJSONObject: bookDict)
            else {
                throw SSEError.invalidEventFormat
            }

            let decoder = JSONDecoder()
            let metadata = try decoder.decode(BookMetadata.self, from: bookData)

            return .result(metadata)

        case "complete", "completed":
            // Extract resultsUrl and optional books from completion event
            guard let jsonData = data.data(using: .utf8) else {
                return .complete(resultsUrl: nil, books: nil)
            }

            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                let resultsUrl = json["resultsUrl"] as? String

                // Try to decode inline books array if present
                var books: [BookMetadata]?
                if let booksArray = json["books"] as? [[String: Any]] {
                    let decoder = JSONDecoder()
                    if let booksData = try? JSONSerialization.data(withJSONObject: booksArray),
                       let decodedBooks = try? decoder.decode([BookMetadata].self, from: booksData) {
                        books = decodedBooks
                    }
                }

                if let resultsUrl = resultsUrl {
                    print("✅ SSE: Completed with results at: \(resultsUrl)")
                }
                return .complete(resultsUrl: resultsUrl, books: books)
            } else {
                print("⚠️ SSE: Completed without resultsUrl or books")
                return .complete(resultsUrl: nil, books: nil)
            }

        case "error", "failed":
            // Error/failed event with rich context
            // Talaria sends "error" for retryable errors and "failed" as a terminal event
            if let jsonData = data.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                // "failed" events may nest error info under "error" key
                let errorObj = json["error"] as? [String: Any]
                let message = errorObj?["message"] as? String
                    ?? json["message"] as? String
                    ?? "Unknown error"
                let code = errorObj?["code"] as? String
                    ?? json["code"] as? String
                let retryable = json["retryable"] as? Bool
                let jobId = json["jobId"] as? String
                return .error(SSEErrorInfo(
                    message: message,
                    code: code,
                    retryable: retryable,
                    jobId: jobId
                ))
            } else {
                return .error(SSEErrorInfo(
                    message: "Unknown error",
                    code: nil,
                    retryable: false,
                    jobId: nil
                ))
            }

        case "canceled":
            return .canceled

        case "segmented":
            // NEW: Segmented image preview
            guard let jsonData = data.data(using: .utf8) else {
                throw SSEError.invalidEventFormat
            }
            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            guard let imageBase64 = json?["image"] as? String,
                  let imageData = Data(base64Encoded: imageBase64),
                  let totalBooks = json?["totalBooks"] as? Int else {
                throw SSEError.invalidEventFormat
            }
            return .segmented(SegmentedPreview(imageData: imageData, totalBooks: totalBooks))

        case "book_progress":
            // NEW: Per-book processing progress
            guard let jsonData = data.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let current = json["current"] as? Int,
                  let total = json["total"] as? Int else {
                throw SSEError.invalidEventFormat
            }
            let stage = json["stage"] as? String
            return .bookProgress(BookProgressInfo(current: current, total: total, stage: stage))

        case "ping":
            // SSE keepalive ping
            return .ping

        case "enrichment_degraded":
            // Enrichment degradation event
            guard let jsonData = data.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw SSEError.invalidEventFormat
            }
            let jobId = json["jobId"] as? String
            let isbn = json["isbn"] as? String
            let title = json["title"] as? String
            let reason = json["reason"] as? String
            let fallbackSource = json["fallbackSource"] as? String
            let timestamp = json["timestamp"] as? String
            return .enrichmentDegraded(EnrichmentDegradedInfo(
                jobId: jobId,
                isbn: isbn,
                title: title,
                reason: reason,
                fallbackSource: fallbackSource,
                timestamp: timestamp
            ))

        default:
            // Forward compatibility: silently ignore unknown event types
            // This ensures older app versions don't crash when backend adds new events
            print("SSE: Unknown event type '\(event)' - skipping for forward compatibility")
            return .ping  // Treat unknown events as no-ops (ping is the lightest event)
        }
    }
}
