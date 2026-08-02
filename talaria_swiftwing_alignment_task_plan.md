# Talaria + SwiftWing Alignment & Usability Improvements — Task Plan

## Goal
Verify that the Talaria backend and SwiftWing iOS app remain aligned on API contract, data models, and error handling; then document and prioritize GUI/function/usability improvements across both repos. Security improvements are explicitly out of scope.

## Status
- **Phase:** 6 complete + deployed and verified live. Phase 7 (enrichment recovery) is next.
- **Started:** 2026-08-01
- **Last Updated:** 2026-08-02
- **Execution plan:** `talaria_swiftwing_alignment_execution_plan.md` (Tasks 1–3 done; 4–11 remain)

## Scope
- Talaria repo: `/Users/juju/dev_repos/talaria`
- SwiftWing repo: `/Users/juju/dev_repos/swiftwing`
- Focus areas: API contract, scan workflow, review queue UX, camera UX, library features

## Phases

| Phase | Description | Files / Areas | Status |
|-------|-------------|---------------|--------|
| 1 | **Contract verification** | Compare Talaria routes + schemas against SwiftWing `OpenAPI/talaria-openapi.yaml` and `TalariaService.swift` | ✅ Complete |
| 2 | **Data model mapping audit** | Map Talaria `DetectedBook` ↔ SwiftWing `BookMetadata` ↔ SwiftData `Book` | ✅ Complete |
| 3 | **Identify GUI/usability gaps** | Camera, review queue, library, settings | ✅ Complete |
| 4 | **Identify functional gaps** | Unused endpoints, retry flows, enrichment degradation | ✅ Complete |
| 5 | **Create prioritized improvement roadmap** | Phase plan with effort + dependencies | ✅ Complete |
| 6 | **Truth pass + spec drift** | Delete stale talaria stubs; correct refuted claims; fix `openapi-static.json` provider enum + TTL | ✅ Complete (2026-08-02) |
| 7 | **Enrichment degradation recovery** | Wire `/v3/books/search` into a manual-lookup recovery sheet for `not_found` / `circuit_open` | 🔄 Next — not started |
| 8 | **Review queue cleanup** | Delete `ProcessingItemDetailPlaceholder`; consolidate/remove unused `ConfidenceBadge`; call `spineDetected()` | ⏸ Queued (fold into Phase 7's branch) |
| 9 | **Camera UX quick wins** | Zoom slider, AE/AF lock indicator, first-run guidance | ⏸ Queued |

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-08-01 | Treat SwiftWing repo as planning-file owner | SwiftWing has explicit `.claude/rules/planning-mandatory.md`; Talaria has its own docs but the user asked per SwiftWing rule |
| 2026-08-01 | Export feature removed from improvement list | Already fully implemented (`LibraryExporter.swift`, `LibraryViewModel.exportLibrary`, `ActivityViewController`, tests) |
| 2026-08-01 | Do not change production code yet | User asked only for alignment assessment + plan; implementation requires explicit go-ahead |
| 2026-08-02 | Corrected 3 wrong claims in findings | Auto-approve exists, detail sheet is implemented, confidence badge shows percentages — findings updated |
| 2026-08-02 | Reordered priority: enrichment recovery > review cleanup > camera polish | Unhappy path (not_found, circuit_open) is a dead end; higher leverage than happy-path cosmetics |
| 2026-08-02 | Deleted `talaria/{task_plan,findings,progress}.md` | Zombie stubs from a 2026-05-05 opencode "Talaria code review". Drove work on `JobStateManagerDO` TTL cleanup and SSE flush config — both deleted from the codebase in the Workflows cutover. Gitignored (`.gitignore:66-68`), so local-only scratch; copies archived to the session scratchpad before removal. |
| 2026-08-02 | Corrected 2 review claims that the code refutes | Reviews asserted no SwiftData migration plan (`BookSchemaVersioning.swift` has V1/V2 + `BookMigrationPlan`) and implied no contract round-trip tests (three exist). Both were driving phantom work. |
| 2026-08-02 | Closed the auto-approve "verify debug toggle" open question | It IS exposed — `FeatureFlagsDebugView.swift:6-45`. Not a gap. |
| 2026-08-02 | Fixed Talaria spec drift at the source rather than noting it | `58ca6eb`: provider enum `isbndb` → `google_books`/`open_library`, results TTL 2h → 24h. Root cause was hand-maintained `openapi-static.json` drifting from `src/schemas/book.ts`. SwiftWing spec refresh is **blocked on deploy** — see findings §5 "Deploy ordering". |
| 2026-08-02 | Recorded review provenance in findings §6 | Work was opencode/ollama-cloud, not Claude. Coverage was 116 SwiftWing paths vs 13 Talaria paths, which explains why Talaria claims didn't hold up. Future readers need that confidence signal. |
| 2026-08-02 | Shipped the whole unshipped backlog rather than cherry-picking | Talaria had been undeployable since 2026-07-17: `npm run validate` is the deploy gate and `biome check` failed on one cosmetic array reflow in `src/router.ts`. Reviewed the production-source hunks of all four backed-up commits before pushing — `r2-multipart.ts` had zero references, `worker-configuration.d.ts` changed only a temp-path comment (identical type hash), and the three paths dropped from the served spec were routes that no longer exist. Nothing to discard. Fix pushed as `6288a5b`; run `30764565663` green through Post-Deploy Validation. |
| 2026-08-02 | Found an unshipped CORS fix in `c639603` | It adds `X-Device-ID`/`X-Admin-Token`/`X-Request-ID` to `allowHeaders` and drops four dead WebSocket ones. Every v3 endpoint requires `X-Device-ID`, so browser clients had been broken since the Workflows cutover; native iOS was unaffected (no `Origin` header → `'*'`, no preflight), which is why SwiftWing never surfaced it. Verified live: preflight now returns `access-control-allow-headers: ...,X-Device-ID,...`. Health also went `3.8.0` → `3.9.0`. |
| 2026-08-02 | Verified the deploy against live bytes, not the CI checkmark | `BookEnrichment.provider` enum is now `google_books`/`open_library`, results TTL reads 24 hours, and `firehose`/`{jobId}/upload`/`{jobId}/cleanup` are gone from the served paths. Only then ran `./Scripts/update-api-spec.sh` — running it before the deploy would have silently re-pulled the stale spec (findings §5). |

## Errors Encountered

| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| None so far | — | — | — |

## Next Actions

1. ~~Deploy talaria, then refresh the committed spec.~~ ✅ Done 2026-08-02 — see Decision Log. Base is stable and pushed on both repos.
2. Phase 8 then Phase 7 on branch `feature/enrichment-recovery` — Tasks 4–7 of `talaria_swiftwing_alignment_execution_plan.md`.
3. Phase 9 on branch `feature/camera-ux` — Tasks 8–10. Independent of Tasks 4–7; can run in parallel.
4. Delete **all four** planning files (these three plus the execution plan) once Phase 9 closes — do not leave them to become the next `talaria/task_plan.md`.
