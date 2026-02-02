# Sprint 2: Vision & Extraction Pipeline

**Sprint Duration:** 2 weeks (Weeks 3-4)
**Theme:** On-device OCR + AI extraction with detailed review
**Parallel Tracks:** 3 concurrent work streams

---

## Sprint Goal

By end of Sprint 2, users can:
1. See extracted book titles and authors in Review tab
2. Edit incorrect extractions before saving
3. View confidence scores for each extraction
4. Experience <1s per-book processing latency

**Demo Scenario:**
```
User opens Review tab → Sees 5 books from previous scan
  → Each shows extracted title: "The Great Gatsby", "1984", etc.
  → Each shows extracted author: "F. Scott Fitzgerald", "George Orwell"
  → User taps "1984" → Detail view opens
  → User sees confidence: 92% (high)
  → User edits title from "1984" to "Nineteen Eighty-Four"
  → User saves → Book added to library with corrected metadata
```

---

## Track A: RecognizeDocumentsRequest Integration

### US-A1: Upgrade VisionService to RecognizeDocumentsRequest
**Priority:** P0 (Critical path)
**Story Points:** 5
**Owner:** TBD

**As a** developer
**I want** to use iOS 26's RecognizeDocumentsRequest instead of VNRecognizeTextRequest
**So that** we get structured text with better accuracy

**Acceptance Criteria:**
- [ ] Modify `Services/VisionService.swift`
- [ ] Replace `VNRecognizeTextRequest` with `RecognizeDocumentsRequest`
- [ ] Enable language correction: `request.textRecognitionOptions.useLanguageCorrection = true`
- [ ] Support multi-language: `recognitionLanguages = ["en-US", "es-ES"]`
- [ ] Extract paragraphs instead of raw text lines
- [ ] Detect ISBNs via `document.text.detectedData`
- [ ] Return structured `DocumentObservation` type
- [ ] Maintain backward compatibility with feature flag

**Technical Notes:**
```swift
// In VisionService.swift
actor VisionService {
    func recognizeText(in image: CIImage) async throws -> DocumentObservation {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.recognitionLanguages = ["en-US", "es-ES"]

        let observations = try await request.perform(on: image)

        guard let document = observations.first?.document else {
            throw VisionError.noTextFound
        }

        return DocumentObservation(
            fullText: document.text.transcript,
            paragraphs: document.paragraphs.map { para in
                Paragraph(
                    text: para.transcript,
                    confidence: para.confidence,
                    boundingBox: para.boundingRegion.boundingBox.cgRect
                )
            },
            detectedISBNs: extractISBNs(from: document.text.detectedData)
        )
    }

    private func extractISBNs(from detectedData: [DetectedData]) -> [String] {
        detectedData.compactMap { data in
            if case .link(let url) = data.match.details,
               url.absoluteString.contains("isbn") {
                return url.absoluteString
            }
            return nil
        }
    }
}
```

**Definition of Done:**
- [ ] Unit tests compare old vs new API accuracy
- [ ] Performance benchmarked (should be similar or faster)
- [ ] Handles vertical text (common on book spines)
- [ ] Code reviewed

---

### US-A2: Create DocumentObservation Model
**Priority:** P0
**Story Points:** 3
**Owner:** TBD

**As a** developer
**I want** a structured model for OCR results
**So that** we can pass rich text data to extraction service

**Acceptance Criteria:**
- [ ] Create `Services/VisionTypes.swift` if not exists
- [ ] Define `DocumentObservation` struct
- [ ] Define `Paragraph` struct with text, confidence, bounding box
- [ ] Conform to `Sendable` for actor isolation
- [ ] Add convenience properties (word count, character count)

**Technical Notes:**
```swift
struct DocumentObservation: Sendable {
    let fullText: String
    let paragraphs: [Paragraph]
    let detectedISBNs: [String]

    var wordCount: Int {
        fullText.split(separator: " ").count
    }

    var isEmpty: Bool {
        fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct Paragraph: Sendable, Identifiable {
    let id = UUID()
    let text: String
    let confidence: Float  // 0.0 to 1.0
    let boundingBox: CGRect  // Normalized coordinates

    var isHighConfidence: Bool {
        confidence >= 0.9
    }
}
```

**Definition of Done:**
- [ ] Model compiles with Swift 6.2
- [ ] Unit tests verify properties
- [ ] Documentation added

---

### US-A3: Integrate OCR into Processing Pipeline
**Priority:** P0
**Story Points:** 5
**Owner:** TBD

**As a** user
**I want** the app to extract text from each book spine automatically
**So that** I don't have to type titles manually

**Acceptance Criteria:**
- [ ] Modify `CameraViewModel.processMultiBook()`
- [ ] Call `VisionService.recognizeText()` for each `SegmentedBook`
- [ ] Store `DocumentObservation` in `ProcessingItem`
- [ ] Update status from `.processing` to `.extracting` during OCR
- [ ] Handle OCR errors (low confidence, no text found)
- [ ] Performance: <150ms per book spine
- [ ] Log OCR results for debugging

**Technical Notes:**
```swift
// In CameraViewModel.swift
private func processMultiBook(_ image: UIImage) async {
    // ... segmentation code from Sprint 1 ...

    for book in segmentedBooks {
        let item = ProcessingItem(
            id: UUID(),
            image: convertToUIImage(book.croppedImage),
            status: .extracting,
            segmentID: book.instanceID
        )
        processingItems.append(item)

        Task {
            do {
                // OCR each book spine
                let observation = try await visionService.recognizeText(
                    in: book.croppedImage
                )

                // Pass to extraction service (Track B)
                let metadata = try await extractionService.extract(
                    from: observation.fullText
                )

                // Update item
                await updateProcessingItem(item.id, with: metadata)

            } catch {
                await markItemAsFailed(item.id, error: error)
            }
        }
    }
}
```

**Definition of Done:**
- [ ] OCR runs for all segmented books
- [ ] Results stored in ProcessingItem
- [ ] Error handling works (shows `.failed` status)
- [ ] Performance meets <150ms target
- [ ] Code reviewed

---

## Track B: Foundation Models Extraction Service

### US-B1: Create BookExtractionService Actor
**Priority:** P0 (Critical path)
**Story Points:** 8
**Owner:** TBD

**As a** developer
**I want** an on-device AI service to extract structured book metadata
**So that** we can replace costly Gemini Flash API calls

**Acceptance Criteria:**
- [ ] Create `Services/BookExtractionService.swift`
- [ ] Actor-isolated for thread safety
- [ ] Initialize `LanguageModelSession` with book-specific system prompt
- [ ] Implement `extract(from: String) async throws -> BookSpineInfo`
- [ ] Handle 4096 token limit (truncate OCR text if needed)
- [ ] Streaming support for progressive UI updates (optional)
- [ ] Feature flag check: `useOnDeviceExtraction`
- [ ] Fallback to Talaria if Foundation Models unavailable

**Technical Notes:**
```swift
import FoundationModels

actor BookExtractionService {
    private let session: LanguageModelSession

    init() {
        session = LanguageModelSession {
            """
            You are a book metadata extraction specialist. Extract structured information
            from OCR-scanned book spines and covers.

            Common OCR errors to handle:
            - Character confusion: 0/O, 1/l/I, 5/S
            - Split words: "TH E" instead of "THE"
            - Merged words: "TheGreat" instead of "The Great"
            - Vertical text read incorrectly

            Guidelines:
            - Title: The main title of the book, cleaned and corrected
            - Author: Primary author's full name
            - Coauthors: List other authors if visible
            - ISBN: Extract ISBN-10 or ISBN-13 if detected
            - Publisher: Publisher name if visible on spine
            - Confidence: Rate your extraction quality (high/medium/low)

            Always provide your best interpretation even with noisy text.
            Return empty strings for fields you cannot determine.
            """
        }
    }

    func extract(from ocrText: String) async throws -> BookSpineInfo {
        // Check availability
        guard SystemLanguageModel.default.availability == .available else {
            throw ExtractionError.modelUnavailable
        }

        // Truncate if needed (leave ~1000 tokens for output)
        let maxInputLength = 12000  // ~3000 tokens
        let truncatedText = String(ocrText.prefix(maxInputLength))

        let prompt = """
            Extract book metadata from this OCR text:

            \(truncatedText)

            Return empty strings for fields that cannot be determined.
            """

        let response = try await session.respond(
            to: prompt,
            generating: BookSpineInfo.self
        )

        return response.content
    }

    func extractWithStreaming(
        from ocrText: String
    ) -> AsyncThrowingStream<BookSpineInfo, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = session.streamResponse(
                        to: "Extract: \(ocrText)",
                        generating: BookSpineInfo.self
                    )

                    for try await partial in stream {
                        continuation.yield(partial)
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

**Definition of Done:**
- [ ] Extraction works for 10+ test book spines
- [ ] Handles common OCR errors correctly
- [ ] Performance <600ms per extraction
- [ ] Feature flag integration works
- [ ] Unit tests cover edge cases
- [ ] Code reviewed

---

### US-B2: Create BookSpineInfo Model with @Generable
**Priority:** P0
**Story Points:** 3
**Owner:** TBD

**As a** developer
**I want** a Foundation Models-compatible extraction schema
**So that** we get structured output from the LLM

**Acceptance Criteria:**
- [ ] Create `Models/BookSpineInfo.swift`
- [ ] Use `@Generable` macro
- [ ] Use `@Guide` annotations for each field
- [ ] Fields: title, author, coauthors, isbn, publisher, confidence
- [ ] Confidence enum: `.high`, `.medium`, `.low`
- [ ] Conform to `Sendable` and `Codable`

**Technical Notes:**
```swift
import FoundationModels

@Generable
struct BookSpineInfo: Sendable, Codable {
    @Guide(description: "The book's title, cleaned of OCR artifacts and formatting")
    let title: String

    @Guide(description: "Primary author's full name (First Last format)")
    let author: String

    @Guide(description: "Additional authors if present on spine (array of full names)")
    let coauthors: [String]

    @Guide(description: "ISBN-10 or ISBN-13 if found in text (digits only)")
    let isbn: String?

    @Guide(description: "Publisher name if visible on spine")
    let publisher: String?

    @Guide(description: "Extraction quality assessment", .anyOf(["high", "medium", "low"]))
    let confidence: String

    var confidenceLevel: ConfidenceLevel {
        ConfidenceLevel(rawValue: confidence) ?? .low
    }
}

enum ConfidenceLevel: String, Codable {
    case high, medium, low

    var score: Float {
        switch self {
        case .high: return 0.9
        case .medium: return 0.7
        case .low: return 0.5
        }
    }
}
```

**Definition of Done:**
- [ ] Model compiles with FoundationModels framework
- [ ] @Guide annotations clear and helpful
- [ ] Unit tests verify structure
- [ ] Documentation added

---

### US-B3: Add Extraction to Processing Pipeline
**Priority:** P0
**Story Points:** 5
**Owner:** TBD

**As a** user
**I want** to see extracted book metadata appear automatically in Review tab
**So that** I can quickly review and save books

**Acceptance Criteria:**
- [ ] Integrate `BookExtractionService` into `CameraViewModel`
- [ ] Call extraction after OCR completes
- [ ] Store `BookSpineInfo` in `ProcessingItem`
- [ ] Update UI in real-time (reactive with @Observable)
- [ ] Show extraction progress (status: `.extracting`)
- [ ] Handle extraction errors gracefully
- [ ] Log extraction time for analytics

**Technical Notes:**
```swift
// In CameraViewModel.swift
private let extractionService = BookExtractionService()

private func processBookSpine(_ book: SegmentedBook, item: ProcessingItem) async {
    do {
        // Step 1: OCR
        item.status = .extracting
        let observation = try await visionService.recognizeText(in: book.croppedImage)

        // Step 2: Extract metadata
        let startTime = CFAbsoluteTimeGetCurrent()
        let metadata = try await extractionService.extract(from: observation.fullText)
        let extractionTime = CFAbsoluteTimeGetCurrent() - startTime

        // Step 3: Update item
        item.extractedTitle = metadata.title
        item.extractedAuthor = metadata.author
        item.confidence = metadata.confidenceLevel.score
        item.status = .ready
        item.lastUpdated = Date()

        // Log for analytics
        print("Extraction completed in \(extractionTime)s")

    } catch ExtractionError.modelUnavailable {
        // Fallback to Talaria full pipeline
        await fallbackToTalaria(item)

    } catch {
        item.status = .failed
        print("Extraction error: \(error)")
    }
}
```

**Definition of Done:**
- [ ] Extraction runs for all OCR results
- [ ] UI updates immediately when metadata available
- [ ] Fallback to Talaria works when FM unavailable
- [ ] Performance meets <600ms target
- [ ] Code reviewed

---

## Track C: Review Tab Detail View

### US-C1: Create BookDetailSheetView
**Priority:** P0
**Story Points:** 8
**Owner:** TBD

**As a** user
**I want** to view and edit extracted book metadata
**So that** I can correct mistakes before saving to library

**Acceptance Criteria:**
- [ ] Create `Features/Review/BookDetailSheetView.swift`
- [ ] Display book spine thumbnail (large view)
- [ ] Show extracted title (editable TextField)
- [ ] Show extracted author (editable TextField)
- [ ] Show confidence badge (visual indicator)
- [ ] Show ISBN if detected (read-only)
- [ ] "Save to Library" button
- [ ] "Discard" button
- [ ] Keyboard dismissal on tap outside
- [ ] Swiss Glass design system styling

**Technical Notes:**
```swift
struct BookDetailSheetView: View {
    @Bindable var item: ProcessingItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var editedTitle: String
    @State private var editedAuthor: String
    @FocusState private var focusedField: Field?

    enum Field {
        case title, author
    }

    init(item: ProcessingItem) {
        self.item = item
        _editedTitle = State(initialValue: item.extractedTitle ?? "")
        _editedAuthor = State(initialValue: item.extractedAuthor ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Book spine thumbnail
                    Image(uiImage: item.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Metadata form
                    VStack(spacing: 16) {
                        // Title field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.headline)
                            TextField("Book title", text: $editedTitle)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .title)
                        }

                        // Author field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Author")
                                .font(.headline)
                            TextField("Author name", text: $editedAuthor)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .author)
                        }

                        // Confidence badge
                        if let confidence = item.confidence {
                            HStack {
                                Text("Confidence:")
                                    .font(.subheadline)
                                ConfidenceBadge(confidence: confidence)
                            }
                        }

                        // ISBN (if detected)
                        if let isbn = item.isbn {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ISBN")
                                    .font(.headline)
                                Text(isbn)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Review Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveToLibrary()
                        dismiss()
                    }
                    .disabled(editedTitle.isEmpty || editedAuthor.isEmpty)
                }
            }
        }
    }

    private func saveToLibrary() {
        // Create Book model
        let book = Book(
            title: editedTitle,
            author: editedAuthor,
            isbn: item.isbn ?? "",
            dateScanned: Date()
        )

        modelContext.insert(book)

        // Mark item as completed
        item.status = .completed
        item.extractedTitle = editedTitle
        item.extractedAuthor = editedAuthor
    }
}
```

**Definition of Done:**
- [ ] Sheet displays correctly on all device sizes
- [ ] Editing works smoothly
- [ ] Save creates Book in SwiftData
- [ ] Validation prevents empty fields
- [ ] Code reviewed

---

### US-C2: Add Navigation from ReviewQueueView to Detail
**Priority:** P0
**Story Points:** 3
**Owner:** TBD

**As a** user
**I want** to tap a book in Review tab to see details
**So that** I can review and edit extracted metadata

**Acceptance Criteria:**
- [ ] Modify `ReviewQueueView` to present `BookDetailSheetView`
- [ ] Use `.sheet(item:)` modifier for navigation
- [ ] Pass selected `ProcessingItem` to detail view
- [ ] Handle sheet dismissal
- [ ] Update list when detail sheet closes

**Technical Notes:**
```swift
// In ReviewQueueView.swift
struct ReviewQueueView: View {
    @State private var processingItems: [ProcessingItem] = []
    @State private var selectedItem: ProcessingItem?

    var body: some View {
        NavigationStack {
            List(processingItems) { item in
                ProcessingItemRow(item: item)
                    .onTapGesture {
                        if item.status == .ready {
                            selectedItem = item
                        }
                    }
            }
            .sheet(item: $selectedItem) { item in
                BookDetailSheetView(item: item)
            }
            .navigationTitle("Review")
        }
    }
}
```

**Definition of Done:**
- [ ] Tap navigation works
- [ ] Sheet presents correctly
- [ ] List updates after sheet dismissal
- [ ] Code reviewed

---

### US-C3: Create ConfidenceBadge Component
**Priority:** P1
**Story Points:** 2
**Owner:** TBD

**As a** user
**I want** visual confidence indicators
**So that** I know which extractions need verification

**Acceptance Criteria:**
- [ ] Create `Features/Review/Components/ConfidenceBadge.swift`
- [ ] Color-coded badges: green (>90%), yellow (70-90%), red (<70%)
- [ ] Show percentage (e.g., "92%")
- [ ] Small size for list view, large for detail view
- [ ] Swiss Glass styling

**Technical Notes:**
```swift
struct ConfidenceBadge: View {
    let confidence: Float
    var size: Size = .small

    enum Size {
        case small, large

        var fontSize: CGFloat {
            switch self {
            case .small: return 11
            case .large: return 14
            }
        }

        var padding: CGFloat {
            switch self {
            case .small: return 4
            case .large: return 8
            }
        }
    }

    var body: some View {
        Text("\(Int(confidence * 100))%")
            .font(.system(size: size.fontSize, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, size.padding)
            .padding(.vertical, size.padding / 2)
            .background(
                Capsule()
                    .fill(color)
            )
    }

    var color: Color {
        if confidence >= 0.9 { return .green }
        if confidence >= 0.7 { return .yellow }
        return .red
    }
}
```

**Definition of Done:**
- [ ] Badge renders correctly in both sizes
- [ ] Colors match design system
- [ ] Accessible with VoiceOver
- [ ] Code reviewed

---

## Sprint 2 Demo Script

**Setup:**
- Sprint 1 complete (segmentation working)
- Multi-book and on-device extraction flags enabled
- Test shelf with 5 well-known books

**Demo Flow:**

1. **Take photo** (Sprint 1 functionality) → 5 books detected

2. **Wait 3-5 seconds** for processing

3. **Open Review tab**
   - ✅ See 5 books with extracted titles:
     - "The Great Gatsby"
     - "To Kill a Mockingbird"
     - "1984"
     - "Pride and Prejudice"
     - "The Catcher in the Rye"
   - ✅ See authors: "F. Scott Fitzgerald", "Harper Lee", etc.
   - ✅ See confidence badges (all green >90%)

4. **Tap "1984"**
   - ✅ Detail sheet opens
   - ✅ Large thumbnail visible
   - ✅ Title and author editable
   - ✅ Confidence: 94% (green badge)

5. **Edit title** to "Nineteen Eighty-Four"

6. **Tap "Save"**
   - ✅ Sheet dismisses
   - ✅ Book appears in Library tab
   - ✅ Review tab shows "Completed" status

**Success Criteria:**
- All 5 books extracted correctly
- Extraction time <5s total (1s per book)
- Editing works smoothly
- Save to library successful

---

## Sprint 2 Acceptance Criteria

**Must Have (P0):**
- [x] RecognizeDocumentsRequest replaces old OCR
- [x] BookExtractionService extracts title/author
- [x] BookDetailSheetView allows editing
- [x] Save to library works
- [x] Confidence badges display

**Should Have (P1):**
- [x] Streaming extraction (progressive UI)
- [x] ISBN detection
- [x] Multi-language OCR support

**Nice to Have (P2):**
- [ ] Coauthor support
- [ ] Publisher extraction
- [ ] Error recovery UI

---

## Sprint 2 Dependencies

**From Sprint 1:**
- InstanceSegmentationService complete
- ProcessingItem model extended
- ReviewQueueView foundation ready

**External:**
- iOS 26+ device or simulator
- iPhone 15 Pro+ for Foundation Models testing

---

## Sprint 2 Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Extraction accuracy | >85% | Manual validation |
| Extraction time | <600ms/book | Instruments |
| OCR accuracy | >90% | Compare to ground truth |
| User edit rate | <20% | Analytics |
| Zero crashes | 100% | QA testing |

---

**Sprint 2 Ready for Kickoff:** Pending Sprint 1 completion
**Next Sprint:** Sprint 3 (Talaria Hybrid Integration)
