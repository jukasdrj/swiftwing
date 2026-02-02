# Epic 5: iOS 26 Visual Intelligence Integration

**Epic Goal:** Enable multi-book shelf scanning with on-device AI extraction and hybrid Talaria enrichment to reduce costs by 95% while improving user experience.

**Business Value:**
- **Cost Reduction:** $0.021 → $0.001 per scan (95% savings)
- **Multi-Book Capability:** Scan entire bookshelves (1-20 books per photo)
- **Faster Feedback:** <1s per book vs. 4.5s current
- **Better UX:** Real-time processing feedback + Review tab workflow

**Target Completion:** 12 weeks (3 months)
**Dependencies:** Talaria text-only enrichment endpoint (backend team)

---

## Sprint Structure Overview

```
Sprint 1 (Weeks 1-2): Foundation & Multi-Book Core
├─ Track A: Instance Segmentation Service
├─ Track B: Review Tab UI Foundation
└─ Track C: Processing Feedback System

Sprint 2 (Weeks 3-4): Vision & Extraction Pipeline
├─ Track A: RecognizeDocumentsRequest Integration
├─ Track B: Foundation Models Extraction Service
└─ Track C: Review Tab Detail View

Sprint 3 (Weeks 5-7): Talaria Hybrid Integration
├─ Track A: Text-Only Enrichment Endpoint
├─ Track B: Result Reconciliation Service
└─ Track C: Review Tab Multi-Book Grid

Sprint 4 (Weeks 8-9): Analytics & Polish
├─ Track A: Accuracy Tracking System
├─ Track B: Performance Optimization
└─ Track C: Feature Flags & Rollout

Sprint 5 (Weeks 10-12): Testing & Validation
├─ Track A: Integration Testing
├─ Track B: TestFlight Beta Program
└─ Track C: Production Rollout
```

---

## Success Metrics

| Metric | Baseline | Target | Measurement |
|--------|----------|--------|-------------|
| Cost per scan | $0.021 | $0.001 | Analytics dashboard |
| Books per photo | 1 | 5 avg, 20 max | Usage analytics |
| Processing latency | 4.5s | <1s per book | Instruments |
| FM accuracy | N/A | >90% | AccuracyTracker |
| User satisfaction | N/A | 4.5+ stars | App Store |

---

## Technical Architecture

```
Camera Capture
    ↓
GenerateForegroundInstanceMaskRequest (segment shelf)
    ↓
For Each Book:
    ├─ RecognizeDocumentsRequest (OCR)
    ├─ Foundation Models (extract title/author)
    └─ Store in ProcessingItem
        ↓
    Immediate UI Update (Review Tab)
        ↓
    Background: Talaria text-only enrichment
        ↓
    Merge results & update Review Tab
```

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| FM accuracy <90% | HIGH | Keep Talaria fallback, measure first |
| Instance segmentation fails | HIGH | Single-book fallback mode |
| Talaria endpoint delayed | MEDIUM | Use full-image upload temporarily |
| 4096 token limit hit | MEDIUM | Truncate OCR text intelligently |
| Multi-book UX confusing | MEDIUM | User testing in Sprint 2-3 |

---

## Feature Flags

```swift
// Gradual rollout controls
UserDefaults.standard.enableMultiBookScanning: Bool = false
UserDefaults.standard.useOnDeviceExtraction: Bool = false
UserDefaults.standard.useTalariaTextEnrichment: Bool = false

// Analytics tracking
UserDefaults.standard.trackExtractionAccuracy: Bool = true
```

---

## Dependencies

**Internal:**
- CameraViewModel refactor (Epic 5 Phase 2A - COMPLETE)
- Review Queue infrastructure (Epic 3 - COMPLETE)
- TalariaService actor (Epic 4 - COMPLETE)

**External:**
- Talaria backend: `/v3/jobs/enrich` endpoint
- Coordination with backend team (Sprint 3)

**Hardware:**
- iPhone 15 Pro+ for Foundation Models testing
- iOS 26+ devices for RecognizeDocumentsRequest

---

## Sprint Breakdown

### Sprint 1: Foundation & Multi-Book Core (Weeks 1-2)
**Theme:** Enable shelf scanning with segmentation + Review tab basics

**Deliverables:**
- Instance segmentation service (detect 1-20 books per photo)
- Processing feedback UI (capture confirmation, progress spinner)
- Review tab foundation (list view with processing states)

**Demo:** User can take shelf photo, see "Processing 5 books...", tap Review tab to see list

---

### Sprint 2: Vision & Extraction Pipeline (Weeks 3-4)
**Theme:** On-device OCR + AI extraction with detailed review

**Deliverables:**
- RecognizeDocumentsRequest integration (structured text)
- Foundation Models extraction service (title/author)
- Review tab detail view (per-book editing)

**Demo:** User sees extracted titles/authors in Review tab, can edit mistakes

---

### Sprint 3: Talaria Hybrid Integration (Weeks 5-7)
**Theme:** Background enrichment + multi-book grid UI

**Deliverables:**
- Talaria text-only enrichment endpoint integration
- Result reconciliation (merge FM + Talaria)
- Review tab multi-book grid layout

**Demo:** User sees immediate results, then enriched data (covers, publisher) appears

---

### Sprint 4: Analytics & Polish (Weeks 8-9)
**Theme:** Measure accuracy + optimize performance

**Deliverables:**
- Accuracy tracking system (FM vs Talaria comparison)
- Performance profiling (latency, memory, battery)
- Feature flags for gradual rollout

**Demo:** Analytics dashboard showing 90%+ FM accuracy, cost savings

---

### Sprint 5: Testing & Validation (Weeks 10-12)
**Theme:** Production readiness + user validation

**Deliverables:**
- Integration test suite (20+ scenarios)
- TestFlight beta program (50+ users)
- Production rollout plan (phased by device capability)

**Demo:** Beta users report 4.5+ star experience, zero regressions

---

## Files to Create/Modify

**New Files (14):**
```
Services/InstanceSegmentationService.swift          (300 lines)
Services/BookExtractionService.swift                (400 lines)
Services/ResultReconciliationService.swift          (250 lines)
Models/SegmentedBook.swift                          (80 lines)
Models/BookSpineInfo.swift                          (100 lines)
Features/Review/MultiBookGridView.swift             (300 lines)
Features/Review/BookDetailSheetView.swift           (250 lines)
Features/Camera/ProcessingFeedbackView.swift        (200 lines)
Analytics/ExtractionAccuracyTracker.swift           (200 lines)
Tests/InstanceSegmentationTests.swift               (300 lines)
Tests/BookExtractionTests.swift                     (250 lines)
Tests/ReviewTabIntegrationTests.swift               (400 lines)
.omc/analysis/extraction-accuracy.json              (data)
.omc/epics/sprint-plans/                            (5 files)
```

**Modified Files (8):**
```
Services/VisionService.swift                        (+150 lines)
Services/VisionTypes.swift                          (+80 lines)
Services/TalariaService.swift                       (+120 lines)
Features/Camera/CameraViewModel.swift               (+200 lines)
Features/Camera/CameraView.swift                    (+100 lines)
Features/Review/ReviewQueueView.swift               (+150 lines)
Models/ProcessingItem.swift                         (+50 lines)
swiftwing/SwiftwingApp.swift                        (+30 lines)
```

**Total LOC:** ~3,500 new lines, ~880 modified lines

---

## Next Steps

1. **Create detailed sprint plans** for each sprint (5 documents)
2. **Write user stories** with acceptance criteria (30+ stories)
3. **Setup sprint tracking** in ralph-tui or GitHub Issues
4. **Kick off Sprint 1** with parallel tracks

---

**Created:** February 2, 2026
**Owner:** SwiftWing Development Team
**Status:** Planning → Ready for Sprint 1
