# Sprint 4: Analytics & Polish

**Sprint Duration:** 2 weeks (Weeks 8-9)
**Theme:** Measure accuracy + optimize performance
**Parallel Tracks:** 3 concurrent work streams

---

## Sprint Goal

Validate that Foundation Models accuracy is >90%, proving we can reduce Talaria dependency. Optimize performance for production readiness.

**Demo Scenario:**
```
Open Analytics Dashboard → See metrics:
  - Foundation Models accuracy: 92%
  - Talaria accuracy: 95%
  - Cost savings: $180/month (90% reduction)
  - Average extraction time: 850ms per book
  - User edit rate: 15% (acceptable)
```

---

## Track A: Accuracy Tracking System

### US-A1: Create ExtractionAccuracyTracker
**Priority:** P0
**Story Points:** 8

**Acceptance Criteria:**
- [ ] Create `Analytics/ExtractionAccuracyTracker.swift`
- [ ] Record every extraction: FM result, Talaria result, user edit
- [ ] Store comparisons in `.omc/analysis/extraction-accuracy.json`
- [ ] Calculate accuracy scores
- [ ] Track by genre, language, confidence level
- [ ] Privacy-preserving (no full book text stored)

**Technical Notes:**
```swift
actor ExtractionAccuracyTracker {
    private var comparisons: [ExtractionComparison] = []

    struct ExtractionComparison: Codable {
        let timestamp: Date
        let bookID: UUID

        // Foundation Models
        let fmTitle: String
        let fmAuthor: String
        let fmConfidence: Float

        // Talaria
        let talariaTitle: String
        let talariaAuthor: String
        let talariaConfidence: Float

        // Ground truth (user correction)
        let userTitle: String?
        let userAuthor: String?

        // Computed
        var fmTitleAccurate: Bool {
            guard let user = userTitle else { return false }
            return fmTitle.lowercased() == user.lowercased()
        }

        var talariaTitleAccurate: Bool {
            guard let user = userTitle else { return false }
            return talariaTitle.lowercased() == user.lowercased()
        }
    }

    func record(_ comparison: ExtractionComparison) {
        comparisons.append(comparison)

        // Persist to disk every 10 comparisons
        if comparisons.count % 10 == 0 {
            Task { await persist() }
        }
    }

    func generateReport() -> AccuracyReport {
        let totalComparisons = comparisons.filter { $0.userTitle != nil }.count
        let fmCorrect = comparisons.filter(\.fmTitleAccurate).count
        let talariaCorrect = comparisons.filter(\.talariaTitleAccurate).count

        return AccuracyReport(
            totalComparisons: totalComparisons,
            fmAccuracy: Float(fmCorrect) / Float(totalComparisons),
            talariaAccuracy: Float(talariaCorrect) / Float(totalComparisons),
            costSavings: Float(comparisons.count) * 0.020  // $0.020 per scan
        )
    }
}
```

**Definition of Done:**
- [ ] Tracking works for all extractions
- [ ] Data persists across app launches
- [ ] Report generation accurate
- [ ] Privacy audit passed

---

### US-A2: Integrate Tracking into Processing Pipeline
**Priority:** P0
**Story Points:** 3

**Acceptance Criteria:**
- [ ] Call tracker when FM extracts
- [ ] Call tracker when Talaria enriches
- [ ] Call tracker when user saves (ground truth)
- [ ] Feature flag: `trackExtractionAccuracy` (default: true)

**Definition of Done:**
- [ ] All extraction paths tracked
- [ ] No performance impact

---

### US-A3: Create Analytics Dashboard View
**Priority:** P1
**Story Points:** 5

**Acceptance Criteria:**
- [ ] Create `Features/Analytics/AnalyticsDashboardView.swift`
- [ ] Show accuracy charts (FM vs Talaria)
- [ ] Show cost savings graph
- [ ] Show latency histogram
- [ ] Export report to JSON
- [ ] Developer-only (hidden from users)

**Definition of Done:**
- [ ] Dashboard renders correctly
- [ ] Data visualizations clear
- [ ] Export works

---

## Track B: Performance Optimization

### US-B1: Profile with Instruments
**Priority:** P0
**Story Points:** 5

**Acceptance Criteria:**
- [ ] Run Time Profiler on 20-book shelf scan
- [ ] Identify bottlenecks
- [ ] Measure memory usage
- [ ] Check battery impact
- [ ] Validate <2s segmentation, <1s extraction

**Findings to Document:**
- CPU usage peaks
- Memory allocation hotspots
- Battery drain rate
- Thermal throttling points

**Definition of Done:**
- [ ] Profiling complete
- [ ] Report written
- [ ] Optimization targets identified

---

### US-B2: Optimize Critical Path
**Priority:** P0
**Story Points:** 8

**Acceptance Criteria:**
- [ ] Reduce segmentation time if >2s
- [ ] Optimize image processing (compression, resizing)
- [ ] Batch API calls where possible
- [ ] Implement image caching
- [ ] Reduce memory footprint

**Definition of Done:**
- [ ] Performance targets met
- [ ] Zero memory leaks
- [ ] Battery impact <5% per minute

---

### US-B3: Add Performance Monitoring
**Priority:** P1
**Story Points:** 3

**Acceptance Criteria:**
- [ ] Log latency for each pipeline stage
- [ ] Track memory usage trends
- [ ] Monitor crash rate
- [ ] Send telemetry (opt-in)

**Definition of Done:**
- [ ] Monitoring implemented
- [ ] Data flows to analytics

---

## Track C: Feature Flags & Rollout

### US-C1: Implement Gradual Rollout System
**Priority:** P0
**Story Points:** 5

**Acceptance Criteria:**
- [ ] Server-side feature flags (if available)
- [ ] Device capability detection
- [ ] Percentage-based rollout (0%, 10%, 50%, 100%)
- [ ] Instant kill switch for emergencies

**Technical Notes:**
```swift
actor FeatureFlagService {
    func isMultiBookEnabled(for deviceID: String) async -> Bool {
        // Check device capability
        guard #available(iOS 26, *) else { return false }

        // Check server-side rollout percentage
        let rolloutPercent = await fetchRolloutPercentage("multiBookScanning")

        // Hash deviceID to stable bucket
        let bucket = hash(deviceID) % 100
        return bucket < rolloutPercent
    }
}
```

**Definition of Done:**
- [ ] Rollout system works
- [ ] Kill switch tested
- [ ] Rollback plan documented

---

### US-C2: Create Rollout Plan Documentation
**Priority:** P0
**Story Points:** 2

**Acceptance Criteria:**
- [ ] Document rollout phases (0% → 10% → 50% → 100%)
- [ ] Define success metrics per phase
- [ ] Create rollback procedures
- [ ] Test matrix (device types, iOS versions)

**Rollout Phases:**
```
Week 1: 0% (internal testing only)
Week 2: 10% (early adopters, iPhone 15 Pro+)
Week 3: 50% (if metrics good)
Week 4: 100% (full rollout)
```

**Definition of Done:**
- [ ] Plan documented
- [ ] Stakeholders approved
- [ ] Rollback tested

---

### US-C3: Add Error Reporting
**Priority:** P1
**Story Points:** 3

**Acceptance Criteria:**
- [ ] Integrate crash reporting (e.g., Sentry, Firebase)
- [ ] Log extraction failures
- [ ] Track API errors
- [ ] User-friendly error messages

**Definition of Done:**
- [ ] Error reporting works
- [ ] Errors traceable
- [ ] User experience preserved

---

## Sprint 4 Demo Script

**Demo: Analytics Dashboard**

1. **Open dashboard** (developer menu)
   - ✅ Accuracy chart: FM 92%, Talaria 95%
   - ✅ Cost graph: $210 → $10/month
   - ✅ Latency histogram: Median 850ms

2. **Export report**
   - ✅ JSON file with 100+ comparisons
   - ✅ Statistical significance validated

3. **Show feature flag controls**
   - ✅ Rollout percentage: 10%
   - ✅ Kill switch ready

**Success Criteria:**
- FM accuracy >90% (target met)
- Cost savings validated
- Rollout plan approved

---

## Sprint 4 Success Metrics

| Metric | Target | Result |
|--------|--------|--------|
| FM accuracy | >90% | TBD |
| Talaria accuracy | >92% | TBD |
| Cost savings | >90% | TBD |
| Extraction time | <1s/book | TBD |
| User edit rate | <20% | TBD |

---

**Sprint 4 Ready for Kickoff:** Pending Sprint 3
**Next Sprint:** Sprint 5 (Testing & Validation)
