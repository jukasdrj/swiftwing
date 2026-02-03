#!/usr/bin/env swift

import Foundation

/// Test script to verify Talaria backend integration with real API
/// Tests the complete workflow: upload → SSE streaming → results

struct BookMetadata: Codable {
    let title: String
    let author: String
    let isbn: String?
    let confidence: Double?
}

struct UploadResponse: Codable {
    let success: Bool
    let data: UploadData

    struct UploadData: Codable {
        let jobId: String
        let sseUrl: String
        let authToken: String?
        let statusUrl: URL?
    }
}

struct SSEEvent {
    let event: String
    let data: String
}

class TalariaBackendTest {
    let baseURL = "https://api.oooefam.net"
    let deviceId = UUID().uuidString  // Must be valid UUID v4

    func runTest() async throws {
        print("📱 SwiftWing Talaria Backend Test")
        print("=" * 50)
        print("")

        // Step 1: Load test image
        print("📸 Step 1: Loading test image...")
        let imagePath = "/Users/juju/dev_repos/swiftwing/test_book_stack.jpg"
        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: imagePath)) else {
            print("❌ Failed to load image from: \(imagePath)")
            return
        }
        print("✅ Loaded image: \(imageData.count) bytes")
        print("")

        // Step 2: Upload to Talaria
        print("🚀 Step 2: Uploading to Talaria...")
        let (jobId, streamUrl, authToken) = try await uploadScan(imageData: imageData)
        print("✅ Upload successful!")
        print("   Job ID: \(jobId)")
        print("   Stream URL: \(streamUrl)")
        print("   Auth Token: \(authToken ?? "none")")
        print("")

        // Step 3: Stream SSE events
        print("📡 Step 3: Streaming SSE events...")
        print("-" * 50)
        var receivedEvents: [SSEEvent] = []
        var resultBooks: [BookMetadata] = []
        var completeBooks: [BookMetadata] = []

        try await streamEvents(streamUrl: streamUrl, authToken: authToken) { event in
            receivedEvents.append(event)

            switch event.event {
            case "progress":
                print("⏳ Progress: \(event.data)")

            case "result":
                print("📚 Result event received:")
                if let book = try? JSONDecoder().decode(BookMetadata.self, from: event.data.data(using: .utf8)!) {
                    resultBooks.append(book)
                    print("   Title: \(book.title)")
                    print("   Author: \(book.author)")
                    print("   ISBN: \(book.isbn ?? "none")")
                    print("   Confidence: \(book.confidence.map { "\(Int($0 * 100))%" } ?? "none")")
                }

            case "complete":
                print("✅ Complete event received")
                if !event.data.isEmpty, let jsonData = event.data.data(using: .utf8) {
                    if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let books = json["books"] as? [[String: Any]] {
                        print("   Inline books count: \(books.count)")
                        completeBooks = books.compactMap { dict in
                            guard let title = dict["title"] as? String,
                                  let author = dict["author"] as? String else { return nil }
                            return BookMetadata(
                                title: title,
                                author: author,
                                isbn: dict["isbn"] as? String,
                                confidence: dict["confidence"] as? Double
                            )
                        }
                    }
                }

            case "error":
                print("❌ Error event: \(event.data)")

            case "ping":
                print("💓 Ping (keepalive)")

            default:
                print("❓ Unknown event: \(event.event) - \(event.data)")
            }
        }

        print("-" * 50)
        print("")

        // Step 4: Analysis
        print("📊 Step 4: Results Analysis")
        print("=" * 50)
        print("")

        print("📈 Event Summary:")
        print("   Total events received: \(receivedEvents.count)")
        print("   .result events: \(receivedEvents.filter { $0.event == "result" }.count)")
        print("   .complete events: \(receivedEvents.filter { $0.event == "complete" }.count)")
        print("   .progress events: \(receivedEvents.filter { $0.event == "progress" }.count)")
        print("   .ping events: \(receivedEvents.filter { $0.event == "ping" }.count)")
        print("   .error events: \(receivedEvents.filter { $0.event == "error" }.count)")
        print("")

        print("📚 Books Received:")
        print("   Via .result events: \(resultBooks.count)")
        print("   Via .complete event: \(completeBooks.count)")
        print("")

        // Test Fix #1: Deduplication
        print("🔍 Fix #1 Test: Deduplication Needed?")
        if resultBooks.count > 0 && completeBooks.count > 0 {
            print("   ⚠️ YES - Both .result and .complete sent books")
            print("   Deduplication guard is CRITICAL")
            print("   Without it, \(resultBooks.count) books would appear twice")
        } else if resultBooks.count > 0 {
            print("   ℹ️ Only .result events sent books")
            print("   Deduplication guard is DEFENSIVE (good to have)")
        } else if completeBooks.count > 0 {
            print("   ℹ️ Only .complete event sent books")
            print("   Deduplication guard is DEFENSIVE (good to have)")
        } else {
            print("   ⚠️ No books received at all!")
        }
        print("")

        // Test Fix #3: Metadata Validation
        print("🔍 Fix #3 Test: Metadata Quality")
        let allBooks = resultBooks + completeBooks
        let emptyTitles = allBooks.filter { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let emptyAuthors = allBooks.filter { $0.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let lowConfidence = allBooks.filter { ($0.confidence ?? 1.0) < 0.3 }

        if emptyTitles.count > 0 {
            print("   ⚠️ Found \(emptyTitles.count) books with empty titles")
            print("   Validation guard would REJECT these")
        } else {
            print("   ✅ All books have valid titles")
        }

        if emptyAuthors.count > 0 {
            print("   ⚠️ Found \(emptyAuthors.count) books with empty authors")
            print("   Validation guard would REJECT these")
        } else {
            print("   ✅ All books have valid authors")
        }

        if lowConfidence.count > 0 {
            print("   ⚠️ Found \(lowConfidence.count) books with low confidence (<30%)")
            print("   Validation guard would WARN but ALLOW these")
            lowConfidence.forEach { book in
                print("      - \(book.title): \(Int((book.confidence ?? 0) * 100))%")
            }
        } else {
            print("   ✅ All books have acceptable confidence")
        }
        print("")

        // Book Details
        print("📖 Book Details (deduplicated):")
        let uniqueBooks = Set(allBooks.map { "\($0.title)|\($0.author)" })
        for (index, bookKey) in uniqueBooks.enumerated() {
            let parts = bookKey.split(separator: "|")
            if let book = allBooks.first(where: { "\($0.title)|\($0.author)" == bookKey }) {
                print("   \(index + 1). \(book.title)")
                print("      Author: \(book.author)")
                print("      ISBN: \(book.isbn ?? "none")")
                print("      Confidence: \(book.confidence.map { "\(Int($0 * 100))%" } ?? "none")")
                print("")
            }
        }

        print("=" * 50)
        print("✅ Test Complete!")
    }

    func uploadScan(imageData: Data) async throws -> (jobId: String, streamUrl: String, authToken: String?) {
        let url = URL(string: "\(baseURL)/v3/jobs/scans")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")

        var body = Data()

        // Image field (API expects photos[] for batch upload support)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photos[]\"; filename=\"book_stack.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "TalariaTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 202 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            throw NSError(domain: "TalariaTest", code: httpResponse.statusCode,
                         userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(errorBody)"])
        }

        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)

        guard uploadResponse.success else {
            throw NSError(domain: "TalariaTest", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Upload failed: success=false"])
        }

        return (uploadResponse.data.jobId, uploadResponse.data.sseUrl, uploadResponse.data.authToken)
    }

    func streamEvents(streamUrl: String, authToken: String?, handler: (SSEEvent) async -> Void) async throws {
        print("🔌 Connecting to SSE stream...")
        print("   URL: \(streamUrl)")
        print("   Device ID: \(deviceId)")
        print("   Auth Token: \(authToken?.prefix(20) ?? "none")...")

        var request = URLRequest(url: URL(string: streamUrl)!)
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "TalariaTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid SSE response"])
        }

        print("✅ SSE connection established")
        print("   Status: \(httpResponse.statusCode)")
        print("   Headers: \(httpResponse.allHeaderFields)")
        print("")

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "TalariaTest", code: httpResponse.statusCode,
                         userInfo: [NSLocalizedDescriptionKey: "SSE HTTP \(httpResponse.statusCode)"])
        }

        var currentEvent = ""
        var currentData = ""
        var isComplete = false
        var lineCount = 0

        for try await line in bytes.lines {
            lineCount += 1
            print("📥 Line \(lineCount): \(line.isEmpty ? "<empty>" : line)")

            if isComplete {
                print("🏁 Stream complete, stopping...")
                break
            }

            if line.isEmpty {
                // End of event
                if !currentEvent.isEmpty {
                    print("📦 Dispatching event: \(currentEvent)")
                    let event = SSEEvent(event: currentEvent, data: currentData)
                    await handler(event)

                    if currentEvent == "complete" || currentEvent == "error" {
                        isComplete = true
                    }
                }
                currentEvent = ""
                currentData = ""
            } else if line.hasPrefix("event:") {
                currentEvent = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if !currentData.isEmpty {
                    currentData += "\n"
                }
                currentData += data
            }
        }

        print("📡 SSE stream ended naturally (line count: \(lineCount))")
    }
}

// String repetition operator
func * (string: String, count: Int) -> String {
    String(repeating: string, count: count)
}

// Run test
Task {
    do {
        let test = TalariaBackendTest()
        try await test.runTest()
    } catch {
        print("❌ Test failed: \(error)")
        print("   Error details: \(error.localizedDescription)")
    }
    exit(0)
}

// Keep the script running
RunLoop.main.run()
