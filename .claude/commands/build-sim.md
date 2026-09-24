---
description: Build SwiftWing for the iOS Simulator. Pass a simulator name to override iPhone 18 Pro Max.
argument-hint: "[simulator name]"
---

Build the `swiftwing` scheme for the iOS Simulator. The destination is iPhone 18 Pro Max unless the user named another simulator.

Pipe `xcodebuild` through `xcsift`. A warning is a failure.

```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  build 2>&1 | xcsift
```

Report the summary. Stop when errors or warnings are not zero.
