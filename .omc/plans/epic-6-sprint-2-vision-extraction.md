# Epic 6 Sprint 2: Vision & Extraction Pipeline

## Context

### Original Request
Implement Sprint 2 of Epic 6 for SwiftWing: on-device OCR via RecognizeDocumentsRequest, Foundation Models extraction via BookExtractionService, and a Review Queue detail view with edit/save capabilities. Three parallel tracks (A: OCR, B: Extraction, C: Review UI) totaling 42 story points.

### Research Findings (Codebase Analysis)

**Critical architectural findings from gap analysis:**

1. **VisionService is a plain class, NOT an actor** (`final class VisionService` at `/Users/juju/dev_repos/swiftwing/swiftwing/Services/VisionService.swift:21`). The sprint spec assumes actor isolation. Since `RecognizeDocumentsRequest` is an async API, a new async method must be added carefully -- either as a standalone async function or by creating a separate actor-based OCR service to avoid breaking the existing synchronous `processFrame()` pipeline.

2. **ProcessingItem is a struct** (`/Users/juju/dev_repos/swiftwing/swiftwing/ProcessingItem.swift:7`). The sprint spec's `BookDetailSheetView` uses `@Bindable var item: ProcessingItem` which requires `@Observable` (class). The detail view MUST use a callback/binding pattern instead, passing `@State` values initialized from the item and writing back via CameraViewModel methods.

3. **ProcessingItem already has Sprint 2 placeholder fields** (lines 24-27): `extractedTitle`, `extractedAuthor`, `confidence`, `lastUpdated`. No new model fields needed for storing extraction results.

4. **ProcessingItem.ProcessingState is missing extraction states**. Current states: `preprocessing`, `uploading`, `analyzing`, `done`, `error`, `offline`, `enriching`. Need to add `.extracting` (for OCR+FM phase).

5. **Feature flag `UseOnDeviceExtraction` already exists** in `FeatureFlagsDebugView.swift` (line 21, AppStorage key).

6. **ReviewQueueView has placeholder infrastructure ready** (line 138-141): `ProcessingItemDetailPlaceholder` sheet wired via `selectedProcessingItem`. Sprint 2 replaces this placeholder.

7. **CameraViewModel.processMultiBook() is the integration point** (lines 248-306). Currently routes each segmented book to `processCaptureWithImageData` (Talaria). Sprint 2 adds a branch: when `UseOnDeviceExtraction` is ON, route through OCR+FM pipeline instead.

8. **BookMetadata vs BookSpineInfo data flow gap**. Existing `PendingBookResult` expects `BookMetadata` (from Talaria/NetworkTypes.swift). FM extraction produces `BookSpineInfo`. A mapper `BookSpineInfo -> BookMetadata` is needed so both paths feed the same review queue.

9. **VisionTypes.swift exists** at `/Users/juju/dev_repos/swiftwing/swiftwing/Services/VisionTypes.swift` -- good location for `DocumentObservation` model.

10. **No `Features/Review/` directory exists**. ReviewQueueView.swift lives at root `swiftwing/` level. New files should be placed consistently -- either at root level or create the Review feature directory.

11. **Book.swift model** already accepts all needed fields (title, author, isbn, publisher, spineConfidence, etc.) -- compatible with both Talaria and FM extraction results.

---

## Work Objectives

### Core Objective
Enable on-device book metadata extraction (OCR + Foundation Models) as an alternative to Talaria cloud processing, with a detail review view for editing and saving extracted books to the library.

### Deliverables
1. **RecognizeDocumentsRequest OCR** -- async text recognition method in VisionService returning structured `DocumentObservation`
2. **BookExtractionService** -- actor-isolated Foundation Models extraction service producing `BookSpineInfo`
3. **BookDetailSheetView** -- full detail view replacing the Sprint 1 placeholder, with edit/save to library
4. **Pipeline integration** -- on-device extraction wired into CameraViewModel's multi-book flow behind feature flag
5. **ConfidenceBadge component** -- reusable color-coded confidence indicator

### Definition of Done
- [ ] All 9 user stories (US-A1 through US-C3) implemented
- [ ] Feature flag `UseOnDeviceExtraction` toggles between on-device and Talaria pipelines
- [ ] OCR performance: <150ms per book spine
- [ ] FM extraction performance: <600ms per book
- [ ] BookDetailSheetView allows editing title/author and saving to SwiftData
- [ ] Zero build errors, zero warnings
- [ ] All existing functionality preserved (Talaria pipeline untouched when flag is OFF)

---

## Must Have / Must NOT Have (Guardrails)

### Must Have
- Feature flag gating for ALL new functionality (no breaking changes to existing pipeline)
- Actor isolation for BookExtractionService (Swift 6.2 strict concurrency)
- BookSpineInfo -> BookMetadata mapper (both paths must feed existing review queue)
- Backward compatibility: existing Talaria pipeline works identically when flag is OFF
- ProcessingState `.extracting` added for OCR+FM processing phase
- Error handling with fallback to Talaria when Foundation Models unavailable
- Swiss Glass design system styling on all new UI components

### Must NOT Have
- Do NOT convert VisionService from class to actor (breaks synchronous `processFrame()` used by AVFoundation delegate queue)
- Do NOT convert ProcessingItem from struct to class (too much existing code depends on value semantics)
- Do NOT use `@Bindable` on ProcessingItem in BookDetailSheetView (struct, not @Observable)
- Do NOT modify the existing Talaria SSE streaming pipeline
- Do NOT add new SwiftData models (use existing Book model)
- Do NOT remove ProcessingItemDetailPlaceholder until BookDetailSheetView is verified working

---

## Task Flow and Dependencies

```
Phase 1: Models & Types (no dependencies, parallel-safe)
  |-- TODO-1: DocumentObservation model (VisionTypes.swift)
  |-- TODO-2: BookSpineInfo model (new file)
  |-- TODO-3: ProcessingState .extracting addition
  |-- TODO-4: BookSpineInfo -> BookMetadata mapper

Phase 2: Services (depends on Phase 1)
  |-- TODO-5: VisionService.recognizeText() async method (depends on TODO-1)
  |-- TODO-6: BookExtractionService actor (depends on TODO-2)

Phase 3: Pipeline Integration (depends on Phase 2)
  |-- TODO-7: CameraViewModel on-device extraction pipeline (depends on TODO-5, TODO-6, TODO-4)

Phase 4: UI (depends on Phase 1, parallel with Phase 2-3)
  |-- TODO-8: ConfidenceBadge component (no dependencies)
  |-- TODO-9: BookDetailSheetView (depends on TODO-8)
  |-- TODO-10: Replace placeholder in ReviewQueueView (depends on TODO-9)

Phase 5: Verification
  |-- TODO-11: Build verification (0 errors, 0 warnings)
  |-- TODO-12: Integration testing (feature flag on/off)
```

---

## Detailed TODOs

### TODO-1: Create DocumentObservation Model
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/VisionTypes.swift` (append to existing)
**Story:** US-A2
**Points:** 3
**Blocked by:** None
**Estimated effort:** Small

**Implementation:**
- Add `DocumentObservation` struct conforming to `Sendable`
- Add `Paragraph` struct with `id`, `text`, `confidence: Float`, `boundingBox: CGRect`
- Add computed properties: `wordCount`, `isEmpty`, `characterCount`
- Add `detectedISBNs: [String]` field
- Conform `Paragraph` to `Identifiable`

**Acceptance Criteria:**
- [ ] `DocumentObservation` and `Paragraph` compile with Swift 6.2 strict concurrency
- [ ] Both types conform to `Sendable`
- [ ] Computed properties work correctly
- [ ] Added to existing VisionTypes.swift (do NOT create new file)

**Code Pattern:**
```swift
// Append to VisionTypes.swift after existing types

// MARK: - Document Observation (Sprint 2: OCR)

struct DocumentObservation: Sendable {
    let fullText: String
    let paragraphs: [Paragraph]
    let detectedISBNs: [String]

    var wordCount: Int { fullText.split(separator: " ").count }
    var characterCount: Int { fullText.count }
    var isEmpty: Bool { fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct Paragraph: Sendable, Identifiable {
    let id: UUID
    let text: String
    let confidence: Float
    let boundingBox: CGRect

    var isHighConfidence: Bool { confidence >= 0.9 }

    init(text: String, confidence: Float, boundingBox: CGRect) {
        self.id = UUID()
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}
```

---

### TODO-2: Create BookSpineInfo Model with @Generable
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/Models/BookSpineInfo.swift` (NEW)
**Story:** US-B2
**Points:** 3
**Blocked by:** None
**Estimated effort:** Small

**Implementation:**
- Create new file in Models directory
- Import `FoundationModels` framework
- Define `BookSpineInfo` with `@Generable` macro
- Use `@Guide` annotations for each field
- Define `ConfidenceLevel` enum (high/medium/low)
- Conform to `Sendable` and `Codable`

**Acceptance Criteria:**
- [ ] Compiles with FoundationModels framework imported
- [ ] `@Generable` macro expands without errors
- [ ] `@Guide` annotations provide clear field descriptions
- [ ] `ConfidenceLevel` enum has `score: Float` computed property
- [ ] File added to Xcode project

**Code Pattern:**
```swift
import Foundation
import FoundationModels

@Generable
struct BookSpineInfo: Sendable, Codable {
    @Guide(description: "The book's title, cleaned of OCR artifacts")
    var title: String

    @Guide(description: "Primary author's full name (First Last format)")
    var author: String

    @Guide(description: "Additional authors if present on spine")
    var coauthors: [String]

    @Guide(description: "ISBN-10 or ISBN-13 if found (digits only)")
    var isbn: String?

    @Guide(description: "Publisher name if visible on spine")
    var publisher: String?

    @Guide(description: "Extraction quality: high, medium, or low")
    var confidence: String
}

enum ConfidenceLevel: String, Codable, Sendable {
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

**IMPORTANT NOTE:** The `@Generable` macro and `@Guide` annotations are iOS 26 Foundation Models APIs. Verify exact syntax against iOS 26 SDK headers. The spec uses `@Guide(description:)` but actual API may differ. Executor must check `import FoundationModels` availability and adapt if needed.

---

### TODO-3: Add .extracting State to ProcessingItem
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/ProcessingItem.swift`
**Story:** US-A3, US-B3
**Points:** 1
**Blocked by:** None
**Estimated effort:** Trivial

**Implementation:**
- Add `.extracting` case to `ProcessingState` enum (between `.preprocessing` and `.uploading`)
- Add border color for `.extracting` (use `.cyan` to distinguish from other states)
- Update `ProcessingItemRow` in ReviewQueueView.swift to handle `.extracting` state display

**Acceptance Criteria:**
- [ ] `.extracting` case added with `.cyan` border color
- [ ] `ProcessingItemRow.statusIcon` handles `.extracting` (show ProgressView with .cyan tint)
- [ ] `ProcessingItemRow.statusDescription` returns "Extracting text..." for `.extracting`
- [ ] No existing functionality broken

**Files to modify:**
1. `/Users/juju/dev_repos/swiftwing/swiftwing/ProcessingItem.swift` -- add enum case + color
2. `/Users/juju/dev_repos/swiftwing/swiftwing/ReviewQueueView.swift` -- add switch cases in `statusIcon` and `statusDescription`

---

### TODO-4: Create BookSpineInfo to BookMetadata Mapper
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/Models/BookSpineInfo.swift` (append to TODO-2 file)
**Story:** US-B3
**Points:** 2
**Blocked by:** TODO-2
**Estimated effort:** Small

**Implementation:**
- Add extension on `BookSpineInfo` with `toBookMetadata()` method
- Map fields: title, author, isbn, publisher, confidence
- Set Talaria-specific fields to nil (coverUrl, publishedDate, pageCount, format, enrichmentStatus)
- Convert `ConfidenceLevel` string to `Double` for `BookMetadata.confidence`

**Acceptance Criteria:**
- [ ] `BookSpineInfo.toBookMetadata()` returns valid `BookMetadata`
- [ ] Confidence maps correctly: "high" -> 0.9, "medium" -> 0.7, "low" -> 0.5
- [ ] Missing fields (coverUrl, etc.) are nil (not fake values)
- [ ] Mapper is used in pipeline integration (TODO-7)

**Dependency Note:** `BookMetadata` (in `NetworkTypes.swift`) is a `public struct` with `let` properties. Its auto-generated memberwise init is `internal` access, which works within the SwiftWing module. If compilation fails due to init accessibility, the executor must add an explicit `public init(...)` to `BookMetadata` in `NetworkTypes.swift`.

**Code Pattern:**
```swift
extension BookSpineInfo {
    func toBookMetadata() -> BookMetadata {
        let confidenceScore = ConfidenceLevel(rawValue: confidence)?.score ?? 0.5
        return BookMetadata(
            title: title,
            author: author,
            isbn: isbn,
            coverUrl: nil,
            publisher: publisher,
            publishedDate: nil,
            pageCount: nil,
            format: nil,
            confidence: Double(confidenceScore),
            enrichmentStatus: nil
        )
    }
}
```

---

### TODO-5: Add recognizeText() Async Method to VisionService
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/VisionService.swift`
**Story:** US-A1
**Points:** 5
**Blocked by:** TODO-1
**Estimated effort:** Medium

**Implementation:**
- Add NEW async method `recognizeText(in image: CIImage) async throws -> DocumentObservation`
- Use `RecognizeDocumentsRequest` (iOS 26 Vision API)
- Enable language correction: `request.textRecognitionOptions.useLanguageCorrection = true`
- Support multi-language: `recognitionLanguages = ["en-US", "es-ES"]`
- Extract paragraphs with confidence scores
- Extract ISBNs via `document.text.detectedData`
- Add `VisionError` enum for error cases
- Do NOT modify existing synchronous `processFrame()` method
- Do NOT convert class to actor

**CRITICAL DESIGN DECISION:** VisionService stays as a plain class. The new `recognizeText()` is a standalone async function that creates its own request objects (not reusing the instance properties `textRequest`/`barcodeRequest`). This avoids thread safety issues since `RecognizeDocumentsRequest.perform(on:)` is already async and creates its own execution context.

**Acceptance Criteria:**
- [ ] `recognizeText()` method added as instance method on VisionService
- [ ] Returns `DocumentObservation` with fullText, paragraphs, detectedISBNs
- [ ] Handles vertical text (common on book spines)
- [ ] Performance: <150ms per book spine (measure with CFAbsoluteTimeGetCurrent)
- [ ] Error cases: `.noTextFound`, `.recognitionFailed`
- [ ] Existing `processFrame()` completely untouched
- [ ] `VisionError` enum defined (in VisionTypes.swift or VisionService.swift)

**Code Pattern:**
```swift
// Add to VisionService.swift

// MARK: - Sprint 2: Async OCR (RecognizeDocumentsRequest)

enum VisionError: Error, LocalizedError {
    case noTextFound
    case recognitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noTextFound: return "No text detected in image"
        case .recognitionFailed(let error): return "OCR failed: \(error.localizedDescription)"
        }
    }
}

extension VisionService {
    func recognizeText(in image: CIImage) async throws -> DocumentObservation {
        let startTime = CFAbsoluteTimeGetCurrent()

        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.recognitionLanguages = [
            Locale.Language(identifier: "en-US"),
            Locale.Language(identifier: "es-ES")
        ]

        let observations = try await request.perform(on: image)

        guard let document = observations.first?.document else {
            throw VisionError.noTextFound
        }

        let paragraphs = document.paragraphs.map { para in
            Paragraph(
                text: para.transcript,
                confidence: para.confidence,
                boundingBox: para.boundingRegion.boundingBox.cgRect
            )
        }

        let isbns = extractISBNsFromDetectedData(document.text.detectedData)

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        print("OCR completed in \(String(format: "%.0f", duration * 1000))ms")

        return DocumentObservation(
            fullText: document.text.transcript,
            paragraphs: paragraphs,
            detectedISBNs: isbns
        )
    }

    private func extractISBNsFromDetectedData(_ detectedData: [DetectedData]) -> [String] {
        // Extract ISBN patterns from detected data
        // Implementation depends on exact iOS 26 API shape
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

**IMPORTANT:** The exact API for `RecognizeDocumentsRequest` must be verified against iOS 26 SDK. The code pattern above is based on the sprint spec but the actual property names, return types, and method signatures may differ. The executor MUST check the SDK headers and adapt.

---

### TODO-6: Create BookExtractionService Actor
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/Services/BookExtractionService.swift` (NEW)
**Story:** US-B1
**Points:** 8
**Blocked by:** TODO-2
**Estimated effort:** Large

**Implementation:**
- Create new actor `BookExtractionService`
- Import `FoundationModels` framework
- Initialize `LanguageModelSession` with book-specific system prompt
- Implement `extract(from ocrText: String) async throws -> BookSpineInfo`
- Check `SystemLanguageModel.default.availability` before each call
- Handle 4096 token limit (truncate input at ~12000 characters)
- Define `ExtractionError` enum
- Feature flag check: `UseOnDeviceExtraction` (AppStorage)
- Add fallback awareness (caller handles fallback, not the service itself)

**Acceptance Criteria:**
- [ ] Actor compiles with Swift 6.2 strict concurrency (no warnings)
- [ ] `extract()` returns `BookSpineInfo` with title, author, confidence
- [ ] Handles common OCR errors in system prompt (0/O confusion, split words, etc.)
- [ ] Performance: <600ms per extraction
- [ ] `ExtractionError.modelUnavailable` thrown when FM not available
- [ ] Input truncation at 12000 characters
- [ ] File added to Xcode project

**Code Pattern:**
```swift
import Foundation
import FoundationModels

enum ExtractionError: Error, LocalizedError {
    case modelUnavailable
    case extractionFailed(Error)
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .modelUnavailable: return "On-device language model unavailable"
        case .extractionFailed(let error): return "Extraction failed: \(error.localizedDescription)"
        case .emptyInput: return "No OCR text to extract from"
        }
    }
}

actor BookExtractionService {
    private var session: LanguageModelSession?

    private func getSession() -> LanguageModelSession {
        if let session = session {
            return session
        }
        let newSession = LanguageModelSession {
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
        session = newSession
        return newSession
    }

    func extract(from ocrText: String) async throws -> BookSpineInfo {
        guard !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractionError.emptyInput
        }

        guard SystemLanguageModel.default.availability == .available else {
            throw ExtractionError.modelUnavailable
        }

        let maxInputLength = 12000
        let truncatedText = String(ocrText.prefix(maxInputLength))

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let currentSession = getSession()
            let response = try await currentSession.respond(
                to: "Extract book metadata from this OCR text:\n\n\(truncatedText)",
                generating: BookSpineInfo.self
            )

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            print("FM extraction completed in \(String(format: "%.0f", duration * 1000))ms")

            return response.content
        } catch {
            throw ExtractionError.extractionFailed(error)
        }
    }
}
```

**IMPORTANT:** FoundationModels API (`LanguageModelSession`, `SystemLanguageModel`, `@Generable`) must be verified against iOS 26 SDK. The exact initializer and method signatures may differ from the sprint spec. The executor MUST check SDK headers and adapt.

---

### TODO-7: Integrate On-Device Extraction into CameraViewModel
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift`
**Story:** US-A3, US-B3
**Points:** 8
**Blocked by:** TODO-3, TODO-4, TODO-5, TODO-6
**Estimated effort:** Large

**Implementation:**
- Add `private let extractionService = BookExtractionService()` property
- Add `private let ocrVisionService = VisionService()` property (for OCR, separate from camera's VisionService used by processFrame)
- **Integration point (per-book loop):** Replace lines 294-298 of CameraViewModel.swift. The existing code creates `let bookItemId = UUID()` at line 294, which is a DIFFERENT UUID from `item.id` of the ProcessingItem appended at line 290. This is an existing bug -- the `bookItemId` passed to `processCaptureWithImageData` and stored in `activeStreamingTasks` can never be used to look up the correct ProcessingItem in the queue. Our fix changes this to `let bookItemId = item.id`, which fixes the ID mismatch for BOTH the on-device and Talaria paths. Add the feature flag conditional branch inside the Task body.
- **Integration point (segmentation-failure fallback):** The catch block at lines 301-305 falls back to single-book processing when segmentation fails. This fallback MUST also respect the feature flag. When `UseOnDeviceExtraction` is ON, construct a CIImage from `imageData` and call `processBookOnDevice`. When OFF, call `processCaptureWithImageData` as before. The `useOnDevice` flag read MUST be hoisted above the for-loop (before line 270) so it is available in both the per-book loop and the catch block.
- Create new method `processBookOnDevice(itemId: UUID, imageData: Data, ciImage: CIImage, modelContext: ModelContext)`:
  1. Use existing `updateQueueItem(id:state:message:)` helper (line 690) to set state to `.extracting` with message "Extracting text..."
  2. Call `ocrVisionService.recognizeText(in: ciImage)` for OCR
  3. Use `updateQueueItemProgress(id:message:)` helper (line 682) to update message to "Analyzing metadata..."
  4. Call `extractionService.extract(from: observation.fullText)` for FM extraction
  5. Map `BookSpineInfo` to `BookMetadata` via `toBookMetadata()`
  6. Call `handleBookResult(metadata:rawJSON:modelContext:)` (line 979) to add to review queue
  7. Update ProcessingItem fields via index lookup: `extractedTitle`, `extractedAuthor`, `confidence`
  8. Use `updateQueueItem(id:state:message:)` to set state to `.done` with message showing title
  9. On `ExtractionError.modelUnavailable`: fallback to `processCaptureWithImageData(itemId:imageData:modelContext:)` (Talaria)
  10. On other errors: use `updateQueueItemError(id:errorMessage:)` helper (line 704)

**Existing Helper Methods (MUST use for all ProcessingItem state mutations):**
- `updateQueueItemState(id:state:)` at line 674 -- state-only updates
- `updateQueueItemProgress(id:message:)` at line 682 -- progress message updates
- `updateQueueItem(id:state:message:)` at line 690 -- combined state+message updates (preferred)
- `updateQueueItemError(id:errorMessage:)` at line 704 -- error state with message

**Acceptance Criteria:**
- [ ] Feature flag ON: OCR+FM pipeline executes for each segmented book
- [ ] Feature flag OFF: Existing Talaria pipeline untouched (same behavior, but with the bookItemId bug fix applied)
- [ ] **Bug fix:** `bookItemId` uses `item.id` instead of `UUID()` so queue lookups work correctly for BOTH pipelines
- [ ] Segmentation-failure fallback (catch block at line 301) also respects feature flag
- [ ] Fallback to Talaria when FM unavailable (ExtractionError.modelUnavailable)
- [ ] All ProcessingItem mutations use existing `updateQueueItem*` helpers (NOT direct struct mutation)
- [ ] ProcessingItem.extractedTitle/extractedAuthor populated after extraction
- [ ] ProcessingItem.state transitions: .preprocessing -> .extracting -> .done
- [ ] Performance logging for OCR and extraction phases
- [ ] Error handling uses `updateQueueItemError(id:errorMessage:)` with user-friendly messages
- [ ] Review queue receives results from both pipelines identically

**Code Pattern:**
```swift
// STEP 1: Hoist feature flag read ABOVE the for-loop (before line 270).
// This makes it available to both the per-book loop AND the segmentation-failure catch block.

let useOnDevice = UserDefaults.standard.bool(forKey: "UseOnDeviceExtraction")

// Create ProcessingItem for each segmented book
for book in books {
    // ... existing CIImage-to-UIImage conversion (lines 272-281) stays unchanged ...

    let item = ProcessingItem(
        imageData: croppedImageData,
        state: .preprocessing,
        progressMessage: "Segmented book \(book.instanceID)"
    )

    withAnimation(.swissSpring) {
        processingQueue.append(item)
    }

    // BUG FIX: Existing code used `let bookItemId = UUID()` which creates an ID
    // different from item.id. Queue lookups by bookItemId would never find the
    // correct ProcessingItem. Fixed by using item.id for both pipelines.
    let bookItemId = item.id

    let task = Task {
        if useOnDevice {
            await processBookOnDevice(
                itemId: bookItemId,
                imageData: croppedImageData,
                ciImage: CIImage(cgImage: croppedCGImage),
                modelContext: modelContext
            )
        } else {
            await processCaptureWithImageData(
                itemId: bookItemId,
                imageData: croppedImageData,
                modelContext: modelContext
            )
        }
    }
    activeStreamingTasks[bookItemId] = task
}


// STEP 2: Update the segmentation-failure catch block (lines 301-305) to respect feature flag:

} catch {
    print("Segmentation failed: \(error.localizedDescription)")
    // Fallback to single-book mode, respecting feature flag
    if useOnDevice {
        // Construct CIImage from raw imageData for on-device pipeline
        if let uiImg = UIImage(data: imageData),
           let cgImg = uiImg.cgImage {
            let ciImg = CIImage(cgImage: cgImg)
            await processBookOnDevice(
                itemId: itemId,
                imageData: imageData,
                ciImage: ciImg,
                modelContext: modelContext
            )
        } else {
            // Image conversion failed -- fall through to Talaria as last resort
            await processCaptureWithImageData(itemId: itemId, imageData: imageData, modelContext: modelContext)
        }
    } else {
        await processCaptureWithImageData(itemId: itemId, imageData: imageData, modelContext: modelContext)
    }
}


// STEP 3: New method (add after processMultiBook):

private func processBookOnDevice(itemId: UUID, imageData: Data, ciImage: CIImage, modelContext: ModelContext) async {
    let startTime = CFAbsoluteTimeGetCurrent()

    // Phase 1: OCR
    updateQueueItem(id: itemId, state: .extracting, message: "Extracting text...")

    do {
        let observation = try await ocrVisionService.recognizeText(in: ciImage)

        let ocrDuration = CFAbsoluteTimeGetCurrent() - startTime
        print("OCR completed in \(String(format: "%.0f", ocrDuration * 1000))ms - \(observation.wordCount) words")

        guard !observation.isEmpty else {
            updateQueueItemError(id: itemId, errorMessage: "No text found on book spine")
            return
        }

        // Phase 2: FM Extraction
        updateQueueItemProgress(id: itemId, message: "Analyzing metadata...")

        let extractionStart = CFAbsoluteTimeGetCurrent()
        let spineInfo = try await extractionService.extract(from: observation.fullText)
        let extractionDuration = CFAbsoluteTimeGetCurrent() - extractionStart
        print("FM extraction completed in \(String(format: "%.0f", extractionDuration * 1000))ms")

        // Phase 3: Map to BookMetadata and add to review queue
        let metadata = spineInfo.toBookMetadata()
        handleBookResult(metadata: metadata, rawJSON: nil, modelContext: modelContext)

        // Update ProcessingItem extraction fields
        if let index = processingQueue.firstIndex(where: { $0.id == itemId }) {
            processingQueue[index].extractedTitle = spineInfo.title
            processingQueue[index].extractedAuthor = spineInfo.author
            processingQueue[index].confidence = ConfidenceLevel(rawValue: spineInfo.confidence)?.score ?? 0.5
            processingQueue[index].lastUpdated = Date()
        }

        let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
        updateQueueItem(id: itemId, state: .done, message: "\(spineInfo.title) (\(String(format: "%.0f", totalDuration * 1000))ms)")

    } catch let extractionError as ExtractionError {
        // Handle ExtractionError specifically -- check for modelUnavailable to trigger Talaria fallback
        if case .modelUnavailable = extractionError {
            print("FM unavailable, falling back to Talaria")
            updateQueueItemProgress(id: itemId, message: "Falling back to cloud processing...")
            await processCaptureWithImageData(itemId: itemId, imageData: imageData, modelContext: modelContext)
        } else {
            updateQueueItemError(id: itemId, errorMessage: extractionError.localizedDescription)
        }

    } catch {
        // Non-ExtractionError (e.g., VisionError from OCR phase)
        updateQueueItemError(id: itemId, errorMessage: "Extraction failed: \(error.localizedDescription)")
    }
}
```

---

### TODO-8: Create ConfidenceBadge Component
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/Features/Review/Components/ConfidenceBadge.swift` (NEW)
**Story:** US-C3
**Points:** 2
**Blocked by:** None
**Estimated effort:** Small

**Implementation:**
- Create `Features/Review/Components/` directory
- Create `ConfidenceBadge` SwiftUI view
- Color-coded: green (>=90%), yellow/orange (70-90%), red (<70%)
- Two sizes: `.small` (for list rows) and `.large` (for detail view)
- Swiss Glass styling (capsule shape, semibold rounded font)
- VoiceOver accessibility: label includes confidence percentage and level

**Acceptance Criteria:**
- [ ] Badge renders correctly in both sizes
- [ ] Colors: green >= 0.9, orange 0.7-0.9, red < 0.7
- [ ] Shows percentage text (e.g., "92%")
- [ ] Accessible with VoiceOver
- [ ] Swiss Glass design system compliant
- [ ] File added to Xcode project

**Code Pattern:**
```swift
struct ConfidenceBadge: View {
    let confidence: Float
    var size: BadgeSize = .small

    enum BadgeSize {
        case small, large
        var fontSize: CGFloat { self == .small ? 11 : 14 }
        var horizontalPadding: CGFloat { self == .small ? 6 : 10 }
        var verticalPadding: CGFloat { self == .small ? 3 : 6 }
    }

    var body: some View {
        Text("\(Int(confidence * 100))%")
            .font(.system(size: size.fontSize, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(Capsule().fill(badgeColor))
            .accessibilityLabel("Confidence: \(Int(confidence * 100)) percent, \(confidenceLabel)")
    }

    private var badgeColor: Color {
        if confidence >= 0.9 { return .green }
        if confidence >= 0.7 { return .orange }
        return .red
    }

    private var confidenceLabel: String {
        if confidence >= 0.9 { return "high" }
        if confidence >= 0.7 { return "medium" }
        return "low"
    }
}
```

---

### TODO-9: Create BookDetailSheetView
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/Features/Review/BookDetailSheetView.swift` (NEW)
**Story:** US-C1
**Points:** 8
**Blocked by:** TODO-8
**Estimated effort:** Large

**Implementation:**
- Create `Features/Review/` directory
- Display book spine thumbnail (from ProcessingItem.thumbnailData)
- Editable title TextField (initialized from item.extractedTitle or progressMessage)
- Editable author TextField (initialized from item.extractedAuthor)
- ConfidenceBadge (large size) if confidence available
- ISBN display (read-only) if detected
- "Save to Library" button (creates Book in SwiftData via modelContext)
- "Discard" button (dismisses sheet)
- Keyboard dismissal on tap outside
- Swiss Glass design system styling

**CRITICAL DESIGN NOTE:** Since ProcessingItem is a struct, BookDetailSheetView CANNOT use `@Bindable`. Instead:
- Accept `ProcessingItem` as `let` parameter
- Initialize `@State` vars from item fields
- On save, call a closure `onSave: (String, String, String?) -> Void` passing (title, author, isbn)
- Parent view (ReviewQueueView) handles SwiftData insertion via CameraViewModel

**Acceptance Criteria:**
- [ ] Sheet displays thumbnail, title field, author field, confidence badge
- [ ] Title and author are editable TextFields
- [ ] Save button disabled when title OR author is empty
- [ ] Save creates Book in SwiftData and dismisses sheet
- [ ] Discard dismisses without saving
- [ ] Swiss Glass styling (dark background, glass cards)
- [ ] Keyboard dismisses on tap outside fields
- [ ] File added to Xcode project

**Code Pattern:**
```swift
struct BookDetailSheetView: View {
    let item: ProcessingItem
    let onSave: (String, String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editedTitle: String
    @State private var editedAuthor: String
    @FocusState private var focusedField: Field?

    enum Field { case title, author }

    init(item: ProcessingItem, onSave: @escaping (String, String, String?) -> Void) {
        self.item = item
        self.onSave = onSave
        _editedTitle = State(initialValue: item.extractedTitle ?? item.progressMessage ?? "")
        _editedAuthor = State(initialValue: item.extractedAuthor ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.swissBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        // Thumbnail
                        thumbnailView
                        // Form fields
                        metadataForm
                    }
                    .padding()
                }
            }
            .navigationTitle("Review Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onTapGesture { focusedField = nil }
        }
    }
}
```

---

### TODO-10: Replace Placeholder in ReviewQueueView
**File:** `/Users/juju/dev_repos/swiftwing/swiftwing/ReviewQueueView.swift`
**Story:** US-C2
**Points:** 3
**Blocked by:** TODO-9
**Estimated effort:** Small

**Implementation:**
- Replace `ProcessingItemDetailPlaceholder` sheet with `BookDetailSheetView`
- Pass `onSave` closure that:
  1. Creates BookMetadata from edited fields
  2. Calls `viewModel.handleBookResult()` or directly creates Book via modelContext
  3. Updates ProcessingItem state to .done
  4. Removes from processing queue
- Keep `ProcessingItemDetailPlaceholder` struct in file (dead code removal can happen later)
- Only show tap-to-detail for items in `.done` or `.extracting` state (not `.uploading`)

**Acceptance Criteria:**
- [ ] Tapping a processing item opens BookDetailSheetView (not placeholder)
- [ ] Sheet only opens for items with extracted data (`.done` state or items with `extractedTitle`)
- [ ] Save from detail view creates Book in SwiftData
- [ ] After save, item removed from processing queue
- [ ] List updates reactively after sheet dismissal

**Dependency Note:** This TODO constructs `BookMetadata` using its memberwise init. Same dependency as TODO-4 -- if init is inaccessible, add explicit `public init(...)` to `BookMetadata` in `NetworkTypes.swift`.

**Code Pattern:**
```swift
// Replace the .sheet modifier:
.sheet(item: $selectedProcessingItem) { item in
    BookDetailSheetView(item: item) { title, author, isbn in
        // Save to library
        let metadata = BookMetadata(
            title: title,
            author: author,
            isbn: isbn,
            coverUrl: nil,
            publisher: nil,
            publishedDate: nil,
            pageCount: nil,
            format: nil,
            confidence: Double(item.confidence ?? 0.5),
            enrichmentStatus: nil
        )
        viewModel.handleBookResult(
            metadata: metadata,
            rawJSON: nil,
            modelContext: modelContext
        )
        // Remove from processing queue
        viewModel.processingQueue.removeAll { $0.id == item.id }
    }
}
```

---

### TODO-11: Build Verification
**Story:** Cross-cutting
**Points:** 1
**Blocked by:** TODO-1 through TODO-10
**Estimated effort:** Small

**Implementation:**
```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' clean build 2>&1 | xcsift
```

**Acceptance Criteria:**
- [ ] 0 errors
- [ ] 0 warnings
- [ ] All new files added to Xcode project target
- [ ] No regressions in existing functionality

---

### TODO-12: Integration Verification
**Story:** Cross-cutting
**Points:** 2
**Blocked by:** TODO-11
**Estimated effort:** Small

**Verification Steps:**
1. Feature flag OFF: Take photo with multi-book scanning ON. Verify Talaria pipeline works identically to Sprint 1.
2. Feature flag ON: Take photo. Verify OCR + FM extraction runs for each segmented book.
3. Verify extracted books appear in Review Queue with confidence badges.
4. Tap a book in review queue. Verify BookDetailSheetView opens with extracted data.
5. Edit title and author. Tap Save. Verify Book appears in Library tab.
6. Verify ProcessingItem removed from queue after save.
7. Test FM unavailable scenario: Force `SystemLanguageModel.default.availability != .available`, verify fallback to Talaria.

**Acceptance Criteria:**
- [ ] Both pipelines (Talaria and on-device) produce identical review queue experience
- [ ] Detail view editing and saving works end-to-end
- [ ] Fallback from FM to Talaria works gracefully
- [ ] No crashes under any test scenario

---

## Commit Strategy

**Commit 1:** "feat(sprint2): Add DocumentObservation and BookSpineInfo models" (TODO-1, TODO-2, TODO-3, TODO-4)
- New types, enum case addition, mapper

**Commit 2:** "feat(sprint2): Add RecognizeDocumentsRequest OCR to VisionService" (TODO-5)
- Async recognizeText() method, VisionError enum

**Commit 3:** "feat(sprint2): Create BookExtractionService actor with Foundation Models" (TODO-6)
- New actor service with LanguageModelSession

**Commit 4:** "feat(sprint2): Integrate on-device extraction pipeline in CameraViewModel" (TODO-7)
- Pipeline branching, feature flag routing, fallback logic
- Bug fix: bookItemId now uses item.id instead of UUID() for correct queue lookups (affects both pipelines)
- Segmentation-failure fallback now respects UseOnDeviceExtraction feature flag

**Commit 5:** "feat(sprint2): Add ConfidenceBadge and BookDetailSheetView" (TODO-8, TODO-9, TODO-10)
- New UI components, placeholder replacement

**Commit 6:** "feat(sprint2): Sprint 2 build verification" (TODO-11, TODO-12)
- Verify clean build, integration tests pass

---

## Success Criteria

| Metric | Target | How to Measure |
|--------|--------|----------------|
| OCR accuracy | >90% | Manual validation with 10 test spines |
| OCR latency | <150ms per spine | CFAbsoluteTimeGetCurrent() logging |
| FM extraction latency | <600ms per book | CFAbsoluteTimeGetCurrent() logging |
| Extraction accuracy | >85% title+author correct | Manual validation |
| User edit rate | <20% of extractions need editing | Review queue analytics |
| Build status | 0 errors, 0 warnings | xcodebuild ... \| xcsift |
| Feature flag isolation | Existing pipeline unaffected | Flag OFF regression test |
| Zero crashes | 100% stability | QA testing all paths |

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| RecognizeDocumentsRequest API differs from spec | Medium | High | Verify against iOS 26 SDK headers; adapt code pattern |
| FoundationModels @Generable syntax differs | Medium | High | Check SDK headers; may need manual Codable instead |
| FM unavailable on Simulator | High | Medium | Test with Talaria fallback; real device testing |
| ProcessingItem struct mutations don't propagate | N/A | N/A | Already mitigated: using closure callback pattern |
| OCR too slow on large images | Low | Medium | Images already cropped by segmentation (small per-book crops) |
| VisionService thread safety with new async method | Low | High | New method creates own request objects, no shared state |
| BookMetadata memberwise init inaccessible | Low | Low | Auto-generated internal init works within module; if fails, add explicit `public init(...)` to NetworkTypes.swift |
| bookItemId bug fix changes Talaria path behavior | Low | Medium | Existing Talaria path used `UUID()` as bookItemId which never matched any ProcessingItem -- switching to `item.id` is strictly a correctness improvement; Talaria pipeline behavior is unchanged except queue lookups now work correctly |
| Segmentation-failure fallback CIImage construction fails | Low | Low | If UIImage/CGImage conversion fails, falls through to Talaria as last resort regardless of feature flag |

---

## File Manifest

### New Files (4)
1. `/Users/juju/dev_repos/swiftwing/swiftwing/Models/BookSpineInfo.swift`
2. `/Users/juju/dev_repos/swiftwing/swiftwing/Services/BookExtractionService.swift`
3. `/Users/juju/dev_repos/swiftwing/swiftwing/Features/Review/BookDetailSheetView.swift`
4. `/Users/juju/dev_repos/swiftwing/swiftwing/Features/Review/Components/ConfidenceBadge.swift`

### Modified Files (5)
1. `/Users/juju/dev_repos/swiftwing/swiftwing/Services/VisionTypes.swift` -- add DocumentObservation, Paragraph
2. `/Users/juju/dev_repos/swiftwing/swiftwing/Services/VisionService.swift` -- add recognizeText() async method, VisionError enum
3. `/Users/juju/dev_repos/swiftwing/swiftwing/ProcessingItem.swift` -- add .extracting state
4. `/Users/juju/dev_repos/swiftwing/swiftwing/ReviewQueueView.swift` -- replace placeholder, add .extracting handling
5. `/Users/juju/dev_repos/swiftwing/swiftwing/CameraViewModel.swift` -- add on-device extraction pipeline, processBookOnDevice method

### Unchanged Files (referenced but not modified)
- `/Users/juju/dev_repos/swiftwing/swiftwing/Models/Book.swift` -- already has all needed fields
- `/Users/juju/dev_repos/swiftwing/swiftwing/Services/NetworkTypes.swift` -- BookMetadata already compatible
- `/Users/juju/dev_repos/swiftwing/swiftwing/Features/Settings/FeatureFlagsDebugView.swift` -- UseOnDeviceExtraction already configured
- `/Users/juju/dev_repos/swiftwing/swiftwing/Services/InstanceSegmentationService.swift` -- no changes needed
