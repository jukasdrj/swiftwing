# SwiftWing iOS App Source Code Reference

**Parent Reference:** [../AGENTS.md](../AGENTS.md) (Project overview and architecture)

**Last Updated:** January 30, 2026
**Status:** Epic 5 Phase 2A-2E Complete (MVVM Refactoring)
**Build:** ✅ SUCCESS (0 errors, 0 warnings)

---

## Quick Navigation

- **First Time?** → Read parent [../AGENTS.md](../AGENTS.md) (project overview)
- **Building?** → See [../CLAUDE.md](../CLAUDE.md#building--running) (Build & Running section)
- **Code Rules?** → Check [../.claude/rules/](../.claude/rules/) (project conventions)
- **Swift Issues?** → See [../.claude/rules/swift-conventions.md](../.claude/rules/swift-conventions.md)
- **Data Issues?** → See [../.claude/rules/swiftdata-patterns.md](../.claude/rules/swiftdata-patterns.md)

---

## Directory Purpose

This is the **main iOS app source code directory** for SwiftWing. It contains:
- ✅ SwiftUI views and view models
- ✅ Actor-based services (network, camera, offline)
- ✅ SwiftData models and data persistence
- ✅ Design system and theme components
- ✅ OpenAPI specification management
- ✅ Performance monitoring and testing utilities

**Total Size:** ~620 KB source code (after Epic 5 refactoring)

---

## Directory Structure

```
swiftwing/
│
├── 📱 APP ENTRY POINT
│   ├── SwiftwingApp.swift              # Entry point, ModelContainer setup
│   ├── RootView.swift                  # Navigation root
│   └── LaunchScreenView.swift          # Launch screen
│
├── 🎥 CAMERA IMPLEMENTATION (Epic 2)
│   ├── CameraView.swift                # Main camera UI (250 lines)
│   │   └── Responsibilities: Preview display, shutter button, progress indicator
│   │
│   ├── CameraViewModel.swift           # Camera business logic (727 lines)
│   │   └── Responsibilities: Capture pipeline, image processing, upload coordination
│   │
│   ├── CameraManager.swift             # AVFoundation isolation (actor)
│   │   └── Responsibilities: Session setup, photo capture, permission handling
│   │
│   ├── CameraPreviewView.swift         # UIViewRepresentable bridge (183 lines)
│   │   └── Responsibilities: Metal preview layer, rotation handling (just fixed Jan 30)
│   │
│   └── CameraPermissionPrimerView.swift # Permission request UI
│       └── Responsibilities: Initial camera permission flow
│
├── 📚 LIBRARY IMPLEMENTATION (Epic 3)
│   ├── LibraryView.swift               # Library grid view (47KB)
│   │   └── Responsibilities: Grid layout, search, book detail modal
│   │
│   ├── LibraryPerformanceOptimizations.swift  # Query strategies
│   │   └── Responsibilities: Caching, prefetch coordination
│   │
│   └── LibraryPrefetchCoordinator.swift # Image prefetching logic
│       └── Responsibilities: Parallel image loads, memory management
│
├── 🔧 SERVICES & NETWORKING (Epic 4)
│   ├── Services/
│   │   ├── TalariaService.swift        # AI backend integration (508 lines, actor)
│   │   │   ├── Core Methods:
│   │   │   │  ├── uploadScan(image:deviceId:) → (jobId, streamUrl)
│   │   │   │  ├── streamEvents(streamUrl:) → AsyncThrowingStream<SSEEvent>
│   │   │   │  └── cleanup(jobId:) → Void
│   │   │   │
│   │   │   ├── Private Helpers:
│   │   │   │  └── parseSSEEvent(event:data:) → SSEEvent
│   │   │   │
│   │   │   └── Responsibilities: Multipart upload, SSE streaming, error handling
│   │   │
│   │   ├── NetworkTypes.swift          # Domain models (2.6KB)
│   │   │   ├── UploadResponse struct (jobId, streamUrl)
│   │   │   ├── BookMetadata struct (title, author, isbn, coverUrl)
│   │   │   ├── SSEEvent enum (progress, result, complete, error)
│   │   │   ├── NetworkError enum
│   │   │   └── Responsibilities: Type-safe network contracts
│   │   │
│   │   ├── NetworkMonitor.swift        # Network status tracking
│   │   │   └── Responsibilities: Reachability checks, connection state
│   │   │
│   │   ├── OfflineQueueManager.swift   # Offline sync queue (actor)
│   │   │   └── Responsibilities: Queue persistence, retry logic
│   │   │
│   │   ├── RateLimitState.swift        # Rate limit tracking
│   │   │   ├── Properties:
│   │   │   │  ├── isRateLimited: Bool
│   │   │   │  ├── remainingTime: TimeInterval
│   │   │   │  └── retryAfter: TimeInterval?
│   │   │   │
│   │   │   └── Responsibilities: Rate limit state management, countdown
│   │   │
│   │   └── StreamManager.swift         # SSE stream coordination
│   │       └── Responsibilities: Concurrent stream limits, connection pooling
│   │
│   ├── NetworkService.swift            # Legacy stub (for migration)
│   │   └── Status: Deprecated (kept for backwards compatibility)
│   │
│   └── PROCESSING QUEUE UI COMPONENTS
│       ├── ProcessingQueueView.swift   # Queue display (159 lines)
│       │   └── Responsibilities: Queue list, status badges, actions
│       │
│       ├── ProcessingItem.swift        # Queue item model (3.4KB)
│       │   ├── Properties: image, title, status, progress
│       │   └── Responsibilities: Item state and persistence
│       │
│       ├── ProcessingThumbnailView.swift # Item thumbnail
│       │   └── Responsibilities: Image preview with skeleton loading
│       │
│       ├── RateLimitOverlay.swift      # Rate limit UI (78 lines)
│       │   └── Responsibilities: Countdown display, user messaging
│       │
│       ├── OfflineIndicatorView.swift  # Offline badge (44 lines)
│       │   └── Responsibilities: Network status badge
│       │
│       └── DuplicateBookAlert.swift    # Duplicate modal (120 lines)
│           └── Responsibilities: Duplicate ISBN detection and user choice
│
├── 💾 DATA & MODELS
│   ├── Models/
│   │   ├── Book.swift                  # SwiftData @Model
│   │   │   ├── Properties:
│   │   │   │  ├── @Attribute(.unique) var isbn: String
│   │   │   │  ├── var id: UUID
│   │   │   │  ├── var title: String
│   │   │   │  ├── var author: String
│   │   │   │  ├── var dateAdded: Date
│   │   │   │  └── (Future: coverUrl, format, confidence)
│   │   │   │
│   │   │   └── Responsibilities: Core persistent entity, ISBN uniqueness
│   │   │
│   │   └── DataSeeder.swift            # Test data generation
│   │       └── Responsibilities: Development fixtures (auto-seed library)
│   │
│   └── DuplicateDetection.swift        # ISBN uniqueness checking
│       └── Responsibilities: Query existing books by ISBN
│
├── 🎨 DESIGN SYSTEM (Theme)
│   ├── Theme.swift                     # Swiss Glass design system (199 lines)
│   │   ├── Colors:
│   │   │  ├── swissBackground (#0D0D0D - black for OLED)
│   │   │  ├── swissText (white for contrast)
│   │   │  └── internationalOrange (#FF4F00 - accent)
│   │   │
│   │   ├── Typography:
│   │   │  ├── jetBrainsMono (data/IDs - brand identity)
│   │   │  └── system SF Pro (UI standard)
│   │   │
│   │   ├── ViewModifiers:
│   │   │  ├── swissGlassCard() (black + ultraThinMaterial + rounded)
│   │   │  └── (animation, spacing helpers)
│   │   │
│   │   └── Responsibilities: Consistent design language across app
│   │
│   ├── AsyncImageWithLoading.swift     # Async image + skeleton (6.8KB)
│   │   ├── Features:
│   │   │  ├── Async image loading from URL
│   │   │  ├── Skeleton loader during fetch
│   │   │  └── Error placeholder
│   │   │
│   │   └── Responsibilities: Reusable image component with UX feedback
│   │
│   ├── OfflineIndicatorView.swift      # Offline status badge
│   │   └── Responsibilities: Network status indicator
│   │
│   └── RateLimitOverlay.swift          # Rate limit countdown display
│       └── Responsibilities: User messaging during rate limit window
│
├── 🚀 PERFORMANCE & MONITORING
│   ├── PerformanceLogger.swift         # Instrumentation (8KB)
│   │   ├── Methods:
│   │   │  ├── logCameraStart(duration:)
│   │   │  ├── logImageProcessing(duration:)
│   │   │  ├── logNetworkRequest(duration:)
│   │   │  └── logMemoryUsage()
│   │   │
│   │   └── Responsibilities: Performance metric collection
│   │
│   ├── PerformanceTestData.swift       # Test data generation (8.3KB)
│   │   ├── Functions:
│   │   │  ├── generateTestDataset(count:container:)
│   │   │  └── generateHighResolutionImages()
│   │   │
│   │   └── Responsibilities: Development testing fixtures
│   │
│   └── StreamManager.swift             # Concurrent stream limits
│       └── Responsibilities: Connection pooling, backpressure management
│
├── 🌍 CONFIGURATION & ASSETS
│   ├── Assets.xcassets/                # App icons, colors, images
│   │   ├── Colors/ - Design system colors (defined in xcassets)
│   │   ├── Icons/ - App icon set (required for App Store)
│   │   └── Images/ - UI images and illustrations
│   │
│   ├── Fonts/                          # Custom fonts
│   │   └── JetBrainsMono-Regular.ttf   # Brand font for data display
│   │
│   ├── Preview Content/                # SwiftUI preview fixtures
│   │   └── Preview Assets.xcassets
│   │
│   └── Info.plist                      # App configuration
│       ├── NSCameraUsageDescription    # Camera permission text
│       └── UIAppFonts                  # Custom font registration
│
├── 📡 OPENAPI SPECIFICATION (Talaria)
│   ├── OpenAPI/
│   │   ├── talaria-openapi.yaml        # **COMMITTED** API spec
│   │   │   └── Why committed?
│   │   │       ✅ Offline builds possible
│   │   │       ✅ Deterministic, reproducible builds
│   │   │       ✅ Version control of API evolution
│   │   │       ✅ Supply chain security (no runtime fetch)
│   │   │
│   │   ├── .talaria-openapi.yaml.sha256 # Integrity checksum
│   │   │   └── Validates spec hasn't been corrupted
│   │   │
│   │   └── openapi-generator-config.yaml # Generator config (future)
│   │       └── Will enable auto-generation (post-MVP)
│   │
│   └── Generated/                      # Build output (NOT committed)
│       └── openapi.yaml                # Copy for generator
│           └── Created by build script from OpenAPI/
│
└── 🛠️ BUILD & CONFIGURATION
    └── (Managed by Xcode project file)
```

---

## Key Files: Detailed Breakdown

### 🟡 CRITICAL: SwiftwingApp.swift (52 lines)

**Purpose:** App entry point and SwiftData setup

**Key Points:**
- ✅ Creates `ModelContainer` with `Book` schema
- ✅ Sets `.modelContainer()` modifier (makes `\.modelContext` available in environment)
- ✅ Optional auto-seed in DEBUG for rapid development
- ⚠️ Note: `.modelContainer()` does NOT put ModelContainer in environment key space

```swift
@Environment(\.modelContext) var modelContext  // ✅ Available after .modelContainer()
@Environment(\.modelContainer) var container   // ❌ Does NOT exist
```

**When to Read:** Understanding app initialization

---

### 🟡 CRITICAL: CameraViewModel.swift (727 lines)

**Purpose:** Camera business logic and state management

**Responsibilities:**
1. **Capture Pipeline:** Coordinates camera → process → upload
2. **State Management:** Current scan status, progress percentage, error handling
3. **Service Coordination:** Calls `CameraManager` and `TalariaService`
4. **UI Updates:** Binds to `CameraView` for reactive updates

**Key Pattern:**
```swift
@Observable
@MainActor
final class CameraViewModel {
    private let cameraManager: CameraManager
    private let talariaService: TalariaService
    // ... state properties ...

    func captureAndProcess() async {
        // 1. Capture image
        let image = await cameraManager.capturePhoto()

        // 2. Upload to Talaria
        let (jobId, streamUrl) = await talariaService.uploadScan(image)

        // 3. Stream results
        for try await event in talariaService.streamEvents(streamUrl) {
            // Update UI state
        }
    }
}
```

**When to Read:**
- Understanding camera capture flow
- Modifying capture pipeline behavior
- Adding/debugging upload logic

---

### 🟡 CRITICAL: CameraView.swift (250 lines)

**Purpose:** Main camera UI (SwiftUI view)

**Responsibilities:**
1. **Preview Display:** Live camera preview (via `CameraPreviewView`)
2. **Shutter Button:** Capture interaction
3. **Progress Indicator:** Upload status feedback
4. **Error Handling:** User-facing error messages

**Architecture (after Epic 5 refactoring):**
- ✅ 250 lines (was 1,098 - **77% reduction**)
- ✅ All business logic moved to `CameraViewModel`
- ✅ View = Pure presentation, no async logic
- ✅ Bindings to `@Observable` viewModel

**When to Read:**
- Understanding camera UI layout
- Modifying camera interface
- Adding preview overlays

---

### 🟡 CRITICAL: CameraManager.swift (224 lines, actor)

**Purpose:** AVFoundation abstraction and isolation

**Responsibilities:**
1. **Session Setup:** Initialize and configure `AVCaptureSession`
2. **Photo Capture:** Non-blocking image capture
3. **Permission Handling:** Camera permission requests
4. **Error Recovery:** Handle camera availability changes

**Key Pattern:**
```swift
actor CameraManager {
    private var session: AVCaptureSession  // Actor-isolated

    func startSession() async throws {
        // Thread-safe operations
    }

    func capturePhoto() async throws -> UIImage {
        // Capture and return image
    }
}
```

**Why Actor?**
- ✅ Prevents data races on `AVCaptureSession`
- ✅ Thread-safe by design (Swift 6.2 requirement)
- ✅ No need for DispatchQueue (prevents deadlocks)

**When to Read:**
- Understanding camera initialization
- Debugging camera issues
- Optimizing camera performance

---

### 🟡 CRITICAL: CameraPreviewView.swift (183 lines)

**Purpose:** UIViewRepresentable bridge for AVCaptureVideoPreviewLayer

**Responsibilities:**
1. **Metal Preview:** Display live camera feed using AVFoundation layer
2. **Rotation Handling:** Update preview layer on device rotation (JUST FIXED Jan 30)
3. **Frame Management:** Keep preview synchronized with SwiftUI view

**Key Fix (Jan 30, 2026):**
- ✅ Fixed rotation handling in `updateUIView`
- ✅ Preview layer now updates frame on rotation
- ✅ No more distorted preview after device rotation

**When to Read:**
- Understanding camera preview rendering
- Debugging preview issues
- Modifying preview appearance

---

### 🟢 TalariaService.swift (508 lines, actor)

**Purpose:** Talaria AI backend integration via actor

**Core Methods:**
```swift
actor TalariaService {
    // 1. Upload image and get streaming URL
    func uploadScan(image: UIImage, deviceId: String)
        async throws -> (jobId: String, streamUrl: URL)

    // 2. Stream real-time events
    func streamEvents(from streamUrl: URL)
        -> AsyncThrowingStream<SSEEvent, Error>

    // 3. Cleanup after completion
    func cleanup(jobId: String) async throws
}
```

**Event Types:**
```swift
enum SSEEvent {
    case progress(String)              // "Looking...", "Reading..."
    case result(BookMetadata)          // Book data from AI
    case complete                      // Job finished
    case error(String)                 // Error occurred
}
```

**Key Features:**
- ✅ Multipart form-data upload
- ✅ Server-Sent Events (SSE) streaming
- ✅ Rate limit handling (429 responses)
- ✅ Domain model translation (OpenAPI → Swift types)

**When to Read:**
- Understanding network flow
- Debugging Talaria integration
- Modifying API contracts

---

### 🟢 NetworkTypes.swift (2.6KB)

**Purpose:** Network domain models (type-safe contracts)

**Key Types:**
```swift
struct UploadResponse {
    let jobId: String
    let streamUrl: URL
}

struct BookMetadata {
    let title: String
    let author: String
    let isbn: String
    let coverUrl: URL?
}

enum SSEEvent {
    case progress(String)
    case result(BookMetadata)
    case complete
    case error(String)
}

enum NetworkError: Error {
    case noConnection
    case timeout
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(Int)
    case invalidResponse
}
```

**When to Read:**
- Understanding API data structures
- Adding new API fields
- Debugging type mismatches

---

### 🟢 LibraryView.swift (47KB)

**Purpose:** Library grid and book browsing UI

**Responsibilities:**
1. **Grid Layout:** LazyVGrid with 2-column layout
2. **Search:** Full-text search across books
3. **Sorting:** By title, date added
4. **Detail Modal:** Book detail sheet
5. **Performance:** Prefetch coordination, caching

**When to Read:**
- Understanding library layout
- Optimizing library performance
- Adding search features

---

### 🟢 PerformanceLogger.swift (8KB)

**Purpose:** Performance instrumentation and metrics

**Logged Metrics:**
- Camera cold start time
- Image processing duration
- Network request latency
- Memory usage
- Frame rate drops

**Usage Pattern:**
```swift
let start = CFAbsoluteTimeGetCurrent()
// ... operation ...
let duration = CFAbsoluteTimeGetCurrent() - start
PerformanceLogger.log(event: "camera_start", duration: duration)
```

**When to Read:**
- Understanding performance targets
- Debugging slow operations
- Adding performance instrumentation

---

## Important Patterns

### ✅ DO: Use @Environment(\.modelContext) for Data Access

```swift
struct MyView: View {
    @Environment(\.modelContext) var modelContext

    func saveBook() {
        let book = Book(isbn: "...", title: "...", author: "...")
        modelContext.insert(book)
        try? modelContext.save()
    }
}
```

### ✅ DO: Use Actors for Isolated State

```swift
actor TalariaService {
    private var session: URLSession  // Isolated

    func upload() async throws { ... }  // Safe, thread-safe
}
```

### ✅ DO: Use @MainActor for UI Updates

```swift
@Observable
@MainActor
final class CameraViewModel {
    var captureProgress: Double = 0  // UI thread safe
}
```

### ❌ DON'T: Use DispatchQueue with async/await

```swift
// DEADLOCK RISK
DispatchQueue.main.async {
    await someAsyncFunction()  // 🔥 DEADLOCK
}
```

### ❌ DON'T: Use Task.detached Unnecessarily

```swift
// BREAKS ACTOR ISOLATION
Task.detached {
    await actorMethod()  // 🔥 Data race risk
}

// USE THIS INSTEAD
Task {
    await actorMethod()  // ✅ Respects isolation
}
```

### ❌ DON'T: Try to Access \.modelContainer

```swift
// DOESN'T EXIST
@Environment(\.modelContainer) var container  // ❌ Compiler error

// USE THIS INSTEAD
@Environment(\.modelContext) var context
let container = context.container  // ✅ Access via context
```

---

## File Dependencies

### View Layer Dependencies
```
CameraView.swift
    ↓ uses
CameraViewModel (507 lines)
    ↓ uses
CameraManager (actor)
    ↓ uses
AVFoundation
```

```
LibraryView.swift
    ↓ queries
Book.swift (@Model)
    ↓ uses
SwiftData
```

### Service Layer Dependencies
```
TalariaService (actor)
    ↓ uses
NetworkTypes.swift
    ↓ calls
Talaria API (HTTPs://api.oooefam.net)
```

```
OfflineQueueManager (actor)
    ↓ coordinates with
TalariaService
    ↓ syncs when
NetworkMonitor.swift (online)
```

---

## Performance Targets (By File)

| Metric | Target | Measured | File |
|--------|--------|----------|------|
| Camera cold start | < 0.5s | TBD | CameraManager |
| Image processing | < 500ms | TBD | CameraViewModel |
| Upload latency | < 1000ms | TBD | TalariaService |
| SSE first event | < 500ms | TBD | TalariaService |
| UI frame rate | > 55 FPS | TBD | All views |
| Library grid scroll | 60 FPS | TBD | LibraryView |

---

## Testing

### Unit Test Location
**Directory:** `../swiftwingTests/`

### Coverage Goals
- **Services:** 80%+ (critical for network logic)
- **ViewModels:** 70%+ (business logic)
- **Views:** Manual testing (SwiftUI Preview)

### Key Test Files to Create (Epic 5 Phase 3A)
- `TalariaServiceTests.swift` - Network mocking, SSE streaming
- `CameraViewModelTests.swift` - Capture pipeline, state transitions
- `BookModelTests.swift` - SwiftData persistence
- `OfflineQueueTests.swift` - Offline sync logic

---

## Build Rules

### ✅ ALWAYS
- Pipe xcodebuild through xcsift for error parsing
- Verify 0 errors AND 0 warnings before committing
- Test on iPhone 17 Pro Max simulator (or latest)
- Use Swift 6.2 with strict concurrency enabled

### ❌ NEVER
- Call xcodebuild without piping to xcsift
- Commit code with warnings
- Use `@unchecked Sendable` (bypasses safety)
- Use `DispatchQueue` with async/await

### Command Pattern
```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift
```

---

## Common Tasks

### Adding a New View
1. Create `MyNewView.swift` in swiftwing/
2. Create `MyNewViewModel.swift` (if has logic)
3. Add navigation link in parent view
4. Test in SwiftUI Preview
5. Run `xcodebuild ... | xcsift` to verify 0/0

### Adding a New Service
1. Create `MyService.swift` in `Services/`
2. Mark as `actor` if mutable state
3. Add domain models to `NetworkTypes.swift`
4. Add error cases to `NetworkError` enum
5. Create unit tests in `swiftwingTests/`

### Fixing a Bug
1. Use `/planning-with-files` if complex (>4 tool calls)
2. Locate file using file structure above
3. Review related test file
4. Make fix with Swift 6.2 compliance
5. Run `xcodebuild ... | xcsift` (must be 0/0)
6. Verify test coverage still > 70%

### Optimizing Performance
1. Use `PerformanceLogger` to measure
2. Compare against targets in Performance Targets table
3. Use Instruments (Time Profiler, System Trace)
4. Document findings in `../findings.md`
5. Reference `PerformanceTestData` for load testing

---

## Quick Reference: When to Read Each File

| Task | Read This File |
|------|---|
| Understand app startup | SwiftwingApp.swift |
| Fix camera issues | CameraManager.swift |
| Modify camera UI | CameraView.swift |
| Add camera features | CameraViewModel.swift |
| Fix camera preview | CameraPreviewView.swift |
| Debug Talaria integration | TalariaService.swift |
| Add API fields | NetworkTypes.swift |
| Fix library performance | LibraryView.swift + LibraryPerformanceOptimizations.swift |
| Understand data persistence | Models/Book.swift |
| Debug offline issues | Services/OfflineQueueManager.swift |
| Add rate limit handling | RateLimitState.swift |
| Fix design issues | Theme.swift |
| Add network status | Services/NetworkMonitor.swift |
| Measure performance | PerformanceLogger.swift |
| Create test fixtures | PerformanceTestData.swift |

---

## Concurrency Model Summary

### Isolation Boundaries

| Layer | Isolation | Threading |
|-------|-----------|-----------|
| Views | @MainActor | Main thread |
| ViewModels | @MainActor | Main thread |
| Services (Actors) | actor (custom) | async/await safe |
| Data | SwiftData + potential DataSyncActor | ModelContext = main |

### Async Call Chains

```
SwiftUI View
  ↓ Button tap
CameraViewModel method (awaits)
  ↓ await call
CameraManager.capturePhoto (actor method, async)
  ↓ await AVFoundation
UIImage returned
  ↓ back to ViewModel
ViewModel updates state
  ↓ @Observable notification
View automatically updates
```

---

## Known Issues & Workarounds

### SwiftData Environment Key
- ❌ `\.modelContainer` does not exist
- ✅ Use `\.modelContext` instead
- ✅ Access container via `modelContext.container`

### Camera Rotation (FIXED Jan 30)
- ✅ CameraPreviewView now handles rotation correctly
- ✅ Preview layer frame updates on device rotation
- ✅ No more distorted preview

### Rate Limiting
- 10 scans per 20 minutes (Talaria API limit)
- `RateLimitOverlay` shows countdown
- `OfflineQueueManager` queues scans when rate limited

---

## References

### Parent Directory
- [../AGENTS.md](../AGENTS.md) - Project architecture overview
- [../CLAUDE.md](../CLAUDE.md) - AI collaboration guide
- [../CURRENT-STATUS.md](../CURRENT-STATUS.md) - Real-time status
- [../.claude/rules/](../.claude/rules/) - Project conventions

### Swift 6.2 & iOS 26
- [../.claude/rules/swift-conventions.md](../.claude/rules/swift-conventions.md) - Actor patterns
- [../.claude/rules/swiftdata-patterns.md](../.claude/rules/swiftdata-patterns.md) - Data layer
- [../findings.md](../findings.md) - iOS 26 research

### Related Epics
- [../EPIC-1-STORIES.md](../EPIC-1-STORIES.md) - Foundation (completed)
- [../EPIC-5-REVIEW-SUMMARY.md](../EPIC-5-REVIEW-SUMMARY.md) - Refactoring findings

---

## File Statistics

### By Category

**Views & ViewModels:** ~1,200 lines
- CameraView.swift: 250 lines
- CameraViewModel.swift: 727 lines
- LibraryView.swift: ~200 lines

**Services (Actor-Based):** ~1,000 lines
- TalariaService.swift: 508 lines
- OfflineQueueManager.swift: ~300 lines
- NetworkMonitor.swift: ~100 lines

**Data & Models:** ~200 lines
- Book.swift: ~50 lines
- NetworkTypes.swift: ~100 lines
- DuplicateDetection.swift: ~50 lines

**UI Components:** ~600 lines
- ProcessingQueueView.swift: 159 lines
- AsyncImageWithLoading.swift: ~200 lines
- Various overlays: ~250 lines

**Infrastructure:** ~400 lines
- Theme.swift: 199 lines
- PerformanceLogger.swift: ~150 lines
- CameraManager.swift: 224 lines

**Total:** ~620 KB (after Epic 5 refactoring)

---

## Last Updated

**January 30, 2026, 11:56 AM UTC**

By: Claude Code (Technical Writer)

**Next Update:** After Epic 5 Phase 3A completion (XCTest infrastructure)

---

**Remember:** This is a child reference for the app source directory. Always refer to the parent [../AGENTS.md](../AGENTS.md) for project-wide context and architecture decisions.
