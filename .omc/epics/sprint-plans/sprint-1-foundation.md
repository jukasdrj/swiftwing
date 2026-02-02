# Sprint 1: Foundation & Multi-Book Core

**Sprint Duration:** 2 weeks (Weeks 1-2)
**Theme:** Enable shelf scanning with segmentation + Review tab basics
**Parallel Tracks:** 3 concurrent work streams

---

## Sprint Goal

By end of Sprint 1, users can:
1. Take a photo of a bookshelf
2. See visual feedback that photo was captured
3. See "Processing X books..." progress indicator
4. Navigate to Review tab to see processing items
5. Tap any item to view processing status

**Demo Scenario:**
```
User opens camera → Points at bookshelf with 5 books → Taps shutter
  → Sees "✓ Photo captured" animation
  → Sees "Processing 5 books..." spinner
  → Taps "Review" tab
  → Sees 5 items in list (all showing "Processing...")
  → Waits 2 seconds
  → Items update to "Ready" state (with placeholder data for now)
```

---

## Track A: Instance Segmentation Service

### US-A1: Create InstanceSegmentationService Actor
**Priority:** P0 (Critical path)
**Story Points:** 8
**Owner:** TBD

**As a** developer
**I want** an actor-isolated service that segments bookshelf photos into individual books
**So that** we can process each book spine independently

**Acceptance Criteria:**
- [ ] Create `Services/InstanceSegmentationService.swift` with actor isolation
- [ ] Implement `segmentBooks(from: CIImage) async throws -> [SegmentedBook]`
- [ ] Use `GenerateForegroundInstanceMaskRequest` from Vision framework
- [ ] Return array of `SegmentedBook` with cropped images and bounding boxes
- [ ] Handle 1-20 books per photo (typical shelf range)
- [ ] Performance: <2 seconds for 10-book shelf
- [ ] Skip background instance (index 0)
- [ ] Generate tight crops around each book spine

**Technical Notes:**
```swift
actor InstanceSegmentationService {
    func segmentBooks(from image: CIImage) async throws -> [SegmentedBook] {
        let request = GenerateForegroundInstanceMaskRequest()
        let observations = try await request.perform(on: image)

        guard let observation = observations.first else {
            throw SegmentationError.noInstancesFound
        }

        var books: [SegmentedBook] = []
        let handler = VNImageRequestHandler(ciImage: image)

        for instanceID in observation.allInstances where instanceID > 0 {
            let singleInstance = IndexSet(integer: instanceID)

            let croppedBuffer = try observation.generateMaskedImage(
                ofInstances: singleInstance,
                from: handler,
                croppedToInstancesExtent: true
            )

            books.append(SegmentedBook(
                instanceID: instanceID,
                croppedImage: CIImage(cvPixelBuffer: croppedBuffer),
                boundingBox: calculateBounds(from: croppedBuffer)
            ))
        }

        return books
    }

    private func calculateBounds(from buffer: CVPixelBuffer) -> CGRect {
        // Implementation: scan pixel buffer for non-zero mask values
        // Return normalized CGRect (0-1 range)
    }
}
```

**Definition of Done:**
- [ ] Code reviewed and approved
- [ ] Unit tests cover 1, 5, 10, 20 book scenarios
- [ ] Edge case tests (0 books, overlapping books)
- [ ] Performance benchmarked with Instruments
- [ ] Documentation comments added

---

### US-A2: Create SegmentedBook Model
**Priority:** P0
**Story Points:** 3
**Owner:** TBD

**As a** developer
**I want** a model representing a segmented book instance
**So that** I can track each book through the processing pipeline

**Acceptance Criteria:**
- [ ] Create `Models/SegmentedBook.swift`
- [ ] Properties: `instanceID`, `croppedImage`, `boundingBox`, `timestamp`
- [ ] Conform to `Identifiable` (use `instanceID` as `id`)
- [ ] Conform to `Sendable` for Swift 6.2 concurrency
- [ ] Add computed property for image size
- [ ] Include creation timestamp for debugging

**Technical Notes:**
```swift
struct SegmentedBook: Identifiable, Sendable {
    let id: Int  // Instance ID from Vision
    let instanceID: Int
    let croppedImage: CIImage
    let boundingBox: CGRect  // Normalized coordinates
    let timestamp: Date

    var imageSize: CGSize {
        croppedImage.extent.size
    }

    init(instanceID: Int, croppedImage: CIImage, boundingBox: CGRect) {
        self.id = instanceID
        self.instanceID = instanceID
        self.croppedImage = croppedImage
        self.boundingBox = boundingBox
        self.timestamp = Date()
    }
}
```

**Definition of Done:**
- [ ] Model compiles with Swift 6.2 strict concurrency
- [ ] Unit tests verify property access
- [ ] Documentation added

---

### US-A3: Integrate Segmentation into CameraViewModel
**Priority:** P0
**Story Points:** 5
**Owner:** TBD

**As a** user
**I want** the camera to automatically detect multiple books when I take a photo
**So that** I don't have to scan each book individually

**Acceptance Criteria:**
- [ ] Add `segmentationService: InstanceSegmentationService` property
- [ ] Modify `capturePhoto()` to call segmentation after capture
- [ ] Create separate `ProcessingItem` for each segmented book
- [ ] Update `@Published var processingItems: [ProcessingItem]` array
- [ ] Add count to processing feedback ("Processing 5 books...")
- [ ] Handle segmentation errors gracefully (fallback to single-book mode)
- [ ] Feature flag: `enableMultiBookScanning` (default: false)

**Technical Notes:**
```swift
// In CameraViewModel.swift
@MainActor
@Observable
class CameraViewModel {
    private let segmentationService = InstanceSegmentationService()
    var processingItems: [ProcessingItem] = []
    var isSegmenting = false

    func capturePhoto() async {
        guard let image = await cameraManager.capturePhoto() else { return }

        // Feature flag check
        if UserDefaults.standard.enableMultiBookScanning {
            await processMultiBook(image)
        } else {
            await processSingleBook(image)
        }
    }

    private func processMultiBook(_ image: UIImage) async {
        isSegmenting = true
        defer { isSegmenting = false }

        do {
            let ciImage = CIImage(cgImage: image.cgImage!)
            let books = try await segmentationService.segmentBooks(from: ciImage)

            // Create ProcessingItem for each book
            for book in books {
                let item = ProcessingItem(
                    id: UUID(),
                    image: convertToUIImage(book.croppedImage),
                    status: .processing,
                    segmentID: book.instanceID
                )
                processingItems.append(item)
            }

        } catch {
            print("Segmentation failed: \(error)")
            // Fallback to single-book mode
            await processSingleBook(image)
        }
    }
}
```

**Definition of Done:**
- [ ] Multi-book workflow tested with 1, 5, 10 book shelves
- [ ] Single-book fallback works when segmentation fails
- [ ] Feature flag toggle works correctly
- [ ] Code reviewed

---

## Track B: Review Tab UI Foundation

### US-B1: Create ProcessingFeedbackView Component
**Priority:** P0
**Story Points:** 5
**Owner:** TBD

**As a** user
**I want** visual feedback when I take a photo
**So that** I know the app is processing my books

**Acceptance Criteria:**
- [ ] Create `Features/Camera/ProcessingFeedbackView.swift`
- [ ] Show checkmark animation on photo capture ("✓ Photo captured")
- [ ] Display count-based progress ("Processing 5 books...")
- [ ] Show spinner/progress indicator
- [ ] Auto-dismiss after 2 seconds (or when processing completes)
- [ ] Swiss Glass design system styling
- [ ] Accessible with VoiceOver support

**Technical Notes:**
```swift
struct ProcessingFeedbackView: View {
    let bookCount: Int
    let isProcessing: Bool
    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            VStack(spacing: 16) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.internationalOrange)

                    Text("Processing \(bookCount) book\(bookCount == 1 ? "" : "s")...")
                        .font(.headline)
                        .foregroundColor(.swissText)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                        .symbolEffect(.bounce)

                    Text("Photo captured")
                        .font(.headline)
                        .foregroundColor(.swissText)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(duration: 0.3), value: isProcessing)
        }
    }
}
```

**Definition of Done:**
- [ ] Component renders correctly in camera view
- [ ] Animations smooth at 60 FPS
- [ ] Auto-dismiss timing works
- [ ] VoiceOver announces status
- [ ] Code reviewed

---

### US-B2: Add Processing Feedback to CameraView
**Priority:** P0
**Story Points:** 3
**Owner:** TBD

**As a** user
**I want** to see capture confirmation immediately after taking a photo
**So that** I know the app received my input

**Acceptance Criteria:**
- [ ] Add `ProcessingFeedbackView` overlay to `CameraView`
- [ ] Show feedback when `capturePhoto()` is called
- [ ] Pass book count from `processingItems.count`
- [ ] Auto-hide after 2 seconds
- [ ] Position above shutter button (not blocking camera preview)
- [ ] Z-index above camera controls

**Technical Notes:**
```swift
// In CameraView.swift
struct CameraView: View {
    @State private var showProcessingFeedback = false
    @State private var processingBookCount = 0

    var body: some View {
        ZStack {
            // Camera preview...

            // Processing feedback overlay
            if showProcessingFeedback {
                ProcessingFeedbackView(
                    bookCount: processingBookCount,
                    isProcessing: viewModel.isSegmenting,
                    isVisible: $showProcessingFeedback
                )
                .position(x: geometry.size.width / 2, y: 200)
            }

            // Shutter button
            Button("Capture") {
                Task {
                    await viewModel.capturePhoto()
                    processingBookCount = viewModel.processingItems.count
                    showProcessingFeedback = true

                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    showProcessingFeedback = false
                }
            }
        }
    }
}
```

**Definition of Done:**
- [ ] Feedback appears immediately on capture
- [ ] Count updates correctly
- [ ] Auto-hide works
- [ ] No UI blocking during processing
- [ ] Code reviewed

---

### US-B3: Enhance ReviewQueueView with Processing States
**Priority:** P0
**Story Points:** 5
**Owner:** TBD

**As a** user
**I want** to see all my processing books in the Review tab
**So that** I can track progress and edit results

**Acceptance Criteria:**
- [ ] Modify `Features/Review/ReviewQueueView.swift`
- [ ] Show `ProcessingItem.status` enum visually
- [ ] Display processing spinner for `.processing` state
- [ ] Show checkmark for `.ready` state
- [ ] Show error icon for `.failed` state
- [ ] List items chronologically (newest first)
- [ ] Tap item to view details (placeholder for Sprint 2)
- [ ] Pull-to-refresh to update states

**Technical Notes:**
```swift
// In ReviewQueueView.swift
struct ReviewQueueView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var processingItems: [ProcessingItem] = []

    var body: some View {
        NavigationStack {
            List(processingItems) { item in
                ProcessingItemRow(item: item)
                    .onTapGesture {
                        // Navigate to detail (Sprint 2)
                        selectedItem = item
                    }
            }
            .refreshable {
                await refreshProcessingItems()
            }
            .navigationTitle("Review")
        }
    }
}

struct ProcessingItemRow: View {
    let item: ProcessingItem

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Image(uiImage: item.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.extractedTitle ?? "Processing...")
                    .font(.headline)
                    .foregroundColor(.swissText)

                Text(statusDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            statusIcon
        }
        .padding(.vertical, 4)
    }

    var statusIcon: some View {
        switch item.status {
        case .processing:
            return AnyView(ProgressView().tint(.internationalOrange))
        case .ready:
            return AnyView(Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green))
        case .failed:
            return AnyView(Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red))
        }
    }

    var statusDescription: String {
        switch item.status {
        case .processing: return "Processing..."
        case .ready: return "Ready for review"
        case .failed: return "Processing failed"
        }
    }
}
```

**Definition of Done:**
- [ ] List displays all processing items
- [ ] Status icons render correctly
- [ ] Tap navigation works (even if detail view is placeholder)
- [ ] Pull-to-refresh works
- [ ] Code reviewed

---

## Track C: Processing Pipeline Infrastructure

### US-C1: Extend ProcessingItem Model
**Priority:** P0
**Story Points:** 3
**Owner:** TBD

**As a** developer
**I want** ProcessingItem to track multi-book metadata
**So that** we can manage individual book processing states

**Acceptance Criteria:**
- [ ] Add `segmentID: Int?` property (instance ID from segmentation)
- [ ] Add `extractedTitle: String?` property (placeholder for Sprint 2)
- [ ] Add `extractedAuthor: String?` property (placeholder for Sprint 2)
- [ ] Add `confidence: Float?` property (extraction confidence)
- [ ] Update `status` enum: `.processing`, `.ready`, `.failed`, `.enriching`
- [ ] Add `lastUpdated: Date` property
- [ ] Ensure SwiftData compatibility

**Technical Notes:**
```swift
// In Models/ProcessingItem.swift
import SwiftData

@Model
final class ProcessingItem {
    @Attribute(.unique) var id: UUID
    var image: Data  // Stored as JPEG data
    var status: ProcessingStatus
    var segmentID: Int?  // NEW: Instance ID from segmentation
    var extractedTitle: String?  // NEW: For Sprint 2
    var extractedAuthor: String?  // NEW: For Sprint 2
    var confidence: Float?  // NEW: Extraction confidence (0-1)
    var lastUpdated: Date  // NEW: Track updates
    var createdAt: Date

    enum ProcessingStatus: String, Codable {
        case processing
        case ready
        case failed
        case enriching  // NEW: Background Talaria enrichment
    }

    init(id: UUID = UUID(), image: UIImage, status: ProcessingStatus, segmentID: Int? = nil) {
        self.id = id
        self.image = image.jpegData(compressionQuality: 0.8)!
        self.status = status
        self.segmentID = segmentID
        self.createdAt = Date()
        self.lastUpdated = Date()
    }
}
```

**Definition of Done:**
- [ ] Model compiles with SwiftData
- [ ] Migration path from old schema works
- [ ] Properties accessible in SwiftUI
- [ ] Code reviewed

---

### US-C2: Add Feature Flags Configuration
**Priority:** P1
**Story Points:** 2
**Owner:** TBD

**As a** developer
**I want** feature flags to control new functionality
**So that** we can enable features incrementally and rollback if needed

**Acceptance Criteria:**
- [ ] Add `UserDefaults` extension for feature flags
- [ ] Flag: `enableMultiBookScanning` (default: false)
- [ ] Flag: `useOnDeviceExtraction` (default: false, Sprint 2)
- [ ] Flag: `useTalariaTextEnrichment` (default: false, Sprint 3)
- [ ] Flag: `trackExtractionAccuracy` (default: true, Sprint 4)
- [ ] Add debug menu to toggle flags (Settings tab or shake gesture)

**Technical Notes:**
```swift
// In Extensions/UserDefaults+FeatureFlags.swift
extension UserDefaults {
    @objc dynamic var enableMultiBookScanning: Bool {
        get { bool(forKey: "EnableMultiBookScanning") }
        set { set(newValue, forKey: "EnableMultiBookScanning") }
    }

    @objc dynamic var useOnDeviceExtraction: Bool {
        get { bool(forKey: "UseOnDeviceExtraction") }
        set { set(newValue, forKey: "UseOnDeviceExtraction") }
    }

    // ... other flags
}

// Debug menu view
struct FeatureFlagsDebugView: View {
    @AppStorage("EnableMultiBookScanning")
    private var multiBook = false

    var body: some View {
        List {
            Toggle("Multi-Book Scanning", isOn: $multiBook)
            // ... other toggles
        }
        .navigationTitle("Feature Flags")
    }
}
```

**Definition of Done:**
- [ ] All flags accessible via UserDefaults
- [ ] Debug menu works
- [ ] Flags persist across app launches
- [ ] Code reviewed

---

### US-C3: Create Unit Test Suite for Segmentation
**Priority:** P1
**Story Points:** 5
**Owner:** TBD

**As a** developer
**I want** comprehensive tests for instance segmentation
**So that** we catch regressions early

**Acceptance Criteria:**
- [ ] Create `Tests/InstanceSegmentationTests.swift`
- [ ] Test: Single book detection
- [ ] Test: 5 book shelf detection
- [ ] Test: 10 book shelf detection
- [ ] Test: 20 book maximum detection
- [ ] Test: No books detected (empty shelf) → error thrown
- [ ] Test: Overlapping books → correct count
- [ ] Test: Performance <2s for 10 books
- [ ] Mock images for consistent testing

**Technical Notes:**
```swift
import XCTest
@testable import swiftwing

final class InstanceSegmentationTests: XCTestCase {
    var service: InstanceSegmentationService!

    override func setUp() async throws {
        service = InstanceSegmentationService()
    }

    func testSingleBookDetection() async throws {
        let testImage = loadTestImage("single-book-shelf.jpg")
        let books = try await service.segmentBooks(from: testImage)

        XCTAssertEqual(books.count, 1)
        XCTAssertGreaterThan(books[0].imageSize.width, 0)
    }

    func testFiveBookShelfDetection() async throws {
        let testImage = loadTestImage("five-book-shelf.jpg")
        let books = try await service.segmentBooks(from: testImage)

        XCTAssertEqual(books.count, 5)

        // Verify each book has valid data
        for book in books {
            XCTAssertGreaterThan(book.boundingBox.width, 0)
            XCTAssertGreaterThan(book.boundingBox.height, 0)
        }
    }

    func testPerformanceWithTenBooks() throws {
        let testImage = loadTestImage("ten-book-shelf.jpg")

        measure {
            _ = try? await service.segmentBooks(from: testImage)
        }

        // Should complete in <2 seconds
    }
}
```

**Definition of Done:**
- [ ] All tests pass on iOS 26 simulator
- [ ] Tests run in CI/CD pipeline
- [ ] Code coverage >80% for segmentation service
- [ ] Code reviewed

---

## Sprint 1 Demo Script

**Setup:**
- iPhone 17 Pro Max simulator (iOS 26)
- Multi-book feature flag enabled
- Test shelf image ready (5 books)

**Demo Flow:**

1. **Launch app** → Camera tab visible

2. **Position camera** → Point at bookshelf image (or use test photo)

3. **Tap shutter button**
   - ✅ See "✓ Photo captured" animation
   - ✅ See "Processing 5 books..." progress spinner

4. **Wait 2 seconds** → Feedback auto-dismisses

5. **Tap "Review" tab**
   - ✅ See 5 items in list
   - ✅ Each shows thumbnail of book spine
   - ✅ Each shows "Processing..." status

6. **Wait another 2 seconds** (simulated processing)
   - ✅ Items update to "Ready for review" status
   - ✅ Checkmark icons appear

7. **Tap any item**
   - ✅ Navigation occurs (even if detail view is placeholder)

**Success Criteria:**
- Zero crashes
- All 5 books detected
- Review tab updates in real-time
- UI stays responsive during processing

---

## Sprint 1 Acceptance Criteria

**Must Have (P0):**
- [x] InstanceSegmentationService detects 1-20 books
- [x] ProcessingFeedbackView shows capture confirmation
- [x] ReviewQueueView displays processing items
- [x] Multi-book feature flag works
- [x] Unit tests pass

**Should Have (P1):**
- [x] Feature flags debug menu
- [x] Performance <2s for 10-book shelf
- [x] Pull-to-refresh in Review tab

**Nice to Have (P2):**
- [ ] Empty state for Review tab
- [ ] Accessibility improvements
- [ ] Haptic feedback on capture

---

## Sprint 1 Risks

| Risk | Mitigation |
|------|------------|
| Segmentation accuracy <80% | Use test images first, validate with real books in Sprint 2 |
| Performance >2s for 10 books | Profile with Instruments, optimize in Sprint 4 if needed |
| Swift 6.2 concurrency issues | Strict actor isolation, leverage existing patterns |

---

## Sprint 1 Dependencies

**Blockers:**
- None (all work can start immediately)

**Parallel Work:**
- Tracks A, B, C can proceed concurrently
- Track A should complete first (foundation for others)

**External:**
- Test device with iOS 26+ (simulator OK for Sprint 1)

---

## Sprint 1 Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Books detected per photo | 1-20 | Unit tests |
| Processing time (10 books) | <2s | Instruments |
| Review tab load time | <0.5s | Manual testing |
| Unit test coverage | >80% | Xcode coverage report |
| Zero crashes | 100% | QA testing |

---

**Sprint 1 Ready for Kickoff:** Yes ✅
**Next Sprint:** Sprint 2 (Vision & Extraction Pipeline)
