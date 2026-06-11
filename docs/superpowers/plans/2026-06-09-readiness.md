# SwiftWing Client Readiness Plan (2026-06-09)

**For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement three independent infrastructure tasks on the SwiftWing client to support backend deprecations and resilience improvements: duplicate detection fallback for ISBN-less books, ProblemDetails decode resilience with enrichmentStatus contract test fixture, and small-perf optimizations (dead code removal + async startup cleanup).

**Architecture:** Three tasks execute in parallel lanes: Lane A (Task 1, duplicate detection) is fully independent; Lane B (Tasks 2-3) are sequential due to shared file modifications in NetworkTypes.swift + TalariaService.swift. Both lanes run in parallel. All work is client-side only; server-side changes are gated on completion of this client readiness.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, async/await, xcodebuild + xcsift (build validation), XCTest (contract fixture tests).

---

## Execution Lanes

### Lane A (Independent) — Task 1: Duplicate Detection Fallback
- **Duration:** ~45 min
- **Model:** haiku [review: stronger model]
- **Reviewer:** Haiku output undergoes skeptical review before acceptance; any test failures escalate back to stronger model
- **Files:** DuplicateDetection.swift (complete rewrite), DataSyncActor.swift (2 method call-site updates), DuplicateDetectionTests.swift (7 new tests)
- **Critical Path:** Write test → fail → implement → pass → commit

### Lane B (Sequential) — Task 2 → Task 3
- **Task 2 Duration:** ~30 min
  - **Model:** haiku [review: stronger model]
  - **Files:** NetworkTypes.swift (3 updates: ProblemDetails struct + 2 use sites), ScanResultsResponseContractTests.swift (new file with 5 contract tests)
- **Task 3 Duration:** ~60 min
  - **Model:** haiku [review: stronger model]
  - **Files:** SSEEventParser.swift (delete), TalariaService.swift (delete streamEvents + 2 cleanup refs + backoff helper + pollScanStatus rewrite), UploadResponseData (make streamUrl optional), CameraViewModel.swift (2 cleanup call removals), ScanUploadCoordinator.swift (1 cleanup removal), ScanJobCoordinator.swift (2 cleanup removals), SwiftwingApp.swift (async startup cleanup), OfflineQueueManager.swift (streaming iterator), SSEEventParserTests.swift (delete), TalariaContractAdherenceTests.swift (update streamUrl assertions)

---

## Task 1: Duplicate Detection Fallback (ISBN-less Books)

**Objective:** Enable fallback duplicate matching on normalized title+author (case-insensitive, whitespace-trimmed, diacritic-insensitive) when incoming ISBN is nil or has `UNKNOWN-` prefix. Two scans of the same book without an ISBN will now be detected as duplicates instead of creating duplicate library rows.

**Files:**
- **Create/Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/Models/DuplicateDetection.swift` (complete replacement, lines 1-45 current)
- **Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/DataSyncActor.swift` (method call sites in `save` and `saveAll`)
- **Modify:** `/Users/juju/dev_repos/swiftwing/swiftwingTests/DuplicateDetectionTests.swift` (add 7 new test functions after existing tests)

### Step 1: Write Failing Tests (7 new test functions)
- [ ] Add all 7 new test functions from spec to `DuplicateDetectionTests.swift` (after existing tests, before closing brace):
  - `findDuplicate_fallbackMatch_twoScansOfSameISBNlessBook`
  - `findDuplicate_fallbackMatch_differentISBNlessBooks`
  - `findDuplicate_isbnTakesPrecedence_sameNormalizedTitleButDifferentISBN`
  - `findDuplicate_normalization_caseDifference`
  - `findDuplicate_normalization_whitespace`
  - `findDuplicate_normalization_diacritics`
  - `findDuplicate_fallbackMatch_emptyTitleOrAuthor`
- [ ] Run subset tests to verify they fail (expected: all 7 fail, finding of new method signature `findDuplicate(isbn:title:author:in:)` does not exist yet):
  ```bash
  cd /Users/juju/dev_repos/swiftwing
  xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
    -only-testing:swiftwingTests/DuplicateDetectionTests 2>&1 | xcsift
  ```
  **Expected:** `errors: X, warnings: 0` where X = number of test failures (all 7 tests fail at compile time due to missing method signature)

### Step 2: Implement DuplicateDetection.swift (Complete Replacement)
- [ ] Replace entire `/Users/juju/dev_repos/swiftwing/swiftwing/Models/DuplicateDetection.swift` with new code:
  ```swift
  import Foundation
  import SwiftData
  import os

  private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "duplicate")

  /// Utility for detecting duplicate books in the library
  /// US-311: Duplicate Detection Warning
  @MainActor
  enum DuplicateDetection {
      /// Error types for duplicate detection
      enum DuplicateDetectionError: LocalizedError {
          case fetchFailed(Error)

          var errorDescription: String? {
              switch self {
              case .fetchFailed(let error):
                  return "Failed to check for duplicate books: \(error.localizedDescription)"
              }
          }
      }

      /// Normalize book title/author for comparison (case-insensitive, whitespace/diacritic-insensitive)
      /// Algorithm: trim → lowercase → fold diacritics → collapse multiple spaces to single
      /// - Parameter text: Raw title or author string
      /// - Returns: Normalized string for comparison
      static func normalizeForComparison(_ text: String) -> String {
          // Step 1: Trim whitespace
          let trimmed = text.trimmingCharacters(in: .whitespaces)
          
          // Step 2: Lowercase
          let lowercased = trimmed.lowercased()
          
          // Step 3: Fold diacritical marks (é → e, ñ → n, etc.)
          let decomposed = lowercased.decomposedWithCompatibilityMapping
          let folded = decomposed.filter { !CharacterSet.decomposables.contains($0.unicodeScalars.first ?? " ") }
          
          // Step 4: Collapse multiple spaces to single space
          let collapsed = folded.components(separatedBy: .whitespaces)
              .filter { !$0.isEmpty }
              .joined(separator: " ")
          
          return collapsed
      }

      /// Checks if a book with the given ISBN/title/author already exists in the library
      /// Dual-path logic:
      /// - Fast path: if ISBN is non-nil and does NOT start with "UNKNOWN-", match by ISBN only
      /// - Fallback path: fetch all books, compare normalized title+author in memory; return nil if either is empty
      /// - Parameters:
      ///   - isbn: The ISBN to check (may be nil or start with "UNKNOWN-" for fallback)
      ///   - title: Book title (used for fallback matching)
      ///   - author: Book author (used for fallback matching)
      ///   - context: SwiftData model context
      /// - Returns: The existing Book if found, nil otherwise
      /// - Throws: DuplicateDetectionError if the database query fails
      static func findDuplicate(isbn: String?, title: String, author: String, in context: ModelContext) throws -> Book? {
          // Fast path: ISBN-based lookup (primary method)
          if let isbn = isbn, !isbn.starts(with: "UNKNOWN-") {
              let predicate = #Predicate<Book> { book in
                  book.isbn == isbn
              }
              
              var descriptor = FetchDescriptor<Book>(predicate: predicate)
              descriptor.fetchLimit = 1
              
              do {
                  let results = try context.fetch(descriptor)
                  return results.first
              } catch {
                  logger.error("Duplicate detection (ISBN) failed: \(error.localizedDescription, privacy: .public)")
                  throw DuplicateDetectionError.fetchFailed(error)
              }
          }
          
          // Fallback path: normalized title+author comparison
          let normalizedTitle = normalizeForComparison(title)
          let normalizedAuthor = normalizeForComparison(author)
          
          // Return nil if either normalized field is empty (can't reliably match)
          guard !normalizedTitle.isEmpty && !normalizedAuthor.isEmpty else {
              return nil
          }
          
          // Fetch all books (small set, in-memory comparison is safe)
          var descriptor = FetchDescriptor<Book>()
          descriptor.fetchLimit = nil  // No limit; we're comparing all
          
          do {
              let allBooks = try context.fetch(descriptor)
              
              // Find first match where normalized title+author match
              let duplicate = allBooks.first { book in
                  let bookNormalizedTitle = normalizeForComparison(book.title)
                  let bookNormalizedAuthor = normalizeForComparison(book.authors.joined(separator: ", "))
                  
                  return bookNormalizedTitle == normalizedTitle && bookNormalizedAuthor == normalizedAuthor
              }
              
              return duplicate
          } catch {
              logger.error("Duplicate detection (fallback) failed: \(error.localizedDescription, privacy: .public)")
              throw DuplicateDetectionError.fetchFailed(error)
          }
      }
  }
  ```
  **Key algorithm:** Fast path uses exact ISBN match via predicate (safe for #Predicate); fallback path fetches all books with FetchDescriptor and compares normalized values in memory (no #Predicate on string functions).
  
  **CRITICAL PREDICATE SAFETY RULE (FIX 3):** normalizeForComparison() MUST NEVER appear inside a #Predicate block. Fast path only uses exact `book.isbn == isbn` comparison. Fallback path ONLY uses FetchDescriptor with no predicate, fetches all books, then applies `normalizeForComparison()` to in-memory strings. If you accidentally put a function call inside #Predicate, SwiftData will fail at runtime (predicates cannot call custom functions).

### Step 3: Update DataSyncActor Call Sites
- [ ] Update `save(book:in:)` method in `/Users/juju/dev_repos/swiftwing/swiftwing/Services/DataSyncActor.swift`:
  - Find the line (currently line ~26-38 per spec) where `findDuplicate(isbn:in:)` is called
  - Replace with:
    ```swift
    if let existing = try DuplicateDetection.findDuplicate(
        isbn: isbn,
        title: book.resolvedTitle,
        author: book.resolvedAuthor,
        in: context
    ) {
    ```
- [ ] Update `saveAll(books:in:)` method in same file:
  - Find the line (currently line ~43-62 per spec) where `findDuplicate(isbn:in:)` is called
  - Replace with same 4-parameter call above (same method but inside loop)

### Step 4: Run Tests (All DuplicateDetection Tests, Old + New)
- [ ] Build clean to ensure 0 errors:
  ```bash
  xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
    clean build 2>&1 | xcsift
  ```
  **Expected:** `errors: 0, warnings: 0`
- [ ] Run full DuplicateDetection test suite (all old + 7 new):
  ```bash
  xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
    -only-testing:swiftwingTests/DuplicateDetectionTests 2>&1 | xcsift
  ```
  **Expected:** `Test Suite 'DuplicateDetectionTests' passed (16 tests in X.XXXs)` (2 old + 7 new + any existing regression tests)

### Step 5: Commit Task 1
- [ ] Stage files:
  ```bash
  cd /Users/juju/dev_repos/swiftwing
  git add swiftwing/Models/DuplicateDetection.swift \
          swiftwing/Services/DataSyncActor.swift \
          swiftwingTests/DuplicateDetectionTests.swift
  ```
- [ ] Create commit:
  ```bash
  git commit -m "$(cat <<'EOF'
  Task 1: Add ISBN-less book duplicate detection fallback

  Enable fallback duplicate matching on normalized title+author when ISBN is nil or has UNKNOWN- prefix. Normalizes case, whitespace, and diacritical marks for comparison. Solves duplicate library rows from multiple scans of same ISBN-less book.

  - Add normalizeForComparison static method (case/diacritic/whitespace insensitive)
  - Extend findDuplicate(isbn:title:author:in:) with dual-path logic
  - Update DataSyncActor.save and saveAll to pass title+author
  - Add 7 comprehensive fallback matching tests

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  EOF
  )"
  ```

### Step 6: Verification
- [ ] Verify commit succeeded:
  ```bash
  git log -1 --oneline
  ```
- [ ] Task 1 is COMPLETE. Proceed to Lane B (Tasks 2 & 3 in sequence).

---

## Task 2: ProblemDetails Resilience + EnrichmentStatus Contract Test

**Objective:** Make `ProblemDetails` struct fields optional (detail, code, retryable) to tolerate incomplete RFC 9457 responses from Talaria. Add contract fixture test pinning enrichmentStatus top-level presence. Decode resilience means missing fields don't mask real API errors as generic invalidResponse.

**CRITICAL COMPILE-ORDER CONSTRAINT:** Making `detail`, `code`, `retryable` optional REQUIRES synchronous update of all use sites in same commit. Skipping any use site breaks compilation. Both steps below are ATOMIC — do not split across commits.

**Files:**
- **Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift` (ProblemDetails struct + use-site updates in same file)
- **Create:** `/Users/juju/dev_repos/swiftwing/swiftwingTests/Unit/Services/ScanResultsResponseContractTests.swift` (new file, 5 test methods)

### Step 1: Write Contract Fixture Test (Failing)
- [ ] Create new file `/Users/juju/dev_repos/swiftwing/swiftwingTests/Unit/Services/ScanResultsResponseContractTests.swift` with complete JSON fixture and 5 assertions:
  ```swift
  import XCTest
  @testable import swiftwing

  final class ScanResultsResponseContractTests: XCTestCase {
      // Complete JSON fixture: 2 books (one success with enrichment, one not_found)
      let fixtureJSON = """
      {
        "success": true,
        "data": {
          "jobId": "550e8400-e29b-41d4-a716-446655440000",
          "status": "completed",
          "results": [
            {
              "title": "The Great Gatsby",
              "author": "F. Scott Fitzgerald",
              "isbn": "9780743273565",
              "confidence": 0.98,
              "format": "hardcover",
              "enrichmentStatus": "success",
              "enrichment": {
                "status": "success",
                "coverUrl": "https://example.com/covers/gatsby.jpg",
                "publisher": "Scribner",
                "publishedDate": "1925-04-10",
                "authors": ["F. Scott Fitzgerald"]
              }
            },
            {
              "title": "Unknown Title",
              "author": "Unknown Author",
              "isbn": "UNKNOWN-2024-001",
              "confidence": 0.45,
              "format": "paperback",
              "enrichmentStatus": "not_found",
              "enrichment": null
            }
          ]
        },
        "metadata": {
          "timestamp": "2026-01-18T12:00:00Z",
          "requestId": "req-abc-123"
        }
      }
      """

      func test_decodeScanResultsResponse_withEnrichmentStatus_success() throws {
          let data = fixtureJSON.data(using: .utf8)!
          let response = try JSONDecoder().decode(ScanResultsResponse.self, from: data)
          XCTAssertTrue(response.success)
          XCTAssertEqual(response.data.results.count, 2)
      }

      func test_decodeScanResultsResponse_book1_enrichmentStatusSuccess() throws {
          let data = fixtureJSON.data(using: .utf8)!
          let response = try JSONDecoder().decode(ScanResultsResponse.self, from: data)
          let book1 = response.data.results[0]
          XCTAssertEqual(book1.enrichmentStatus, .success)
          XCTAssertNotNil(book1.enrichment)
          XCTAssertEqual(book1.enrichment?.publisher, "Scribner")
      }

      func test_decodeScanResultsResponse_book2_enrichmentStatusNotFound() throws {
          let data = fixtureJSON.data(using: .utf8)!
          let response = try JSONDecoder().decode(ScanResultsResponse.self, from: data)
          let book2 = response.data.results[1]
          XCTAssertEqual(book2.enrichmentStatus, .notFound)
          XCTAssertNil(book2.enrichment)
      }

      func test_decodeScanResultsResponse_enrichmentStatusIsNonNil_contractSeam() throws {
          let data = fixtureJSON.data(using: .utf8)!
          let response = try JSONDecoder().decode(ScanResultsResponse.self, from: data)
          for book in response.data.results {
              XCTAssertNotNil(book.enrichmentStatus, "enrichmentStatus must be non-nil for contract compliance")
          }
      }

      func test_decodeScanResultsResponse_allBooksDecodedSuccessfully() throws {
          let data = fixtureJSON.data(using: .utf8)!
          let response = try JSONDecoder().decode(ScanResultsResponse.self, from: data)
          XCTAssertEqual(response.data.results.count, 2)
          XCTAssertEqual(response.data.results[0].isbn, "9780743273565")
          XCTAssertEqual(response.data.results[1].isbn, "UNKNOWN-2024-001")
      }
  }
  ```

- [ ] Build and verify tests fail (expected: enrichmentStatus property doesn't exist in BookMetadata yet):
  ```bash
  xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
    -only-testing:swiftwingTests/ScanResultsResponseContractTests 2>&1 | xcsift
  ```
  **Expected:** Compilation error: `Type 'BookMetadata' has no member 'enrichmentStatus'`

### Step 2: Make ProblemDetails Fields Optional + Update ALL Use Sites (ATOMIC COMMIT)
**BOLD:** Steps 2a, 2b, 2c MUST be completed together before any build. Splitting breaks compilation.

#### Step 2a: Make ProblemDetails Fields Optional
- [ ] In `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift` at lines 77-88, replace:
  ```swift
  public struct ProblemDetails: Codable, Sendable {
      let success: Bool
      let type: String
      let title: String
      let status: Int
      let detail: String
      let code: String
      let retryable: Bool
      let retryAfterMs: Int?
      let instance: String?
      let metadata: [String: AnyCodableValue]?
  }
  ```
  With:
  ```swift
  public struct ProblemDetails: Codable, Sendable {
      let success: Bool
      let type: String
      let title: String
      let status: Int
      let detail: String?              // ← NOW OPTIONAL
      let code: String?                // ← NOW OPTIONAL
      let retryable: Bool?             // ← NOW OPTIONAL
      let retryAfterMs: Int?
      let instance: String?
      let metadata: [String: AnyCodableValue]?
  }
  ```

#### Step 2b: Update NetworkError.localizedDescription Use Site (lines 145-146)
- [ ] Find:
  ```swift
  case .apiError(let problem):
      return problem.detail
  ```
  Replace with:
  ```swift
  case .apiError(let problem):
      return problem.detail ?? "Unknown API error"
  ```

#### Step 2c: Update Documentation Comments (lines 71-73 and 117-119)
- [ ] At lines 71-73, find:
  ```swift
  /// } catch NetworkError.apiError(let problem) {
  ///     if problem.retryable {
  ///         let delayMs = problem.retryAfterMs ?? 60000
  ```
  Replace with:
  ```swift
  /// } catch NetworkError.apiError(let problem) {
  ///     if problem.retryable ?? false {
  ///         let delayMs = problem.retryAfterMs ?? 60_000
  ```

- [ ] At lines 117-119, find:
  ```swift
  /// } catch NetworkError.apiError(let problem) {
  ///     print("API Error: \(problem.code) - \(problem.detail)")
  /// }
  ```
  Replace with:
  ```swift
  /// } catch NetworkError.apiError(let problem) {
  ///     print("API Error: \(problem.code ?? "UNKNOWN") - \(problem.detail ?? "unknown error")")
  /// }
  ```

#### Step 2d: Verify No Other problem.detail / problem.code / problem.retryable Reads
- [ ] Search for all uses of `.detail`, `.code`, `.retryable` on problem/ProblemDetails in entire codebase:
  ```bash
  grep -rn "problem\\.detail\|problem\\.code\|problem\\.retryable\|problem\\.retryAfterMs" /Users/juju/dev_repos/swiftwing/swiftwing/ --include="*.swift"
  ```
  Expected results:
  - `/NetworkTypes.swift:72` (doc comment — UPDATE per 2c)
  - `/NetworkTypes.swift:118` (doc comment — UPDATE per 2c)
  - `/NetworkTypes.swift:146` (localizedDescription — UPDATE per 2b)
  - `/NetworkTypes.swift:167` (retryAfterMs in TalariaService.uploadScan — **verify**: `problemDetails.retryAfterMs.map { TimeInterval($0) / 1000.0 }` is safe, field is already optional)
  All found instances are now either updated or safe (retryAfterMs was already optional). If any NEW instances appear, add `?? fallback` handling.

### Step 5: Run Contract Tests
- [ ] Build clean:
  ```bash
  xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
    clean build 2>&1 | xcsift
  ```
  **Expected:** `errors: 0, warnings: 0`
- [ ] Run new contract tests:
  ```bash
  xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
    -only-testing:swiftwingTests/ScanResultsResponseContractTests 2>&1 | xcsift
  ```
  **Expected:** `Test Suite 'ScanResultsResponseContractTests' passed (5 tests in X.XXXs)`
- [ ] Also verify existing TalariaContractAdherenceTests still pass (existing tests should not break):
  ```bash
  xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
    -only-testing:swiftwingTests/TalariaContractAdherenceTests 2>&1 | xcsift
  ```
  **Expected:** `Test Suite 'TalariaContractAdherenceTests' passed (X tests in X.XXXs)`

### Step 6: Commit Task 2
- [ ] Stage files:
  ```bash
  cd /Users/juju/dev_repos/swiftwing
  git add swiftwing/Services/NetworkTypes.swift \
          swiftwingTests/Unit/Services/ScanResultsResponseContractTests.swift
  ```
- [ ] Create commit:
  ```bash
  git commit -m "$(cat <<'EOF'
  Task 2: ProblemDetails resilience + enrichmentStatus contract test

  Make ProblemDetails fields (detail, code, retryable) optional to tolerate incomplete RFC 9457 responses. Add contract fixture test pinning enrichmentStatus at top-level per new server schema. Decode resilience prevents masking real API errors as generic invalidResponse.

  - Make detail, code, retryable optional with sensible defaults at use sites
  - Update localizedDescription to return fallback when detail is nil
  - Add ScanResultsResponseContractTests with 2-book fixture (success + not_found enrichmentStatus)
  - Pin contract seam with non-nil assertions for both enrichmentStatus cases

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  EOF
  )"
  ```

### Step 7: Verification
- [ ] Verify commit succeeded:
  ```bash
  git log -1 --oneline
  ```
- [ ] Task 2 is COMPLETE. Proceed to Task 3.

---

## Task 3: Strips + Small-Perf Cluster (Delete Dead Code, Async Startup)

**Objective:** Remove SSE streaming stack (dead code, HTTP polling is production path), delete cleanup() no-op roundtrip, make streamUrl/token optional for server transition, add adaptive backoff helper, move startup temp cleanup to background task, implement streaming iterator for offline queue manager.

**LOCKED DECISION:** JobStatus.canceled is KEPT (server deploy will make it real). Only remove SSE-parser references. streamUrl/token become optional now; field deletion is blocked until talaria Task 6 deploys.

**Files:**
- **Delete:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/SSEEventParser.swift` (entire file, 258 lines)
- **Delete:** `/Users/juju/dev_repos/swiftwing/swiftwingTests/SSEEventParserTests.swift` (entire file)
- **Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift` (UploadResponseData struct, line 316-321, make streamUrl optional)
- **Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift` (delete streamEvents method 201-425, add backoffDelay helper, rewrite pollScanStatus, update uploadScan response handling for optional streamUrl)
- **Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/Features/Camera/CameraViewModel.swift` (remove 2 cleanup() calls, lines ~314 and ~326)
- **Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/Features/Camera/ScanUploadCoordinator.swift` (remove cleanup call at line 104)
- **Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/Features/Camera/ScanJobCoordinator.swift` (remove 2 cleanup calls)
- **Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/App/SwiftwingApp.swift` (async startup cleanup, make cleanupOrphanedTempPhotos async)
- **Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/OfflineQueueManager.swift` (add streamQueuedScans iterator, deprecate getAllQueuedScans)
- **Modify:** `/Users/juju/dev_repos/swiftwing/swiftwingTests/Unit/Services/TalariaContractAdherenceTests.swift` (update streamUrl assertions to handle optional)

### Checkpoint: Before Deletions
- [ ] Build clean to establish baseline:
  ```bash
  xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
    clean build 2>&1 | xcsift
  ```
  **Expected:** `errors: 0, warnings: 0`

### Step 1: Delete SSEEventParser.swift
- [ ] Delete entire file `/Users/juju/dev_repos/swiftwing/swiftwing/Services/SSEEventParser.swift`:
  ```bash
  rm /Users/juju/dev_repos/swiftwing/swiftwing/Services/SSEEventParser.swift
  ```

### Step 2: Delete SSEEventParserTests.swift
- [ ] Delete entire file `/Users/juju/dev_repos/swiftwing/swiftwingTests/SSEEventParserTests.swift`:
  ```bash
  rm /Users/juju/dev_repos/swiftwing/swiftwingTests/SSEEventParserTests.swift
  ```

### Step 3: Make streamUrl Optional in UploadResponseData
- [ ] In `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift` at lines 316-321, find:
  ```swift
  public struct UploadResponseData: Codable, Sendable {
      let jobId: String
      let status: JobStatus
      let streamUrl: URL
      let token: String?
  }
  ```
  Replace with:
  ```swift
  public struct UploadResponseData: Codable, Sendable {
      let jobId: String
      let status: JobStatus
      let streamUrl: URL?
      let token: String?
  }
  ```

### Step 4: Update TalariaService.uploadScan Response Handling
- [ ] In `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift` at lines 158-160, find:
  ```swift
  e2eLogger.info("Upload response received: JobID=\(uploadResponse.data.jobId, privacy: .public) StreamURL=\(uploadResponse.data.streamUrl, privacy: .public) Status=\(String(describing: uploadResponse.data.status), privacy: .public)")

  return (jobId: uploadResponse.data.jobId, streamUrl: uploadResponse.data.streamUrl, status: uploadResponse.data.status, token: uploadResponse.data.token)
  ```
  Replace with:
  ```swift
  guard let streamUrl = uploadResponse.data.streamUrl else {
      e2eLogger.error("Upload response missing streamUrl (required)")
      throw NetworkError.invalidResponse
  }
  
  e2eLogger.info("Upload response received: JobID=\(uploadResponse.data.jobId, privacy: .public) Status=\(String(describing: uploadResponse.data.status), privacy: .public)")

  return (jobId: uploadResponse.data.jobId, streamUrl: streamUrl, status: uploadResponse.data.status, token: uploadResponse.data.token)
  ```

### Step 5: Add backoffDelay Helper to TalariaService
- [ ] In `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift`, add this method immediately before `streamEvents()` (around line 200):
  ```swift
  /// Calculate exponential backoff delay with maximum cap (4s)
  /// Strategy: 1s, 1s, 2s, 2s, then 4s cap (never resets during scan lifetime)
  /// - Parameter attempt: Current attempt number (1-based)
  /// - Returns: Delay in seconds
  private nonisolated func backoffDelay(for attempt: Int) -> TimeInterval {
      let exponentialDelay = min(pow(2.0, Double(attempt - 1)), 4.0)
      return exponentialDelay
  }
  ```

### Step 6: Delete streamEvents() Method
- [ ] In same file (TalariaService.swift), find and delete the entire `nonisolated func streamEvents(jobId:authToken:)` method. This is dead code; production path is HTTP polling via `pollScanStatus()`. Method begins with docstring "Stream real-time scan progress events via Server-Sent Events with automatic retry" and runs approximately 200+ lines with SSE parsing logic.
  ```bash
  grep -n "nonisolated func streamEvents" /Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift
  ```
  Once you locate it, delete the entire function definition (all lines until the next top-level function).

### Step 7: Rewrite pollScanStatus with Adaptive Backoff
- [ ] In same file around line 613, find method `func pollScanStatus(jobId:interval:)` and update its polling loop with adaptive backoff:
  ```swift
  // Before:
  func pollScanStatus(jobId: String, interval: TimeInterval = 1.0) async throws -> [BookMetadata] {
      var results: [BookMetadata] = []
      
      for attempt in 1...30 {
          try await Task.sleep(for: .seconds(interval))  // Fixed delay
          
          let statusResponse = try await fetchJobStatus(jobId: jobId)
          if statusResponse.data.status == .completed { ... }
          else if statusResponse.data.status == .canceled { ... }
      }
  }
  
  // After:
  func pollScanStatus(jobId: String, interval: TimeInterval = 1.0) async throws -> [BookMetadata] {
      var results: [BookMetadata] = []
      var pollAttempt = 0
      
      for _ in 1...30 {
          pollAttempt += 1
          let backoff = backoffDelay(for: pollAttempt)
          e2eLogger.debug("Poll attempt \(pollAttempt, privacy: .public): backing off \(String(format: "%.1f", backoff))s before next check")
          try await Task.sleep(for: .seconds(backoff))  // Adaptive backoff
          
          let statusResponse = try await fetchJobStatus(jobId: jobId)
          if statusResponse.data.status == .completed { ... }
          else if statusResponse.data.status == .canceled { ... }
      }
  }
  ```
  Key changes:
  - Add `var pollAttempt = 0` before loop
  - Track poll attempt count
  - Calculate adaptive backoff using `backoffDelay(for:)` helper
  - Add debug log showing attempt number and backoff delay
  - **KEEP** the `.canceled` case (only matches `== .completed` and `== .failed`, then also checks `.canceled` — it survives deletion of streamEvents)

### Step 8: Verify Backoff Consolidation
- [ ] After deleting `streamEvents()` method (which contained backoff calculations), verify no orphaned backoff code remains:
  ```bash
  grep -n "pow(2.0, Double" /Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift
  ```
  **Expected:** No results (streamEvents had the only duplication; pollScanStatus now uses centralized backoffDelay helper). If results appear, replace with `backoffDelay(for: attempt)` call.

### Step 9: Delete cleanup() Method from TalariaService
- [ ] In `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift`, find and delete the entire `func cleanup(jobId:authToken:)` method. This is a server no-op; R2 images auto-delete. Method signature is `func cleanup(jobId: String, authToken: String? = nil) async throws`.
  ```bash
  grep -n "func cleanup(jobId" /Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift
  ```
  Once located, delete the entire method (approximately 80+ lines of HTTP DELETE + response handling).

### Step 10: Remove cleanup() Call Sites (CameraViewModel)
- [ ] In `/Users/juju/dev_repos/swiftwing/swiftwing/Features/Camera/CameraViewModel.swift`:
  - **Line 314** (inside task cancellation handler):
    ```swift
    // Before:
    if Task.isCancelled {
        await scanCoordinator.cleanup(jobId: uploadResult.jobId, authToken: authToken)
        if let tempFileURL { await scanCoordinator.cleanupTempFile(tempFileURL) }
        return
    }
    
    // After:
    if Task.isCancelled {
        if let tempFileURL { await scanCoordinator.cleanupTempFile(tempFileURL) }
        return
    }
    ```
    Delete the entire `await scanCoordinator.cleanup(...)` line.
    
  - **Line 326** (inside success handler):
    ```swift
    // Before:
    // Cleanup server resources (non-blocking); temp file deferred until review action
    await scanCoordinator.cleanup(jobId: uploadResult.jobId, authToken: authToken)
    
    // Auto-remove from queue after 5 seconds
    await removeQueueItemAfterDelay(id: capturedItemId, delay: 5.0)
    
    // After:
    // Auto-remove from queue after 5 seconds
    await removeQueueItemAfterDelay(id: capturedItemId, delay: 5.0)
    ```
    Delete the `await scanCoordinator.cleanup(...)` line and preceding comment.
    
  - **Line ~393** (inside error handler `handleProcessingError`):
    ```swift
    // Before:
    if let jid = jobId {
        await scanCoordinator.cleanup(jobId: jid, authToken: authToken)
    }
    if let tempFileURL { await scanCoordinator.cleanupTempFile(tempFileURL) }
    
    // After:
    if let tempFileURL { await scanCoordinator.cleanupTempFile(tempFileURL) }
    ```
    Delete the entire cleanup block (lines 392-394); keep the tempFileURL cleanup.

### Step 11: Remove cleanup() Call Site (ScanUploadCoordinator)
- [ ] In `/Users/juju/dev_repos/swiftwing/swiftwing/Features/Camera/ScanUploadCoordinator.swift` at line 104, find:
  ```swift
  try await talariaService.cleanup(jobId: jobId)
  ```
  Delete this line entirely.

### Step 12: Remove cleanup() Call Sites (ScanJobCoordinator)
- [ ] In `/Users/juju/dev_repos/swiftwing/swiftwing/Features/Camera/ScanJobCoordinator.swift`:
  - Find line ~214 with `try await talariaService.cleanup(jobId: jobId, authToken: token)` and delete it
  - Find line ~266 with `try await service.cleanup(jobId: activeJobId, authToken: storedAuthToken)` and delete it

### Step 13: Async Startup Cleanup (SwiftwingApp)
- [ ] In `/Users/juju/dev_repos/swiftwing/swiftwing/App/SwiftwingApp.swift`, replace `init()` method (lines 24-39 per CLAUDE.md structure):
  ```swift
  init() {
      configureForUITesting()
      cleanupOrphanedTempPhotos()
      // ... DEBUG section
  }
  ```
  With:
  ```swift
  init() {
      configureForUITesting()
      
      // Move orphaned temp file cleanup to background — don't block app init
      Task(priority: .background) {
          await cleanupOrphanedTempPhotos()
      }

      // ... DEBUG section
  }
  ```
- [ ] Change method signature from `private func cleanupOrphanedTempPhotos()` to `private func cleanupOrphanedTempPhotos() async` (add `async`)
- [ ] Update docstring to note async execution: "Runs asynchronously in background to avoid blocking app init."

### Step 14: Streaming Iterator for OfflineQueueManager
- [ ] In `/Users/juju/dev_repos/swiftwing/swiftwing/Services/OfflineQueueManager.swift`, replace `getAllQueuedScans()` method with two methods:
  - New method `streamQueuedScans()` returning `AsyncThrowingStream<(metadata: QueuedScanMetadata, imageData: Data), Error>`:
    ```swift
    func streamQueuedScans() -> AsyncThrowingStream<(metadata: QueuedScanMetadata, imageData: Data), Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Load all metadata first (small, fast)
                    let allMetadata = try loadAllQueuedMetadata()
                    
                    // Sort by capture date (oldest first)
                    let sorted = allMetadata.sorted { $0.captureDate < $1.captureDate }
                    
                    // Yield each scan as loaded (memory-efficient, one at a time)
                    for metadata in sorted {
                        if let imageData = try loadImageData(for: metadata.id) {
                            continuation.yield((metadata: metadata, imageData: imageData))
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    ```
  - Deprecate old `getAllQueuedScans()` with wrapper:
    ```swift
    @available(*, deprecated, renamed: "streamQueuedScans")
    func getAllQueuedScans() async throws -> [(metadata: QueuedScanMetadata, imageData: Data)] {
        var results: [(metadata: QueuedScanMetadata, imageData: Data)] = []
        for try await item in streamQueuedScans() {
            results.append(item)
        }
        return results
    }
    ```
  - Key logic: Load all metadata first (small), sort by capture date, then yield each scan as loaded (one at a time, memory-efficient)

### Step 15: Find and Update getAllQueuedScans Call Sites
- [ ] Search for all `getAllQueuedScans()` calls in codebase:
  ```bash
  grep -rn "getAllQueuedScans" /Users/juju/dev_repos/swiftwing/swiftwing/ --include="*.swift"
  ```
- [ ] For each call site found, replace pattern:
  ```swift
  let scans = try await offlineQueueManager.getAllQueuedScans()
  for (metadata, imageData) in scans {
  ```
  With:
  ```swift
  for try await (metadata, imageData) in offlineQueueManager.streamQueuedScans() {
  ```

### Step 16: Update TalariaContractAdherenceTests streamUrl Assertions
- [ ] In `/Users/juju/dev_repos/swiftwing/swiftwingTests/Unit/Services/TalariaContractAdherenceTests.swift`, find all assertions on `streamUrl`:
  - Lines referencing `response.data.streamUrl.absoluteString` or `streamUrl` in assertions
  - Update assertions to handle optional (still check non-nil for now, since server still sends it):
    ```swift
    XCTAssertNotNil(response.data.streamUrl, "streamUrl expected in current API version")
    XCTAssertEqual(response.data.streamUrl?.absoluteString, "https://...")
    ```

### Step 17: Test Deletion Changes
- [ ] Build clean after all deletions:
  ```bash
  xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
    clean build 2>&1 | xcsift
  ```
  **Expected:** `errors: 0, warnings: 0`
- [ ] Run all tests to verify deletions don't break contract/functionality:
  ```bash
  xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
    -only-testing:swiftwingTests 2>&1 | xcsift
  ```
  **Expected:** All tests pass (SSEEventParserTests.swift deletion removes those tests; rest should pass)

### Step 18: Commit Task 3
- [ ] Stage files (deletions + modifications):
  ```bash
  cd /Users/juju/dev_repos/swiftwing
  git add swiftwing/Services/SSEEventParser.swift \
          swiftwing/Services/TalariaService.swift \
          swiftwing/Services/NetworkTypes.swift \
          swiftwing/Services/OfflineQueueManager.swift \
          swiftwing/Features/Camera/CameraViewModel.swift \
          swiftwing/Features/Camera/ScanUploadCoordinator.swift \
          swiftwing/Features/Camera/ScanJobCoordinator.swift \
          swiftwing/App/SwiftwingApp.swift \
          swiftwingTests/SSEEventParserTests.swift \
          swiftwingTests/Unit/Services/TalariaContractAdherenceTests.swift
  ```
- [ ] Handle deletions in git:
  ```bash
  git rm swiftwing/Services/SSEEventParser.swift \
         swiftwingTests/SSEEventParserTests.swift
  ```
- [ ] Create commit:
  ```bash
  git commit -m "$(cat <<'EOF'
  Task 3: Strip dead SSE stack + small-perf cluster

  Remove dead Server-Sent Events streaming implementation (production path is HTTP polling). Delete cleanup() no-op roundtrip (server auto-deletes images). Make streamUrl optional for server transition. Add adaptive exponential backoff helper. Move app startup temp cleanup to background task. Implement streaming iterator for offline queue manager.

  DELETED:
  - SSEEventParser.swift (dead code, replaced by HTTP polling)
  - SSEEventParserTests.swift (tests for deleted parser)

  MODIFIED:
  - TalariaService: remove streamEvents(), add backoffDelay(), rewrite pollScanStatus with adaptive backoff, remove cleanup() method
  - UploadResponseData: make streamUrl optional (tolerate absence for server transition)
  - uploadScan response handling: guard streamUrl, update log
  - CameraViewModel: remove 2 cleanup() call sites
  - ScanUploadCoordinator: remove cleanup() call
  - ScanJobCoordinator: remove 2 cleanup() calls
  - SwiftwingApp: move cleanupOrphanedTempPhotos to background Task
  - OfflineQueueManager: add streamQueuedScans iterator, deprecate getAllQueuedScans
  - TalariaContractAdherenceTests: update streamUrl assertions for optional

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  EOF
  )"
  ```

### Step 19: Post-Deletion Polling Verification
**FIX 5:** After SSE deletions, verify TalariaService's HTTP polling path survives with canceled handling:
- [ ] Confirm `pollScanStatus()` at line 613 still compiles and handles `status == .canceled`:
  ```bash
  grep -A 50 "func pollScanStatus" /Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift | grep -A 5 "== .canceled"
  ```
  Expected output (surviving block):
  ```swift
  } else if statusResponse.data.status == .canceled {
      e2eLogger.info("Scan job was canceled")
      return results  // or appropriate empty/error return
  }
  ```
  
- [ ] Build clean to verify no errors after all Task 3 deletions:
  ```bash
  xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
    clean build 2>&1 | xcsift
  ```
  **Expected:** `errors: 0, warnings: 0`

### Step 20: Verification
- [ ] Verify commit succeeded:
  ```bash
  git log -1 --oneline
  ```
- [ ] Task 3 is COMPLETE.

---

## Deploy Order

**Critical sequencing:** Client Tasks 1-3 deploy FIRST (client tolerates server both before and after); then Talaria deploys server fixes; then final field-deletion checkbox unblocks.

### Phase 1: Client Readiness (This Plan)
- ✅ Lane A + Lane B Tasks 1-3 complete and merged (all 3 commits on main)
- ✅ Full build: `errors: 0, warnings: 0`
- ✅ All unit + contract tests passing

### Phase 2: Talaria Server Deploy (Separate Plan)
- [ ] [BLOCKED] Awaiting talaria/docs/superpowers/plans/2026-06-09-phase2-talaria-deploy.md
  - Server: emit TOP-LEVEL `enrichmentStatus` in results (client already expects this via Task 2 contract test)
  - Server: stop sending streamUrl/token in upload response (client tolerates absence via Task 3 optional)

### Phase 3: Client Follow-up (Final Checkbox)
- [ ] [BLOCKED until talaria Task 6 deployed (POST 202 no longer contains streamUrl/token)] Delete streamUrl/token fields from UploadResponseData
  - File: `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift` (lines 316-321)
  - Action: Remove both fields entirely; update uploadScan return tuple to exclude them
  - Commit message: "Task 3b: Remove streamUrl/token fields after server deploys"

### Phase 4: Verification Gate
- [ ] [BLOCKED until Phase 2 completes] Cross-product verification (client + server integration)
  - Reference: `talaria/docs/superpowers/plans/2026-06-09-phase4-verification-gate.md`
  - Smoke test: Upload scan with current server + new client; verify enrichmentStatus decodes correctly
  - Regression: Verify duplicate detection works with both ISBN and ISBN-less books

---

## Out of Scope (Deliberate)

### Deferred Items
1. **Book.rawJSON removal** — SwiftData migration risk; already captured in separate epic (Epic 7 design doc)
2. **Three-queue-manager consolidation** — Architectural refactor deferred; OfflineQueueManager + sync paths are stable
3. **LibraryView query optimization** — Already predicate-based (not full-table scan); review refuted further optimization need

### Not Touching
- SSE event enum cases (SSEEvent.canceled etc.) — only SSE **parser** is deleted; enum definition stays for future server cancel feature
- JobStatus.canceled enum case — KEPT per locked decision (talaria companion plan implements cancel real)
- Authorization Bearer header behavior — Already removed in Task 3 (no-op cleanup); no additional auth changes needed

---

## Done When

✅ **All non-blocked checkboxes complete**
✅ **Full build via xcsift:** `errors: 0, warnings: 0`
✅ **All tests passing:**
  - DuplicateDetectionTests (2 old + 7 new = 9 total)
  - ScanResultsResponseContractTests (5 new)
  - TalariaContractAdherenceTests (existing, now with optional streamUrl handling)
  - All other swiftwingTests
✅ **Three commits on main:**
  1. Task 1: Duplicate detection fallback
  2. Task 2: ProblemDetails resilience + contract test
  3. Task 3: Strips + small-perf
✅ **Deploy-order position satisfied:** Client tasks 1-3 ready before talaria server deploy

---

## Notes for Implementation Agents

### Haiku Agent Notes
- **Task 1** is fully independent; can be executed in parallel with Tasks 2-3 in other agents
- **Tasks 2-3** are sequential (share NetworkTypes.swift + TalariaService.swift); execute in order in same agent
- All code in spec is COMPLETE (no placeholders); execute verbatim
- **Critical:** Always pipe xcodebuild through xcsift — parse `errors: 0, warnings: 0` before declaring task complete
- Test failures = escalate back to stronger model; don't iterate locally
- Use exact file paths and line ranges from this document

### Reviewer Notes (Stronger Model)
- Review haiku output against spec word-by-word for exact line matches
- Verify no warnings introduced (Swift 6.2 strict concurrency)
- Confirm tests reflect both happy-path and edge cases (diacritics, empty fields, etc.)
- Check commit messages align with task objectives
- Verify deleted files are gone from git (not just `.gitignore`d)
- Validate optional field handling is consistent across use sites

### Risk Mitigations
- **SSEEventParser deletion risks:** Clean grep to confirm no other imports exist; spec verified no call sites outside TalariaService (which we delete streamEvents from)
- **cleanup() call site deletions:** Systematic search before deletion; coordinate with grep results
- **Task 3 complexity:** Sequential checkpoint before deletions; build baseline to confirm no hidden breakage

---

## Appendix: Conflicts Resolved Between Specs and Actual Code

| Conflict | Spec Says | Actual Code | Resolution |
|----------|-----------|-------------|------------|
| DuplicateDetection file state | Complete replacement (164-287) | Currently has old 1-method findDuplicate | Use spec version entirely; test failures will guide correctness |
| ProblemDetails optionality | detail/code/retryable optional | All non-optional currently | Change matches spec exactly; defaults applied at single use site (line 146) |
| UploadResponseData streamUrl | Optional now | Currently non-optional | Add `?` per spec; guard in uploadScan response handler |
| TalariaService streamEvents | Delete entire method | Exists at ~201-425 | Delete verbatim; confirm no orphaned references post-deletion |
| Backoff calculations | Consolidate via helper | Duplicated in streamEvents | Delete streamEvents removes duplicates; helper never called by other code (streamEvents is sole caller) |
| cleanupOrphanedTempPhotos | Make async, move to Task(priority:.background) | Sync, called directly in init | Convert to async, wrap in Task per spec (non-blocking startup) |
| OfflineQueueManager | Add streamQueuedScans, deprecate getAllQueuedScans | Only has getAllQueuedScans | Add new method, keep old as deprecated wrapper (backward compat) |

---

**Plan Version:** 1.0  
**Created:** 2026-06-09  
**Status:** Ready for execution  
**Blockers:** None (all prerequisites met)

---

## EXECUTION STATUS (2026-06-10)

**All 3 tasks executed and reviewed** on branch `readiness-2026-06-09` (5 commits, 99d64c3..4ebe824).
Final whole-branch review → READY TO MERGE. Gates green: clean build errors:0/warnings:0 · full unit suite 3/3 consecutive clean runs (104-105 tests).
Notable deviations (all reviewed): uploadScan streamUrl guard removed entirely — tuple is URL?, client tolerates server omission NOW (Phase 2 safe); queueItem regression caught+fixed in review; OfflineQueueManager gained a test-scoped queueDirectory init; offline-queue tests made deterministic; two pre-existing warnings fixed.
**Phase 3 checkbox (delete streamUrl/token fields) remains BLOCKED until talaria Task 6 deploys.**
Deploy order: install THIS build on family devices FIRST, then deploy talaria.
