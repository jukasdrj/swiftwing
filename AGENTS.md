# AGENTS.md

Native iOS book-spine scanner. SwiftUI, SwiftData, Swift 6 strict concurrency. It talks to Talaria and keeps the library on device.

**Bundle ID:** `com.ooheynerds.swiftwing`
**Deployment:** iOS 27.0+

Status lives in `CURRENT-STATUS.md`. Orientation: `START-HERE.md`.

## Commands

Never call `xcodebuild` without piping it through `xcsift`. `xcsift` reads that log on stdin. It is not a build command. Warnings are failures.

```bash
make build      # simulator build, iPhone 18 Pro Max, through xcsift
make test-ui    # UI tests, -parallel-testing-enabled NO
make update-spec
```

The same `xcodebuild … 2>&1 | xcsift` lines are in the `Makefile`.

## Invariants

- Actors for mutable shared state. No `DispatchSemaphore` or `DispatchGroup` with async/await. `Task.detached` only for CPU work that must leave the actor (image encode).
- SwiftData writes go through `DataSyncActor` (`@MainActor`). Use `@Environment(\.modelContext)`. `\.modelContainer` is not an environment key.
- `ImagePreprocessor` emits one upright JPEG for Talaria: long edge at most 1920, EXIF tag 1. No contrast, denoise, or second encode.
- Scan upload is one upright JPEG or PNG under 10MB. Talaria forwards those bytes unchanged.
- Enrichment recovery persists `PendingBookResult.resolvedMetadata`, not `.metadata`.
- Do not invent Talaria response fields. Spec: `swiftwing/OpenAPI/talaria-openapi.yaml`. Contract tests: `swiftwingTests/Unit/Services/TalariaContractAdherenceTests.swift`.
- Skills, loaded when the task matches: `swift-concurrency-pro`, `swiftdata-pro`, `swiftui-pro`, `swift-testing-pro`, `new-feature-slice`, `run-contract-tests`. They live in `.claude/skills/<name>/SKILL.md`. `.agents/skills` points there.
- Path-scoped Swift and SwiftData rules: `.claude/rules/`. Large-task planning stays in `.claude/rules/planning-mandatory.md`.
