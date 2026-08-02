# Talaria Deploy Unblock + Phases 7–9 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the four backed-up Talaria commits to production, resync SwiftWing's committed OpenAPI spec against the real live spec, then close Phases 7, 8, and 9 of the alignment work and delete the planning files.

**Architecture:** Task 1 unblocks a stuck CI gate in `talaria` (one formatter fix). Tasks 2–3 are the verify-then-resync chain that everything downstream depends on. Tasks 4–7 are SwiftWing feature work on a single branch (`feature/enrichment-recovery`): dead-code removal first so the review queue is clean, then the manual-lookup recovery path built on `GET /v3/books/search`. Tasks 8–10 are camera UX on a second branch. Task 11 closes out.

**Tech Stack:** Talaria — TypeScript, Cloudflare Workers/Workflows, Biome 2.4, Vitest, GitHub Actions. SwiftWing — Swift 6.2, SwiftUI, SwiftData, Swift Testing, AVFoundation, iOS 26.

---

## Global Constraints

- **Talaria branch is `talaria`, not `main`.** Push to `talaria` triggers `Deploy to Production`.
- **Talaria deploy gate has TWO steps**, both inside the `Pre-Deployment Checks` job: `npm run validate` (= `biome check` + smoke tests), then `npm run test:safe` (= smoke + `TEST_SAFE_MODE=true` node suite). Both must be run locally before any push.
- **SwiftWing builds must be `errors: 0, warnings: 0`.** Any warning is a failure (`.claude/rules/build-workflow.md`).
- **Never call `xcodebuild` without piping through `xcsift`.**
- **SwiftWing tests use Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest.
- **git binary:** use `/Library/Developer/CommandLineTools/usr/bin/git` — `/usr/bin/git` exits 69 on this machine (Xcode-beta license block).
- **Remotes:** both repos are `jukasdrj`. Solo-dev flow: branch → commit → push. No PR ceremony.
- **New Swift files must be added to the Xcode project** (`swiftwing.xcodeproj`) or the build fails with "cannot find X in scope".

---

## Verified Starting State (2026-08-02)

Facts below were measured, not assumed. Re-check only if time has passed.

| Fact | Value |
|---|---|
| Last successful Talaria deploy | run `29606900836`, commit `d9fbdca`, 2026-07-17T19:16Z |
| Unshipped commits | **four**: `c639603`, `8a17385`, `d69f97d`, `58ca6eb` (three from July — the earlier report said two) |
| Failing CI runs | `29607181462`, `29607293043`, `30761699905` — all identical |
| Blocker | `biome check` — **1 error in 114 files**, `src/router.ts:59-65`, `allowHeaders` array wants to collapse to one line |
| `npm run test:safe` locally | **1095 passed, 1 skipped, 54 files** — green |
| Live prod spec | still stale: `BookEnrichment.provider` enum is `["isbndb"]`, results doc says "cached in KV for 2 hours" |
| Expected after deploy | `provider` enum `["google_books","open_library"]`, TTL 24 hours |

**Consequence:** the formatter fix is the *only* thing between the current tree and a green deploy. The second gate (`test:safe`) has never run since July 17 but passes locally, so it will not surprise you.

---

### Task 1: Unblock the Talaria deploy gate

The unshipped set includes production-source changes that have never been reviewed in the context of shipping them. Review is bounded to the two commits that touch deployed behavior, then fix and push.

**Files:**
- Modify: `/Users/juju/dev_repos/talaria/src/router.ts:59-65`

**Interfaces:**
- Produces: a green `Deploy to Production` run whose deployed spec has `provider` enum `google_books`/`open_library` — Task 2 asserts on this.

- [ ] **Step 1: Review the two behavior-bearing July commits**

`d69f97d` is docs-only — skip it. Review these two:

```bash
cd /Users/juju/dev_repos/talaria
G=/Library/Developer/CommandLineTools/usr/bin/git

# c639603 — OpenAPI alignment + SSE/DO-era test removal.
# Only these paths can affect production; the rest is tests/docs.
$G show c639603 -- src/api-v3/index.ts src/router.ts
$G show c639603 --stat -- src/utils/r2/r2-multipart.ts

# 8a17385 — deploy config. Changes `"//"` pseudo-keys to real JSONC comments
# so Wrangler stops deploying comments as env vars (env.//).
$G show 8a17385 -- wrangler.jsonc
```

Expected findings (confirm, don't assume): `c639603` deletes `src/utils/r2/r2-multipart.ts` (282 lines, dead after the Workflows cutover) and makes small edits to the v3 router/index; `8a17385` is a pure comment-syntax change plus a `worker-configuration.d.ts` regen. If either shows a change you can't account for, **stop and report** rather than pushing.

- [ ] **Step 2: Confirm the formatter is the only blocker**

```bash
cd /Users/juju/dev_repos/talaria
npx biome check .
```

Expected: `Checked 114 files ... Found 1 error.` — `src/router.ts` format only.

- [ ] **Step 3: Apply the formatter fix**

```bash
npx biome check --write src/router.ts
```

This collapses lines 59–65 to:

```ts
      allowHeaders: ['Content-Type', 'Authorization', 'X-Device-ID', 'X-Admin-Token', 'X-Request-ID'],
```

- [ ] **Step 4: Verify the diff is cosmetic only**

```bash
/Library/Developer/CommandLineTools/usr/bin/git diff src/router.ts
```

Expected: exactly one hunk, the `allowHeaders` array reflow. **No other files, no other hunks.** If `--write` touched anything else, revert and fix by hand.

- [ ] **Step 5: Run both CI gates locally**

```bash
npm run validate    # biome check + smoke tests
npm run test:safe   # smoke + node suite (~3 min)
```

Expected: `validate` clean; `test:safe` reports `Test Files 50 passed | 4 skipped (54)`, `Tests 1095 passed | 1 skipped`.

- [ ] **Step 6: Commit**

```bash
/Library/Developer/CommandLineTools/usr/bin/git add src/router.ts
/Library/Developer/CommandLineTools/usr/bin/git commit -m "style: satisfy biome format on router allowHeaders

Unblocks the npm run validate deploy gate, which has failed on this
single formatting error since c639603 (2026-07-17). No behavior change."
```

- [ ] **Step 7: Push and watch the run**

```bash
/Library/Developer/CommandLineTools/usr/bin/git push origin talaria
gh run watch --exit-status
```

Expected: `Pre-Deployment Checks` → `Deploy to Cloudflare Workers` → `Post-Deploy Validation` all green. This ships all five commits (`c639603`, `8a17385`, `d69f97d`, `58ca6eb`, and this one) at once.

If `Post-Deploy Validation` fails on "Verify live deployment is fresh", the deploy itself succeeded — re-read that step's output before treating it as a rollback condition.

---

### Task 2: Verify the deploy is actually live

Do not take a green CI run as proof the spec changed. Assert on the live bytes.

**Files:** none — verification only.

**Interfaces:**
- Consumes: the deploy from Task 1.
- Produces: a confirmed-fresh `https://api.oooefam.net/v3/openapi.json` — Task 3 fetches this exact document.

- [ ] **Step 1: Assert the provider enum flipped**

```bash
curl -s https://api.oooefam.net/v3/openapi.json > /tmp/live-spec.json
grep -c 'google_books' /tmp/live-spec.json
grep -c 'isbndb' /tmp/live-spec.json
```

Expected: `google_books` count ≥ 1. The `isbndb` count will still be non-zero — `AdminMetricsResponse.costAttribution.avgIsbndbCallsPerScan` legitimately keeps the name. What must be gone is the enum: re-grep for the `BookEnrichment` provider specifically.

```bash
python3 -c "import json;print(json.load(open('/tmp/live-spec.json'))['components']['schemas']['BookEnrichment']['properties']['provider']['enum'])"
```

Expected: `['google_books', 'open_library']`. If it prints `['isbndb']`, the deploy did not land — stop and diagnose before continuing.

- [ ] **Step 2: Assert the results TTL updated**

```bash
grep -o 'cached in KV for [0-9]* hours' /tmp/live-spec.json
```

Expected: `cached in KV for 24 hours`. If it says 2 hours, the deploy is stale.

- [ ] **Step 3: Record the result**

Append to the Decision Log in `talaria_swiftwing_alignment_task_plan.md`:

```markdown
| 2026-08-02 | Talaria deploy unblocked and verified live | Formatter fix on `src/router.ts` cleared `npm run validate`; shipped 5 commits backed up since 2026-07-17. Live spec now serves `google_books`/`open_library` + 24h TTL. |
```

No commit yet — this file is deleted in Task 11.

---

### Task 3: Refresh SwiftWing's committed OpenAPI spec

Blocked until Task 2 passes. Running this earlier re-pulls the stale spec and looks like success.

**Files:**
- Modify: `swiftwing/OpenAPI/talaria-openapi.yaml`
- Modify: `swiftwing/OpenAPI/.talaria-openapi.yaml.sha256`

**Interfaces:**
- Consumes: the verified-live spec from Task 2.
- Produces: a committed spec whose `BookEnrichment.provider` enum matches production — Task 5's `BookSearchResult` model is written against this file.

- [ ] **Step 1: Fetch the spec**

```bash
cd /Users/juju/dev_repos/swiftwing
./Scripts/update-api-spec.sh
```

- [ ] **Step 2: Review the diff before committing**

```bash
/Library/Developer/CommandLineTools/usr/bin/git diff swiftwing/OpenAPI/talaria-openapi.yaml
```

Expected changes: `provider` enum `isbndb` → `google_books`/`open_library`; results TTL description 2h → 24h. Anything larger means the spec drifted further than Phase 6 recorded — read it before accepting.

Rollback if it looks wrong: `/Library/Developer/CommandLineTools/usr/bin/git checkout swiftwing/OpenAPI/`

- [ ] **Step 3: Build to confirm nothing downstream broke**

```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift
```

Expected: `errors: 0, warnings: 0`.

- [ ] **Step 4: Commit**

```bash
/Library/Developer/CommandLineTools/usr/bin/git add swiftwing/OpenAPI/
/Library/Developer/CommandLineTools/usr/bin/git commit -m "chore(api): refresh committed Talaria spec after deploy

Picks up the corrected BookEnrichment provider enum (google_books /
open_library, was isbndb) and the 24h results TTL from talaria 58ca6eb."
/Library/Developer/CommandLineTools/usr/bin/git push origin main
```

---

### Task 4: Phase 8 — remove review-queue dead code

Done first, on the Phase 7 branch, so Task 7 wires the recovery sheet into a clean `ReviewCardView`.

**Files:**
- Modify: `swiftwing/Features/ReviewQueue/ReviewQueueView.swift:314-350` (delete `ProcessingItemDetailPlaceholder`)
- Delete: `swiftwing/UIComponents/ConfidenceBadge.swift`
- Modify: `swiftwing/Features/Camera/CameraViewModel.swift:459-461` (call `spineDetected()`)
- Modify: `swiftwing/Services/NetworkTypes.swift:364-366` (stale SSE comment)

**Interfaces:**
- Produces: branch `feature/enrichment-recovery`, used by Tasks 5–7.

**Decisions made here (with rationale, so the implementer doesn't re-litigate):**

- `ProcessingItemDetailPlaceholder` has **zero call sites** — the live sheet at `ReviewQueueView.swift:116` is `ProcessingItemDetailSheet`. Pure dead code; delete outright.
- `ConfidenceBadge` → **delete, don't adopt.** `ReviewCardView` already has a private `confidenceBadge` using thresholds 0.8/0.5 with icon + tinted background (Swiss Glass). `ConfidenceBadge` is a white-on-capsule design with thresholds 0.9/0.7. Adopting it would silently move the confidence bands users see and clash with the theme. Deleting removes the ambiguity the findings flagged. *(If you disagree, the alternative is a UX change and belongs in its own task, not a cleanup one.)*
- `spineDetected()` belongs in the `onBookResult` callback — that is the moment a spine resolves into a book. Note `haptics.errorOccurred()` and `haptics.retryTriggered()` are already wired at lines 388/470/493/570, so `spineDetected()` is the only orphan.

- [x] **Step 1: Create the branch**

```bash
cd /Users/juju/dev_repos/swiftwing
/Library/Developer/CommandLineTools/usr/bin/git checkout -b feature/enrichment-recovery
```

- [x] **Step 2: Confirm the placeholder is unreferenced**

```bash
grep -rn --include='*.swift' 'ProcessingItemDetailPlaceholder' .
```

Expected: exactly one hit — the declaration at `ReviewQueueView.swift:318`. If there are call sites, stop; the finding was wrong.

- [x] **Step 3: Delete the placeholder**

Remove the whole block from `ReviewQueueView.swift`, starting at the comment header:

```swift
// MARK: - US-B3: Processing Item Detail Placeholder

/// Placeholder detail view for processing items
/// Sprint 2 will implement full book detail editing here
struct ProcessingItemDetailPlaceholder: View {
```

…through its closing brace (ends just before `// Section header for confidence grouping with optional batch action`).

- [x] **Step 4: Confirm ConfidenceBadge is unreferenced, then delete it**

```bash
grep -rn --include='*.swift' 'ConfidenceBadge' . | grep -v 'UIComponents/ConfidenceBadge.swift'
```

Expected: no output (all hits are the file's own declaration and `#Preview`).

```bash
/Library/Developer/CommandLineTools/usr/bin/git rm swiftwing/UIComponents/ConfidenceBadge.swift
```

Then remove the file reference from `swiftwing.xcodeproj` (open in Xcode and delete, or the build will fail on a missing file reference).

- [x] **Step 5: Call `spineDetected()`**

In `swiftwing/Features/Camera/CameraViewModel.swift`, in `buildScanCallbacks`:

```swift
            onBookResult: { [weak self] metadata, rawJSON, _, _ in
                self?.haptics.spineDetected()
                self?.reviewQueueManager.handleBookResult(metadata: metadata, rawJSON: rawJSON, thumbnailData: capturedThumbnailData, preScannedISBN: capturedISBN, originalPhotoURL: originalPhotoURL, modelContext: modelContext)
            },
```

- [x] **Step 6: Fix the stale SSE comment**

In `swiftwing/Services/NetworkTypes.swift`, replace:

```swift
/// **SSE vs. Results Endpoint:**
/// - **SSE `result` events:** Includes title, author, isbn, coverUrl, enrichmentStatus, confidence, boundingBox
/// - **Results endpoint:** Same fields plus optional pageCount, format, publishedDate
```

with:

```swift
/// **Results endpoint (`GET /v3/jobs/scans/{jobId}/results`):**
/// - `?format=lite` (what the client requests): title, author, isbn, coverUrl,
///   enrichmentStatus, confidence — no boundingBox
/// - `?format=full`: the above plus boundingBox, pageCount, format, publishedDate
/// - SSE was removed in the Workflows cutover (talaria 3.9.0); there are no result events.
```

- [x] **Step 7: Build**

```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift
```

Expected: `errors: 0, warnings: 0`.

- [x] **Step 8: Commit**

```bash
/Library/Developer/CommandLineTools/usr/bin/git add -u
/Library/Developer/CommandLineTools/usr/bin/git commit -m "chore(review-queue): drop dead placeholder + badge, wire spine haptic

- Delete ProcessingItemDetailPlaceholder (zero call sites; the live sheet
  is ProcessingItemDetailSheet)
- Delete unused UIComponents/ConfidenceBadge (conflicting 0.9/0.7 bands vs
  the review card's 0.8/0.5; adopting it would move user-visible bands)
- Call haptics.spineDetected() from onBookResult — the only orphaned
  CameraHapticsManager method
- Replace the stale SSE-vs-results doc comment in NetworkTypes"
```

---

### Task 5: Phase 7a — `BookSearchResult` model + `TalariaService.searchBook`

**Files:**
- Modify: `swiftwing/Services/NetworkTypes.swift` (append `BookSearchResult`)
- Modify: `swiftwing/Services/TalariaService.swift` (append `searchBook`)
- Test: `swiftwingTests/Unit/Services/BookSearchTests.swift` (create)

**Interfaces:**
- Produces:
  - `public struct BookSearchResult: Sendable, Equatable, Codable` with `isbn: String?`, `isbn13: String?`, `title: String`, `authors: [String]`, `publisher: String?`, `publishedDate: String?`, `coverUrl: URL?`, `source: String`, `confidence: Double`, `fuzzyMatched: Bool`
  - `func searchBook(isbn: String?, title: String?, author: String?) async throws -> BookSearchResult` on `TalariaService`
  - Task 6 consumes `BookSearchResult`; Task 7 calls `searchBook`.

**Contract** (from the live spec, `GET /v3/books/search`): requires header `X-Device-ID`; at least one of `isbn`/`title`/`author` as query params; `200` → `{success, data: BookSearchResult, metadata}`; `400` missing params; `401` bad device id; `404` no match — all errors as `application/problem+json`.

**Error mapping decision:** 404 throws `NetworkError.apiError(problemDetails)`. Do **not** add a `NetworkError.notFound` case — `NetworkError` is switched exhaustively in several call sites and a new case is a wider change than this task warrants. Task 7 detects "no match" by inspecting `problem.status == 404`.

- [x] **Step 1: Write the failing tests**

Create `swiftwingTests/Unit/Services/BookSearchTests.swift`. It reuses the `SequencedURLProtocol` already defined in `swiftwingTests/Unit/Services/PollScanStatusResilienceTests.swift`.

```swift
import Foundation
import Testing
@testable import swiftwing

@Suite(.serialized) struct BookSearchTests {

    private func makeService() -> TalariaService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SequencedURLProtocol.self]
        return TalariaService(
            deviceId: "550e8400-e29b-41d4-a716-446655440000",
            session: URLSession(configuration: config)
        )
    }

    private func successBody() -> Data {
        """
        {"success":true,"data":{"isbn":"9780743273565","isbn13":"9780743273565",
        "title":"The Great Gatsby","authors":["F. Scott Fitzgerald"],
        "publisher":"Scribner","publishedDate":"2004-09-30",
        "coverUrl":"https://example.com/cover.jpg","source":"google",
        "confidence":0.97,"fuzzyMatched":false},
        "metadata":{"timestamp":"2026-08-02T00:00:00Z"}}
        """.data(using: .utf8)!
    }

    @Test("decodes a 200 search result into BookSearchResult")
    func decodesSuccess() async throws {
        SequencedURLProtocol.script([(200, successBody())])
        let result = try await makeService().searchBook(isbn: "9780743273565", title: nil, author: nil)

        #expect(result.title == "The Great Gatsby")
        #expect(result.authors == ["F. Scott Fitzgerald"])
        #expect(result.isbn13 == "9780743273565")
        #expect(result.confidence == 0.97)
        #expect(result.fuzzyMatched == false)
        #expect(result.coverUrl?.absoluteString == "https://example.com/cover.jpg")
    }

    @Test("404 surfaces as apiError with status 404, not a decode failure")
    func notFoundSurfacesAsApiError() async throws {
        let problem = """
        {"success":false,"type":"https://api.oooefam.net/errors/not-found",
        "title":"Not Found","status":404,"detail":"No matching book found"}
        """.data(using: .utf8)!
        SequencedURLProtocol.script([(404, problem)])

        await #expect(throws: NetworkError.self) {
            _ = try await makeService().searchBook(isbn: nil, title: "Nonexistent", author: nil)
        }
    }

    @Test("throws before hitting the network when all params are nil")
    func requiresAtLeastOneParameter() async throws {
        SequencedURLProtocol.script([(200, successBody())])

        await #expect(throws: NetworkError.self) {
            _ = try await makeService().searchBook(isbn: nil, title: nil, author: nil)
        }
        #expect(SequencedURLProtocol.recordedRequestCount() == 0)
    }
}
```

- [x] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:swiftwingTests/BookSearchTests \
  2>&1 | xcsift
```

Expected: compile failure — `cannot find 'BookSearchResult' in scope`.

- [x] **Step 3: Add the model**

Append to `swiftwing/Services/NetworkTypes.swift`:

```swift
// MARK: - Book Search (GET /v3/books/search)

/// Single best-match result from Talaria's manual book lookup endpoint.
/// Used by the enrichment-recovery flow when a scanned spine comes back
/// `not_found` or `circuit_open`.
public struct BookSearchResult: Sendable, Equatable, Codable {
    public let isbn: String?
    public let isbn13: String?
    public let title: String
    public let authors: [String]
    public let publisher: String?
    public let publishedDate: String?
    public let coverUrl: URL?
    /// `cache` | `google` | `fuzzy`
    public let source: String
    public let confidence: Double
    public let fuzzyMatched: Bool

    /// Authors joined for display, matching BookMetadata's singular `author` shape.
    public var joinedAuthors: String { authors.joined(separator: ", ") }
}

/// Envelope for `GET /v3/books/search`.
struct BookSearchResponse: Decodable {
    let success: Bool
    let data: BookSearchResult
}
```

- [x] **Step 4: Add the service method**

Append inside the `TalariaService` actor in `swiftwing/Services/TalariaService.swift`, before `// MARK: - Private Helpers`:

```swift
    /// Look up a single best-match book by ISBN, title, and/or author.
    ///
    /// Used by the enrichment-recovery flow: when a scanned spine returns
    /// `not_found` or `circuit_open`, the user can search manually and graft
    /// the result onto the pending review item.
    ///
    /// - Throws: `NetworkError.invalidResponse` if no search parameter is given;
    ///   `NetworkError.apiError` (with `status == 404`) when nothing matches.
    func searchBook(isbn: String?, title: String?, author: String?) async throws -> BookSearchResult {
        var queryItems: [URLQueryItem] = []
        if let isbn, !isbn.trimmingCharacters(in: .whitespaces).isEmpty {
            queryItems.append(URLQueryItem(name: "isbn", value: isbn))
        }
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
            queryItems.append(URLQueryItem(name: "title", value: title))
        }
        if let author, !author.trimmingCharacters(in: .whitespaces).isEmpty {
            queryItems.append(URLQueryItem(name: "author", value: author))
        }

        // The API 400s on an empty query; fail locally instead of burning a request.
        guard !queryItems.isEmpty else {
            throw NetworkError.invalidResponse
        }

        var components = URLComponents(string: "\(baseURL)/v3/books/search")
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw NetworkError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(self.deviceId, forHTTPHeaderField: "X-Device-ID")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                let decoded = try JSONDecoder().decode(BookSearchResponse.self, from: data)
                guard decoded.success else { throw NetworkError.invalidResponse }
                return decoded.data

            case 400, 401, 404, 429, 500...599:
                if let problem = try? JSONDecoder().decode(ProblemDetails.self, from: data) {
                    if httpResponse.statusCode == 429 {
                        throw NetworkError.rateLimited(
                            retryAfter: problem.retryAfterMs.map { TimeInterval($0) / 1000.0 }
                        )
                    }
                    throw NetworkError.apiError(problem)
                }
                throw NetworkError.serverError(httpResponse.statusCode)

            default:
                throw NetworkError.serverError(httpResponse.statusCode)
            }
        } catch let error as NetworkError {
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw NetworkError.noConnection
            case .timedOut:
                throw NetworkError.timeout
            default:
                throw NetworkError.invalidResponse
            }
        } catch {
            throw NetworkError.invalidResponse
        }
    }
```

- [x] **Step 5: Add the test file to the Xcode project**

Add `swiftwingTests/Unit/Services/BookSearchTests.swift` to the `swiftwingTests` target in Xcode.

- [x] **Step 6: Run the tests to verify they pass**

```bash
xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:swiftwingTests/BookSearchTests \
  2>&1 | xcsift
```

Expected: 3 tests pass, `errors: 0, warnings: 0`.

- [x] **Step 7: Commit**

```bash
/Library/Developer/CommandLineTools/usr/bin/git add swiftwing/Services/NetworkTypes.swift swiftwing/Services/TalariaService.swift swiftwingTests/Unit/Services/BookSearchTests.swift swiftwing.xcodeproj
/Library/Developer/CommandLineTools/usr/bin/git commit -m "feat(api): add BookSearchResult + TalariaService.searchBook

Wraps GET /v3/books/search for the enrichment-recovery flow. 404 surfaces
as NetworkError.apiError(status: 404) rather than a new enum case, keeping
existing exhaustive switches intact."
```

---

### Task 6: Phase 7b — recovered metadata on `PendingBookResult`

`PendingBookResult.metadata` is `let`, and the existing override pattern is `editedTitle`/`editedAuthor`. A search result carries ISBN, cover, publisher, and date too — so it needs a whole-metadata override, following the same shape.

**Files:**
- Modify: `swiftwing/Models/PendingBookResult.swift`
- Modify: `swiftwing/Features/ReviewQueue/ReviewQueueManager.swift` (add `applyRecoveredMetadata`)
- Test: `swiftwingTests/ReviewQueueManagerTests.swift` (extend)

**Interfaces:**
- Consumes: `BookSearchResult` from Task 5.
- Produces:
  - `PendingBookResult.recoveredMetadata: BookMetadata?` and `var resolvedMetadata: BookMetadata`
  - `ReviewQueueManager.applyRecoveredMetadata(id: UUID, from result: BookSearchResult)`
  - Task 7 calls `applyRecoveredMetadata` and reads `resolvedMetadata`.

- [x] **Step 1: Write the failing test**

Append to `swiftwingTests/ReviewQueueManagerTests.swift`:

```swift
    @Test("applyRecoveredMetadata replaces title, author, isbn and cover on the pending book")
    func applyRecoveredMetadataGraftsSearchResult() async throws {
        let manager = ReviewQueueManager()
        let original = BookMetadata(
            title: nil,
            author: nil,
            isbn: nil,
            confidence: 0.4,
            enrichmentStatus: .notFound
        )
        let pending = PendingBookResult(metadata: original, rawJSON: nil)
        manager.pendingBooks = [pending]

        let searchResult = BookSearchResult(
            isbn: "9780743273565",
            isbn13: "9780743273565",
            title: "The Great Gatsby",
            authors: ["F. Scott Fitzgerald"],
            publisher: "Scribner",
            publishedDate: "2004-09-30",
            coverUrl: URL(string: "https://example.com/cover.jpg"),
            source: "google",
            confidence: 0.97,
            fuzzyMatched: false
        )

        manager.applyRecoveredMetadata(id: pending.id, from: searchResult)

        let updated = try #require(manager.pendingBooks.first)
        #expect(updated.resolvedTitle == "The Great Gatsby")
        #expect(updated.resolvedAuthor == "F. Scott Fitzgerald")
        #expect(updated.resolvedISBN == "9780743273565")
        #expect(updated.resolvedMetadata.coverUrl?.absoluteString == "https://example.com/cover.jpg")
        #expect(updated.resolvedMetadata.enrichmentStatus == .success)
        // The original AI result stays intact for provenance.
        #expect(updated.metadata.title == nil)
    }
```

If `ReviewQueueManager` requires init arguments or `pendingBooks` is not settable, mirror the setup used by the tests already in this file rather than the sketch above.

- [x] **Step 2: Run to verify it fails**

```bash
xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:swiftwingTests/ReviewQueueManagerTests \
  2>&1 | xcsift
```

Expected: compile failure — `value of type 'PendingBookResult' has no member 'resolvedMetadata'`.

- [x] **Step 3: Add the override to `PendingBookResult`**

In `swiftwing/Models/PendingBookResult.swift`, add the stored property alongside the existing edits and rewrite the resolvers to read through it:

```swift
    // Editable overrides (nil = use metadata value)
    var editedTitle: String?
    var editedAuthor: String?

    /// Whole-metadata override from a manual `/v3/books/search` lookup.
    /// Kept separate from `metadata` so the original AI result stays available
    /// for provenance and debugging.
    var recoveredMetadata: BookMetadata?

    /// Metadata to display and persist: manual lookup wins over the AI result.
    var resolvedMetadata: BookMetadata { recoveredMetadata ?? metadata }

    // Resolved values (prefer edit over recovery over original)
    var resolvedTitle: String { editedTitle ?? resolvedMetadata.resolvedTitle }
    var resolvedAuthor: String { editedAuthor ?? resolvedMetadata.resolvedAuthor }

    /// ISBN resolution: prefer resolved metadata, fall back to Vision barcode, then placeholder
    var resolvedISBN: String { resolvedMetadata.isbn ?? preScannedISBN ?? "UNKNOWN-\(id.uuidString)" }
```

Set `self.recoveredMetadata = nil` in `init`, and extend `==`:

```swift
    static func == (lhs: PendingBookResult, rhs: PendingBookResult) -> Bool {
        lhs.id == rhs.id
            && lhs.editedTitle == rhs.editedTitle
            && lhs.editedAuthor == rhs.editedAuthor
            && lhs.recoveredMetadata == rhs.recoveredMetadata
    }
```

- [x] **Step 4: Add the manager method**

In `swiftwing/Features/ReviewQueue/ReviewQueueManager.swift`, next to `updatePendingBookEdits`:

```swift
    /// Graft a manual `/v3/books/search` result onto a pending review item.
    ///
    /// Clears any prior inline edits so the card shows the looked-up values
    /// rather than a half-edited mix, and marks enrichment `.success` — the
    /// data now comes from a real lookup, not a failed enrichment pass.
    func applyRecoveredMetadata(id: UUID, from result: BookSearchResult) {
        guard let index = pendingBooks.firstIndex(where: { $0.id == id }) else { return }
        let existing = pendingBooks[index]

        pendingBooks[index].recoveredMetadata = BookMetadata(
            title: result.title,
            author: result.joinedAuthors,
            isbn: result.isbn13 ?? result.isbn,
            coverUrl: result.coverUrl,
            publisher: result.publisher,
            publishedDate: result.publishedDate,
            pageCount: existing.metadata.pageCount,
            format: existing.metadata.format,
            confidence: result.confidence,
            boundingBox: existing.metadata.boundingBox,
            enrichmentStatus: .success
        )
        pendingBooks[index].editedTitle = nil
        pendingBooks[index].editedAuthor = nil
    }
```

- [x] **Step 5: Point approval at the resolved metadata**

`approveBook` currently reads `pendingBook.metadata`. Audit every use and switch the ones that feed the saved `Book` to `resolvedMetadata`, or a recovered book saves with its stale AI values:

```bash
grep -n '\.metadata' swiftwing/Features/ReviewQueue/ReviewQueueManager.swift
```

For each hit inside `approveBook`, `autoApproveBook`, `addBookToLibraryIfNotDuplicate`, and `isDuplicateResult`, replace `pendingBook.metadata` with `pendingBook.resolvedMetadata`. Leave `handleBookResult`'s own `metadata:` parameter alone — that is the inbound AI result, before any pending item exists.

- [x] **Step 6: Run the tests**

```bash
xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:swiftwingTests/ReviewQueueManagerTests \
  2>&1 | xcsift
```

Expected: all pass, `errors: 0, warnings: 0`.

- [x] **Step 7: Commit**

```bash
/Library/Developer/CommandLineTools/usr/bin/git add -u
/Library/Developer/CommandLineTools/usr/bin/git commit -m "feat(review-queue): support recovered metadata on pending books

PendingBookResult.metadata is immutable and the existing overrides only
cover title/author. Adds recoveredMetadata + resolvedMetadata following
the same pattern, and routes approval through resolvedMetadata so a
manually looked-up book saves its looked-up values."
```

---

### Task 7: Phase 7c — manual-lookup sheet wired into the review card

**Files:**
- Create: `swiftwing/Features/ReviewQueue/ManualLookupSheet.swift`
- Modify: `swiftwing/Features/ReviewQueue/ReviewCardView.swift`
- Modify: `swiftwing/Features/ReviewQueue/ReviewQueueView.swift` (pass the callback through)

**Interfaces:**
- Consumes: `TalariaService.searchBook` (Task 5), `applyRecoveredMetadata` (Task 6).
- Produces: user-visible recovery path — the deliverable of Phase 7.

**Entry condition:** the "Look up manually" button appears only when `book.resolvedMetadata.enrichmentStatus` is `.notFound` or `.circuitOpen`. Once a lookup succeeds, status becomes `.success` and the button disappears on its own.

- [x] **Step 1: Create the sheet**

Create `swiftwing/Features/ReviewQueue/ManualLookupSheet.swift`:

```swift
import SwiftUI

/// Manual book lookup for scans whose enrichment failed (`not_found` /
/// `circuit_open`). Wraps `GET /v3/books/search` and hands the chosen result
/// back to the review queue.
struct ManualLookupSheet: View {
    let book: PendingBookResult
    let talariaService: TalariaService
    let onApply: (BookSearchResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var author: String
    @State private var isbn: String
    @State private var result: BookSearchResult?
    @State private var isSearching = false
    @State private var message: String?

    init(
        book: PendingBookResult,
        talariaService: TalariaService,
        onApply: @escaping (BookSearchResult) -> Void
    ) {
        self.book = book
        self.talariaService = talariaService
        self.onApply = onApply
        // Seed from whatever the scan did manage to read.
        _title = State(initialValue: book.resolvedMetadata.title ?? "")
        _author = State(initialValue: book.resolvedMetadata.author ?? "")
        _isbn = State(initialValue: book.resolvedMetadata.isbn ?? book.preScannedISBN ?? "")
    }

    private var canSearch: Bool {
        !isSearching && [title, author, isbn].contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.swissBackground.ignoresSafeArea()

                Form {
                    Section("Search") {
                        TextField("Title", text: $title)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("lookup_title_field")
                        TextField("Author", text: $author)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("lookup_author_field")
                        TextField("ISBN", text: $isbn)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.custom("JetBrainsMono-Regular", size: 15))
                            .accessibilityIdentifier("lookup_isbn_field")
                    }

                    Section {
                        Button(action: { Task { await search() } }) {
                            HStack {
                                if isSearching { ProgressView().padding(.trailing, 4) }
                                Text(isSearching ? "Searching…" : "Search")
                            }
                        }
                        .disabled(!canSearch)
                        .accessibilityIdentifier("lookup_search_button")
                    }

                    if let message {
                        Section { Text(message).foregroundStyle(.secondary) }
                    }

                    if let result {
                        Section("Best match") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.title).font(.headline)
                                Text(result.joinedAuthors).font(.subheadline).foregroundStyle(.secondary)
                                if let isbn = result.isbn13 ?? result.isbn {
                                    Text("ISBN: \(isbn)")
                                        .font(.custom("JetBrainsMono-Regular", size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(Int(result.confidence * 100))% match · \(result.source)\(result.fuzzyMatched ? " · fuzzy" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button("Use this book") {
                                onApply(result)
                                dismiss()
                            }
                            .accessibilityIdentifier("lookup_apply_button")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Find This Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        isSearching = true
        message = nil
        result = nil
        defer { isSearching = false }

        do {
            result = try await talariaService.searchBook(
                isbn: isbn.isEmpty ? nil : isbn,
                title: title.isEmpty ? nil : title,
                author: author.isEmpty ? nil : author
            )
        } catch NetworkError.apiError(let problem) where problem.status == 404 {
            message = "No match found. Try a different spelling, or search by ISBN."
        } catch NetworkError.noConnection {
            message = "No connection. Check your network and try again."
        } catch {
            message = "Search failed. Please try again."
        }
    }
}
```

If `ProblemDetails.status` is not an `Int` (check `NetworkTypes.swift`), adjust the `where` clause to match its actual type.

- [x] **Step 2: Add the button to `ReviewCardView`**

Add a property and render it conditionally. In the `init` and stored properties:

```swift
    var onManualLookup: (() -> Void)?
```

(add `onManualLookup: (() -> Void)? = nil` to the `init` signature and assign it).

Add the computed condition and button, placed just above the Approve/Reject `HStack`:

```swift
    private var needsRecovery: Bool {
        switch book.resolvedMetadata.enrichmentStatus {
        case .notFound, .circuitOpen: return true
        default: return false
        }
    }
```

```swift
                if needsRecovery, let onManualLookup {
                    Button(action: onManualLookup) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass.circle")
                            Text("Look up manually")
                        }
                        .font(.body.bold())
                        .foregroundStyle(Color.internationalOrange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.internationalOrange, lineWidth: 1)
                        )
                    }
                    .accessibilityIdentifier("review_manual_lookup_button")
                }
```

Also switch the card's ISBN row from `book.metadata.isbn` to `book.resolvedMetadata.isbn` so a recovered ISBN shows.

- [x] **Step 3: Wire the sheet in `ReviewQueueView`**

Add state next to the existing sheet state:

```swift
    @State private var bookForManualLookup: PendingBookResult?
```

Pass the callback at the `ReviewCardView(...)` construction site:

```swift
                                onManualLookup: { bookForManualLookup = book }
```

Add the sheet alongside the existing `.sheet` modifiers:

```swift
            .sheet(item: $bookForManualLookup) { book in
                ManualLookupSheet(
                    book: book,
                    talariaService: viewModel.talariaService
                ) { result in
                    viewModel.reviewQueueManager.applyRecoveredMetadata(id: book.id, from: result)
                }
            }
```

If `CameraViewModel` does not expose `talariaService`, add a `let talariaService: TalariaService` accessor rather than constructing a second instance — a fresh `TalariaService()` would generate a different device ID and get a 401.

- [x] **Step 4: Add the new file to the Xcode project**

Add `swiftwing/Features/ReviewQueue/ManualLookupSheet.swift` to the `swiftwing` target.

- [x] **Step 5: Build and run the full test suite**

```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift

xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:swiftwingTests \
  2>&1 | xcsift
```

Expected: `errors: 0, warnings: 0`, all tests pass.

- [ ] **Step 6: Verify in the simulator** — NOT DONE, needs a human on a simulator

Launch the app, get a book into the review queue with `not_found` or `circuit_open` (use `FeatureFlagsDebugView` or a fixture injection). Confirm: the button appears, a search returns a match, "Use this book" updates the card's title/author/ISBN, and the button then disappears.

- [x] **Step 7: Commit**

```bash
/Library/Developer/CommandLineTools/usr/bin/git add -A swiftwing/Features/ReviewQueue swiftwing.xcodeproj
/Library/Developer/CommandLineTools/usr/bin/git commit -m "feat(review-queue): manual lookup recovery for failed enrichment

Books returning not_found or circuit_open were a dead end in the review
queue. Adds a lookup sheet backed by GET /v3/books/search that grafts the
result onto the pending item via applyRecoveredMetadata.

Closes Phase 7."
/Library/Developer/CommandLineTools/usr/bin/git push -u origin feature/enrichment-recovery
```

---

### Task 8: Phase 9a — zoom slider

`CameraManager` is `@MainActor @Observable` with `setZoom(_:)` clamping to 1.0–4.0 and a published `currentZoomFactor`. `CameraView.swift:25-26` already routes a pinch gesture into it. This task surfaces the same control as a slider.

**Files:**
- Modify: `swiftwing/Features/Camera/CameraOverlayView.swift`

**Interfaces:**
- Consumes: `viewModel.cameraManager.setZoom(_:)` and `.currentZoomFactor` (both already exist).

- [ ] **Step 1: Create the branch**

```bash
cd /Users/juju/dev_repos/swiftwing
/Library/Developer/CommandLineTools/usr/bin/git checkout main
/Library/Developer/CommandLineTools/usr/bin/git pull
/Library/Developer/CommandLineTools/usr/bin/git checkout -b feature/camera-ux
```

- [ ] **Step 2: Add the slider to the overlay**

In `CameraOverlayView.swift`, add a view and include it in the top-level `ZStack`:

```swift
    /// Zoom control. Mirrors the pinch gesture already wired in CameraView so
    /// the two stay in sync through cameraManager.currentZoomFactor.
    private var zoomSlider: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))

                Slider(
                    value: Binding(
                        get: { viewModel.cameraManager.currentZoomFactor },
                        set: { viewModel.cameraManager.setZoom($0) }
                    ),
                    in: 1.0...4.0
                )
                .tint(Color.internationalOrange)
                .accessibilityIdentifier("camera_zoom_slider")
                .accessibilityLabel("Zoom")
                .accessibilityValue("\(String(format: "%.1f", viewModel.cameraManager.currentZoomFactor))×")

                Text("\(String(format: "%.1f", viewModel.cameraManager.currentZoomFactor))×")
                    .font(.custom("JetBrainsMono-Regular", size: 12))
                    .foregroundStyle(.white)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 32)
            .padding(.bottom, 140)   // clears the shutter button
        }
    }
```

Add `zoomSlider` to the `ZStack` in `body`, after `statusOverlays`. If it collides with `ProcessingFeedbackView`, gate it with `if !showProcessingFeedback`.

- [ ] **Step 3: Build**

```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift
```

Expected: `errors: 0, warnings: 0`.

- [ ] **Step 4: Verify in the simulator** — slider moves, the `×` readout tracks it, and pinching updates the slider position.

- [ ] **Step 5: Commit**

```bash
/Library/Developer/CommandLineTools/usr/bin/git add -u
/Library/Developer/CommandLineTools/usr/bin/git commit -m "feat(camera): add zoom slider to the capture overlay

Surfaces the existing setZoom/currentZoomFactor pair that until now was
only reachable by pinch."
```

---

### Task 9: Phase 9b — AE/AF lock

`CameraManager.setFocusPoint(_:)` sets `.autoFocus`/`.autoExpose` on tap. This adds an explicit lock so a shelf stays sharp across a burst of captures.

**Files:**
- Modify: `swiftwing/Features/Camera/CameraManager.swift`
- Modify: `swiftwing/Features/Camera/CameraOverlayView.swift`

**Interfaces:**
- Produces: `CameraManager.isExposureFocusLocked: Bool` and `func toggleExposureFocusLock()`.

- [ ] **Step 1: Add the lock to `CameraManager`**

Add the observable property next to `currentZoomFactor`:

```swift
    /// True when focus and exposure are pinned via toggleExposureFocusLock().
    private(set) var isExposureFocusLocked = false
```

Add the method after `setFocusPoint`:

```swift
    /// Pin or release focus + exposure. Locking holds the current values so a
    /// burst of shelf captures doesn't re-hunt focus between frames.
    func toggleExposureFocusLock() {
        guard let device = videoDevice else { return }
        let shouldLock = !isExposureFocusLocked
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if shouldLock {
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            } else {
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
            }
            isExposureFocusLocked = shouldLock
        } catch {
            logger.warning("Failed to toggle AE/AF lock: \(error.localizedDescription)")
        }
    }
```

Also clear the lock when the user taps to refocus — add as the first line of `setFocusPoint`:

```swift
        isExposureFocusLocked = false
```

- [ ] **Step 2: Add the control and indicator**

In `CameraOverlayView.swift`:

```swift
    private var lockControl: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: { viewModel.cameraManager.toggleExposureFocusLock() }) {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.cameraManager.isExposureFocusLocked ? "lock.fill" : "lock.open")
                        Text("AE/AF")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(viewModel.cameraManager.isExposureFocusLocked ? Color.internationalOrange : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityIdentifier("camera_ae_af_lock_button")
                .accessibilityLabel(viewModel.cameraManager.isExposureFocusLocked ? "Unlock exposure and focus" : "Lock exposure and focus")
                .padding(.trailing, 16)
            }
            Spacer()
        }
        .padding(.top, 8)
    }
```

Add `lockControl` to the `ZStack` in `body`.

- [ ] **Step 3: Build**

```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift
```

Expected: `errors: 0, warnings: 0`.

- [ ] **Step 4: Verify on a physical device.** The simulator's fake camera does not report `.locked` support, so the button will no-op there. Confirm on hardware that the icon fills, the tint turns orange, and tapping the preview to refocus clears the lock.

- [ ] **Step 5: Commit**

```bash
/Library/Developer/CommandLineTools/usr/bin/git add -u
/Library/Developer/CommandLineTools/usr/bin/git commit -m "feat(camera): add AE/AF lock with indicator

Holds focus and exposure across a burst of shelf captures. Tapping the
preview to refocus releases the lock."
```

---

### Task 10: Phase 9c — first-run camera guidance

`OnboardingView` already exists behind `@AppStorage("hasCompletedOnboarding")` (`RootView.swift:6,57`). This adds a separate, camera-specific coach overlay with its own key, so it can appear the first time the camera tab is opened without re-running onboarding.

**Files:**
- Create: `swiftwing/Features/Camera/CameraFirstRunGuidance.swift`
- Modify: `swiftwing/Features/Camera/CameraView.swift`

- [ ] **Step 1: Create the guidance overlay**

Create `swiftwing/Features/Camera/CameraFirstRunGuidance.swift`:

```swift
import SwiftUI

/// One-time coach overlay for the camera tab. Uses its own AppStorage key —
/// separate from `hasCompletedOnboarding` — so it can be reset or shown
/// independently of app onboarding.
struct CameraFirstRunGuidance: View {
    @AppStorage("hasSeenCameraGuidance") private var hasSeenCameraGuidance = false
    let onDismiss: () -> Void

    private let tips: [(icon: String, title: String, body: String)] = [
        ("books.vertical", "Fill the frame", "Get the spines edge to edge — one shelf at a time works best."),
        ("hand.tap", "Tap to focus", "Tap any spine to focus and set exposure there."),
        ("lock", "Lock it in", "Tap AE/AF to hold focus across a run of shots."),
        ("checklist", "Review before saving", "Everything lands in the review queue first — nothing is added without your approval.")
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Scanning Shelves")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(tips, id: \.title) { tip in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: tip.icon)
                                .font(.title3)
                                .foregroundStyle(Color.internationalOrange)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tip.title)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text(tip.body)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .dynamicTypeSize(.xSmall ... .accessibility3)

                Button(action: dismiss) {
                    Text("Start Scanning")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.internationalOrange)
                        .clipShape(.rect(cornerRadius: 8))
                }
                .accessibilityIdentifier("camera_guidance_dismiss_button")
            }
            .padding(28)
            .swissGlassCard()
            .padding(24)
        }
        .transition(.opacity)
    }

    private func dismiss() {
        hasSeenCameraGuidance = true
        onDismiss()
    }
}
```

- [ ] **Step 2: Present it from `CameraView`**

Add to `CameraView`:

```swift
    @AppStorage("hasSeenCameraGuidance") private var hasSeenCameraGuidance = false
    @State private var showGuidance = false
```

Add to the outermost `ZStack`, on top:

```swift
            if showGuidance {
                CameraFirstRunGuidance { withAnimation(.swissSpring) { showGuidance = false } }
            }
```

And on appear:

```swift
        .onAppear {
            if !hasSeenCameraGuidance { showGuidance = true }
        }
```

- [ ] **Step 3: Add the file to the Xcode project** (`swiftwing` target).

- [ ] **Step 4: Build**

```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift
```

Expected: `errors: 0, warnings: 0`.

- [ ] **Step 5: Verify** — delete the app from the simulator, relaunch, complete onboarding, open the camera tab: guidance shows once. Kill and relaunch: it does not show again.

- [ ] **Step 6: Commit and push**

```bash
/Library/Developer/CommandLineTools/usr/bin/git add -A swiftwing/Features/Camera swiftwing.xcodeproj
/Library/Developer/CommandLineTools/usr/bin/git commit -m "feat(camera): first-run scanning guidance

Separate AppStorage key from app onboarding so camera guidance can show
on first camera-tab visit and be reset independently.

Closes Phase 9."
/Library/Developer/CommandLineTools/usr/bin/git push -u origin feature/camera-ux
```

---

### Task 11: Close out — merge and delete the planning files

The point of this task is that these files do not survive to become the next `talaria/task_plan.md`.

**Files:**
- Delete: `talaria_swiftwing_alignment_task_plan.md`
- Delete: `talaria_swiftwing_alignment_findings.md`
- Delete: `talaria_swiftwing_alignment_progress.md`
- Delete: `talaria_swiftwing_alignment_execution_plan.md` (this file)

- [ ] **Step 1: Merge both feature branches**

```bash
cd /Users/juju/dev_repos/swiftwing
G=/Library/Developer/CommandLineTools/usr/bin/git
$G checkout main
$G merge --no-ff feature/enrichment-recovery
$G merge --no-ff feature/camera-ux
```

Resolve conflicts in `swiftwing.xcodeproj/project.pbxproj` by taking both file additions.

- [ ] **Step 2: Full build + test on the merged tree**

```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  clean build 2>&1 | xcsift

xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  2>&1 | xcsift
```

Expected: `errors: 0, warnings: 0`, all tests pass. **Do not proceed to Step 3 until this is green** — the planning files are the record of what was attempted.

- [ ] **Step 3: Delete the planning files**

```bash
/Library/Developer/CommandLineTools/usr/bin/git rm --ignore-unmatch \
  talaria_swiftwing_alignment_task_plan.md \
  talaria_swiftwing_alignment_findings.md \
  talaria_swiftwing_alignment_progress.md \
  talaria_swiftwing_alignment_execution_plan.md
rm -f talaria_swiftwing_alignment_*.md
```

(`--ignore-unmatch` + the `rm` covers the case where these are gitignored local-only scratch, as `talaria/{task_plan,findings,progress}.md` were.)

- [ ] **Step 4: Commit and push**

```bash
/Library/Developer/CommandLineTools/usr/bin/git add -A
/Library/Developer/CommandLineTools/usr/bin/git commit -m "chore: close Talaria/SwiftWing alignment work, remove planning files

Phases 7-9 complete. Deleting the planning files per the plan's own exit
condition — stale plan files drove phantom work once already."
/Library/Developer/CommandLineTools/usr/bin/git push origin main
/Library/Developer/CommandLineTools/usr/bin/git branch -d feature/enrichment-recovery feature/camera-ux
```

- [ ] **Step 5: Update `swiftwing/CLAUDE.md`**

Its "Last Updated: 2026-07-17" and Epic 6 status are now stale. Bump the date and note that the manual-lookup recovery path exists so the next session doesn't rediscover it.

---

## Dependency Graph

```
Task 1 (talaria deploy) ──► Task 2 (verify live) ──► Task 3 (spec refresh)
                                                          │
                            Task 4 (Phase 8) ◄────────────┘
                                  │
                                  ▼
                            Task 5 ──► Task 6 ──► Task 7   [feature/enrichment-recovery]

                            Task 8 ──► Task 9 ──► Task 10  [feature/camera-ux]
                                  (independent of 4-7; can run in parallel)

                            Tasks 7 + 10 ──► Task 11 (merge + cleanup)
```

Tasks 4–7 technically only need Task 3 for spec *accuracy*, not compilation — but running them against a stale spec is how the Phase 6 drift happened. Keep the ordering.

---

## Open Questions

1. **Task 1 Step 1 review depth.** The plan reviews only the production-source hunks of `c639603` and `8a17385`, not the ~4000 deleted test lines. If you want the deleted tests audited too, that is a separate task and should be done before pushing — but note those tests were deleted *because* they covered SSE/DO code paths that no longer exist, and the surviving suite is green at 1095 tests.
2. **`ConfidenceBadge`: delete vs adopt** (Task 4). The plan deletes it. Adopting it instead changes the confidence bands shown in the review queue from 0.8/0.5 to 0.9/0.7 — a user-visible change, not a cleanup.
3. **Task 9 verification needs hardware.** AE/AF lock cannot be meaningfully verified in the simulator.
