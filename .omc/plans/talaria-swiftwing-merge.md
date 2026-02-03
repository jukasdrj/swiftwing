# Talaria-SwiftWing Merge Plan

## Context

### Original Request
Merge Talaria backend's Gemini vision logic into SwiftWing iOS app to:
1. Eliminate network API layer (direct Gemini API calls from iOS)
2. Use Talaria's proven Gemini vision prompts locally
3. Deprecate on-device Vision API segmentation code (Epic 4-5)
4. Reduce latency, improve offline capability
5. Simplify codebase (one repo instead of two)

### Problem Statement
- iOS 26 Vision API (`VNGenerateForegroundInstanceMaskRequest`) cannot handle horizontal book stacks
- User's test case: 5 books stacked horizontally detected as 1 object
- Vision API only works for vertical books on shelves
- Competing solutions successfully handle both orientations using Gemini/YOLO

### Strategic Decision
Replace on-device Vision segmentation with Gemini 2.5 Flash vision API (same model Talaria uses) called directly from the iOS app.

---

## Research Findings

### Talaria Architecture Analysis

**Key Files Examined:**
- `/Users/juju/dev_repos/talaria/src/providers/gemini-provider.ts` - Core Gemini vision integration (600 lines)
- `/Users/juju/dev_repos/talaria/src/types/gemini-schemas.ts` - Response schemas (167 lines)
- `/Users/juju/dev_repos/talaria/src/utils/validation/isbn-validation.ts` - ISBN validation utilities (89 lines)
- `/Users/juju/dev_repos/talaria/src/utils/concurrency/retry.ts` - Retry logic with backoff (374 lines)

**What Talaria Does:**
1. Receives JPEG image via HTTP multipart upload
2. Converts to base64 (chunked for Workers compatibility)
3. Sends to Gemini API with structured output schema
4. Parses response (scene_confidence, visible_spine_count, readable_spine_count, books[])
5. Returns via SSE stream with progress updates

**Gemini Prompt (Optimized):**
```
You are an expert bookshelf analyzer. Analyze the image quality first, then identify books.

CRITICAL: Return ONLY valid JSON matching the exact schema.

Image Quality Assessment:
- scene_confidence (0.0-1.0): Overall scene quality
- visible_spine_count: Total book spines visible
- readable_spine_count: Spines with readable text

Book Extraction Rules (for readable spines only):
- title (REQUIRED): Extract exactly as written on spine
- author (if visible): Full name if readable
- ISBN: ONLY valid 10 or 13-digit numbers
- format: hardcover, paperback, mass-market, or unknown
- confidence (0.0-1.0): Your confidence in text clarity
```

**Response Schema (JSON):**
```typescript
{
  scene_confidence: number,       // 0.0-1.0
  visible_spine_count: integer,   // Total visible
  readable_spine_count: integer,  // Identified count
  books: [
    {
      title: string,              // Required
      author?: string | null,
      isbn?: string | null,
      format?: "hardcover" | "paperback" | "mass-market" | "unknown",
      confidence?: number         // 0.0-1.0
    }
  ]
}
```

### SwiftWing Architecture Analysis

**Files to Modify/Deprecate:**
- `swiftwing/Services/TalariaService.swift` - 687 lines (DEPRECATE network client)
- `swiftwing/Services/InstanceSegmentationService.swift` - 114 lines (DEPRECATE Vision API)
- `swiftwing/Services/VisionService.swift` - 318 lines (KEEP barcode detection, DEPRECATE rectangle detection)
- `swiftwing/CameraViewModel.swift` - 1388 lines (MODIFY to use GeminiService)
- `swiftwing/Services/NetworkTypes.swift` - 336 lines (KEEP BookMetadata, ADD Gemini types)

**Current Processing Pipeline:**
```
CameraCapture -> ImagePreprocessor -> InstanceSegmentationService (Vision API)
                                   -> TalariaService (Network upload)
                                   -> SSE Stream
                                   -> BookMetadata result
```

**Proposed Pipeline:**
```
CameraCapture -> ImagePreprocessor -> GeminiService (Direct API call)
                                   -> BookMetadata result
```

### GoogleGenerativeAI Swift SDK

**Package:** `google-generative-ai-swift` (official Google SDK)
**URL:** https://github.com/google-ai-edge/generative-ai-swift

**Key Features:**
- Native Swift async/await support
- Structured output with JSON schemas
- Vision input support (image + text prompts)
- Streaming response support

**Installation:**
```swift
// Package.swift or Xcode SPM
.package(url: "https://github.com/google-ai-edge/generative-ai-swift", from: "0.4.0")
```

---

## Work Objectives

### Core Objective
Replace network-dependent Talaria integration with direct Gemini API calls from iOS, using the exact same prompts and schemas that power Talaria's production bookshelf scanner.

### Deliverables
1. **GeminiService.swift** - New actor-isolated service for direct Gemini API calls
2. **GeminiTypes.swift** - Swift Codable types matching Talaria's Gemini schemas
3. **Deprecation of TalariaService** - Comment out network client code
4. **Deprecation of InstanceSegmentationService** - Comment out Vision API segmentation
5. **Updated CameraViewModel** - Wire to GeminiService instead of Talaria

### Definition of Done
- [ ] GeminiService successfully calls Gemini 2.5 Flash with bookshelf image
- [ ] Response parsing matches Talaria's proven schema
- [ ] Horizontal book stacks correctly identified (root cause fix)
- [ ] All existing tests pass
- [ ] Build succeeds with 0 errors, 0 warnings
- [ ] Deprecated code clearly marked with `// DEPRECATED:` comments

---

## Must Have / Must NOT Have

### Must Have (Guardrails)
1. **Use Talaria's exact prompt** - Proven 95.5% detection rate
2. **Use structured output** - `responseSchema` for type-safe JSON
3. **Maintain actor isolation** - GeminiService must be an actor
4. **Preserve retry logic** - Exponential backoff with jitter
5. **Scene confidence threshold** - Reject images with confidence < 0.3
6. **API key security** - Use iOS Keychain, not hardcoded

### Must NOT Have
1. **No breaking changes to BookMetadata** - Existing library must work
2. **No deletion of deprecated code** - Comment out for rollback
3. **No changes to UI/UX** - Same user experience
4. **No changes to SwiftData models** - Book @Model unchanged

---

## Task Flow and Dependencies

```
Sprint 1: Foundation (Parallel Tasks)
├── [1.1] Add GoogleGenerativeAI SDK → SPM dependency
├── [1.2] Create GeminiTypes.swift → Port Talaria schemas
└── [1.3] Create GeminiService.swift (skeleton) → Actor structure

Sprint 2: Core Integration (Sequential)
├── [2.1] Implement GeminiService.scanBookshelf() → Main API call
├── [2.2] Implement retry logic → Port from Talaria
├── [2.3] Implement ISBN validation → Port from Talaria
└── [2.4] Implement scene confidence check → Quality gate

Sprint 3: Deprecation (Sequential)
├── [3.1] Comment out TalariaService → Network client
├── [3.2] Comment out InstanceSegmentationService → Vision API
├── [3.3] Comment out VisionService rectangle detection → Keep barcode only
└── [3.4] Update CameraViewModel → Wire to GeminiService

Sprint 4: API Key Management (Sequential)
├── [4.1] Add Keychain wrapper → Secure storage
├── [4.2] Add Settings UI → API key entry
└── [4.3] Add first-launch check → Prompt for key if missing

Sprint 5: Testing & Validation (Parallel)
├── [5.1] Unit tests for GeminiTypes decoding
├── [5.2] Integration test with real Gemini API
├── [5.3] Test horizontal book stack detection
└── [5.4] Performance benchmarking vs Talaria

Sprint 6: Cleanup & Documentation
├── [6.1] Update CLAUDE.md → New architecture
├── [6.2] Update README → Gemini API setup
└── [6.3] Archive Talaria-specific OpenAPI files
```

---

## Detailed TODOs

### Sprint 1: Foundation

#### [1.1] Add GoogleGenerativeAI SDK
**Description:** Add Google's official Generative AI Swift SDK as a package dependency.

**Acceptance Criteria:**
- [ ] SDK added to Package.swift or via Xcode SPM
- [ ] Can import `GoogleGenerativeAI` in Swift files
- [ ] Build succeeds

**Files:**
- `swiftwing.xcodeproj/project.pbxproj` (SPM modification)

---

#### [1.2] Create GeminiTypes.swift
**Description:** Port Talaria's Gemini response schemas to Swift Codable structs.

**Acceptance Criteria:**
- [ ] `BookshelfScanResponse` struct with scene_confidence, spine counts, books array
- [ ] `DetectedBook` struct with title, author, isbn, format, confidence
- [ ] `BookFormat` enum (hardcover, paperback, mass-market, unknown)
- [ ] All types are `Sendable` for actor safety

**Source Reference:**
- `/Users/juju/dev_repos/talaria/src/types/gemini-schemas.ts`

**Files:**
- `swiftwing/Services/GeminiTypes.swift` (NEW)

**Code Skeleton:**
```swift
import Foundation

/// Book format types detected from visual cues
enum BookFormat: String, Codable, Sendable {
    case hardcover
    case paperback
    case massMarket = "mass-market"
    case unknown
}

/// Detected book from Gemini vision analysis
struct GeminiDetectedBook: Codable, Sendable {
    let title: String
    let author: String?
    let isbn: String?
    let format: BookFormat?
    let confidence: Double?
}

/// Gemini bookshelf scan response
struct GeminiBookshelfResponse: Codable, Sendable {
    let scene_confidence: Double
    let visible_spine_count: Int
    let readable_spine_count: Int
    let books: [GeminiDetectedBook]
}

/// Scene quality error (confidence < 0.3)
struct GeminiImageQualityError: Error {
    let sceneConfidence: Double
    let message: String
}
```

---

#### [1.3] Create GeminiService.swift (Skeleton)
**Description:** Create actor-isolated service skeleton for Gemini API integration.

**Acceptance Criteria:**
- [ ] Actor declaration with proper isolation
- [ ] Public API method signature defined
- [ ] Error types defined

**Files:**
- `swiftwing/Services/GeminiService.swift` (NEW)

**Code Skeleton:**
```swift
import Foundation
import GoogleGenerativeAI

/// Errors from Gemini vision service
enum GeminiServiceError: Error {
    case imageQualityTooLow(sceneConfidence: Double)
    case apiKeyMissing
    case invalidResponse
    case apiError(String)
    case rateLimited(retryAfter: TimeInterval?)
}

/// Actor-isolated service for direct Gemini API calls
/// Replaces TalariaService network dependency
actor GeminiService {
    private let model: GenerativeModel?
    private let apiKey: String?

    /// Model configuration (matches Talaria's production settings)
    private static let modelName = "gemini-2.5-flash"
    private static let temperature: Float = 0.1  // Low for consistency
    private static let maxOutputTokens: Int = 1024

    init() {
        // Load API key from Keychain
        self.apiKey = KeychainHelper.getGeminiAPIKey()

        if let apiKey = apiKey {
            self.model = GenerativeModel(
                name: Self.modelName,
                apiKey: apiKey,
                generationConfig: GenerationConfig(
                    temperature: Self.temperature,
                    maxOutputTokens: Self.maxOutputTokens
                )
            )
        } else {
            self.model = nil
        }
    }

    /// Scan bookshelf image and extract book metadata
    /// - Parameter imageData: JPEG image data
    /// - Returns: Array of BookMetadata
    /// - Throws: GeminiServiceError
    func scanBookshelf(_ imageData: Data) async throws -> [BookMetadata] {
        // Implementation in Sprint 2
        fatalError("Not implemented")
    }
}
```

---

### Sprint 2: Core Integration

#### [2.1] Implement GeminiService.scanBookshelf()
**Description:** Implement the main Gemini API call with Talaria's proven prompt.

**Acceptance Criteria:**
- [ ] Sends image to Gemini with structured output schema
- [ ] Uses exact prompt from Talaria (copy-paste)
- [ ] Parses response to BookMetadata array
- [ ] Handles scene_confidence < 0.3 as error

**Source Reference:**
- `/Users/juju/dev_repos/talaria/src/providers/gemini-provider.ts` (lines 220-277)

**Files:**
- `swiftwing/Services/GeminiService.swift`

---

#### [2.2] Implement Retry Logic
**Description:** Port Talaria's retry with exponential backoff and jitter.

**Acceptance Criteria:**
- [ ] 3 retries with 500ms, 1s, 2s backoff schedule
- [ ] Random jitter (0-200ms) to prevent thundering herd
- [ ] Retry only on 429, 500, 502, 503, 504 errors
- [ ] Fail immediately on 400, 401, 403, 404

**Source Reference:**
- `/Users/juju/dev_repos/talaria/src/utils/concurrency/retry.ts`

**Files:**
- `swiftwing/Services/RetryHelper.swift` (NEW)

---

#### [2.3] Implement ISBN Validation
**Description:** Port Talaria's ISBN-10 and ISBN-13 checksum validation.

**Acceptance Criteria:**
- [ ] `isValidISBN10Checksum()` with Modulo 11 algorithm
- [ ] `isValidISBN13Checksum()` with Modulo 10 algorithm
- [ ] `isValidISBN()` main entry point
- [ ] Strip hyphens/spaces before validation

**Source Reference:**
- `/Users/juju/dev_repos/talaria/src/utils/validation/isbn-validation.ts`

**Files:**
- `swiftwing/Services/ISBNValidator.swift` (NEW)

---

#### [2.4] Implement Scene Confidence Check
**Description:** Implement quality gate for low-quality images.

**Acceptance Criteria:**
- [ ] Reject images with scene_confidence < 0.3
- [ ] Return user-friendly error message
- [ ] Log scene analysis metrics for debugging

**Files:**
- `swiftwing/Services/GeminiService.swift`

---

### Sprint 3: Deprecation

#### [3.1] Comment Out TalariaService
**Description:** Deprecate the network client while preserving code for rollback.

**Acceptance Criteria:**
- [ ] Add `// DEPRECATED: Replaced by GeminiService (direct API calls)` header
- [ ] Comment out all method implementations
- [ ] Keep struct/class declarations for type references
- [ ] Update any imports in other files

**Files:**
- `swiftwing/Services/TalariaService.swift`

---

#### [3.2] Comment Out InstanceSegmentationService
**Description:** Deprecate the Vision API segmentation service.

**Acceptance Criteria:**
- [ ] Add deprecation header comment
- [ ] Comment out `segmentBooks()` implementation
- [ ] Keep `SegmentedBook` struct if used elsewhere

**Files:**
- `swiftwing/Services/InstanceSegmentationService.swift`

---

#### [3.3] Comment Out VisionService Rectangle Detection
**Description:** Keep barcode detection, deprecate rectangle detection.

**Acceptance Criteria:**
- [ ] Keep `barcodeRequest` and barcode handling
- [ ] Comment out `rectangleRequest` initialization
- [ ] Comment out rectangle observation processing
- [ ] Keep text recognition for OCR fallback

**Files:**
- `swiftwing/Services/VisionService.swift`

---

#### [3.4] Update CameraViewModel
**Description:** Wire CameraViewModel to use GeminiService instead of TalariaService.

**Acceptance Criteria:**
- [ ] Replace `TalariaService()` instantiation with `GeminiService()`
- [ ] Update `processCaptureWithImageData()` to call GeminiService
- [ ] Remove SSE streaming logic (no longer needed)
- [ ] Simplify processing pipeline (direct API call)
- [ ] Keep rate limiting logic (Gemini has quotas too)

**Files:**
- `swiftwing/CameraViewModel.swift`

**Key Changes:**
```swift
// Before (lines 462-810)
let talariaService = TalariaService()
let (jobId, streamUrl, authToken) = try await talariaService.uploadScan(...)
let eventStream = talariaService.streamEvents(...)
for try await event in eventStream { ... }

// After
let geminiService = GeminiService()
let books = try await geminiService.scanBookshelf(imageData)
for book in books {
    handleBookResult(metadata: book, rawJSON: nil, modelContext: modelContext)
}
```

---

### Sprint 4: API Key Management

#### [4.1] Add Keychain Wrapper
**Description:** Secure storage for Gemini API key using iOS Keychain.

**Acceptance Criteria:**
- [ ] `KeychainHelper.setGeminiAPIKey(_ key: String)`
- [ ] `KeychainHelper.getGeminiAPIKey() -> String?`
- [ ] `KeychainHelper.deleteGeminiAPIKey()`
- [ ] Proper error handling for Keychain errors

**Files:**
- `swiftwing/Utilities/KeychainHelper.swift` (NEW)

---

#### [4.2] Add Settings UI
**Description:** Allow users to enter their Gemini API key in Settings.

**Acceptance Criteria:**
- [ ] Settings section for "API Configuration"
- [ ] Secure text field for API key entry
- [ ] "Save" button to store in Keychain
- [ ] Visual indicator when key is configured

**Files:**
- `swiftwing/Settings/SettingsView.swift` (NEW or MODIFY)

---

#### [4.3] Add First-Launch Check
**Description:** Prompt user for API key if not configured.

**Acceptance Criteria:**
- [ ] Check for API key on app launch
- [ ] Show onboarding sheet if missing
- [ ] Link to Google AI Studio for key generation
- [ ] Validate key format before saving

**Files:**
- `swiftwing/App/SwiftwingApp.swift`
- `swiftwing/Onboarding/APIKeyOnboardingView.swift` (NEW)

---

### Sprint 5: Testing & Validation

#### [5.1] Unit Tests for GeminiTypes Decoding
**Description:** Test JSON decoding for all Gemini response types.

**Acceptance Criteria:**
- [ ] Test valid response decoding
- [ ] Test missing optional fields
- [ ] Test format enum edge cases
- [ ] Test confidence range validation

**Files:**
- `swiftwingTests/GeminiTypesTests.swift` (NEW)

---

#### [5.2] Integration Test with Real Gemini API
**Description:** End-to-end test with actual Gemini API (requires API key).

**Acceptance Criteria:**
- [ ] Test with sample bookshelf image
- [ ] Verify response structure matches expectations
- [ ] Test error handling (invalid key, rate limit)
- [ ] Measure latency

**Files:**
- `swiftwingTests/GeminiServiceIntegrationTests.swift` (NEW)

---

#### [5.3] Test Horizontal Book Stack Detection
**Description:** Verify the root cause fix - horizontal books now detected correctly.

**Acceptance Criteria:**
- [ ] Test with 5 horizontal books (user's original test case)
- [ ] Verify all 5 books detected (not 1)
- [ ] Test mixed orientation (vertical + horizontal)
- [ ] Document detection accuracy

**Files:**
- `swiftwingTests/HorizontalBookStackTests.swift` (NEW)

---

#### [5.4] Performance Benchmarking
**Description:** Compare latency and accuracy vs Talaria network path.

**Acceptance Criteria:**
- [ ] Measure end-to-end latency (capture to result)
- [ ] Compare with Talaria baseline (upload + SSE)
- [ ] Measure battery impact
- [ ] Document improvements

**Files:**
- `swiftwingTests/PerformanceBenchmarkTests.swift` (NEW)

---

### Sprint 6: Cleanup & Documentation

#### [6.1] Update CLAUDE.md
**Description:** Document new architecture in CLAUDE.md.

**Acceptance Criteria:**
- [ ] Remove Talaria API integration section
- [ ] Add GeminiService documentation
- [ ] Update architecture diagram
- [ ] Document API key setup

**Files:**
- `CLAUDE.md`

---

#### [6.2] Update README
**Description:** Update README with new setup instructions.

**Acceptance Criteria:**
- [ ] Add "Getting a Gemini API Key" section
- [ ] Update architecture overview
- [ ] Remove Talaria references

**Files:**
- `README.md`

---

#### [6.3] Archive Talaria-Specific Files
**Description:** Move Talaria-specific files to archive directory.

**Acceptance Criteria:**
- [ ] Move `swiftwing/OpenAPI/talaria-openapi.yaml` to `archive/`
- [ ] Move related scripts
- [ ] Update .gitignore if needed

**Files:**
- `archive/` (NEW directory)
- `swiftwing/OpenAPI/` (MOVE contents)

---

## Commit Strategy

### Sprint 1 Commit
```
feat: Add GoogleGenerativeAI SDK and Gemini types

- Add google-generative-ai-swift package dependency
- Create GeminiTypes.swift with BookshelfScanResponse, DetectedBook
- Create GeminiService.swift skeleton with actor isolation
```

### Sprint 2 Commit
```
feat: Implement GeminiService with direct Gemini API calls

- Implement scanBookshelf() with Talaria's proven prompt
- Add retry logic with exponential backoff
- Add ISBN validation utilities
- Add scene confidence quality gate
```

### Sprint 3 Commit
```
refactor: Deprecate network-based Talaria integration

- DEPRECATED: TalariaService.swift (replaced by GeminiService)
- DEPRECATED: InstanceSegmentationService.swift (Vision API)
- DEPRECATED: VisionService rectangle detection
- Wire CameraViewModel to GeminiService
```

### Sprint 4 Commit
```
feat: Add secure API key management

- Add KeychainHelper for secure storage
- Add Settings UI for API key entry
- Add first-launch onboarding for API key
```

### Sprint 5 Commit
```
test: Add comprehensive tests for Gemini integration

- Unit tests for GeminiTypes decoding
- Integration tests for GeminiService
- Horizontal book stack detection tests
- Performance benchmarks
```

### Sprint 6 Commit
```
docs: Update documentation for new architecture

- Update CLAUDE.md with GeminiService docs
- Update README with API key setup
- Archive Talaria-specific files
```

---

## Success Criteria

### Technical Success
- [ ] Build succeeds with 0 errors, 0 warnings
- [ ] All unit tests pass
- [ ] Integration tests pass with valid API key
- [ ] Horizontal book stacks detected correctly

### User Experience Success
- [ ] Same or better detection accuracy
- [ ] Faster response time (no network round-trip to Talaria)
- [ ] Clear API key setup flow
- [ ] Graceful error handling

### Operational Success
- [ ] No Talaria backend dependency
- [ ] Single repository (SwiftWing only)
- [ ] Reduced operational complexity
- [ ] Clear rollback path (deprecated code preserved)

---

## Rollback Plan

If Gemini direct integration causes issues:

1. **Uncomment TalariaService** - Remove deprecation comments
2. **Uncomment InstanceSegmentationService** - Restore Vision API path
3. **Revert CameraViewModel** - Wire back to TalariaService
4. **Keep GeminiService** - As optional alternative path
5. **Add feature flag** - `UseGeminiDirect` toggle in Settings

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Gemini API rate limits | Medium | Medium | Implement retry logic, add user-facing rate limit UI |
| API key exposure | Low | High | Keychain storage, never log keys |
| Detection accuracy regression | Low | Medium | A/B test with Talaria before full cutover |
| Breaking existing library | Low | High | Don't modify BookMetadata, preserve all fields |
| User friction (API key) | Medium | Medium | Clear onboarding, link to Google AI Studio |

---

## Appendix: Ported Code Reference

### Gemini Prompt (From Talaria)
```
You are an expert bookshelf analyzer. Analyze the image quality first, then identify books.

CRITICAL: Return ONLY valid JSON matching the exact schema. Do NOT include any text outside the JSON structure.

Image Quality Assessment:
- scene_confidence (0.0-1.0): Overall scene quality based on lighting, focus, angle, glare. <0.3 = poor quality (too dark, blurry, or obstructed).
- visible_spine_count: Total book spines visible (including unreadable ones).
- readable_spine_count: Spines with readable text that you identified.

Book Extraction Rules (for readable spines only):
- title (REQUIRED): Extract exactly as written on spine
- author (if visible): Full name if readable, empty string "" if not visible
- ISBN: ONLY valid 10 or 13-digit numbers (NO hyphens, NO invalid checksums). Use empty string "" if ISBN not visible or unreadable.
- format: MUST be one of: "hardcover" (thick spine 3mm+, matte), "paperback" (flexible, glossy), "mass-market" (small 4x7", thin), or "unknown"
- confidence (0.0-1.0): Your confidence in text clarity for this specific book. Reduce if text is blurry, partially obscured, or ambiguous.

Validation:
- If you cannot read a book spine clearly, REDUCE confidence score (do not guess)
- If ISBN is partially visible or checksums don't validate, use empty string ""
- If unsure of format, use "unknown" (do not guess)
- Skip non-book items entirely (decorations, DVDs, etc.)

Output valid JSON ONLY per the provided schema. No additional text or explanations.
```

### Generation Config (From Talaria)
```swift
let config = GenerationConfig(
    temperature: 0.1,        // Low for consistency
    topK: 40,                // Allow some variation
    topP: 0.95,              // Nucleus sampling
    maxOutputTokens: 1024    // Handles ~40 books
)
```

### Retry Schedule (From Talaria)
```swift
let backoffSchedule = [500, 1000, 2000]  // milliseconds
let maxRetries = 3
let jitterRange = 0...200  // milliseconds
```
