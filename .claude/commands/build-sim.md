---
argument-hint: [device]
model: haiku
allowed-tools:
  - Bash
---

# Build for Simulator

Build SwiftWing for iOS Simulator: **{{$1 | default: "iPhone 17 Pro Max"}}**

**CRITICAL**: Always pipe through xcsift for readable output!

```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name={{$1 | default: "iPhone 17 Pro Max"}}' \
  build 2>&1 | xcsift
```

**Available Devices**:
- iPhone 17 Pro Max (default)
- iPhone 17 Pro
- iPhone 17
- iPad Pro (14-inch)

**Build Requirements**:
- ✅ 0 errors (mandatory)
- ✅ 0 warnings (goal)
- ✅ Clean build in < 30s
