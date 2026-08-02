# Talaria + SwiftWing Alignment Findings

## 1. Contract Alignment — ✅ ALIGNED

### Endpoints
| Endpoint | Talaria Implementation | SwiftWing Spec | SwiftWing Client |
|----------|------------------------|----------------|------------------|
| `POST /v3/jobs/scans` | `src/api-v3/jobs/scans.ts` lines 184-339 | `OpenAPI/talaria-openapi.yaml` lines 29-88 | `TalariaService.uploadScan(image:deviceId:)` |
| `GET /v3/jobs/scans/{jobId}` | lines 341-417 | lines 89-116 | `pollScanStatus(jobId:)` |
| `GET /v3/jobs/scans/{jobId}/results` | lines 419-509 | lines 149-187 | `fetchPollingResults(jobId:)` |
| `DELETE /v3/jobs/scans/{jobId}` | lines 511-581 | lines 117-148 | Not currently used in client flow |

### Data Fields
Talaria returns `DetectedBook` with:
- `title` (required)
- `confidence` (required)
- `isbn`, `author`, `authors[]`, `coverUrl`, `publisher`, `publishedDate`, `format`, `boundingBox`, `enrichmentStatus`, nested `enrichment`

SwiftWing `BookMetadata` (in `Services/NetworkTypes.swift`):
- Decodes all fields above
- Forward-compatible: accepts singular `author` or plural `authors[]`
- Normalizes placeholder ISBN `"unknown"` to `nil`
- `EnrichmentStatus` enum handles `success`, `not_found`, `error`, `circuit_open`, `review_needed`, with unknowns defaulting to `.pending`

### Minor Gaps / Notes
1. ~~**Talaria spec says `BookEnrichment.provider` enum = `isbndb`**~~ — ✅ **FIXED 2026-08-02** (talaria `58ca6eb`). Verified: `talaria/src/schemas/book.ts:133` defines `z.enum(['google_books', 'open_library'])`; the spec advertised `["isbndb"]`, a provider removed Feb 2026. Corrected in `openapi-static.json`, which is **hand-maintained** (`src/router.ts:141`), not regenerated. SwiftWing's committed spec still needs refreshing — see "Deploy ordering" below.
2. **SwiftWing `BookMetadata` does not decode `format` enum** — it stores format as `String?`, so any unknown Talaria format strings pass through safely.
3. **DELETE endpoint not surfaced in UI** — exists and works, but SwiftWing has no user-facing cancel.
4. ~~**KV TTL mismatch**~~ — ✅ **FIXED 2026-08-02** (talaria `58ca6eb`). Verified: `book-scan-workflow.ts:94` writes `job:results:{jobId}` at `expirationTtl: 86400`, and `scans.ts:466` reads that same key. Spec description corrected 2h → 24h.
5. **`BookMetadata` missing nested `enrichment` object decode** — ✅ verified 2026-08-02: `CodingKeys` (`NetworkTypes.swift:427`) has no `enrichment` case, so the nested object is dropped. Also confirmed `pageCount` (decoded at `NetworkTypes.swift:494`) appears nowhere in `scans-schemas.ts` or `openapi-static.json` — it is a client-side phantom field.
6. **Stale SSE documentation inside the contract file** (unlisted by the original review) — `NetworkTypes.swift:365` documents *"SSE `result` events: Includes title, author, isbn, coverUrl…"*. SSE was removed in the Workflows cutover; both `CLAUDE.md` files already say so. Misleading comment in the one file most likely to be read when touching the contract.

## 2. Workflow Alignment

### Talaria pipeline (`src/workflows/book-scan-workflow.ts`)
1. R2 image upload
2. Gemini Vision OCR
3. Immediate R2 delete (privacy)
4. Waterfall enrichment (Google Books + cache)
5. KV store results for 24h

### SwiftWing flow (`CameraViewModel.swift`)
1. Capture + preprocess image
2. Upload via `TalariaService`
3. Poll status until `completed`/`failed`/`canceled`
4. Fetch `?format=lite` results
5. Deduplicate via ISBN and add to review queue / library

### Alignment verdict
The polling workflow matches. The old SSE/firehose paths referenced in historical code are dead and correctly treated as 404 by both sides.

## 3. Functional / GUI / Usability Gaps Identified

### Already implemented (no action needed)
- **Library export** (`LibraryExporter.swift`, `LibraryViewModel.exportLibrary`, `ActivityViewController`) — complete with Hardcover CSV format and tests.
- **Review queue** with confidence grouping and bulk approve.
- **Offline queue** with retry on reconnect.
- **Rate-limit handling** with countdown and deferred retry.
- **Duplicate detection** alert.

### Camera UX (SwiftWing)
| Gap | Why it matters |
|-----|----------------|
| No visible zoom slider | Only pinch-to-zoom; one-handed use is hard |
| No AE/AF lock indicator | Focus tap shows brackets, but no lock confirmation |
| `CameraHapticsManager` has distinct haptics (error=heavy, retry=medium, success=light, auto-approve=light) but **`spineDetected()` never called** — 0 call sites |
| Minimal empty-state guidance | First-time users don't know tap-to-focus / pinch-to-zoom (library has empty-state views; camera does not) |

### Review Queue (SwiftWing)
| Gap | Why it matters |
|-----|----------------|
| `ProcessingItemDetailPlaceholder` at `ReviewQueueView.swift:318-346` is **dead code** — never referenced, confusing | Should be removed; actual detail sheet is `ProcessingItemDetailSheet` in `BookDetailSheetView.swift:7-145` (fully implemented: editable title/author, ISBN display, confidence indicator, Save/Discard) |
| No "rescan this book" action | User must manually re-capture if metadata is wrong |
| ~~Auto-approve not exposed in FeatureFlagsDebugView?~~ — ✅ **RESOLVED 2026-08-02: no gap.** It IS exposed: `FeatureFlagsDebugView.swift:6-45` has the enable toggle, a threshold slider rendering `Int(threshold * 100)%`, a toast toggle, and a reset-to-defaults (0.90). | No action — remove from list |
| `ConfidenceBadge` standalone component exists but **unused** — review cards use inline badge (`ReviewCardView.swift:124-149` renders "95%") | Consolidate or remove dead component |

### Library (SwiftWing)
| Gap | Why it matters |
|-----|----------------|
| `/v3/books/search` not used | Endpoint exists but no manual ISBN/title lookup in UI |
| No scan history / log | Can't see past scans or reopen a previous batch |

### Backend (Talaria)
| Gap | Why it matters |
|-----|----------------|
| No enrichment retry endpoint | `circuit_open` / `error` statuses force full re-scan from client |
| No `minConfidence` filter on results | Client receives all results and filters locally |
| Book search lacks pagination | Single-result design; hard to scale if catalog grows |

## 4. Recommended Priority Order (Revised)

1. **Enrichment degradation recovery** — `/v3/books/search` exists but no manual lookup UI (user hits `not_found` with zero recovery path); no backend retry for `circuit_open`/`error` forces full re-scan + re-photo
2. **Review queue cleanup** — remove dead `ProcessingItemDetailPlaceholder`; consolidate/remove unused `ConfidenceBadge`; verify auto-approve debug toggle
3. **Camera UX quick wins** (zoom slider, focus lock, hook up `spineDetected()` haptic) — low effort, high daily impact
4. **Library search + scan history** — adds post-scan value
5. **API ergonomics** (pagination, confidence filter, spec drift fix) — nice-to-have later

**Rationale**: The happy path works. The unhappy path (enrichment failure, not_found) is currently a dead end — higher leverage than camera cosmetics.

## 5. Risks / Constraints

- SwiftWing requires **0 errors, 0 warnings** on every build (`xcodebuild ... | xcsift`).
- Swift 6.2 strict concurrency: new UI helpers must use `@MainActor` or actors correctly.
- Any new book fields need updates in three places: Talaria schema, `BookMetadata`, SwiftData `Book` model. ~~**SwiftData migration cost**: `Book.swift` must use `@VersionedSchema` first, otherwise every new field = "wipe library" release.~~ — ✅ **CORRECTED 2026-08-02: already solved, risk overstated.** `Models/BookSchemaVersioning.swift` defines `BookSchemaV1`/`BookSchemaV2` as `VersionedSchema` and `BookMigrationPlan: SchemaMigrationPlan` (line 97) with a lightweight stage (line 110). Additive fields are a normal lightweight migration, not a data-loss event.
- Talaria R2 images are deleted immediately after Gemini; a retry-enrichment endpoint can only re-run enrichment on cached detections, not re-OCR.

### Deploy ordering (blocks the SwiftWing spec refresh)

`Scripts/update-api-spec.sh` fetches the **live** `https://api.oooefam.net/v3/openapi.json`. The spec corrections in talaria `58ca6eb` are committed but **not deployed**, so running the script now would re-pull the old `isbndb`/2-hour spec and silently undo the fix. Correct order:

1. Merge + `npm run deploy` in talaria
2. Confirm `curl -s https://api.oooefam.net/v3/openapi.json | grep -A3 '"provider"'` shows `google_books`
3. Then `./Scripts/update-api-spec.sh` in swiftwing and commit the refreshed YAML

Until step 1 lands, `swiftwing/OpenAPI/talaria-openapi.yaml` still carries the wrong provider enum. This is documentation-only drift — no client code reads the `provider` field today.

## 6. Provenance & confidence

These findings originated in **opencode** (ollama-cloud), 2026-08-01 22:29 → 2026-08-02 10:03, across five sessions: an initial plan review plus two `@general` verifier subagents (deepseek-v4-pro), then two critical-review passes (minimax-m3, then nemotron-3-ultra which wrote the file edits). Not Claude Code — which is why none of it appears in Claude's session history.

**Coverage was heavily asymmetric.** Tool-call audit of those sessions: **116 distinct SwiftWing paths read vs. 13 Talaria paths**, with `openapi-static.json` read exactly once and zero Talaria files edited. Practical consequence:

- **SwiftWing claims** were mostly grounded and survived re-verification.
- **Talaria claims** were largely inferred. The reviews asserted the runtime "hardcodes `google_books`" — it does not; `src/schemas/book.ts:133` is a two-value enum. Right conclusion (spec is wrong), wrong reasoning.
- Two review recommendations were **already satisfied** and should not drive work: a `BookMetadata` round-trip test (three exist: `ScanResultsResponseContractTests`, `TalariaContractAdherenceTests`, `PollScanStatusResilienceTests`) and a SwiftData migration plan (`BookSchemaVersioning.swift`).

**Rule going forward:** treat any Talaria-side claim in this document as unverified until read against `talaria/src/`.
