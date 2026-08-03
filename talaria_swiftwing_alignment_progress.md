# Talaria + SwiftWing Alignment — Session Progress

## Session: 2026-08-01

### Completed
- Read `talaria/CLAUDE.md`, `talaria/AGENTS.md`
- Read `swiftwing/CLAUDE.md`, `swiftwing/AGENTS.md`
- Read Talaria route implementations:
  - `src/api-v3/jobs/scans.ts`
  - `src/api-v3/jobs/scans-schemas.ts`
  - `src/api-v3/openapi-static.json`
  - `src/workflows/book-scan-workflow.ts`
- Read SwiftWing integration code:
  - `swiftwing/Services/TalariaService.swift`
  - `swiftwing/Services/NetworkTypes.swift`
  - `swiftwing/Models/Book.swift`
  - `swiftwing/Features/Camera/CameraView.swift`
  - `swiftwing/Features/Camera/CameraViewModel.swift`
  - `swiftwing/Features/ReviewQueue/ReviewQueueView.swift`
  - `swiftwing/Features/Library/LibraryView.swift`
  - `swiftwing/Features/Library/LibraryViewModel.swift`
  - `swiftwing/Features/Library/LibraryExporter.swift`
  - `swiftwingTests/LibraryExporterTests.swift`
- Verified export feature is fully implemented and removed it from improvement list
- Created planning files:
  - `talaria_swiftwing_alignment_task_plan.md`
  - `talaria_swiftwing_alignment_findings.md`
  - `talaria_swiftwing_alignment_progress.md`

### Verification
- No code changes made.
- No build/test commands run (research-only session).

### Open Questions
- ~~Which phase should be implemented first?~~ → Resolved 2026-08-02: Phase 7 (enrichment recovery).
- ~~Should planning files remain in repo until work begins?~~ → Resolved: keep until Phase 9 closes, then delete (see task plan Next Actions #3).

---

## Session: 2026-08-02 (Claude Code)

### Completed — Phase 6 (truth pass + spec drift)
- Traced review provenance: opencode/ollama-cloud, 2026-08-01, five sessions. Audited tool calls — 116 SwiftWing paths vs 13 Talaria paths read.
- Verified against live code (all confirmed dead/unwired): `ProcessingItemDetailPlaceholder` (`ReviewQueueView.swift:318`, 0 call sites), `ConfidenceBadge` (referenced only in its own `#Preview`), `spineDetected()` (`CameraHapticsManager.swift:24`, 0 call sites), `/v3/books/search` (no Swift caller).
- **Refuted 2 review claims:** SwiftData migration plan exists (`BookSchemaVersioning.swift:97,110`); three contract round-trip test files exist.
- **Closed 1 open question:** auto-approve IS in `FeatureFlagsDebugView.swift:6-45`.
- **Found 1 unlisted gap:** stale SSE doc comment at `NetworkTypes.swift:365`.
- Deleted `talaria/{task_plan,findings,progress}.md` (May 5 zombies; gitignored, archived to scratchpad first).
- Fixed `talaria/src/api-v3/openapi-static.json` — provider enum + 2 descriptions + results TTL.

### Verification
- talaria `npm run test:smoke` → **114 passed, 10 files**.
- talaria `npm run validate` → lint fails in `src/router.ts` (allowHeaders formatting). **Pre-existing**: confirmed by `git stash` + `biome check src/router.ts` on pristine HEAD — same failure, and that file is not in my diff. Left unfixed deliberately; unrelated to this change.
- JSON validity of edited spec confirmed via `json.load`.
- No SwiftWing Swift code changed this session → no xcodebuild run required.

### Errors Encountered
| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| `grep --include=*.swift` → "no matches found" | 1 | zsh glob expansion; quote the pattern (`--include="*.swift"`) | ✅ |
| talaria stubs absent from new worktree | 1 | They are gitignored (`.gitignore:66-68`), so untracked and not carried into worktrees — deleted from the main checkout instead | ✅ |
| `npm run validate` fails on lint | 1 | Pre-existing `router.ts` formatting error, verified against pristine HEAD; out of scope | ✅ (not mine) |

---

## Session: 2026-08-02 (cont.) — Tasks 4–7 on `feature/enrichment-recovery`

Execution plan Tasks 4–7 (Phases 8 then 7). Branch pushed to `origin/feature/enrichment-recovery`.

### Completed

| Task | Commit | Change |
|---|---|---|
| 4 — Phase 8 | `ee0a352` | Deleted `ProcessingItemDetailPlaceholder` + `UIComponents/ConfidenceBadge.swift`; called `haptics.spineDetected()` from `onBookResult`; replaced the stale SSE-vs-results comment in `NetworkTypes.swift` |
| 5 — Phase 7a | `bca7c15` | `BookSearchResult` model + `TalariaService.searchBook` wrapping `GET /v3/books/search` |
| — | `541ebdd` | Test-isolation fix (see Errors) |
| 6 — Phase 7b | `452c5a4` | `PendingBookResult.recoveredMetadata` / `resolvedMetadata`; `ReviewQueueManager.applyRecoveredMetadata`; approval **and** dedup routed through `resolvedMetadata` |
| 7 — Phase 7c | `9057591` | `ManualLookupSheet.swift`; conditional "Look up manually" button on `ReviewCardView`; sheet wired into `ReviewQueueView` |
| — | `a54b298` | Plan updates |

### Verification
- App target build: **0 errors, 0 warnings**.
- Full `swiftwingTests`: **147 passed, 0 failed, 0 errors, 0 warnings**.
- Test count reconciled: 106 `@Test` declarations, 5 parameterized, expanding to 147. The first full run reported only **146** — the isolation race wasn't merely failing two tests, it was stopping one from running at all.
- Both deletions were confirmed zero-call-site by grep **before** removal, per the plan's stop condition.
- `BookSearchResult` was checked field-by-field against `OpenAPI/talaria-openapi.yaml:634` rather than trusted from the plan — required/optional split matches exactly.

### Errors Encountered
| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| `BookSearchTests/decodesSuccess` + `PollScanStatusResilienceTests/transientBlipsAreAbsorbedAndScanSucceeds` fail in the full suite; both pass in isolation | 1 | The plan said to reuse `SequencedURLProtocol`. Its response script is **static**, and Swift Testing's `.serialized` only orders tests *within* one suite — two suites racing on it clobber each other. Gave `BookSearchTests` its own `BookSearchURLProtocol`. | ✅ |
| Plan sketch used `manager.pendingBooks`; real property is `pendingReviewBooks` | 1 | Plan anticipated this; seeded via `handleBookResult`, which also requires non-empty **author** as well as title. | ✅ |
| `ManualLookupSheet.swift` not compiled after creation | 1 | The app target is **not** a filesystem-synchronized group (only `swiftwingTests`/`swiftwingUITests` are), so new app files need explicit `project.pbxproj` entries. Added all four (build file, file ref, group child, sources phase). | ✅ |

### Remaining
1. **Task 7 Step 6 — simulator verification (NOT DONE).** Needs a human: drive a `not_found` / `circuit_open` book into the review queue, then confirm the button appears, a search returns a match, "Use this book" updates title/author/ISBN, and the button then disappears. Everything below the UI is unit-tested; this path is not.
2. **Tasks 8–10 — Phase 9 camera UX** on `feature/camera-ux` (zoom slider, AE/AF lock, first-run guidance). Independent of this branch; can start now.
3. **Task 11 — close out:** merge both branches, then delete **all four** planning files.

### Known follow-up (out of scope, not a blocker)
`SequencedURLProtocol`'s doc comment in `PollScanStatusResilienceTests.swift:5-7` still asserts that `.serialized` makes it parallel-safe. That invariant breaks for any second suite that uses it. Left as-is to keep this branch scoped; worth correcting at the source before the next test reuses it.
