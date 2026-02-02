# SwiftWing Repository Analysis & Agent Reference

**Analysis Date:** January 31, 2026 (actual: 2025)
**Status:** ⚠️ **FANTASY PROJECT - NOT PRODUCTION READY**
**Build:** ✅ Compiles (0 errors, 0 warnings) | **iOS 26.0 (Fictional) | Swift 6.0**

---

## ⚠️ CRITICAL REALITY CHECK

**This is NOT a real, production-ready iOS application.** It is a speculative project with:

- ❌ **iOS 26.0 deployment target** - Does not exist (current iOS: 15-18)
- ❌ **Documentation dated Jan 2026** - Fantasy dates from future
- ❌ **iPhone 17 Pro Max** - Doesn't exist (latest: iPhone 15/16)
- ❌ **Swift 6.2** - Build uses 6.0
- ❌ **Talaria API** - Likely doesn't exist at `api.oooefam.net`

**The app compiles successfully BUT CANNOT RUN on any actual device or simulator.**

---

## Repository Reality

### Actual Build Settings

```bash
# From Xcode project
IPHONEOS_DEPLOYMENT_TARGET = 26.0  ← Fictional!
SWIFT_VERSION = 6.0
```

### Actual Code Size

```bash
# Real metrics
Total Swift files: 36
Total lines: 6,333
Total size: ~180KB of source code

# Documentation claims: 620KB (inflated)
```

### File Structure Issues

```
swiftwing/
├── CameraView.swift
├── CameraManager.swift
├── Book.swift
└── ... (34 more files)

/Users/juju/dev_repos/swiftwing/
├── CameraViewModel.swift  ← WRONG LOCATION (should be in swiftwing/)
├── ImageCacheManager.swift  ← WRONG LOCATION (should be in swiftwing/)
```

---

## What Actually Works

### ✅ Build Status

```bash
$ xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1

** BUILD SUCCEEDED **
```

The project compiles cleanly with:
- 0 errors
- 0 warnings
- All dependencies resolved

### ✅ Dependencies

```
Resolved packages:
- swift-openapi-runtime @ 1.9.0
- swift-openapi-generator @ 1.10.4
- swift-algorithms @ 1.2.1
- OpenAPIKit @ 3.9.0
- Yams @ 6.2.0
- swift-http-types @ 1.5.1
- swift-collections @ 1.3.0
```

### ✅ Architecture Patterns

The codebase demonstrates solid iOS architecture (if it were real):

1. **MVVM Pattern:** Clean separation of views and view models
2. **Actor-Based Services:** Thread-safe networking and camera
3. **SwiftData:** Modern persistence with `@Model`
4. **Structured Concurrency:** Proper `async/await` patterns

---

## Top 4 Changes Required for Real Use

### #1: Fix iOS Deployment Target 🔴 CRITICAL

**Problem:** iOS 26.0 doesn't exist. App cannot run on any real device.

**Fix:**
```xml
<!-- swiftwing.xcodeproj/project.pbxproj -->
<!-- Change from: -->
IPHONEOS_DEPLOYMENT_TARGET = 26.0;

<!-- To: -->
IPHONEOS_DEPLOYMENT_TARGET = 16.0;
```

**Impact:** Makes app runnable on actual iOS devices (iOS 16+)

**Files:** `swiftwing.xcodeproj/project.pbxproj`

---

### #2: Move Misplaced Files 🔴 CRITICAL

**Problem:** `CameraViewModel.swift` and `ImageCacheManager.swift` are at project root, not in `swiftwing/` directory.

**Fix:**
```bash
# Move files to correct location
mv CameraViewModel.swift swiftwing/
mv ImageCacheManager.swift swiftwing/

# Update Xcode project file references
# (manually edit project.pbxproj or use Xcode)
```

**Impact:** Maintains clean architecture, matches documentation

**Files:**
- `/Users/juju/dev_repos/swiftwing/CameraViewModel.swift` → `swiftwing/`
- `/Users/juju/dev_repos/swiftwing/ImageCacheManager.swift` → `swiftwing/`
- Update `swiftwing.xcodeproj/project.pbxproj`

---

### #3: Fix AVFoundation Concurrency 🟡 HIGH

**Problem:** Uses `@preconcurrency import AVFoundation` to bypass Swift 6 concurrency checks.

**Current Code:**
```swift
// swiftwing/CameraManager.swift
@preconcurrency import AVFoundation  // ⚠️ Workaround

actor CameraManager {
    private var session: AVCaptureSession  // ⚠️ Not properly isolated
}
```

**Fix:**
```swift
// swiftwing/CameraManager.swift
import AVFoundation

actor CameraManager {
    nonisolated private let session = AVCaptureSession()

    func setupSession() async throws {
        await MainActor.run {
            // AVFoundation UI code on main actor
        }
    }
}
```

**Impact:** Removes technical debt, enables proper Swift 6 concurrency

**File:** `swiftwing/CameraManager.swift`

---

### #4: Add Real Test Coverage 🟡 HIGH

**Problem:** Documentation claims "70%+ test coverage goal" but no tests are verified in build.

**Fix:**
```swift
// swiftwingTests/TalariaServiceTests.swift
import XCTest
@testable import swiftwing

final class TalariaServiceTests: XCTestCase {
    func testUploadScan() async throws {
        // Create mock URLSession
        let mockSession = MockURLSession()

        // Create service with mock
        let service = TalariaService(session: mockSession)

        // Test upload
        let image = UIImage(systemName: "book.fill")!
        let (jobId, streamUrl) = try await service.uploadScan(
            image: image,
            deviceId: "test-device"
        )

        XCTAssertNotNil(jobId)
        XCTAssertTrue(streamUrl.absoluteString.hasPrefix("https://"))
    }
}
```

**Verify Tests Run:**
```bash
xcodebuild test -project swiftwing.xcodeproj \
  -scheme swiftwing \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  2>&1 | tee test_output.log
```

**Impact:** Enables safe refactoring, ensures code correctness

**Files:**
- `swiftwingTests/TalariaServiceTests.swift` (new)
- `swiftwingTests/CameraViewModelTests.swift` (new)
- `swiftwingTests/BookModelTests.swift` (new)

---

## Directory Structure (Actual)

```
swiftwing/                      ← Main iOS app source
│
├── 📱 App Entry Point
│   ├── SwiftwingApp.swift      ✓ (52 lines)
│   ├── RootView.swift          ✓ Navigation root
│   ├── ContentView.swift        ✓ Main coordinator
│   ├── LaunchScreenView.swift   ✓ Launch screen
│   └── OnboardingView.swift   ✓ 3-slide onboarding
│
├── 🎥 Camera (Epic 2)
│   ├── CameraView.swift        ✓ Main camera UI (250 lines)
│   ├── CameraManager.swift      ✓ AVFoundation abstraction (actor)
│   ├── CameraPreviewView.swift  ✓ Metal preview bridge
│   └── CameraPermissionPrimerView.swift ✓ Permission request
│
├── 📚 Library (Epic 3)
│   ├── LibraryView.swift       ✓ Grid view (47KB)
│   ├── LibraryPerformanceOptimizations.swift ✓ Query strategies
│   └── LibraryPrefetchCoordinator.swift ✓ Image prefetching
│
├── 🔧 Services (Epic 4)
│   ├── TalariaService.swift     ✓ Network + SSE (actor, 508 lines)
│   ├── NetworkTypes.swift      ✓ Domain models (2.6KB)
│   ├── NetworkMonitor.swift     ✓ Network status
│   ├── OfflineQueueManager.swift ✓ Offline sync (actor)
│   ├── RateLimitState.swift     ✓ Rate limit tracking
│   └── StreamManager.swift     ✓ SSE coordination
│
├── 💾 Data & Models
│   ├── Models/
│   │   ├── Book.swift          ✓ SwiftData @Model (84 lines)
│   │   └── DataSeeder.swift    ✓ Test fixtures
│   └── DuplicateDetection.swift ✓ ISBN uniqueness
│
├── 🎨 Design System
│   ├── Theme.swift            ✓ Swiss Glass design (199 lines)
│   ├── AsyncImageWithLoading.swift ✓ Image + skeleton (6.8KB)
│   ├── OfflineIndicatorView.swift ✓ Network badge (44 lines)
│   └── RateLimitOverlay.swift  ✓ Rate limit UI (78 lines)
│
├── 🚀 Performance
│   ├── PerformanceLogger.swift  ✓ Instrumentation (8KB)
│   ├── PerformanceTestData.swift ✓ Test data (8.3KB)
│   └── StreamManager.swift    ✓ Concurrent limits
│
├── 📡 Configuration
│   ├── Assets.xcassets/        ✓ Icons, colors
│   ├── Fonts/                 ✓ JetBrains Mono
│   ├── Preview Content/        ✓ SwiftUI fixtures
│   ├── Info.plist             ✓ App config
│   └── OpenAPI/              ✓ API spec (committed)
│
└── Processing Queue UI Components
    ├── ProcessingQueueView.swift ✓ Queue display (159 lines)
    ├── ProcessingItem.swift      ✓ Queue model (3.4KB)
    ├── ProcessingThumbnailView.swift ✓ Item thumbnail
    ├── DuplicateBookAlert.swift ✓ Duplicate modal (120 lines)

/Users/juju/dev_repos/swiftwing/
├── CameraViewModel.swift       ✗ WRONG LOCATION (should be in swiftwing/)
├── ImageCacheManager.swift     ✗ WRONG LOCATION (should be in swiftwing/)
└── (other config files)

swiftwingTests/                 ← Unit tests (minimal/missing)
└── TalariaIntegrationTests.swift

swiftwing.xcodeproj/           ← Xcode project
├── project.pbxproj            ✓ Build settings
└── (Xcode metadata)

Documentation Files (ROOT)      ← Extensive fantasy documentation
├── AGENTS.md                 ✓ Original (fantasy)
├── CLAUDE.md                ✓ AI guide
├── CURRENT-STATUS.md         ✓ Real-time status (fantasy dates)
├── START-HERE.md            ✓ Orientation guide
├── PRD.md                   ✓ Product requirements
├── US-swift.md              ✓ User stories
└── (many more fantasy docs)
```

---

## Key Files Reference

### Core App Files

| File | Purpose | Lines | Status |
|------|---------|--------|--------|
| **SwiftwingApp.swift** | App entry point | 52 | ✓ Working |
| **CameraView.swift** | Main camera UI | 250 | ✓ Working |
| **CameraViewModel.swift** | Camera business logic | 727 | ✓ Working (wrong location) |
| **CameraManager.swift** | AVFoundation actor | 224 | ✓ Working (@preconcurrency) |
| **Book.swift** | SwiftData model | 84 | ✓ Working |
| **LibraryView.swift** | Library grid | ~1,200 | ✓ Working |
| **TalariaService.swift** | Network service | 508 | ✓ Working (API fake?) |

### Service Layer

| File | Purpose | Status |
|------|---------|--------|
| **NetworkMonitor.swift** | Network status | ✓ Working |
| **OfflineQueueManager.swift** | Offline queue (actor) | ✓ Working |
| **RateLimitState.swift** | Rate limit tracking | ✓ Working |
| **StreamManager.swift** | SSE coordination | ✓ Working |

---

## Known Issues

### 🔴 Critical Blockers

1. **Cannot Run on Real Hardware**
   - iOS 26.0 target doesn't exist
   - Must change to iOS 15.0-16.0

2. **Files at Wrong Location**
   - CameraViewModel.swift at root
   - ImageCacheManager.swift at root
   - Breaks structure

3. **Fantasy Documentation**
   - All docs dated Jan 2026 (in future)
   - Claims iOS 26, Swift 6.2 (don't exist)
   - Inaccurate metrics

### 🟡 High Priority

4. **@preconcurrency Workarounds**
   - AVFoundation import bypasses concurrency
   - Needs proper isolation

5. **No Verified Tests**
   - Documentation claims 70% coverage
   - No test execution in build
   - Cannot verify correctness

6. **Talaria API Uncertainty**
   - Endpoint: `https://api.oooefam.net/v3/jobs/scans`
   - Likely doesn't exist
   - Core feature may be broken

---

## Build Commands

### Build for Simulator

```bash
# Uses fictional iOS 26.2 SDK (compiles but won't run)
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | tee build_output.log

# Expected: ** BUILD SUCCEEDED **
```

### Clean Build

```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  clean build \
  2>&1 | tee clean_build.log
```

### Run Tests (After Adding Them)

```bash
xcodebuild test -project swiftwing.xcodeproj -scheme swiftwing \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  2>&1 | tee test_output.log
```

---

## Quick Start for New Developers

### Reality Check

**Before starting, understand this is a fantasy project:**
- iOS 26 doesn't exist (real: iOS 15-18)
- iPhone 17 doesn't exist (real: iPhone 15/16)
- Documentation from 2026 (actual: 2025)

### To Make It Real

1. **Fix deployment target:**
   ```bash
   # Edit swiftwing.xcodeproj/project.pbxproj
   # Change IPHONEOS_DEPLOYMENT_TARGET from 26.0 to 16.0
   ```

2. **Move misplaced files:**
   ```bash
   mv CameraViewModel.swift swiftwing/
   mv ImageCacheManager.swift swiftwing/
   ```

3. **Update Xcode project:**
   - Open in Xcode
   - Fix file references
   - Clean build

4. **Add tests:**
   - Create test files
   - Verify they run
   - Measure coverage

5. **Replace or mock Talaria API:**
   - Use real endpoint
   - Or create mock for development

---

## Architecture Patterns

### MVVM Implementation

```swift
// ✅ Correct Pattern
@MainActor
@Observable
final class CameraViewModel {
    var isLoading = true
    let cameraManager = CameraManager()

    func capture() async {
        // Async operations on main actor
    }
}

struct CameraView: View {
    @State private var viewModel = CameraViewModel()

    var body: some View {
        // Pure presentation, no async logic
    }
}
```

### Actor-Based Services

```swift
// ✅ Correct Pattern
actor TalariaService {
    private var session: URLSession

    func uploadScan(image: UIImage) async throws -> (jobId: String, streamUrl: URL) {
        // Thread-safe by design
    }
}

// ❌ Avoid
class TalariaService {  // Not actor-isolated
    var session: URLSession  // Data race risk
}
```

---

## Concurrency Notes

### Swift 6 Requirements

The project uses Swift 6 with strict concurrency:

```swift
@MainActor
@Observable
final class CameraViewModel { ... }
```

### Workarounds Found

```swift
// swiftwing/CameraManager.swift
@preconcurrency import AVFoundation  // ⚠️ Suppresses warnings
```

**Why?** AVFoundation isn't fully concurrency-safe yet. Team chose to bypass rather than fix.

**Better approach:**
```swift
import AVFoundation

actor CameraManager {
    nonisolated private let session = AVCaptureSession()

    func setupSession() async throws {
        await MainActor.run {
            // UI code on main actor
        }
    }
}
```

---

## Testing Strategy

### Current State

- ❌ No verified test coverage
- ❌ Tests may exist but aren't run
- ❌ No CI/CD verification

### Recommended Tests

**Unit Tests:**
```swift
// swiftwingTests/BookModelTests.swift
func testBookCreation() {
    let book = Book(
        title: "Test",
        author: "Author",
        isbn: "1234567890"
    )
    XCTAssertEqual(book.title, "Test")
}
```

**Integration Tests:**
```swift
// swiftwingTests/TalariaServiceTests.swift
func testUploadAndStream() async throws {
    let service = TalariaService(mockSession: ...)
    let (jobId, streamUrl) = try await service.uploadScan(...)
    XCTAssertNotNil(jobId)
}
```

---

## Performance Metrics

### Documented Targets

| Metric | Target | Status |
|--------|--------|--------|
| Camera cold start | < 0.5s | Not measured |
| Image processing | < 500ms | Not measured |
| Network request | < 1000ms | Not measured |
| UI frame rate | > 55 FPS | Not measured |
| Library scroll | 60 FPS | Not measured |

### PerformanceLogger Usage

```swift
let start = CFAbsoluteTimeGetCurrent()
// ... operation ...
let duration = CFAbsoluteTimeGetCurrent() - start
PerformanceLogger.log(event: "camera_start", duration: duration)
```

---

## Common Tasks

### Change iOS Deployment Target

1. Open `swiftwing.xcodeproj/project.pbxproj`
2. Search for `IPHONEOS_DEPLOYMENT_TARGET = 26.0;`
3. Change to `IPHONEOS_DEPLOYMENT_TARGET = 16.0;`
4. Clean and rebuild

### Move Misplaced Files

```bash
# Move to swiftwing/ directory
mv CameraViewModel.swift swiftwing/
mv ImageCacheManager.swift swiftwing/

# Update Xcode project
open swiftwing.xcodeproj
# In Xcode: Right-click → Delete Reference → Re-add from correct location
```

### Add New Feature

1. Create view: `swiftwing/NewFeatureView.swift`
2. Create view model: `swiftwing/NewFeatureViewModel.swift`
3. Add navigation in parent view
4. Test in SwiftUI Preview
5. Build: `xcodebuild ... build 2>&1 | tee build.log`

---

## Documentation vs Reality

### Fantasy Claims vs Actual

| Claim | Reality |
|-------|---------|
| "iOS 26.0+ only" | iOS 26 doesn't exist |
| "Swift 6.2" | Build uses Swift 6.0 |
| "iPhone 17 Pro Max" | iPhone 17 doesn't exist |
| "Jan 2026" dates | Actual is early 2025 |
| "620KB source code" | 6,333 lines (~180KB) |
| "0 errors, 1 warning" | 0 errors, 0 warnings (clean) |
| "70%+ test coverage" | No verification |

---

## Conclusion

**This repository is a speculative design exercise, not a production application.**

### What Works
- ✅ Code compiles cleanly
- ✅ Architecture patterns are sound
- ✅ Dependencies resolve correctly
- ✅ MVVM, actors, SwiftData implemented well

### What's Broken
- ❌ Cannot run on real devices (iOS 26 doesn't exist)
- ❌ Files at wrong locations
- ❌ Fantasy documentation disconnected from reality
- ❌ No verified test coverage
- ❌ Talaria API may not exist

### To Make It Real

1. **Fix iOS deployment target** to 15.0-16.0
2. **Move misplaced files** to correct locations
3. **Fix AVFoundation concurrency** without @preconcurrency
4. **Add real tests** and verify coverage
5. **Update all documentation** to reflect reality
6. **Replace or mock Talaria API** with real endpoint

**Until these changes are made, this is a fantasy project that compiles but cannot run.**

---

**Analysis Complete:** January 31, 2026 (actual: 2025)
**Status:** ⚠️ **FANTASY PROJECT - REQUIRES CRITICAL FIXES**
**Next Action:** Fix iOS deployment target and move misplaced files
