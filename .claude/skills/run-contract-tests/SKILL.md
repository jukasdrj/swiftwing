---
name: run-contract-tests
description: Runs the Talaria contract adherence tests only. Use when the user asks to check the OpenAPI contract, Talaria decoding, or /run-contract-tests.
disable-model-invocation: true
---

Run only `TalariaContractAdherenceTests`. Do not run the full test target.

From the repo root:

```bash
xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -only-testing:swiftwingTests/Unit/Services/TalariaContractAdherenceTests \
  -parallel-testing-enabled NO \
  2>&1 | xcsift
```

Read the xcsift summary. The run is successful only when there are 0 errors, 0 warnings, and the contract tests pass.

The committed spec is `swiftwing/OpenAPI/talaria-openapi.yaml`. Fixtures live in `swiftwingTests/Fixtures/TalariaContractFixtures.swift`. Scan status is HTTP polling. Do not add SSE, firehose, or cleanup calls.
