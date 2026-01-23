# Findings: SwiftWing Technical Research

**Date:** 2026-01-22
**Project:** SwiftWing - Native iOS Book Spine Scanner

---

## iOS Version Clarification ⚠️ UPDATED

**Finding:** User mentioned "iOS 26.1" and this is **CORRECT** - iOS 26 was released September 2025!

**Evidence from Web Research (January 2026):**
- **iOS 26**: Released September 15, 2025 (announced at WWDC June 9, 2025)
- **iOS 26.2.1**: Current version (minor bug fixes and security patches)
- **iOS 26.3**: Expected January 26, 2026
- **Swift 6.2**: Released at WWDC '25 with enhanced concurrency

**CRITICAL UPDATE:** iOS 26 introduces **Liquid Glass** design language!
- Unified design with rounded, translucent elements inspired by visionOS
- Camera app completely reworked with this interface
- Streamlined menus, fluid animations
- This REPLACES our "Swiss Utility" concept or requires significant adaptation

**Recommendation:**
- Target **iOS 26.0+** as minimum deployment (current gen devices)
- Leverage **Liquid Glass** design system (not Swiss Utility)
- Use **Swift 6.2** concurrency features
- Consider iOS 26.3 features for launch timeline

---

## Liquid Glass Design Language (iOS 26)

**Official Design System:** Apple's new unified design language introduced with iOS 26.

### Key Characteristics

1. **Translucent Elements**
   - Rounded, glass-like UI components
   - Material effects with depth and layering
   - Inspired by visionOS spatial computing

2. **Camera App Reference**
   - Completely redesigned in iOS 26
   - Streamlined menus and controls
   - Viewfinder-first approach (deference principle)

3. **Fluid Multitasking**
   - Seamless mode switching
   - Contextual control access
   - Dynamic Island integration for real-time updates

### Adaptation Strategy for SwiftWing

**Option A: Full Liquid Glass Adoption**
- Use translucent materials (`.ultraThinMaterial`, `.thinMaterial`)
- Rounded corners on all UI elements
- Glass-effect buttons and overlays
- Follow iOS 26 Camera app as reference

**Option B: Hybrid Approach**
- Keep high-contrast black/white base
- Add Liquid Glass translucency for overlays/menus
- Use international orange accent with glass effects
- Blend minimalism with iOS 26 aesthetics

**Recommendation:** Option B - Maintains brand identity while respecting platform conventions.

---

## Swift Concurrency Best Practices (Swift 6.2)

### 1. Actor-Based Architecture (Swift 6.2)

**Core Principle:** Only use actors when you have **mutable instance properties** to protect. Avoid empty actors.

**Key Pattern:**
```swift
actor CameraManager {
    private var session: AVCaptureSession
    private var isRunning: Bool = false  // Mutable state to protect

    func startSession() async throws {
        guard !isRunning else { return }
        // Thread-safe camera operations
        isRunning = true
    }
}

actor DataSyncActor {
    private var pendingEvents: [SSEEvent] = []  // Mutable queue

    func handleSSEEvent(_ event: SSEEvent) async {
        pendingEvents.append(event)
        await processQueue()
    }
}
```

**New in Swift 6.2:**
- `@concurrent` attribute for Swift Concurrency work
- Compile-time data race elimination
- Enhanced structured concurrency validation

**Benefits:**
- Eliminates data races at **compile time** (Swift 6.2)
- Compiler-enforced thread safety
- Natural fit for camera sessions and network streams

**Trade-offs:**
- Slight indirection overhead
- Reserve for truly shared state (don't over-actorize)

**Pitfalls to Avoid (2026 Best Practices):**
- ❌ Don't use `DispatchSemaphore` or `DispatchGroup` with async work (deadlock risk)
- ❌ Avoid detached tasks unless necessary (don't inherit priority)
- ❌ Never `await` code that synchronously waits for the main thread
- ❌ Don't overuse `await` in tight loops (performance issues)

---

### 2. AsyncStream for Server-Sent Events

**Recommended Pattern:**
```swift
func streamEvents(from url: URL) -> AsyncThrowingStream<SSEEvent, Error> {
    AsyncThrowingStream { continuation in
        Task {
            let (bytes, _) = try await URLSession.shared.bytes(from: url)
            for try await line in bytes.lines {
                if line.hasPrefix("data:") {
                    // Parse and yield event
                    continuation.yield(event)
                }
            }
            continuation.finish()
        }
    }
}
```

**Benefits:**
- Native async/await integration
- Automatic backpressure handling
- Clean cancellation semantics

---

### 3. SwiftUI Task Integration

**Pattern:**
```swift
struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()

    var body: some View {
        CameraPreview()
            .task {
                await cameraManager.startSession()
            }
    }
}
```

**Benefits:**
- Automatic lifecycle management
- Cancellation when view disappears
- No manual cleanup needed

---

## iOS 26 Camera APIs (Current Generation)

### Enhanced AVFoundation Features (iOS 18-26)

1. **Zero Shutter Lag (iOS 18+)**
   - Capture frames **before** shutter button press
   - Requires hardware integration with Camera Control button
   - **Use for:** Instant capture in US-106

2. **AVCaptureEventInteraction (iOS 18+)**
   - Physical Camera Control button integration
   - Hardware-level shutter control
   - **Use for:** Enhanced shutter mechanics

3. **Deferred Photo Processing (iOS 18+)**
   - Improved processing pipeline
   - Background processing without blocking capture
   - **Use for:** US-107 background image processing

4. **Video Effects and Reactions (iOS 18+)**
   - Built-in effects framework
   - Not applicable to book scanning but good to know

### SwiftUI Camera Integration (iOS 26)

**Critical:** SwiftUI still has **no built-in camera views** - must use AVFoundation bridge.

**Best Practice Pattern:**
```swift
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}
```

**Combine with @Observable (iOS 17+):**
```swift
@Observable
class CameraViewModel {
    var session = AVCaptureSession()
    var isRecording = false

    func startSession() async {
        // Use structured concurrency
    }
}
```

### Performance Recommendations

- **Frame Rate:** Cap at 30 FPS for spine scanning (balance quality vs battery)
- **Pixel Format:** `kCVPixelBufferPixelFormatType_420YpCbCr8BiPlanarVideoRange` for efficient YUV processing
- **Buffer Queue:** Process frames in dedicated actor queue to avoid main thread blocking

---

## Architecture Recommendations

### MVVM + Actor Services Pattern

```
┌─────────────────────────────────────┐
│          SwiftUI Views              │
│  (CameraView, LibraryView, etc.)    │
└──────────────┬──────────────────────┘
               │
       ┌───────▼────────┐
       │  View Models   │
       │ (@Observable)  │
       └───────┬────────┘
               │
       ┌───────▼────────────────────┐
       │    Actor Services          │
       │  • CameraActor             │
       │  • NetworkActor            │
       │  • DataSyncActor           │
       └───────┬────────────────────┘
               │
       ┌───────▼────────┐
       │   SwiftData    │
       │  (Persistence) │
       └────────────────┘
```

**Module Organization:**
```
Features/
  ├── Camera/
  │   ├── Views/
  │   ├── ViewModels/
  │   └── Actors/
  ├── Library/
  │   ├── Views/
  │   ├── ViewModels/
  │   └── Models/
  ├── Analysis/
  │   └── Services/
  └── Networking/
      └── Actors/
```

---

## SwiftData Schema Design

### Book Model
```swift
@Model
final class Book {
    @Attribute(.unique) var isbn: String
    var title: String
    var author: String
    var coverUrl: URL?
    var format: String?
    var addedDate: Date
    var spineConfidence: Double?

    init(isbn: String, title: String, author: String) {
        self.isbn = isbn
        self.title = title
        self.author = author
        self.addedDate = Date()
    }
}
```

**Key Features:**
- `.unique` attribute on ISBN for automatic deduplication
- URL type for type-safe cover URLs
- Optional fields for incomplete scans

---

## Performance Optimization Strategies

### Camera Performance
- **Cold Start Target:** < 0.5s from launch to live feed
- **Method:** Pre-warm camera session during splash screen
- **Monitoring:** Add performance logging with `CFAbsoluteTimeGetCurrent()`

### Memory Management
- **Image Downsampling:** Resize to max 1920px before upload
- **JPEG Compression:** Quality 0.85 (balance size vs quality)
- **Cache Strategy:** Use `URLCache` for cover images with size limit

### Battery Efficiency
- **Auto-Pause:** Stop camera after 30s inactivity
- **Background Tasks:** Use `Task.detached` with `.userInitiated` priority
- **Network Batching:** Group multiple scans if possible

### SSE Connection Management
- **Timeout:** 5-minute max per stream
- **Retry Logic:** Exponential backoff (1s, 2s, 4s max 3 retries)
- **Compression:** Request GZIP encoding from backend

---

## Talaria Backend Integration

### Endpoints (from US-swift.md)

1. **POST /v3/jobs/scans**
   - Upload multipart/form-data image
   - Response: `{ jobId: String, streamUrl: URL }`
   - Status: 202 Accepted

2. **SSE Stream** (from streamUrl)
   - Events: `progress`, `result`, `complete`, `error`
   - Keep-alive: heartbeat every 30s
   - Auto-reconnect on disconnect

3. **DELETE /v3/jobs/scans/{jobId}/cleanup**
   - Fire-and-forget cleanup
   - Call after `complete` event

### Error Handling

- **429 Too Many Requests:** Extract `Retry-After` header, disable shutter
- **Network Errors:** Queue scans locally, retry when online
- **Parse Errors:** Log to analytics, show user-friendly message

---

## Design System: Swiss Utility

### Typography
- **Headers/Data:** JetBrains Mono (monospaced precision)
- **Body:** San Francisco Pro (system default) or Inter

### Color Palette
```swift
extension Color {
    static let swissBackground = Color.black
    static let swissText = Color.white
    static let internationalOrange = Color(red: 1.0, green: 0.23, blue: 0.19)
}
```

### UI Components
- **Borders:** 1px solid white (`.border(.white, width: 1)`)
- **Shadows:** None (elevation: 0)
- **Motion:** `.spring(duration: 0.2)` or `.linear`
- **Haptics:** `.sensoryFeedback()` for all interactions

---

## Testing Strategy

### Unit Tests
- Actor isolation with `XCTestExpectation`
- Mock SSE streams with `AsyncStream`
- SwiftData in-memory stores for persistence tests

### Integration Tests
- Camera authorization flow
- End-to-end scan → upload → result flow
- Offline mode with queued uploads

### Performance Tests
- Camera cold start < 0.5s
- Image processing < 500ms
- UI frame rate > 55 FPS during scanning

---

## Security & Privacy

### Data Handling
- **Device ID:** Store in Keychain (not UserDefaults)
- **Images:** Process in temp directory, delete after upload
- **Network:** Use certificate pinning for Talaria backend

### Permissions
- **Camera:** Show primer screen before requesting
- **Copy:** "Wingtip needs your camera to see books. Images are processed and deleted instantly."

---

## iOS 26 Vision Framework for Book Scanning

**Date Added:** 2026-01-22
**Epic Target:** Epic 4 (Intelligence Layer)

### Context

iOS 26 is the current major release (released September 2025), with iOS 26.2 being the latest version. iOS 26.3 is in beta as of January 2026. The OS introduces the **Liquid Glass** design language across all platforms.

### Apple Intelligence 2.0 - On-Device Capabilities

**Visual Intelligence Features:**
- Real-time object identification in camera feeds
- Instant contextual actions (recipes, shopping links, etc.) based on what the camera sees
- Core ML 4.0 supports object recognition, predictive analytics, NLP, and AR spatial computing

**On-Device Processing Benefits:**
- All processing happens locally (no cloud uploads)
- Sensitive data like personal documents remains private
- Native Swift integration for developers

### Vision Framework Text Recognition (OCR)

**VNRecognizeTextRequest Capabilities:**
- Recognizes text in 26 languages
- Detects both printed and handwritten text
- Real-time camera feed text extraction (via VisionKit)
- Extracts structural elements from documents

**Configuration Options:**
```swift
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate  // or .fast for speed-optimized
request.recognitionLanguages = ["en"] // Target specific languages
request.usesLanguageCorrection = true
```

**Integration Pattern:**
```swift
// Process image with Vision framework
func recognizeText(in image: CGImage) async throws -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate

    let handler = VNImageRequestHandler(cgImage: image)
    try handler.perform([request])

    guard let observations = request.results else { return [] }
    return observations.compactMap { $0.topCandidates(1).first?.string }
}
```

### Potential Integration for SwiftWing (Epic 4)

**Architecture Options:**

**Option A: Talaria-Only (Original Plan)**
```
Capture → Upload image to Talaria → SSE stream → Enriched metadata
```
- **Pro:** Backend handles all complexity
- **Con:** Requires image upload, privacy concerns

**Option B: Hybrid Vision + Talaria**
```
Capture → On-device Vision OCR → Extract text → Send to Talaria for parsing/enrichment
```
- **Pro:** Privacy (no image upload, just text)
- **Pro:** Faster (less data transfer)
- **Pro:** Works with poor connectivity
- **Con:** More complex (Vision integration + Talaria)

**Option C: Vision Fallback**
```
Capture → Try Talaria → If fails/slow, use Vision OCR → Enrich locally or queue
```
- **Pro:** Works offline
- **Pro:** Talaria-first for best accuracy, Vision as backup
- **Con:** Most complex architecture

### What Vision Can Do vs What Talaria Should Do

**Vision Framework (On-Device):**
- Extract raw text from book spine image
- Identify text regions and bounding boxes
- Provide confidence scores for recognized text

**Talaria Backend (Intelligence Layer):**
1. Parse/structure the OCR text (distinguishing title from author from ISBN)
2. Enrich with additional metadata (cover images, formats, publisher, etc.)
3. Handle ambiguous cases where OCR confidence is low
4. Provide book recommendations and related titles

**Key Insight:** Vision gives you **raw text extraction**; Talaria provides the **intelligence layer** to turn that into structured book data.

### Decision Deferred to Epic 4

**Why not Epic 2:**
- Epic 2 focuses on camera capture mechanics only (vertical slice)
- Adding Vision OCR now violates separation of concerns
- Don't know if Vision OCR accuracy is sufficient for book spines yet
- Premature to choose architecture before testing with real data

**When to Decide (Epic 4):**
- Test both Vision and Talaria approaches with real book spines
- Measure accuracy, speed, and data transfer costs
- Consider privacy implications (image upload vs text-only)
- Evaluate offline mode requirements

### Open Questions for Epic 4

1. ❓ Vision OCR accuracy on book spines vs Talaria image analysis?
2. ❓ Hybrid approach (Vision + Talaria) vs Talaria-only?
3. ❓ Offline-first with Vision fallback?
4. ❓ Privacy preference: On-device only vs cloud-enhanced?
5. ❓ Performance: Vision local processing time vs Talaria upload + analysis?

### References

- [Apple Vision Framework Docs](https://developer.apple.com/documentation/vision)
- [VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)
- Core ML 4.0 for additional on-device intelligence
- iOS 26 release notes (September 2025)

---

## Open Questions

1. ❓ Exact Talaria backend URL and API version?
2. ❓ Rate limits per device per day?
3. ❓ Cover image CDN CORS policy?
4. ❓ Analytics/crash reporting requirements?
5. ❓ App Store deployment timeline?

---

## Key Technical Decisions

| Decision | Reasoning | Alternatives Considered |
|----------|-----------|------------------------|
| Actors for concurrency | Compiler-enforced thread safety | Manual GCD (error-prone) |
| SwiftData over Core Data | Modern API, better SwiftUI integration | Realm (extra dependency) |
| AsyncStream for SSE | Native Swift concurrency | Combine (legacy), third-party libs |
| 30 FPS camera cap | Battery efficiency | 60 FPS (overkill for spines) |
| MVVM pattern | SwiftUI standard, testable | VIPER (overengineered for scope) |

---

## References

- [US-swift.md](US-swift.md) - Existing user stories
- [flutter-legacy/prd.json](flutter-legacy/prd.json) - Flutter reference
- Grok conversation: iOS 17+ development best practices
- Apple Docs: [SwiftData](https://developer.apple.com/documentation/swiftdata), [AVFoundation](https://developer.apple.com/av-foundation/)
