# Epic 5: iOS 26 Visual Intelligence - Ready to Start

**Status:** ✅ Fully Planned - Ready for Sprint 1 Kickoff
**Created:** February 2, 2026
**Estimated Completion:** May 2026 (12 weeks)

---

## Quick Links

- **Epic Overview:** [epic-5-visual-intelligence.md](./epic-5-visual-intelligence.md)
- **Sprint 1 (Weeks 1-2):** [sprint-1-foundation.md](./sprint-plans/sprint-1-foundation.md)
- **Sprint 2 (Weeks 3-4):** [sprint-2-extraction.md](./sprint-plans/sprint-2-extraction.md)
- **Sprint 3 (Weeks 5-7):** [sprint-3-talaria-hybrid.md](./sprint-plans/sprint-3-talaria-hybrid.md)
- **Sprint 4 (Weeks 8-9):** [sprint-4-analytics-polish.md](./sprint-plans/sprint-4-analytics-polish.md)
- **Sprint 5 (Weeks 10-12):** [sprint-5-testing-rollout.md](./sprint-plans/sprint-5-testing-rollout.md)

---

## Business Impact

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| **Cost per scan** | $0.021 | $0.001 | 95% reduction |
| **Monthly cost** (10k scans) | $210 | $10 | $200 savings |
| **Annual savings** | — | — | **$2,400** |
| **Books per photo** | 1 | 5 avg, 20 max | 5x productivity |
| **Processing latency** | 4.5s | <1s per book | 78% faster |

---

## Sprint Breakdown

### Sprint 1: Foundation & Multi-Book Core (Weeks 1-2)
**Goal:** Enable shelf scanning with segmentation

**Key Deliverables:**
- InstanceSegmentationService (detect 1-20 books)
- ProcessingFeedbackView (capture confirmation)
- ReviewQueueView with processing states

**Demo:** User takes shelf photo → Sees "Processing 5 books..." → Review tab shows list

**User Stories:** 9 stories, 42 story points
**Parallel Tracks:** 3 (can work concurrently)

---

### Sprint 2: Vision & Extraction Pipeline (Weeks 3-4)
**Goal:** On-device OCR + AI extraction

**Key Deliverables:**
- RecognizeDocumentsRequest integration
- BookExtractionService (Foundation Models)
- BookDetailSheetView (editing)

**Demo:** User sees extracted titles/authors → Can edit mistakes → Save to library

**User Stories:** 9 stories, 46 story points
**Parallel Tracks:** 3

---

### Sprint 3: Talaria Hybrid Integration (Weeks 5-7)
**Goal:** Background enrichment + cost savings

**Key Deliverables:**
- Text-only enrichment endpoint (/v3/jobs/enrich)
- ResultReconciliationService
- MultiBookGridView (grid layout)

**Demo:** Immediate results → 2s later cover images appear → 96% cost reduction

**User Stories:** 8 stories, 47 story points (includes backend work)
**Parallel Tracks:** 3
**Dependencies:** Backend team delivers enrichment endpoint

---

### Sprint 4: Analytics & Polish (Weeks 8-9)
**Goal:** Measure accuracy + optimize

**Key Deliverables:**
- ExtractionAccuracyTracker
- Performance profiling with Instruments
- Feature flags & rollout system

**Demo:** Analytics dashboard shows 92% FM accuracy → Cost savings validated

**User Stories:** 9 stories, 38 story points
**Parallel Tracks:** 3

---

### Sprint 5: Testing & Validation (Weeks 10-12)
**Goal:** Production readiness

**Key Deliverables:**
- 20+ integration tests
- 50-user TestFlight beta
- Phased production rollout (10% → 100%)

**Demo:** Beta results: 4.6 stars → Zero crashes → 100% rollout approved

**User Stories:** 12 stories, 54 story points
**Parallel Tracks:** 3

---

## Total Effort

| Metric | Count |
|--------|-------|
| **Total User Stories** | 47 |
| **Total Story Points** | 227 |
| **Sprints** | 5 |
| **Weeks** | 12 |
| **Parallel Tracks** | 3 per sprint |
| **New Files** | 14 |
| **Modified Files** | 8 |
| **Lines of Code** | ~4,500 |

---

## Critical Path

**Must Complete in Order:**
1. Sprint 1 → Sprint 2 → Sprint 3 (foundation)
2. Sprint 3 → Sprint 4 (analytics depends on hybrid)
3. Sprint 4 → Sprint 5 (testing depends on analytics)

**Can Run in Parallel:**
- Within each sprint: All 3 tracks concurrent
- Sprint 2 + Backend work (enrichment endpoint)
- Sprint 4 analytics + performance optimization

---

## Key Success Metrics

| Metric | Target | How We'll Measure |
|--------|--------|-------------------|
| **Foundation Models accuracy** | >90% | AccuracyTracker in Sprint 4 |
| **Cost reduction** | >90% | Billing reports |
| **User satisfaction** | >4.5 stars | TestFlight feedback |
| **Multi-book adoption** | >70% | Analytics dashboard |
| **Zero regressions** | 100% | Regression test suite |
| **Production crash rate** | <0.5% | Crash reporting |

---

## Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| FM accuracy <90% | MEDIUM | HIGH | Keep Talaria fallback, measure Sprint 2 |
| Backend endpoint delayed | MEDIUM | MEDIUM | Use full-image upload temporarily |
| Instance segmentation <80% | LOW | HIGH | Fallback to single-book mode |
| 4096 token limit hit | LOW | MEDIUM | Truncate OCR text intelligently |
| Beta feedback negative | LOW | HIGH | Iterate in Sprint 5, delay rollout |

---

## Dependencies

**Internal:**
- CameraViewModel refactor (Epic 5 Phase 2A) ✅ COMPLETE
- Review Queue infrastructure (Epic 3) ✅ COMPLETE
- TalariaService actor (Epic 4) ✅ COMPLETE

**External:**
- Backend team: `/v3/jobs/enrich` endpoint (Sprint 3)
- iOS 26+ devices for testing
- iPhone 15 Pro+ for Foundation Models

**Hardware:**
- 2x iPhone 16 Pro test devices ($2,400) - Optional but recommended

---

## Feature Flags

```swift
// Gradual rollout controls
UserDefaults.standard.enableMultiBookScanning: Bool = false
UserDefaults.standard.useOnDeviceExtraction: Bool = false
UserDefaults.standard.useTalariaTextEnrichment: Bool = false
UserDefaults.standard.trackExtractionAccuracy: Bool = true
```

**Rollout Plan:**
- Week 1-2: Internal only (0%)
- Week 11: Early adopters (10% → 50%)
- Week 12: Full rollout (100%)

---

## Review Tab Workflow (Critical to Epic)

**User Journey:**
1. **Camera Tab:** Take photo of bookshelf
2. **Immediate Feedback:** "Processing 5 books..." (2s)
3. **Review Tab:** See extracted books in grid
4. **Tap Book:** Open detail view with metadata
5. **Edit (if needed):** Correct title/author
6. **Save:** Add to library

**Why Review Tab is Critical:**
- Users need to verify AI extractions before saving
- Multi-book requires visual grid layout
- Editing capability essential for accuracy
- Progressive enrichment (FM → Talaria) visible here

---

## Next Steps to Start Sprint 1

### Immediate Actions (This Week)

1. **Kickoff Meeting**
   - Review Sprint 1 plan with team
   - Assign user stories to developers
   - Establish daily standup time

2. **Setup Environment**
   - Create feature branch: `feature/epic-5-visual-intelligence`
   - Enable feature flags in development
   - Setup test devices (iOS 26 simulator OK for Sprint 1)

3. **Track A (Segmentation):** Start immediately
   - US-A1: Create InstanceSegmentationService
   - US-A2: Create SegmentedBook model
   - US-A3: Integrate into CameraViewModel

4. **Track B (Review UI):** Start immediately
   - US-B1: Create ProcessingFeedbackView
   - US-B2: Add to CameraView
   - US-B3: Enhance ReviewQueueView

5. **Track C (Infrastructure):** Start immediately
   - US-C1: Extend ProcessingItem model
   - US-C2: Add feature flags
   - US-C3: Create unit tests

### Ready to Code

All sprint plans include:
- ✅ Acceptance criteria
- ✅ Technical notes with code snippets
- ✅ Definition of done
- ✅ Test scenarios
- ✅ Demo scripts

**No blockers to starting Sprint 1 today.**

---

## Communication Plan

**Daily Standups (15 min):**
- What I completed yesterday
- What I'm working on today
- Any blockers

**Sprint Reviews (Every 2 weeks):**
- Demo working software
- Collect stakeholder feedback
- Adjust priorities

**Sprint Retrospectives:**
- What went well
- What to improve
- Action items

---

## Definition of Done (Epic Level)

**Epic 5 is DONE when:**
- [x] All 5 sprints complete
- [x] All P0 user stories delivered
- [x] Beta testing successful (>4.5 stars)
- [x] Production rollout at 100%
- [x] Cost savings validated ($200+/month)
- [x] FM accuracy >90%
- [x] Zero critical bugs
- [x] Documentation complete
- [x] Retrospective held

---

## Questions?

**For sprint details:** See individual sprint plan markdown files
**For epic overview:** See [epic-5-visual-intelligence.md](./epic-5-visual-intelligence.md)
**For technical architecture:** See comparative research analysis

---

**Epic 5 Status:** 🚀 READY TO START
**Recommended Start Date:** February 3, 2026 (Monday)
**Expected Completion:** May 2, 2026 (Friday)

**Let's build the future of book scanning! 📚✨**
