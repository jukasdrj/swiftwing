# Swift 6.2 & iOS 26 Conventions

## Language & Platform

### Swift 6.2 Requirements
- **Strict Concurrency**: Enabled (data race prevention)
- **Complete Concurrency Checking**: All warnings treated as errors
- **Target**: iOS 26.0+ only (latest devices)
- **Build Requirements**: 0 errors, 0 warnings (non-negotiable)

### Actor-Based Architecture
Use actors for all mutable shared state:
```swift
actor TalariaService {
    private var activeJobs: [UUID: ScanJob] = [:]
    // Thread-safe by design
}
```

**Critical Rules**:
- ✅ Use `actor` for mutable shared state
- ✅ Use `@MainActor` for all UI updates
- ✅ Use structured concurrency (`TaskGroup`, `async let`)
- ❌ Never use `DispatchQueue` with async/await (deadlock risk)
- ❌ Never use `Task.detached` (breaks actor isolation)

## Architecture Patterns

### MVVM with Actors
```
SwiftUI Views → @Observable ViewModels → Actor Services → SwiftData
```

**View Layer** (SwiftUI):
- Pure presentation logic
- `@Bindable`, `@State`, `@Environment`
- Delegate actions to ViewModel

**ViewModel Layer** (`@Observable`):
- Business logic coordination
- Calls actor services
- Maintains view state
- Example: `CameraViewModel` (727 lines)

**Service Layer** (Actors):
- `TalariaService` - Network + SSE streaming
- `CameraManager` - AVFoundation isolation
- `DataSyncActor` - SwiftData write coordination
- `NetworkMonitor` - Network state tracking

**Data Layer** (SwiftData):
- `@Model` classes with `#Unique` constraints
- ModelContext for queries
- DataSyncActor for thread-safe writes

### Vertical Slice Development
Each epic delivers **complete feature** (UI → Logic → Data → Network):
- ✅ Epic 2: Camera (full stack: CameraView → CameraViewModel → CameraManager → File I/O)
- ✅ Epic 4: AI Integration (full stack: UI → TalariaService → SSE → SwiftData)

❌ **NOT** horizontal layering:
- Don't build all models first, then all services, then all views
- Each epic is independently testable and shippable

## SwiftData Conventions

### Model Definitions
```swift
@Model
final class Book {
    @Attribute(.unique) var isbn: String  // Uniqueness constraint
    var title: String
    var authors: [String]
    var dateScanned: Date

    init(isbn: String, title: String) {
        self.isbn = isbn
        self.title = title
        self.authors = []
        self.dateScanned = Date()
    }
}
```

**Rules**:
- ✅ Use `#Unique` for ISBN (duplicate detection)
- ✅ All writes via `DataSyncActor` (thread safety)
- ✅ Queries on `@MainActor` (UI consistency)
- ❌ Never directly mutate from background threads

### Data Sync Pattern
```swift
actor DataSyncActor {
    private let modelContext: ModelContext

    func save(book: BookMetadata) async throws {
        // Actor-isolated write
        let book = Book(isbn: book.isbn, title: book.title)
        modelContext.insert(book)
        try modelContext.save()
    }
}
```

## UI/UX Design System

### Swiss Glass Theme
**60% Swiss Utility + 40% Liquid Glass**

**Typography**:
- System font (San Francisco)
- Clear hierarchy: Title, Headline, Body, Caption
- High contrast for readability

**Colors**:
- Primary: System blue
- Background: Frosted glass effect
- Shadows: Subtle depth cues
- Accent: Minimal, purposeful

**Components**:
- Rounded corners (12-16pt radius)
- Subtle shadows (0.05 opacity)
- Glass morphism backgrounds
- Smooth animations (0.3s default)

**Layout**:
- Generous whitespace
- Edge-to-edge content
- Safe area insets respected
- Dynamic Type support

## Camera Implementation

### Zero-Lag Preview
```swift
// Async video capture setup
let captureSession = AVCaptureSession()
captureSession.sessionPreset = .photo

// Non-blocking preview
let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
previewLayer.videoGravity = .resizeAspectFill
```

**Performance Targets**:
- Cold start: < 0.5s
- UI frame rate: > 55 FPS
- Image capture: < 500ms
- Zero UI blocking during capture

### Image Processing Pipeline
1. Capture UIImage from AVFoundation
2. Compress to JPEG (0.8 quality)
3. Upload to Talaria via chunked transfer
4. Stream progress via SSE
5. Save metadata to SwiftData

**Concurrency Pattern**:
```swift
Task {
    let image = await cameraManager.capturePhoto()
    let compressed = await ImageProcessor.compress(image)
    let jobId = await talariaService.startScan()
    await talariaService.uploadImage(jobId, compressed)
    // UI updates on MainActor automatically
}
```

## Network & API Integration

### Talaria Service (Actor)
```swift
actor TalariaService {
    func startScan() async throws -> UUID
    func uploadImage(_ jobId: UUID, _ data: Data) async throws
    func streamProgress(_ jobId: UUID) async throws -> AsyncStream<ScanProgress>
    func fetchResults(_ jobId: UUID) async throws -> [BookMetadata]
}
```

**SSE Streaming**:
- Server-Sent Events for real-time progress
- Automatic reconnection on network loss
- Offline queue for failed uploads
- Rate limiting (10 scans / 20 minutes)

**Error Handling**:
```swift
do {
    let results = try await talariaService.fetchResults(jobId)
} catch TalariaError.rateLimitExceeded {
    // Show rate limit overlay
} catch TalariaError.networkUnavailable {
    // Queue for offline retry
} catch {
    // Generic error handling
}
```

## Build & Testing

### Xcodebuild Requirements
**CRITICAL**: Always pipe through `xcsift`:
```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift
```

**Why xcsift?**
- Xcodebuild output is unstructured and hard to parse
- xcsift formats errors/warnings for human readability
- Required for CI/CD pipeline success validation

**Build Success Criteria**:
- ✅ 0 errors (mandatory)
- ✅ 0 warnings (goal)
- ✅ Build time < 30s (clean build)

### Testing Strategy
**Epic 1-2**: Manual verification (tap buttons, see results)
**Epic 3+**: XCTest unit tests (target 70%+ coverage)

**Performance Testing**:
```swift
let start = CFAbsoluteTimeGetCurrent()
// Operation to measure
let elapsed = CFAbsoluteTimeGetCurrent() - start
assert(elapsed < 0.5, "Camera start too slow")
```

**Test Coverage Goals**:
- Services: 80%+
- ViewModels: 70%+
- Views: Manual testing (SwiftUI Preview)

## OpenAPI Spec Management

### Committed Spec Pattern
- Spec **committed** to repository (not fetched during build)
- Location: `swiftwing/OpenAPI/talaria-openapi.yaml`
- SHA256 checksum: `.talaria-openapi.yaml.sha256`
- Build phase copies spec to `swiftwing/Generated/openapi.yaml`

**Update Process**:
```bash
./Scripts/update-api-spec.sh         # Normal update (checksum verification)
./Scripts/update-api-spec.sh --force # Force update (bypass checksum)
```

**Why Committed?**
- ✅ Offline builds possible
- ✅ Reproducible builds
- ✅ No network dependency during development
- ✅ Explicit API version control

## What NOT to Do

### Avoid These Patterns
❌ **Don't mix DispatchQueue with async/await**:
```swift
// BAD - causes deadlocks
DispatchQueue.main.async {
    await someAsyncFunction()  // DEADLOCK RISK
}

// GOOD - use MainActor
@MainActor
func updateUI() {
    // Guaranteed main thread
}
```

❌ **Don't use Task.detached**:
```swift
// BAD - breaks actor isolation
Task.detached {
    await someActorMethod()  // Actor isolation broken
}

// GOOD - use structured concurrency
Task {
    await someActorMethod()  // Actor isolation maintained
}
```

❌ **Don't ignore Swift 6.2 concurrency warnings**:
- All warnings → errors in this project
- Data race warnings are critical bugs
- Fix immediately, never suppress

❌ **Don't add unnecessary dependencies**:
- Use native frameworks first (URLSession, not Alamofire)
- Use SwiftData, not Core Data
- Use AVFoundation, not third-party camera libs

### Removed/Avoided Features
- ❌ Flutter (legacy implementation archived)
- ❌ Combine framework (use async/await)
- ❌ UIKit (SwiftUI-first)
- ❌ Core Data (use SwiftData)
- ❌ RxSwift (use async/await)

## Performance Standards

### App Performance
- **Cold launch**: < 1.5s to first frame
- **Camera start**: < 0.5s
- **UI responsiveness**: > 55 FPS
- **Image processing**: < 500ms
- **Network request**: < 200ms (P95)

### Memory
- **Baseline**: < 50 MB
- **With camera**: < 150 MB
- **Peak (processing)**: < 200 MB
- **Image cache**: Max 100 MB

### Battery
- **Camera usage**: < 5% per minute
- **Background**: 0% (no background execution)
- **Network**: Minimal impact (batch uploads)

## Epic-Based Development

### Current Epic Status
- **Epic 1**: ✅ Foundation (Complete - Jan 22, Grade: A 95/100)
- **Epic 2**: ✅ Camera (Complete - Jan 23, Grade: A 98/100)
- **Epic 3**: ✅ Library (Complete - Jan 24, Grade: A 97/100)
- **Epic 4**: ✅ AI Integration (Complete - Jan 25, Grade: A 99/100)
- **Epic 5**: ✅ Refactoring (Complete — MVVM extraction, OSLog migration, actor cleanup)
- **Epic 6**: 🔄 App Store Launch (In Progress)

### Epic 5 Achievement
**CameraView Refactor** (Phase 2A):
- Before: 1,098 lines (monolithic)
- After: 250 lines (view) + 727 lines (ViewModel)
- **77% size reduction** in view layer
- MVVM pattern fully established
- All Epic 4 features preserved

### Ralph-TUI Integration
- Epic config: `epic-1.json` through `epic-6.json`
- Vertical slice development
- User story tracking
- Acceptance criteria validation
