#!/usr/bin/env swift

import Foundation

/// Manual integration script against live Talaria (3.9.0+).
/// Workflow: upload → HTTP status poll → results (no SSE).
///
/// Usage:
///   swift test_talaria_backend.swift
/// Requires a JPEG at test_book_stack.jpg in the repo root (or set IMAGE_PATH).

struct BookMetadata: Codable {
    let title: String?
    let author: String?
    let isbn: String?
    let confidence: Double?
    let enrichmentStatus: String?
    let coverUrl: String?
}

struct UploadResponse: Codable {
    let success: Bool
    let data: UploadData

    struct UploadData: Codable {
        let jobId: String
        let status: String
    }
}

struct JobStatusResponse: Codable {
    let success: Bool
    let data: JobStatusData

    struct JobStatusData: Codable {
        let jobId: String
        let status: String
        let progress: Double?
        let error: JobError?
    }

    struct JobError: Codable {
        let code: String
        let message: String
    }
}

struct ResultsResponse: Codable {
    let success: Bool
    let data: ResultsData

    struct ResultsData: Codable {
        let jobId: String
        let status: String
        let results: [BookMetadata]
    }
}

class TalariaBackendTest {
    let baseURL = "https://api.oooefam.net"
    let deviceId = UUID().uuidString  // Must be valid UUID v4
    let session = URLSession.shared

    func runTest() async throws {
        print("📱 SwiftWing Talaria Backend Test (polling, API 3.9.0+)")
        print(String(repeating: "=", count: 50))
        print("")

        // Step 1: Load test image
        print("📸 Step 1: Loading test image...")
        let imagePath = ProcessInfo.processInfo.environment["IMAGE_PATH"]
            ?? "/Users/juju/dev_repos/swiftwing/test_book_stack.jpg"
        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: imagePath)) else {
            print("❌ Failed to load image from: \(imagePath)")
            print("   Set IMAGE_PATH or place test_book_stack.jpg in the repo root.")
            return
        }
        print("✅ Loaded image: \(imageData.count) bytes")
        print("")

        // Step 2: Upload to Talaria
        print("🚀 Step 2: Uploading to Talaria...")
        let (jobId, status) = try await uploadScan(imageData: imageData)
        print("✅ Upload successful!")
        print("   Job ID: \(jobId)")
        print("   Status: \(status)")
        print("")

        // Step 3: Poll job status
        print("📡 Step 3: Polling job status...")
        print(String(repeating: "-", count: 50))
        try await pollUntilComplete(jobId: jobId)
        print("")

        // Step 4: Fetch results
        print("📚 Step 4: Fetching results (format=lite)...")
        let books = try await fetchResults(jobId: jobId)
        print("✅ Received \(books.count) book(s)")
        for (i, book) in books.enumerated() {
            print("   [\(i + 1)] \(book.title ?? "Unknown Title") — \(book.author ?? "Unknown Author")")
            print("       ISBN: \(book.isbn ?? "none")  conf: \(book.confidence.map { String(format: "%.0f%%", $0 * 100) } ?? "n/a")  enrichment: \(book.enrichmentStatus ?? "n/a")")
            if let cover = book.coverUrl {
                print("       cover: \(cover)")
            }
        }
        print("")
        print("🎉 Polling workflow complete.")
    }

    func uploadScan(imageData: Data) async throws -> (jobId: String, status: String) {
        guard let url = URL(string: "\(baseURL)/v3/jobs/scans") else {
            throw URLError(.badURL)
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photos[]\"; filename=\"spine.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
            print("❌ Upload HTTP \(http.statusCode): \(bodyText)")
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(UploadResponse.self, from: data)
        guard decoded.success else {
            throw URLError(.cannotParseResponse)
        }
        return (decoded.data.jobId, decoded.data.status)
    }

    func pollUntilComplete(jobId: String) async throws {
        guard let url = URL(string: "\(baseURL)/v3/jobs/scans/\(jobId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")

        let maxAttempts = 75
        for attempt in 1...maxAttempts {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("   attempt \(attempt): non-200, retrying...")
                try await Task.sleep(for: .seconds(min(pow(2.0, Double((attempt - 1) / 2)), 4.0)))
                continue
            }

            let status = try JSONDecoder().decode(JobStatusResponse.self, from: data)
            let s = status.data.status
            let progress = status.data.progress.map { String(format: "%.0f%%", $0 * 100) } ?? "?"
            print("   attempt \(attempt): status=\(s) progress=\(progress)")

            switch s {
            case "completed":
                return
            case "failed":
                let err = status.data.error
                throw NSError(
                    domain: "TalariaTest",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "\(err?.code ?? "SCAN_FAILED"): \(err?.message ?? "failed")"]
                )
            case "canceled":
                throw CancellationError()
            default:
                try await Task.sleep(for: .seconds(min(pow(2.0, Double((attempt - 1) / 2)), 4.0)))
            }
        }
        throw URLError(.timedOut)
    }

    func fetchResults(jobId: String) async throws -> [BookMetadata] {
        guard let url = URL(string: "\(baseURL)/v3/jobs/scans/\(jobId)/results?format=lite") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
            print("❌ Results HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(bodyText)")
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(ResultsResponse.self, from: data)
        return decoded.data.results
    }
}

// MARK: - Entry

let test = TalariaBackendTest()
let semaphore = DispatchSemaphore(value: 0)
Task {
    do {
        try await test.runTest()
    } catch {
        print("❌ Test failed: \(error)")
    }
    semaphore.signal()
}
semaphore.wait()
