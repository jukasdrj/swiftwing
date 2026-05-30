---
name: run-contract-tests
description: Runs Talaria contract adherence tests only (fast, no full suite needed)
disable-model-invocation: true
---

cd /Users/juju/dev_repos/swiftwing && xcodebuild test \
  -project swiftwing.xcodeproj \
  -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:swiftwingTests/Unit/Services/TalariaContractAdherenceTests \
  -parallel-testing-enabled NO \
  2>&1 | xcsift
