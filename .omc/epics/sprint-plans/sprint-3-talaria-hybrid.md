# Sprint 3: Talaria Hybrid Integration

**Sprint Duration:** 3 weeks (Weeks 5-7)
**Theme:** Background enrichment + multi-book grid UI
**Parallel Tracks:** 3 concurrent work streams

---

## Sprint Goal

Users see immediate results from on-device extraction, then enriched data (cover images, publisher info) appears automatically in the background.

**Demo Scenario:**
```
User scans 5 books → Immediate extraction shown (titles/authors)
  → Review tab shows books with placeholder covers
  → 2 seconds later: Real cover images appear
  → Publisher info populates
  → "Enriched by Talaria" badge shows
```

**Cost Savings Realized:**
- Before: 5 books × $0.021 = $0.105 per shelf scan
- After: 5 books × $0.001 = $0.005 per shelf scan
- **96% reduction** per multi-book scan

---

## Track A: Talaria Text-Only Enrichment

### US-A1: Create Text-Only Enrichment Endpoint (Backend)
**Priority:** P0
**Story Points:** 13 (Backend team)
**Owner:** Backend Team

**As a** backend developer
**I want** a new endpoint that accepts extracted text instead of images
**So that** we can enrich metadata without costly OCR

**Acceptance Criteria:**
- [ ] Create `POST /v3/jobs/enrich` endpoint
- [ ] Accept JSON payload: `{text, isbn, title, author}`
- [ ] Return enrichment data: `{coverUrl, publisher, year, verified*}`
- [ ] No image upload required
- [ ] Response time <200ms (no OCR overhead)
- [ ] OpenAPI spec updated

**API Contract:**
```json
// Request
POST /v3/jobs/enrich
{
  "text": "Full OCR text from spine",
  "isbn": "978-0-451-52493-5",  // optional
  "title": "1984",              // optional (from FM)
  "author": "George Orwell"      // optional (from FM)
}

// Response
{
  "jobId": "uuid",
  "enrichment": {
    "coverUrl": "https://covers.openlibrary.org/...",
    "publisher": "Penguin Books",
    "publicationYear": 1949,
    "verifiedTitle": "Nineteen Eighty-Four",  // Authoritative
    "verifiedAuthor": "George Orwell",
    "genre": "Dystopian Fiction",
    "pageCount": 328
  },
  "source": "talaria",
  "confidence": 0.95
}
```

**Definition of Done:**
- [ ] Endpoint deployed to staging
- [ ] OpenAPI spec committed
- [ ] Integration tests pass
- [ ] Performance <200ms validated

---

### US-A2: Add Talaria Enrichment to TalariaService
**Priority:** P0
**Story Points:** 5
**Owner:** iOS Team

**As a** developer
**I want** SwiftWing to call the new text-only enrichment endpoint
**So that** we reduce API costs while improving UX

**Acceptance Criteria:**
- [ ] Add `enrichMetadata()` method to `TalariaService`
- [ ] Accept `BookSpineInfo` + OCR text as parameters
- [ ] Return `EnrichmentResult` type
- [ ] Handle 429 rate limiting
- [ ] Feature flag: `useTalariaTextEnrichment`
- [ ] Fallback to full-image upload if endpoint unavailable

**Technical Notes:**
```swift
// In TalariaService.swift
actor TalariaService {
    func enrichMetadata(
        text: String,
        extractedInfo: BookSpineInfo
    ) async throws -> EnrichmentResult {
        let payload = EnrichmentRequest(
            text: text,
            isbn: extractedInfo.isbn,
            title: extractedInfo.title,
            author: extractedInfo.author
        )

        let response = try await post("/v3/jobs/enrich", body: payload)
        return try decoder.decode(EnrichmentResult.self, from: response)
    }
}

struct EnrichmentResult: Codable {
    let coverUrl: URL?
    let publisher: String?
    let publicationYear: Int?
    let verifiedTitle: String
    let verifiedAuthor: String
    let genre: String?
    let confidence: Float
}
```

**Definition of Done:**
- [ ] Method implemented and tested
- [ ] Error handling covers all cases
- [ ] Unit tests pass
- [ ] Code reviewed

---

### US-A3: Integrate Background Enrichment into Pipeline
**Priority:** P0
**Story Points:** 8
**Owner:** iOS Team

**As a** user
**I want** enriched metadata to appear automatically after initial extraction
**So that** I get complete book information without delays

**Acceptance Criteria:**
- [ ] Call `enrichMetadata()` after on-device extraction completes
- [ ] Run enrichment in background (non-blocking)
- [ ] Update `ProcessingItem` status to `.enriching`
- [ ] Merge enrichment results with existing data
- [ ] Prefer Talaria's `verifiedTitle/Author` if confidence >0.9
- [ ] Update Review tab UI reactively
- [ ] Show "Enriched" badge when complete

**Technical Notes:**
```swift
// In CameraViewModel.swift
private func processBookSpine(_ book: SegmentedBook, item: ProcessingItem) async {
    // Step 1-2: OCR + Extraction (Sprint 2)
    let observation = try await visionService.recognizeText(in: book.croppedImage)
    let metadata = try await extractionService.extract(from: observation.fullText)

    // Update UI immediately
    item.extractedTitle = metadata.title
    item.extractedAuthor = metadata.author
    item.status = .ready

    // Step 3: Background enrichment (non-blocking)
    Task.detached(priority: .utility) {
        await enrichInBackground(item, observation: observation, metadata: metadata)
    }
}

private func enrichInBackground(
    _ item: ProcessingItem,
    observation: DocumentObservation,
    metadata: BookSpineInfo
) async {
    guard UserDefaults.standard.useTalariaTextEnrichment else { return }

    do {
        item.status = .enriching

        let enrichment = try await talariaService.enrichMetadata(
            text: observation.fullText,
            extractedInfo: metadata
        )

        // Merge results
        item.coverUrl = enrichment.coverUrl
        item.publisher = enrichment.publisher
        item.publicationYear = enrichment.publicationYear

        // Use verified data if high confidence
        if enrichment.confidence > 0.9 {
            item.extractedTitle = enrichment.verifiedTitle
            item.extractedAuthor = enrichment.verifiedAuthor
        }

        item.status = .enriched
        item.lastUpdated = Date()

    } catch {
        // Enrichment failed, but user still has FM extraction
        print("Enrichment failed: \(error)")
        item.status = .ready  // Keep as ready (not a blocker)
    }
}
```

**Definition of Done:**
- [ ] Background enrichment works without blocking UI
- [ ] Results merge correctly
- [ ] Review tab updates automatically
- [ ] Enrichment failures don't break workflow
- [ ] Code reviewed

---

## Track B: Result Reconciliation Service

### US-B1: Create ResultReconciliationService
**Priority:** P1
**Story Points:** 5
**Owner:** iOS Team

**As a** developer
**I want** a service to intelligently merge FM and Talaria results
**So that** users get the most accurate metadata

**Acceptance Criteria:**
- [ ] Create `Services/ResultReconciliationService.swift`
- [ ] Compare FM vs Talaria title/author
- [ ] Use Levenshtein distance for fuzzy matching
- [ ] Prefer Talaria if confidence >0.9 AND matches closely
- [ ] Log discrepancies for accuracy tracking (Sprint 4)
- [ ] Return reconciled `BookMetadata` object

**Technical Notes:**
```swift
actor ResultReconciliationService {
    func reconcile(
        fmResult: BookSpineInfo,
        talariaResult: EnrichmentResult
    ) -> BookMetadata {
        let titleMatch = levenshteinSimilarity(
            fmResult.title,
            talariaResult.verifiedTitle
        )
        let authorMatch = levenshteinSimilarity(
            fmResult.author,
            talariaResult.verifiedAuthor
        )

        // Use Talaria if high confidence AND close match
        let finalTitle = (talariaResult.confidence > 0.9 && titleMatch > 0.8)
            ? talariaResult.verifiedTitle
            : fmResult.title

        let finalAuthor = (talariaResult.confidence > 0.9 && authorMatch > 0.8)
            ? talariaResult.verifiedAuthor
            : fmResult.author

        return BookMetadata(
            title: finalTitle,
            author: finalAuthor,
            isbn: fmResult.isbn ?? "",
            coverUrl: talariaResult.coverUrl,
            publisher: talariaResult.publisher,
            confidence: max(fmResult.confidenceLevel.score, talariaResult.confidence),
            source: talariaResult.confidence > 0.9 ? .talaria : .foundationModels
        )
    }

    private func levenshteinSimilarity(_ s1: String, _ s2: String) -> Float {
        // Implementation of Levenshtein distance
        // Returns 0.0-1.0 similarity score
    }
}
```

**Definition of Done:**
- [ ] Reconciliation logic handles all cases
- [ ] Unit tests cover edge cases
- [ ] Performance acceptable (<50ms)
- [ ] Code reviewed

---

## Track C: Multi-Book Grid UI

### US-C1: Create MultiBookGridView
**Priority:** P0
**Story Points:** 8
**Owner:** iOS Team

**As a** user
**I want** to see all my scanned books in a grid layout
**So that** I can quickly browse and select books to review

**Acceptance Criteria:**
- [ ] Create `Features/Review/MultiBookGridView.swift`
- [ ] 2-column grid on iPhone, 3-4 columns on iPad
- [ ] Show book thumbnail, title, author, confidence badge
- [ ] Lazy loading for performance
- [ ] Tap to open detail sheet
- [ ] Swiss Glass card styling
- [ ] Skeleton loaders during processing

**Technical Notes:**
```swift
struct MultiBookGridView: View {
    @Binding var items: [ProcessingItem]
    @Binding var selectedItem: ProcessingItem?

    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    BookGridCard(item: item)
                        .onTapGesture {
                            selectedItem = item
                        }
                }
            }
            .padding()
        }
    }
}

struct BookGridCard: View {
    let item: ProcessingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail with overlay
            ZStack(alignment: .topTrailing) {
                Image(uiImage: item.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Status badge
                StatusBadge(status: item.status)
                    .padding(8)
            }

            // Metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(item.extractedTitle ?? "Processing...")
                    .font(.headline)
                    .lineLimit(2)

                Text(item.extractedAuthor ?? "Unknown Author")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let confidence = item.confidence {
                    ConfidenceBadge(confidence: confidence, size: .small)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.swissBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}
```

**Definition of Done:**
- [ ] Grid renders correctly on all device sizes
- [ ] Performance smooth with 20+ books
- [ ] Tap navigation works
- [ ] Code reviewed

---

### US-C2: Replace ReviewQueueView List with Grid
**Priority:** P0
**Story Points:** 3
**Owner:** iOS Team

**As a** user
**I want** to see books in a visual grid instead of a list
**So that** I can identify books by cover at a glance

**Acceptance Criteria:**
- [ ] Replace `List` with `MultiBookGridView` in `ReviewQueueView`
- [ ] Keep pull-to-refresh functionality
- [ ] Maintain existing detail navigation
- [ ] Add view toggle (list/grid) as optional enhancement

**Definition of Done:**
- [ ] Grid replaces list view
- [ ] All existing functionality preserved
- [ ] Code reviewed

---

## Sprint 3 Demo Script

**Demo Flow:**

1. **Take shelf photo** → 5 books detected

2. **Immediate feedback** (0.5s later)
   - ✅ Review tab shows 5 books with FM extraction
   - ✅ Titles/authors visible
   - ✅ Placeholder covers

3. **Background enrichment** (2s later)
   - ✅ Cover images load progressively
   - ✅ Publisher info appears
   - ✅ "Enriched" badges show

4. **Tap any book**
   - ✅ Detail sheet shows full metadata
   - ✅ Verified title/author (if Talaria confidence >0.9)
   - ✅ Source badge: "Foundation Models + Talaria"

5. **Save to library** → Book stored with complete metadata

**Success Criteria:**
- Immediate user feedback (<1s)
- Enrichment completes within 2-3s
- Cost reduced by 96% validated

---

## Sprint 3 Dependencies

**Blockers:**
- Backend team must deliver `/v3/jobs/enrich` endpoint

**From Previous Sprints:**
- Sprint 1: Segmentation complete
- Sprint 2: Extraction pipeline working

---

## Sprint 3 Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Enrichment latency | <2s | Analytics |
| Cost per scan | $0.001 | Billing |
| Reconciliation accuracy | >95% | Manual validation |
| Grid load time | <0.5s (20 books) | Instruments |

---

**Sprint 3 Ready for Kickoff:** Pending Sprint 2 + backend endpoint
**Next Sprint:** Sprint 4 (Analytics & Polish)
