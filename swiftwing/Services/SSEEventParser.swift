//
//  SSEEventParser.swift
//  swiftwing
//
//  Created by Claude Code on 2026-02-02.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "sse-parser")

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
/// // event == .progress(ProgressInfo(message: "Reading...", ...))
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
            // Progress event with rich progress data
            if let jsonData = data.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                let message = json["message"] as? String
                    ?? json["stage"] as? String
                    ?? "Processing..."
                let progress = json["progress"] as? Double
                let processedCount = json["processedCount"] as? Int
                let totalCount = json["totalCount"] as? Int
                return .progress(ProgressInfo(
                    message: message,
                    progress: progress,
                    processedCount: processedCount,
                    totalCount: totalCount
                ))
            } else {
                return .progress(ProgressInfo(message: "Processing...", progress: nil, processedCount: nil, totalCount: nil))
            }

        case "result":
            // Result event with book metadata
            // Talaria may send book data in two formats:
            //   1. Nested: { jobId, status, book: { title, author, isbn, ... } }
            //   2. Flat:   { title, author, isbn, coverUrl, ... }
            guard let jsonData = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else {
                throw SSEError.invalidEventFormat
            }

            let decoder = JSONDecoder()

            // Try nested "book" key first (legacy format)
            if let bookDict = json["book"] as? [String: Any],
               let bookData = try? JSONSerialization.data(withJSONObject: bookDict) {
                let metadata = try decoder.decode(BookMetadata.self, from: bookData)
                return .result(metadata)
            }

            // Fall back to flat format (current API per OpenAPI spec)
            let metadata = try decoder.decode(BookMetadata.self, from: jsonData)
            return .result(metadata)

        case "complete", "completed":
            // Talaria SSE event name is "completed" but the JSON type field is "complete".
            // Both are handled here for robustness.
            // Extract resultsUrl, optional books, summary stats, and duration from completion event
            guard let jsonData = data.data(using: .utf8) else {
                return .complete(resultsUrl: nil, books: nil, summary: nil, duration: nil, truncation: nil)
            }

            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                let resultsUrl = json["resultsUrl"] as? String

                // Decode inline books
                var books: [BookMetadata]?
                if let booksArray = json["books"] as? [[String: Any]] {
                    let decoder = JSONDecoder()
                    if let booksData = try? JSONSerialization.data(withJSONObject: booksArray),
                       let decodedBooks = try? decoder.decode([BookMetadata].self, from: booksData) {
                        books = decodedBooks
                    }
                }

                // Extract summary stats (top-level fields + nested summary dict)
                var summary: ScanSummary?
                let nestedSummary = json["summary"] as? [String: Any]

                // Top-level fields are primary (new Talaria format).
                // Nested summary dict fields are fallback (legacy format).
                // Remove nested fallbacks after Swiftwing 1.1 ships.
                let totalDetected = json["totalDetected"] as? Int ?? nestedSummary?["totalDetected"] as? Int
                let totalUnique = json["totalUnique"] as? Int ?? nestedSummary?["totalUnique"] as? Int

                if let totalDetected, let totalUnique {
                    summary = ScanSummary(
                        totalDetected: totalDetected,
                        totalUnique: totalUnique,
                        approved: json["approved"] as? Int ?? nestedSummary?["approved"] as? Int ?? 0,
                        needsReview: json["needsReview"] as? Int ?? nestedSummary?["needsReview"] as? Int ?? 0,
                        reviewNeeded: nestedSummary?["review_needed"] as? Int,
                        degradedCount: nestedSummary?["degraded_count"] as? Int
                    )
                }

                // Extract duration
                var duration: ScanDuration?
                if let durationDict = json["duration"] as? [String: Any] {
                    duration = ScanDuration(
                        totalMs: durationDict["totalMs"] as? Int,
                        uploadMs: durationDict["uploadMs"] as? Int,
                        geminiMs: durationDict["geminiMs"] as? Int,
                        enrichmentMs: durationDict["enrichmentMs"] as? Int,
                        cleanupMs: durationDict["cleanupMs"] as? Int
                    )
                }

                // Extract truncation metadata
                var truncation: TruncationMetadata?
                if let metadataDict = json["metadata"] as? [String: Any] {
                    let truncationSuspected = metadataDict["truncation_suspected"] as? Bool ?? false
                    let outputTruncated = metadataDict["output_truncated"] as? Bool ?? false
                    if truncationSuspected || outputTruncated {
                        truncation = TruncationMetadata(
                            truncationSuspected: truncationSuspected,
                            outputTruncated: outputTruncated
                        )
                    }
                }

                if let resultsUrl = resultsUrl {
                    logger.info("SSE: Completed with results at: \(resultsUrl, privacy: .public)")
                }
                return .complete(resultsUrl: resultsUrl, books: books, summary: summary, duration: duration, truncation: truncation)
            } else {
                logger.debug("SSE: Completed without resultsUrl or books")
                return .complete(resultsUrl: nil, books: nil, summary: nil, duration: nil, truncation: nil)
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
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            guard let imageBase64 = json?["image"] as? String,
                  let imageData = Data(base64Encoded: imageBase64),
                  let totalBooks = json?["totalBooks"] as? Int else {
                throw SSEError.invalidEventFormat
            }
            return .segmented(SegmentedPreview(imageData: imageData, totalBooks: totalBooks))

        case "book_progress":
            // NEW: Per-book processing progress
            guard let jsonData = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
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
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
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
            // Forward compatibility: unknown event types are silently ignored.
            // Throw a dedicated error so the caller can skip without yielding a fake event.
            // TalariaService catches SSEError.unknownEvent and continues the stream.
            logger.debug("SSE: Unknown event type '\(event, privacy: .public)' - ignoring for forward compatibility")
            throw SSEError.unknownEvent(event)
        }
    }
}
