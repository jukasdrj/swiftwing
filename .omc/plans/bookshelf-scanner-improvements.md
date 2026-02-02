# Bookshelf Scanner Improvements Plan

**Plan ID:** bookshelf-scanner-improvements
**Created:** 2026-02-01
**Status:** READY FOR REVIEW (Revision 2)
**Source:** External analysis session (`/Users/juju/dev_repos/BOOKSHELF_SCANNER_LESSONS.md`, outside the swiftwing repo). Requirements extracted from comparative analysis of bookshelf-scanner, swiftwing, and wingtip repositories.
**Scope:** SwiftWing repository ONLY

---

## Context

### Original Request

Implement critical gaps and high-value features identified from an external bookshelf-scanner analysis:
1. Image preprocessing pipeline (contrast, brightness, denoising, rotation detection)
2. SSE disconnection detection with backend cleanup
3. Review queue UI for low-confidence books
4. Progressive results UX with segmented image preview

### Interview Summary

- **Project:** SwiftWing iOS 26 book spine scanner (Swift 6.2, SwiftUI, SwiftData)
- **Current State:** Epic 5 refactoring in progress (Phases 2A-2E complete, CameraView refactored to MVVM)
- **Architecture:** MVVM + Actor-based services, MainActor CameraViewModel (876 lines), TalariaService actor for network/SSE
- **Existing Features:** Camera capture, image resize/compress, SSE streaming, review queue (basic), library with confidence filter
- **Gaps Identified:** No image preprocessing, no SSE disconnect detection, review queue lacks confidence awareness, no progressive results UI

### Research Findings (Metis Consultation)

**Critical Architecture Insights:**
1. **ImagePreprocessor MUST be a separate actor** -- CIFilter processing on MainActor would block UI (CameraViewModel is @MainActor)
2. **Use Data/URL for image handoff, NOT base64 strings** -- Base64 has 33% overhead; prefer binary Data or temp file URLs
3. **SSE disconnection needs explicit task cancellation** -- URLSession.bytes suspension points may hang if backend doesn't close socket; need explicit URLSessionDataTask cancellation
4. **Progressive state machine in ProcessingItem** -- Use enum-based status rather than boolean flags
5. **SSE protocol must handle unknown event types gracefully** -- Backward compatibility for older app versions
6. **Review queue: confidence-based sorting > filter toggle** -- Float low-confidence items to top automatically
7. **CIContext with RGBA8 working format** -- Optimize GPU/CPU handoff during image processing

---

## Work Objectives

### Core Objective

Add image preprocessing, SSE lifecycle management, confidence-aware review queue, and progressive results UX to SwiftWing's scanning pipeline.

### Deliverables

1. **ImagePreprocessor actor** -- CIFilter-based pipeline: contrast (1.5x), brightness (auto), denoising, rotation detection
2. **SSE disconnection handling** -- Detect navigation/backgrounding mid-scan, call DELETE cleanup endpoint, cancel URLSession tasks
3. **Enhanced ReviewQueueView** -- Confidence-based sorting, visual confidence indicators, edit capability for low-confidence books
4. **Progressive results UI** -- Segmented image preview, per-book progress counter, new SSE event type support

### Definition of Done

- [ ] All 4 features implemented and integrated
- [ ] Build passes with 0 errors, 0 warnings (`xcodebuild ... | xcsift`)
- [ ] Image preprocessing measured at < 500ms for 1920px images
- [ ] SSE cleanup confirmed via print logs when navigating away mid-scan
- [ ] Review queue sorts low-confidence books to top
- [ ] Progressive results shows segmented preview when backend supports it (graceful degradation when not)
- [ ] No regressions to existing capture/upload/streaming pipeline
- [ ] All new code follows Swift 6.2 strict concurrency (no @unchecked Sendable)

---

## Guardrails

### MUST Have
- Actor isolation for ImagePreprocessor (NOT MainActor)
- Backward compatibility with current SSE event protocol
- Graceful degradation for progressive results (works without backend changes)
- All existing tests continue to pass
- Build with 0 errors, 0 warnings

### MUST NOT Have
- Do NOT create new SwiftData models (use existing Book + PendingBookResult)
- Do NOT modify Talaria backend (client-side only changes)
- Do NOT touch wingtip repository
- Do NOT add third-party dependencies (use native CIFilter, Vision framework)
- Do NOT break existing review queue approve/reject flow
- Do NOT use Task.detached (breaks actor isolation per project rules)

---

## Task Flow and Dependencies

```
Task 1: ImagePreprocessor Actor (NEW FILE)
    |
    v
Task 2: Integrate Preprocessing into Capture Pipeline (MODIFY CameraViewModel)
    |
    v
Task 3: SSE Disconnection Detection (MODIFY CameraViewModel + CameraView)
    |
    v
Task 4: Enhanced Review Queue UI (MODIFY ReviewQueueView + PendingBookResult + CameraViewModel)
    |
    v
Task 5: Progressive Results - Network Types and SSE Parsing (MODIFY NetworkTypes + TalariaService + CameraViewModel)
    |
    v
Task 6: Progressive Results - UI Components (NEW FILE + MODIFY CameraView + CameraViewModel + ProcessingItem)
    |
    v
Task 7: Integration Testing & Verification
```

Tasks 1-2 are sequential (preprocessor must exist before integration).
Tasks 3-4 are independent of each other but depend on Tasks 1-2 being stable.
Tasks 5-6 are sequential (types before UI).
Task 7 verifies everything together.

---

## Detailed TODOs

### Task 1: Create ImagePreprocessor Actor

**Priority:** CRITICAL
**Effort:** 2 hours
**New File:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/ImagePreprocessor.swift`

**Description:**
Create an actor-isolated image preprocessing pipeline using Core Image (CIFilter). This actor runs OFF the MainActor to avoid blocking UI during expensive filter operations. The pipeline applies 4 stages: contrast enhancement, adaptive brightness adjustment, noise reduction, and rotation detection/correction.

**Implementation Details:**

```swift
// /Users/juju/dev_repos/swiftwing/swiftwing/Services/ImagePreprocessor.swift

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Actor-isolated image preprocessing pipeline for book spine recognition
/// Applies contrast enhancement, brightness adjustment, denoising, and rotation correction
/// Runs OFF MainActor to avoid blocking UI during CIFilter processing
///
/// Performance target: < 500ms for 1920px max dimension images
/// Memory: Uses CIContext with RGBA8 working format for GPU optimization
actor ImagePreprocessor {

    /// Shared CIContext for filter rendering (reused across calls)
    private let ciContext: CIContext

    /// Processing metrics
    struct PreprocessingResult: Sendable, Codable {
        let processedData: Data
        let wasRotated: Bool
        let brightnessAdjustment: Float
        let processingTimeMs: Int
    }

    init() {
        // Use RGBA8 working format for optimized GPU/CPU handoff
        self.ciContext = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .highQualityDownsample: true
        ])
    }

    /// Full preprocessing pipeline
    func preprocess(_ imageData: Data) async -> PreprocessingResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            return PreprocessingResult(
                processedData: imageData,
                wasRotated: false,
                brightnessAdjustment: 0,
                processingTimeMs: 0
            )
        }

        var ciImage = CIImage(cgImage: cgImage)

        // Step 1: Rotation detection and correction
        let wasRotated = detectAndCorrectRotation(&ciImage)

        // Step 2: Contrast enhancement (1.5x)
        applyContrastEnhancement(&ciImage, factor: 1.5)

        // Step 3: Adaptive brightness adjustment
        let brightnessAdj = applyAdaptiveBrightness(&ciImage)

        // Step 4: Noise reduction
        applyNoiseReduction(&ciImage)

        // Render to Data (JPEG, 0.85 quality)
        let outputData = renderToJPEG(ciImage, quality: 0.85) ?? imageData

        let duration = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        return PreprocessingResult(
            processedData: outputData,
            wasRotated: wasRotated,
            brightnessAdjustment: brightnessAdj,
            processingTimeMs: duration
        )
    }
}
```

**Key Methods to Implement:**

1. `detectAndCorrectRotation(_ image: inout CIImage) -> Bool`
   - Check aspect ratio: if height/width > 2.0, rotate 90 degrees CCW
   - Use `image.transformed(by: CGAffineTransform(rotationAngle: -.pi / 2))`
   - Translate origin back to (0,0) after rotation
   - Return true if rotated

2. `applyContrastEnhancement(_ image: inout CIImage, factor: Float)`
   - Use CIFilter "CIColorControls" with kCIInputContrastKey = factor
   - Guard against nil outputImage

3. `applyAdaptiveBrightness(_ image: inout CIImage) -> Float`
   - Calculate average luminance by sampling a downscaled version (64x64)
   - Target luminance: 128 (mid-gray)
   - If avg < 100: brighten by +0.1 to +0.2
   - If avg > 180: darken by -0.1 to -0.2
   - Use CIFilter "CIColorControls" with kCIInputBrightnessKey

4. `applyNoiseReduction(_ image: inout CIImage)`
   - Use CIFilter "CINoiseReduction" with inputNoiseLevel = 0.02, inputSharpness = 0.4
   - Light denoising to avoid losing spine text detail

5. `renderToJPEG(_ image: CIImage, quality: CGFloat) -> Data?`
   - Use ciContext.jpegRepresentation(of:colorSpace:options:)
   - Fallback: render to CGImage then UIImage JPEG

**Unit Test Plan:**
- Test with blank/white image (no crash)
- Test with tall narrow image (aspect > 2.0) verifying rotation
- Test with dark image (avg luminance < 100) verifying brightness increase
- Test with bright image (avg luminance > 180) verifying brightness decrease
- Test performance: 1920x1080 image processed in < 500ms
- Test nil/corrupt imageData returns original data unchanged

**Acceptance Criteria:**
- [ ] Actor compiles with zero warnings under Swift 6.2 strict concurrency
- [ ] Processing time < 500ms for a 1920x1080 test image
- [ ] Rotated images (aspect ratio > 2.0) are correctly detected and rotated
- [ ] Output JPEG maintains reasonable quality (no visible artifacts)
- [ ] All properties and methods are actor-isolated (no nonisolated leaks)
- [ ] PreprocessingResult conforms to Codable for consistency

---

### Task 2: Integrate Preprocessing into Capture Pipeline

**Priority:** CRITICAL
**Effort:** 1.5 hours
**Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`
**Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/ProcessingItem.swift`

**Description:**
Insert the ImagePreprocessor into the existing capture pipeline between image capture and upload. The preprocessing runs after the raw image is captured but before the resize/compress/upload step. Update ProcessingItem to show a "Preprocessing..." state.

**Changes to CameraViewModel.swift:**

In `processCaptureWithImageData()` method (around line 253), insert preprocessing BEFORE the `Self.processImage(imageData)` call:

```swift
// BEFORE (current code at ~line 253):
let fileURL = try await Self.processImage(imageData)

// AFTER (with preprocessing):
// Step 1: Preprocess image (contrast, brightness, denoising, rotation)
updateQueueItemProgress(id: item.id, message: "Preprocessing...")
let preprocessor = ImagePreprocessor()
let preprocessResult = await preprocessor.preprocess(imageData)
print("Preprocessing: \(preprocessResult.processingTimeMs)ms, rotated: \(preprocessResult.wasRotated), brightness adj: \(preprocessResult.brightnessAdjustment)")

// Step 2: Process (resize + compress) the preprocessed image
let fileURL = try await Self.processImage(preprocessResult.processedData)
```

**Changes to ProcessingItem.swift:**

Add a `.preprocessing` state to `ProcessingState`:

```swift
enum ProcessingState: Equatable {
    case preprocessing  // NEW: Purple border - preprocessing (CIFilter pipeline)
    case uploading      // Yellow border
    case analyzing      // Blue border
    case done           // Green border
    case error          // Red border
    case offline        // Gray border

    var borderColor: Color {
        switch self {
        case .preprocessing: return .purple  // NEW
        case .uploading: return .yellow
        case .analyzing: return .blue
        case .done: return .green
        case .error: return .red
        case .offline: return .gray
        }
    }
}
```

**Performance Consideration:**
- ImagePreprocessor() is created fresh per capture call. Since it's an actor, the CIContext is per-instance.
- For high-frequency scanning (bulk mode), consider making ImagePreprocessor a property of CameraViewModel instead. However, since it's NOT @MainActor, it cannot be a stored property of the @MainActor CameraViewModel directly. Solution: store it as a let constant initialized in init, since actor references are Sendable.

```swift
// In CameraViewModel, add as stored property:
private let imagePreprocessor = ImagePreprocessor()
```

**Acceptance Criteria:**
- [ ] Preprocessing runs before every upload (visible in console logs)
- [ ] Processing queue shows "Preprocessing..." message briefly
- [ ] Purple border state appears in ProcessingQueueView
- [ ] Total capture-to-upload time increases by < 500ms
- [ ] Existing capture flow (offline queue, rate limiting) unaffected
- [ ] Build: 0 errors, 0 warnings

---

### Task 3: SSE Disconnection Detection with Backend Cleanup

**Priority:** HIGH
**Effort:** 2 hours
**Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`
**Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraView.swift`

**Description:**
Add explicit SSE stream disconnection detection. When the user navigates away from the camera screen or backgrounds the app during an active scan, the app should: (1) cancel the URLSession streaming task, (2) call the DELETE cleanup endpoint on Talaria, (3) remove the processing item from the queue. Currently, cleanup only happens on terminal SSE events or explicit Task.isCancelled checks.

**Changes to CameraViewModel.swift:**

**1. Add jobAuthTokens map (new stored property, around line 38):**

```swift
// MARK: - US-406: Active Streaming Tasks
var activeStreamingTasks: [UUID: Task<Void, Never>] = [:]

// NEW: Job ID to auth token mapping for cleanup calls
private var jobAuthTokens: [String: String] = [:]
```

**2. Store auth token when upload succeeds (in processCaptureWithImageData, after line 287):**

```swift
let (uploadedJobId, streamUrl, uploadedAuthToken) = try await talariaService.uploadScan(image: uploadData, deviceId: scanDeviceId)
jobId = uploadedJobId
authToken = uploadedAuthToken

// NEW: Store auth token for disconnect cleanup
if let uploadedAuthToken = uploadedAuthToken {
    jobAuthTokens[uploadedJobId] = uploadedAuthToken
}
```

**3. Clean up auth token on normal completion (in the .complete and .error cases):**

After the existing `performCleanup(...)` calls in the switch cases, add:

```swift
// Remove auth token (job is done)
if let jid = jobId {
    jobAuthTokens.removeValue(forKey: jid)
}
```

**4. Replace `cancelAllStreamingTasks()` entirely (line 534):**

```swift
// MARK: - US-406: Stream Cancellation
func cancelAllStreamingTasks() {
    let taskCount = activeStreamingTasks.count
    guard taskCount > 0 else { return }

    print("Cancelling \(taskCount) active SSE streams (navigation/backgrounding)")

    // Cancel all Swift Task instances (triggers Task.isCancelled in stream loops)
    for (_, task) in activeStreamingTasks {
        task.cancel()
    }
    activeStreamingTasks.removeAll()

    // Collect all in-progress job IDs that need backend cleanup
    let activeJobIds = processingQueue
        .filter { $0.state == .uploading || $0.state == .analyzing || $0.state == .preprocessing }
        .compactMap { $0.jobId }

    // Fire-and-forget cleanup calls to backend with stored auth tokens
    for activeJobId in activeJobIds {
        let storedAuthToken = jobAuthTokens[activeJobId]
        Task {
            let service = TalariaService()
            do {
                try await service.cleanup(jobId: activeJobId, authToken: storedAuthToken)
                print("Backend cleanup sent for disconnected job: \(activeJobId)")
            } catch {
                print("Backend cleanup failed for \(activeJobId): \(error.localizedDescription)")
            }
        }
    }

    // Clear all auth tokens (all jobs are being abandoned)
    jobAuthTokens.removeAll()

    // Remove in-progress items from queue with animation
    withAnimation(.swissSpring) {
        processingQueue.removeAll {
            $0.state == .uploading || $0.state == .analyzing || $0.state == .preprocessing
        }
    }
}
```

**5. Add `onDisappear` cleanup in CameraView.swift (line 195):**

The current `onDisappear` only calls `viewModel.stopCamera()`. Add streaming task cancellation.

**IMPORTANT TabView context note:** In SwiftUI TabView, `onDisappear` fires when switching tabs. This is intentional behavior -- we WANT to cancel active streams when user navigates to Library or Review tabs. The camera session is also stopped, so there's no ambiguity. When the user returns to the camera tab, `.task` re-runs `setupCamera()`, and any new scans start fresh.

```swift
// In CameraView.swift, modify onDisappear (line 195):
.onDisappear {
    viewModel.cancelAllStreamingTasks()  // NEW: Cancel SSE streams + backend cleanup
    viewModel.stopCamera()
}
```

**Acceptance Criteria:**
- [ ] Navigating away from Camera tab during active scan triggers cleanup
- [ ] Backend receives DELETE cleanup request (visible in console logs)
- [ ] In-progress queue items are removed on navigation away
- [ ] App backgrounding (willResignActive) triggers cleanup (already wired)
- [ ] Auth tokens are preserved for cleanup calls via jobAuthTokens map
- [ ] No orphaned URLSession tasks after navigation
- [ ] onDisappear in TabView context correctly cleans up when switching tabs
- [ ] Build: 0 errors, 0 warnings

---

### Task 4: Enhanced Review Queue UI

**Priority:** HIGH
**Effort:** 3 hours
**Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/ReviewQueueView.swift`
**Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/Models/PendingBookResult.swift`
**Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`

**Description:**
Enhance the existing ReviewQueueView with confidence-aware sorting, visual confidence indicators, and inline editing capability for low-confidence results. Low-confidence books (< 0.5) float to the top with warning badges. Medium confidence (0.5-0.8) shows caution indicators. High confidence (> 0.8) shows green checkmarks.

**Changes to PendingBookResult.swift (COMPLETE REPLACEMENT):**

Add editable override fields and resolved value accessors:

```swift
import Foundation

/// Represents a book scan result awaiting user review
/// In-memory only -- does not persist across app launches
/// Used by ReviewQueueView for approve/reject workflow
struct PendingBookResult: Identifiable, Equatable {
    let id: UUID
    let metadata: BookMetadata      // Original AI result (immutable)
    let rawJSON: String?
    let thumbnailData: Data?        // From ProcessingItem for visual reference
    let scannedDate: Date
    let confidence: Double?

    // Editable overrides (nil = use metadata value)
    var editedTitle: String?         // NEW
    var editedAuthor: String?        // NEW

    // Resolved values (prefer edit over original)
    var resolvedTitle: String { editedTitle ?? metadata.title }
    var resolvedAuthor: String { editedAuthor ?? metadata.author }

    init(metadata: BookMetadata, rawJSON: String?, thumbnailData: Data? = nil) {
        self.id = UUID()
        self.metadata = metadata
        self.rawJSON = rawJSON
        self.thumbnailData = thumbnailData
        self.scannedDate = Date()
        self.confidence = metadata.confidence
        self.editedTitle = nil
        self.editedAuthor = nil
    }

    static func == (lhs: PendingBookResult, rhs: PendingBookResult) -> Bool {
        lhs.id == rhs.id
    }
}
```

**Changes to CameraViewModel.swift -- approveBook() (line 675):**

Replace the current `approveBook()` to use resolved values:

```swift
// CURRENT (line 675):
func approveBook(_ pendingBook: PendingBookResult, modelContext: ModelContext) {
    let isbn = pendingBook.metadata.isbn ?? "UNKNOWN-\(UUID().uuidString)"

    // Duplicate detection at approve time
    do {
        if let duplicate = try DuplicateDetection.findDuplicate(isbn: isbn, in: modelContext) {
            pendingBookBeingApproved = pendingBook
            pendingBookMetadata = pendingBook.metadata
            pendingRawJSON = pendingBook.rawJSON
            duplicateBook = duplicate
            withAnimation(.swissSpring) {
                showDuplicateAlert = true
            }
            return
        }
    } catch {
        // Proceed with add on detection failure
    }

    addBookToLibrary(metadata: pendingBook.metadata, rawJSON: pendingBook.rawJSON, modelContext: modelContext)

    withAnimation(.swissSpring) {
        pendingReviewBooks.removeAll { $0.id == pendingBook.id }
    }

    print("Book approved and added to library: \(pendingBook.metadata.title)")
}

// REPLACEMENT:
func approveBook(_ pendingBook: PendingBookResult, modelContext: ModelContext) {
    let isbn = pendingBook.metadata.isbn ?? "UNKNOWN-\(UUID().uuidString)"

    // Duplicate detection at approve time
    do {
        if let duplicate = try DuplicateDetection.findDuplicate(isbn: isbn, in: modelContext) {
            pendingBookBeingApproved = pendingBook
            pendingBookMetadata = pendingBook.metadata
            pendingRawJSON = pendingBook.rawJSON
            duplicateBook = duplicate
            withAnimation(.swissSpring) {
                showDuplicateAlert = true
            }
            return
        }
    } catch {
        // Proceed with add on detection failure
    }

    // Use resolved values (prefers user edits over AI results)
    addBookToLibrary(
        title: pendingBook.resolvedTitle,
        author: pendingBook.resolvedAuthor,
        metadata: pendingBook.metadata,
        rawJSON: pendingBook.rawJSON,
        modelContext: modelContext
    )

    withAnimation(.swissSpring) {
        pendingReviewBooks.removeAll { $0.id == pendingBook.id }
    }

    print("Book approved and added to library: \(pendingBook.resolvedTitle)")
}
```

**Changes to CameraViewModel.swift -- approveAllBooks() (line 711):**

Replace to use resolved values:

```swift
// CURRENT (line 711):
func approveAllBooks(modelContext: ModelContext) {
    let count = pendingReviewBooks.count
    for book in pendingReviewBooks {
        addBookToLibrary(metadata: book.metadata, rawJSON: book.rawJSON, modelContext: modelContext)
    }

    withAnimation(.swissSpring) {
        pendingReviewBooks.removeAll()
    }

    print("All \(count) books approved and added to library")
}

// REPLACEMENT:
func approveAllBooks(modelContext: ModelContext) {
    let count = pendingReviewBooks.count
    for book in pendingReviewBooks {
        addBookToLibrary(
            title: book.resolvedTitle,
            author: book.resolvedAuthor,
            metadata: book.metadata,
            rawJSON: book.rawJSON,
            modelContext: modelContext
        )
    }

    withAnimation(.swissSpring) {
        pendingReviewBooks.removeAll()
    }

    print("All \(count) books approved and added to library")
}
```

**Changes to CameraViewModel.swift -- addBookToLibrary() (line 724):**

Add title/author override parameters:

```swift
// CURRENT (line 724):
func addBookToLibrary(metadata: BookMetadata, rawJSON: String?, modelContext: ModelContext) {
    // ...
    let newBook = Book(
        title: metadata.title,
        author: metadata.author,
        // ...

// REPLACEMENT:
func addBookToLibrary(title: String? = nil, author: String? = nil, metadata: BookMetadata, rawJSON: String?, modelContext: ModelContext) {
    let publishedDate: Date?
    if let dateString = metadata.publishedDate {
        let formatter = ISO8601DateFormatter()
        publishedDate = formatter.date(from: dateString)
    } else {
        publishedDate = nil
    }

    let newBook = Book(
        title: title ?? metadata.title,        // Use override if provided
        author: author ?? metadata.author,      // Use override if provided
        isbn: metadata.isbn ?? "UNKNOWN-\(UUID().uuidString)",
        coverUrl: metadata.coverUrl,
        format: metadata.format,
        publisher: metadata.publisher,
        publishedDate: publishedDate,
        pageCount: metadata.pageCount,
        spineConfidence: metadata.confidence,
        addedDate: Date(),
        rawJSON: rawJSON
    )

    modelContext.insert(newBook)

    do {
        try modelContext.save()
        print("Book added to library: \(title ?? metadata.title)")

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

    } catch {
        print("Failed to save book: \(error)")
    }
}
```

**NOTE:** The existing call sites that pass only `metadata:` and `rawJSON:` (e.g., in `handleBookResult`, `addDuplicateAnyway`) continue to work unchanged because `title` and `author` default to `nil`.

**Changes to ReviewQueueView.swift:**

1. **Add confidence-based sorting to the book list:**

```swift
private var sortedPendingBooks: [PendingBookResult] {
    viewModel.pendingReviewBooks.sorted { a, b in
        // Low confidence first (needs most attention)
        let confA = a.confidence ?? 1.0
        let confB = b.confidence ?? 1.0
        return confA < confB
    }
}
```

2. **Add confidence badge to ReviewCardView:**

```swift
// In ReviewCardView, add visual confidence indicator:
private var confidenceBadge: some View {
    let confidence = book.confidence ?? 1.0
    let (icon, color, label) = confidenceDisplay(confidence)

    return HStack(spacing: 4) {
        Image(systemName: icon)
            .font(.caption)
        Text(label)
            .font(.caption.bold())
    }
    .foregroundColor(color)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(color.opacity(0.15))
    .cornerRadius(6)
}

private func confidenceDisplay(_ confidence: Double) -> (String, Color, String) {
    if confidence >= 0.8 {
        return ("checkmark.circle.fill", .green, "\(Int(confidence * 100))%")
    } else if confidence >= 0.5 {
        return ("exclamationmark.triangle.fill", .orange, "\(Int(confidence * 100))%")
    } else {
        return ("xmark.octagon.fill", .red, "\(Int(confidence * 100))%")
    }
}
```

3. **Add inline title/author editing for low-confidence books:**

```swift
// In ReviewCardView, add edit state:
@State private var isEditing = false
@State private var editedTitle: String
@State private var editedAuthor: String

// Initialize from book's resolved values in init
init(book: PendingBookResult, onApprove: @escaping () -> Void, onReject: @escaping () -> Void) {
    self.book = book
    self.onApprove = onApprove
    self.onReject = onReject
    self._editedTitle = State(initialValue: book.resolvedTitle)
    self._editedAuthor = State(initialValue: book.resolvedAuthor)
}

// Show edit fields when isEditing = true:
if isEditing {
    TextField("Title", text: $editedTitle)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
            // Write back to PendingBookResult via binding
        }
    TextField("Author", text: $editedAuthor)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
            // Write back to PendingBookResult via binding
        }
}
```

**Note on edit propagation:** Since `PendingBookResult` is a value type in an array, the ReviewCardView needs a way to write edits back. The recommended approach is to pass a binding or use a callback:

```swift
// In ReviewQueueView, pass edit callback:
ReviewCardView(
    book: book,
    onApprove: {
        viewModel.approveBook(book, modelContext: modelContext)
    },
    onReject: {
        viewModel.rejectBook(book)
    },
    onEdit: { editedTitle, editedAuthor in
        viewModel.updatePendingBookEdits(
            id: book.id,
            title: editedTitle,
            author: editedAuthor
        )
    }
)

// In CameraViewModel, add edit handler:
func updatePendingBookEdits(id: UUID, title: String?, author: String?) {
    if let index = pendingReviewBooks.firstIndex(where: { $0.id == id }) {
        pendingReviewBooks[index].editedTitle = title
        pendingReviewBooks[index].editedAuthor = author
    }
}
```

4. **Add section headers for confidence groups:**

```swift
// Group books by confidence tier:
private var lowConfidenceBooks: [PendingBookResult] {
    sortedPendingBooks.filter { ($0.confidence ?? 1.0) < 0.5 }
}

private var mediumConfidenceBooks: [PendingBookResult] {
    sortedPendingBooks.filter {
        let c = $0.confidence ?? 1.0
        return c >= 0.5 && c < 0.8
    }
}

private var highConfidenceBooks: [PendingBookResult] {
    sortedPendingBooks.filter { ($0.confidence ?? 1.0) >= 0.8 }
}
```

Display with section headers:
```swift
if !lowConfidenceBooks.isEmpty {
    SectionHeader(title: "Needs Review", count: lowConfidenceBooks.count, color: .red)
    ForEach(lowConfidenceBooks) { ... }
}
if !mediumConfidenceBooks.isEmpty {
    SectionHeader(title: "Verify", count: mediumConfidenceBooks.count, color: .orange)
    ForEach(mediumConfidenceBooks) { ... }
}
if !highConfidenceBooks.isEmpty {
    SectionHeader(title: "Ready to Add", count: highConfidenceBooks.count, color: .green)
    ForEach(highConfidenceBooks) { ... }
}
```

**Acceptance Criteria:**
- [ ] Low-confidence books (< 0.5) appear at top with red badge
- [ ] Medium-confidence (0.5-0.8) appear in middle with orange badge
- [ ] High-confidence (>= 0.8) appear at bottom with green badge
- [ ] Section headers show counts per confidence tier
- [ ] Inline editing works for title and author fields
- [ ] Edited values propagate via `updatePendingBookEdits()` to `PendingBookResult`
- [ ] `approveBook()` uses `resolvedTitle`/`resolvedAuthor` (edit overrides AI values)
- [ ] `approveAllBooks()` uses `resolvedTitle`/`resolvedAuthor` for each book
- [ ] `addBookToLibrary()` accepts optional title/author overrides
- [ ] Existing direct calls to `addBookToLibrary(metadata:rawJSON:modelContext:)` still compile (defaults to nil)
- [ ] "Approve All" still works correctly with edited values
- [ ] Existing approve/reject flow is not broken
- [ ] Swiss Glass design system is maintained
- [ ] Build: 0 errors, 0 warnings

---

### Task 5: Progressive Results - Network Types, SSE Parsing, and CameraViewModel Handling

**Priority:** NICE-TO-HAVE (HIGH VALUE)
**Effort:** 2.5 hours
**Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift`
**Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift`
**Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`

**Description:**
Extend the SSE event protocol to support progressive results: segmented image preview and per-book progress counters. These new event types are additive -- the existing protocol continues to work. The TalariaService parser gracefully ignores unknown event types for backward compatibility.

**CRITICAL: CameraViewModel must be updated in this task** to handle the new SSE event cases. Adding cases to the `SSEEvent` enum without updating the `switch event` in `processCaptureWithImageData()` (line 313) would make the switch non-exhaustive and break the build.

**Changes to NetworkTypes.swift:**

Add new SSE event cases and supporting types:

```swift
enum SSEEvent: Sendable {
    case progress(String)               // Existing: status text
    case result(BookMetadata)           // Existing: book identified
    case complete                       // Existing: job finished
    case error(String)                  // Existing: job failed
    case canceled                       // Existing: job canceled
    case segmented(SegmentedPreview)    // NEW: segmented image with detected regions
    case bookProgress(BookProgressInfo) // NEW: per-book processing progress
}

/// Segmented image preview from backend after initial detection
struct SegmentedPreview: Sendable, Codable {
    let imageData: Data       // JPEG data of annotated image with bounding boxes
    let totalBooks: Int        // Number of book spines detected
}

/// Per-book processing progress update
struct BookProgressInfo: Sendable, Codable {
    let current: Int           // Which book is being processed (1-based)
    let total: Int             // Total books detected
    let stage: String?         // Optional stage description
}
```

**Changes to TalariaService.swift:**

Update `parseSSEEvent()` (line 424) to handle new event types:

```swift
nonisolated private func parseSSEEvent(event: String, data: String) throws -> SSEEvent {
    switch event {
    case "progress":
        // Progress event with message
        if let jsonData = data.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let message = json["message"] as? String {
            return .progress(message)
        } else {
            throw SSEError.invalidEventFormat
        }

    case "result":
        // Result event with book metadata
        guard let jsonData = data.data(using: .utf8) else {
            throw SSEError.invalidEventFormat
        }
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(BookMetadata.self, from: jsonData)
        return .result(metadata)

    case "complete", "completed":
        return .complete

    case "error":
        // Error event with message
        if let jsonData = data.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let message = json["message"] as? String {
            return .error(message)
        } else {
            return .error("Unknown error")
        }

    case "canceled":
        return .canceled

    case "segmented":
        // NEW: Segmented image preview
        guard let jsonData = data.data(using: .utf8) else {
            throw SSEError.invalidEventFormat
        }
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        guard let imageBase64 = json?["image"] as? String,
              let imageData = Data(base64Encoded: imageBase64),
              let totalBooks = json?["totalBooks"] as? Int else {
            throw SSEError.invalidEventFormat
        }
        return .segmented(SegmentedPreview(imageData: imageData, totalBooks: totalBooks))

    case "book_progress":
        // NEW: Per-book processing progress
        guard let jsonData = data.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let current = json["current"] as? Int,
              let total = json["total"] as? Int else {
            throw SSEError.invalidEventFormat
        }
        let stage = json["stage"] as? String
        return .bookProgress(BookProgressInfo(current: current, total: total, stage: stage))

    default:
        // BACKWARD COMPATIBILITY: Ignore unknown event types instead of throwing
        // This ensures older app versions don't crash when backend adds new events
        print("SSE: Unknown event type '\(event)' - ignoring for forward compatibility")
        throw SSEError.invalidEventFormat  // Will be caught and logged by caller
    }
}
```

**Also update the terminal-event check in `streamEvents()`** (around line 262) to include new non-terminal cases:

```swift
// In TalariaService.streamEvents(), update the switch after continuation.yield:
switch sseEvent {
case .complete:
    print("SSE: Complete event received - finishing stream")
    continuation.finish()
    return
case .error(let message):
    print("SSE: Error event received: \(message)")
    continuation.finish()
    return
case .canceled:
    print("SSE: Canceled event received")
    continuation.finish()
    return
case .progress, .result, .segmented, .bookProgress:
    // Continue processing stream
    break
}
```

**Changes to CameraViewModel.swift -- SSE switch statement (line 313):**

Add handling for new event types in the `for try await event in eventStream` switch:

```swift
for try await event in eventStream {
    // Check for task cancellation (app backgrounding)
    if Task.isCancelled {
        print("SSE stream cancelled (app backgrounding)")
        await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService, authToken: authToken)
        return
    }

    switch event {
    case .progress(let message):
        print("SSE progress: \(message)")
        updateQueueItemProgress(id: item.id, message: message)

    case .result(let bookMetadata):
        print("Book identified: \(bookMetadata.title) by \(bookMetadata.author)")
        let rawJSON: String?
        if let jsonData = try? JSONEncoder().encode(bookMetadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            rawJSON = jsonString
        } else {
            rawJSON = nil
        }
        handleBookResult(metadata: bookMetadata, rawJSON: rawJSON, modelContext: modelContext)

    case .complete:
        let streamDuration = CFAbsoluteTimeGetCurrent() - streamStart
        print("SSE stream lasted \(String(format: "%.1f", streamDuration))s")
        updateQueueItem(id: item.id, state: .done, message: nil)
        await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService, authToken: authToken)
        if let jid = jobId { jobAuthTokens.removeValue(forKey: jid) }
        await removeQueueItemAfterDelay(id: item.id, delay: 5.0)

    case .error(let errorMessage):
        print("SSE error (jobId: \(jobId ?? "unknown")): \(errorMessage)")
        updateQueueItemError(id: item.id, errorMessage: errorMessage)
        await showProcessingErrorOverlay(errorMessage)
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService, authToken: authToken)
        if let jid = jobId { jobAuthTokens.removeValue(forKey: jid) }

    case .canceled:
        print("SSE job canceled (jobId: \(jobId ?? "unknown"))")
        updateQueueItem(id: item.id, state: .error, message: "Canceled")
        await performCleanup(jobId: jobId, tempFileURL: tempFileURL, talariaService: talariaService, authToken: authToken)
        if let jid = jobId { jobAuthTokens.removeValue(forKey: jid) }
        await removeQueueItemAfterDelay(id: item.id, delay: 3.0)

    // NEW: Progressive results event handling
    case .segmented(let preview):
        print("Segmented preview: \(preview.totalBooks) books detected (\(preview.imageData.count) bytes)")
        updateQueueItemSegmented(id: item.id, preview: preview)

    case .bookProgress(let progress):
        print("Book progress: \(progress.current)/\(progress.total)")
        updateQueueItemProgress(id: item.id, message: "Processing book \(progress.current)/\(progress.total)")
    }
}
```

**Also add the helper method `updateQueueItemSegmented` to CameraViewModel:**

```swift
private func updateQueueItemSegmented(id: UUID, preview: SegmentedPreview) {
    if let index = processingQueue.firstIndex(where: { $0.id == id }) {
        withAnimation(.swissSpring) {
            processingQueue[index].segmentedPreview = preview.imageData
            processingQueue[index].detectedBookCount = preview.totalBooks
        }
    }
}
```

**Acceptance Criteria:**
- [ ] New SSEEvent cases compile with Sendable conformance
- [ ] SegmentedPreview and BookProgressInfo conform to Codable
- [ ] Parser handles "segmented" and "book_progress" events correctly
- [ ] Unknown event types are gracefully logged and ignored (no crash)
- [ ] Existing SSE event handling (progress, result, complete, error, canceled) unchanged
- [ ] Base64 image decoding works for segmented preview
- [ ] CameraViewModel switch statement is exhaustive (handles .segmented and .bookProgress)
- [ ] TalariaService terminal-event switch is exhaustive (handles .segmented and .bookProgress as non-terminal)
- [ ] Build: 0 errors, 0 warnings

---

### Task 6: Progressive Results - UI Components

**Priority:** NICE-TO-HAVE (HIGH VALUE)
**Effort:** 3 hours
**New File:** `/Users/juju/dev_repos/swiftwing/swiftwing/SegmentedPreviewOverlay.swift`
**Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraView.swift`
**Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`
**Modify:** `/Users/juju/dev_repos/swiftwing/swiftwing/ProcessingItem.swift`

**Description:**
Create UI components that show progressive scan results: a segmented image preview overlay that appears when the backend sends a detection preview, and a per-book progress counter. These components integrate into the existing CameraView overlay stack.

**New File: SegmentedPreviewOverlay.swift**

```swift
// /Users/juju/dev_repos/swiftwing/swiftwing/SegmentedPreviewOverlay.swift

import SwiftUI

/// Shows the segmented image preview with detected book regions highlighted
/// Appears as a semi-transparent overlay on the camera view after initial detection
struct SegmentedPreviewOverlay: View {
    let imageData: Data
    let totalBooks: Int
    let currentBook: Int
    let totalProcessed: Int

    var body: some View {
        VStack(spacing: 16) {
            // Segmented image with bounding boxes
            if let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.internationalOrange.opacity(0.5), lineWidth: 2)
                    )
                    .frame(maxHeight: 200)
            }

            // Book count badge
            HStack(spacing: 8) {
                Image(systemName: "books.vertical")
                    .font(.body)
                Text("\(totalBooks) books detected")
                    .font(.body.bold())
            }
            .foregroundColor(.swissText)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .swissGlassOverlay()

            // Progress bar (if processing has started)
            if totalProcessed > 0 {
                VStack(spacing: 8) {
                    ProgressView(value: Double(totalProcessed), total: Double(totalBooks))
                        .progressViewStyle(.linear)
                        .tint(.internationalOrange)
                        .frame(width: 200)

                    Text("Processing book \(currentBook)/\(totalBooks)")
                        .font(.caption)
                        .foregroundColor(.swissText.opacity(0.8))
                }
            }
        }
        .padding(24)
        .swissGlassCard()
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
```

**Changes to ProcessingItem.swift:**

Add segmented preview data:

```swift
struct ProcessingItem: Identifiable, Equatable {
    // ... existing properties ...

    // Progressive results state
    var segmentedPreview: Data?         // NEW: Annotated image from backend
    var detectedBookCount: Int?         // NEW: Total books found in image
    var currentBookIndex: Int?          // NEW: Which book is being processed

    static func == (lhs: ProcessingItem, rhs: ProcessingItem) -> Bool {
        lhs.id == rhs.id  // Keep identity-based equality
    }
}
```

**Changes to CameraViewModel.swift:**

Add helper method for book progress updates (in addition to `updateQueueItemSegmented` from Task 5):

```swift
private func updateQueueItemBookProgress(id: UUID, current: Int, total: Int) {
    if let index = processingQueue.firstIndex(where: { $0.id == id }) {
        withAnimation(.swissSpring) {
            processingQueue[index].currentBookIndex = current
            processingQueue[index].progressMessage = "Processing book \(current)/\(total)"
        }
    }
}
```

**Changes to CameraView.swift:**

Add segmented preview overlay in the ZStack (after processing error overlay):

```swift
// Segmented preview overlay (shows when processing item has preview data)
if let activeItem = viewModel.processingQueue.first(where: { $0.segmentedPreview != nil && $0.state == .analyzing }),
   let previewData = activeItem.segmentedPreview {
    SegmentedPreviewOverlay(
        imageData: previewData,
        totalBooks: activeItem.detectedBookCount ?? 0,
        currentBook: activeItem.currentBookIndex ?? 0,
        totalProcessed: activeItem.currentBookIndex ?? 0
    )
    .padding(.horizontal, 32)
    .padding(.bottom, 160) // Above shutter button
    .transition(.opacity.combined(with: .scale(scale: 0.95)))
}
```

**Memory Management:**
The segmented preview image (Data) is stored in ProcessingItem, which is in-memory. For a typical annotated image (~200KB JPEG), holding 1-2 previews is fine. Clear the data when the item transitions to `.done`:

```swift
// In updateQueueItem when transitioning to .done:
processingQueue[index].segmentedPreview = nil  // Release memory
```

**Acceptance Criteria:**
- [ ] SegmentedPreviewOverlay renders correctly with test image data
- [ ] Overlay appears when a processing item receives segmented preview
- [ ] Progress bar shows accurate book processing count
- [ ] Overlay disappears when processing completes
- [ ] Memory is released when preview data is cleared
- [ ] Graceful degradation: no overlay shown if backend doesn't send segmented events
- [ ] Swiss Glass design system applied correctly
- [ ] Build: 0 errors, 0 warnings

---

### Task 7: Integration Testing and Verification

**Priority:** REQUIRED
**Effort:** 1.5 hours
**No file changes** -- verification only

**Description:**
Verify all 4 features work correctly together and with existing functionality. Run build verification, test each feature individually, and verify no regressions.

**Verification Steps:**

1. **Build Verification:**
```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' clean build 2>&1 | xcsift
```
Expected: 0 errors, 0 warnings

2. **Preprocessing Verification:**
   - Capture a photo in simulator
   - Verify console logs show preprocessing time < 500ms
   - Verify "Preprocessing..." message appears briefly in processing queue

3. **SSE Disconnection Verification:**
   - Start a scan (capture and upload)
   - While scan is in progress, switch to Library tab
   - Verify console shows "Backend cleanup sent for disconnected job: [jobId]"
   - Verify processing queue is cleared

4. **Review Queue Verification:**
   - Scan multiple books (or use test data with varying confidence)
   - Open Review tab
   - Verify books are sorted by confidence (low first)
   - Verify section headers show correct counts
   - Verify confidence badges show correct colors
   - Test inline editing of title/author
   - Approve an edited book and verify library has edited values (resolvedTitle/resolvedAuthor)
   - Approve All with some edited books and verify all edits persisted

5. **Progressive Results Verification (Backend-Dependent):**
   - If Talaria sends segmented events: verify overlay appears with book count
   - If Talaria does NOT send segmented events: verify no overlay appears (graceful degradation)
   - Verify unknown SSE event types are logged but don't crash

6. **Regression Testing:**
   - Full scan flow: capture -> preprocess -> upload -> stream -> result -> approve -> library
   - Offline queue: disable network, capture, re-enable network, verify upload
   - Rate limiting: trigger rate limit, verify countdown and retry
   - Duplicate detection: scan same book twice, verify alert
   - Bulk approve: scan multiple books, approve all
   - Verify `addBookToLibrary(metadata:rawJSON:modelContext:)` still works for non-review-queue callers

**Acceptance Criteria:**
- [ ] Build: 0 errors, 0 warnings
- [ ] All 4 features work independently
- [ ] All 4 features work together in a full scan flow
- [ ] No regressions in existing functionality
- [ ] Console logs show expected behavior at each stage

---

## Commit Strategy

**Recommended commit sequence (one per task):**

1. `feat: Add ImagePreprocessor actor with CIFilter pipeline`
   - Files: ImagePreprocessor.swift (new)
   - Scope: New file only, no integration

2. `feat: Integrate image preprocessing into capture pipeline`
   - Files: CameraViewModel.swift, ProcessingItem.swift
   - Scope: Pipeline integration

3. `fix: Add SSE disconnection detection with backend cleanup`
   - Files: CameraViewModel.swift, CameraView.swift
   - Scope: Lifecycle management, jobAuthTokens map

4. `feat: Enhance review queue with confidence-based sorting and editing`
   - Files: ReviewQueueView.swift, PendingBookResult.swift, CameraViewModel.swift
   - Scope: Review queue UX, approveBook/approveAllBooks with resolved values

5. `feat: Add progressive results SSE types, parsing, and CameraViewModel handling`
   - Files: NetworkTypes.swift, TalariaService.swift, CameraViewModel.swift
   - Scope: Protocol extension + exhaustive switch handling

6. `feat: Add segmented preview overlay and progressive results UI`
   - Files: SegmentedPreviewOverlay.swift (new), CameraView.swift, CameraViewModel.swift, ProcessingItem.swift
   - Scope: Progressive UI

---

## Risk Matrix

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| CIFilter processing exceeds 500ms target | Medium | Medium | Profile with Instruments; reduce filter quality; skip denoising if slow |
| Memory pressure from segmented preview images | Low | Medium | Clear Data when item completes; limit to 1 active preview |
| SSE cleanup call fails (network lost) | Medium | Low | Fire-and-forget cleanup; backend has its own timeout cleanup |
| Review queue edit state conflicts with approve | Low | Medium | Clear edit state on approve; use resolved values consistently |
| Backend doesn't send new SSE event types | Expected | None | Graceful degradation by design; progressive UI only shows when events arrive |
| Rotation detection false positives (non-book tall images) | Low | Low | Only rotate if aspect ratio > 2.0 (conservative threshold) |
| Swift 6.2 concurrency warnings from actor boundaries | Medium | High | Test each task independently; fix warnings before proceeding |
| ProcessingItem Equatable breaks with new mutable fields | Medium | Medium | Keep identity-based equality (id only); don't compare mutable state |
| onDisappear fires in TabView when switching tabs | Expected | None | Intentional: cancel streams when leaving camera tab; fresh state on return |

---

## Success Criteria

| Metric | Target | Measurement |
|--------|--------|-------------|
| Image preprocessing time | < 500ms | Console log in ImagePreprocessor |
| Build result | 0 errors, 0 warnings | xcodebuild ... \| xcsift |
| Recognition accuracy improvement | 15-30% (requires A/B test) | Compare scan success rate before/after |
| Perceived latency reduction | 40% (subjective) | User testing with progressive results |
| SSE cleanup reliability | 100% on navigation away | Console log verification |
| Review queue confidence sort | Low-confidence always on top | Visual verification |
| Memory overhead (segmented preview) | < 1MB per active item | Instruments profiling |
| Regression count | 0 | Full regression test suite |

---

## File Change Summary

### New Files (2)
| File | Purpose |
|------|---------|
| `/Users/juju/dev_repos/swiftwing/swiftwing/Services/ImagePreprocessor.swift` | Actor-isolated CIFilter preprocessing pipeline |
| `/Users/juju/dev_repos/swiftwing/swiftwing/SegmentedPreviewOverlay.swift` | SwiftUI view for segmented image preview |

### Modified Files (7)
| File | Tasks | Changes |
|------|-------|---------|
| `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift` | 2, 3, 4, 5, 6 | Add preprocessing call, jobAuthTokens map, SSE disconnect cleanup, approveBook/approveAllBooks with resolved values, addBookToLibrary with title/author overrides, updatePendingBookEdits, progressive state handlers, exhaustive SSE switch |
| `/Users/juju/dev_repos/swiftwing/swiftwing/CameraView.swift` | 3, 6 | Add onDisappear cleanup, segmented preview overlay |
| `/Users/juju/dev_repos/swiftwing/swiftwing/Services/TalariaService.swift` | 5 | Parse new SSE event types (segmented, book_progress), graceful unknown handling, exhaustive terminal-event switch |
| `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift` | 5 | Add SSEEvent.segmented, .bookProgress cases + SegmentedPreview, BookProgressInfo structs |
| `/Users/juju/dev_repos/swiftwing/swiftwing/ReviewQueueView.swift` | 4 | Confidence sorting, section headers, confidence badges, inline editing with edit callback |
| `/Users/juju/dev_repos/swiftwing/swiftwing/Models/PendingBookResult.swift` | 4 | Add editedTitle, editedAuthor, resolvedTitle, resolvedAuthor |
| `/Users/juju/dev_repos/swiftwing/swiftwing/ProcessingItem.swift` | 2, 6 | Add .preprocessing state, segmentedPreview/detectedBookCount/currentBookIndex fields |

### Xcode Project
| File | Changes |
|------|---------|
| `/Users/juju/dev_repos/swiftwing/swiftwing.xcodeproj/project.pbxproj` | Add 2 new Swift files to build target |

---

## Estimated Total Effort

| Task | Effort |
|------|--------|
| Task 1: ImagePreprocessor Actor | 2.0h |
| Task 2: Pipeline Integration | 1.5h |
| Task 3: SSE Disconnection | 2.0h |
| Task 4: Review Queue Enhancement | 3.0h |
| Task 5: Progressive Results Types + CameraViewModel | 2.5h |
| Task 6: Progressive Results UI | 3.0h |
| Task 7: Integration Testing | 1.5h |
| **Total** | **15.5h** |

---

## Notes for Executor Agents

- **Build command:** Always use `xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift`
- **New files must be added to Xcode project** via project.pbxproj modification
- **Swift 6.2 strict concurrency is enabled** -- all new actors must be properly isolated
- **@MainActor CameraViewModel** -- any method called from non-MainActor context needs `await`
- **ImagePreprocessor is NOT @MainActor** -- it's a standalone actor for CPU-bound work
- **Do NOT use Task.detached** -- breaks actor isolation per project rules
- **Swiss Glass design system** -- use `.swissGlassCard()`, `.swissGlassOverlay()`, `.swissSpring` animation
- **ProcessingItem equality** -- uses identity-based (id only), not property-based comparison
- **New structs (SegmentedPreview, BookProgressInfo, PreprocessingResult) must be Codable** for consistency with existing NetworkTypes patterns
- **Task 5 MUST update CameraViewModel** -- adding SSE cases without updating the switch will break the build
- **`addBookToLibrary` signature change** uses default parameters so existing callers are not broken
