# On-Device ML Experiment (Archived)

**Date Archived:** 2026-02-03
**Status:** Experiment concluded - Talaria workflow superior
**Reason:** Foundation Models insufficient for book spine text extraction use case

## What Was This?

An experiment to use iOS 26's new **Foundation Models** framework for on-device book metadata extraction, eliminating the need for Talaria backend calls.

## Architecture

### BookScannerViewModel.swift (431 lines)
- Replacement for CameraViewModel
- Used Vision Framework for OCR
- Fed OCR text to Foundation Models for metadata extraction
- Direct to Review Queue (no network calls)

### BookExtractionService.swift (64 lines)
- Actor-isolated service wrapping `LanguageModelSession`
- Used `@Generable` BookSpineInfo struct
- Extracted title, author, ISBN, publisher, confidence

### BookSpineInfo.swift (95 lines)
- `@Generable` struct with `@Guide` property wrappers
- Defined schema for Foundation Models output
- Confidence levels: high (90%), medium (70%), low (50%)

## Why It Didn't Work

### 1. **Low Accuracy on Book Spines**
- Book spine text is:
  - Vertically oriented (requires rotation)
  - Mixed fonts and sizes
  - Often partial/obscured
  - Lacks context (no cover, no full title page)

- Foundation Models struggled with:
  - Abbreviated titles
  - Author last names only
  - Publisher logos (not text)
  - Spine-specific formatting

**Result:** 30-40% confidence vs. Talaria's 85-95%

### 2. **Missing Enrichment Data**
Foundation Models only extracted what was visible on spine:
- ❌ Cover images (Talaria fetches from Google Books)
- ❌ Full metadata (page count, genre, publication date)
- ❌ ISBN validation (Talaria cross-references multiple sources)
- ❌ Multiple editions handling

### 3. **No Real-Time Feedback**
- Talaria SSE streaming: progress messages, multi-book tracking
- Foundation Models: synchronous, no status updates
- User experience: "black box" processing vs. live feedback

### 4. **Offline Benefits Not Realized**
- Intended use case: scan books without internet
- Reality: users still need Talaria for cover images and enrichment
- Can't build complete library offline

## What We Learned

### ✅ **Foundation Models are good at:**
- Structured data extraction from well-formatted text
- Form parsing, receipt OCR
- Document classification
- Q&A over long documents

### ❌ **Foundation Models struggle with:**
- Domain-specific knowledge (book metadata)
- Ambiguous/incomplete input (spine text)
- Validation against external databases
- Enrichment requiring web searches

### 🎯 **Talaria's advantages:**
- Specialized book spine recognition models
- Multi-source ISBN validation
- Cover image fetching (Google Books, Open Library)
- Genre/category inference
- Edition resolution (hardcover vs. paperback)
- Real-time progress via SSE

## Code Highlights

### Using @Generable
```swift
#if canImport(FoundationModels)
import FoundationModels

@Generable
struct BookSpineInfo: Sendable, Codable {
    @Guide(description: "The book's title, cleaned of OCR artifacts")
    var title: String

    @Guide(description: "Primary author's full name (First Last format)")
    var author: String

    @Guide(description: "Extraction quality: high, medium, or low")
    var confidence: String
}
#endif
```

### Extraction Flow
```swift
actor BookExtractionService {
    private let session: LanguageModelSession

    func extract(from ocrText: String) async throws -> BookSpineInfo {
        guard SystemLanguageModel.default.availability == .available else {
            throw ExtractionError.modelUnavailable
        }

        let response = try await session.respond(
            to: prompt,
            generating: BookSpineInfo.self
        )

        return response.content
    }
}
```

### Integration with Vision
```swift
// OCR with Vision Framework
let visionService = VisionService()
let document = try await visionService.recognizeText(in: ciImage)

// Extract metadata with Foundation Models
let metadata = try await extractionService.extract(from: document.fullText)

// Convert to BookMetadata
let bookResult = PendingBookResult(
    metadata: metadata.toBookMetadata(),
    rawJSON: nil,
    thumbnailData: imageData
)
```

## Performance Comparison

| Metric | Foundation Models | Talaria |
|--------|-------------------|---------|
| **Extraction Time** | ~500ms | ~2000ms (upload + processing) |
| **Accuracy** | 30-40% | 85-95% |
| **Cover Images** | ❌ | ✅ |
| **Full Metadata** | ❌ | ✅ |
| **Offline Support** | ✅ | ❌ |
| **Multi-Book Scan** | ⚠️ (no progress) | ✅ (SSE events) |
| **User Feedback** | ❌ | ✅ (real-time) |

## Future Considerations

### When to Revisit?

1. **Foundation Models v2+**
   - Apple adds domain-specific book knowledge
   - Better handling of vertical text
   - ISBN database integration

2. **Hybrid Approach**
   - Use Foundation Models for quick preview
   - Background Talaria call for enrichment
   - User sees fast result, gets full data later

3. **Offline-First Requirements**
   - User explicitly needs offline-only scanning
   - Accept lower accuracy trade-off
   - Manual ISBN entry fallback

## How to Resurrect

If you want to try this again:

```bash
# Copy files back
cp .archive/experiments/on-device-ml/BookScannerViewModel.swift swiftwing/
cp .archive/experiments/on-device-ml/BookExtractionService.swift swiftwing/Services/
cp .archive/experiments/on-device-ml/BookSpineInfo.swift swiftwing/Models/

# Add to Xcode project
open swiftwing.xcodeproj

# Update RootView.swift
@State private var viewModel = BookScannerViewModel()

# Feature flag
UserDefaults.standard.set(true, forKey: "UseOnDeviceExtraction")
```

## Related Files Still in Codebase

These files support on-device processing but are also used by Talaria:

- `swiftwing/Services/VisionService.swift` - OCR (used by both)
- `swiftwing/Services/InstanceSegmentationService.swift` - Multi-book detection
- `swiftwing/Services/HoughLineSegmentation.swift` - Line detection
- `swiftwing/Services/ImagePreprocessor.swift` - Image enhancement

## Conclusion

**Decision:** Talaria workflow is superior for SwiftWing's use case.

Foundation Models are impressive for general-purpose text extraction, but book spine scanning requires:
- Domain-specific training data
- External database integration
- Rich metadata enrichment
- Real-time user feedback

Talaria provides all of these. On-device ML remains an interesting experiment for offline scenarios, but not viable as primary workflow.

**Archived for:** Documentation and potential future exploration.
