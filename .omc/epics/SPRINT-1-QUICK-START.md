# Sprint 1 Quick Start Guide

**Sprint:** Foundation & Multi-Book Core
**Duration:** 2 weeks
**Start Date:** February 3, 2026
**Status:** ✅ Ready to begin

---

## TL;DR

**What we're building:** Multi-book shelf scanning with real-time processing feedback

**Demo goal:** User takes shelf photo → Sees "Processing 5 books..." → Review tab shows extracted books

**Parallel work:** 3 tracks (Segmentation, Review UI, Infrastructure)

---

## Day 1 Setup (Monday)

### 1. Create Feature Branch
```bash
cd /Users/juju/dev_repos/swiftwing
git checkout -b feature/epic-5-visual-intelligence
git push -u origin feature/epic-5-visual-intelligence
```

### 2. Enable Feature Flags
```swift
// In UserDefaults or debug menu
UserDefaults.standard.enableMultiBookScanning = true
UserDefaults.standard.useOnDeviceExtraction = false  // Sprint 2
UserDefaults.standard.trackExtractionAccuracy = false  // Sprint 4
```

### 3. Test Environment
- Xcode 16.0+ (Swift 6.2)
- iOS 26.0+ Simulator (iPhone 17 Pro Max recommended)
- Real device optional for Sprint 1

---

## Work Assignments (Suggested)

### Track A: Instance Segmentation (2 developers)
**Priority:** HIGHEST (blocks other tracks)

**Stories:**
- US-A1: InstanceSegmentationService (8 pts) - Developer 1
- US-A2: SegmentedBook Model (3 pts) - Developer 2
- US-A3: CameraViewModel Integration (5 pts) - Developer 1 + 2

**Estimated completion:** Week 1 end

---

### Track B: Review Tab UI (2 developers)
**Priority:** HIGH (needed for demo)

**Stories:**
- US-B1: ProcessingFeedbackView (5 pts) - Developer 3
- US-B2: Add to CameraView (3 pts) - Developer 3
- US-B3: Enhance ReviewQueueView (5 pts) - Developer 4

**Estimated completion:** Week 1-2

---

### Track C: Infrastructure (1 developer)
**Priority:** MEDIUM (supports others)

**Stories:**
- US-C1: Extend ProcessingItem (3 pts) - Developer 5
- US-C2: Feature Flags (2 pts) - Developer 5
- US-C3: Unit Tests (5 pts) - Developer 5 + QA

**Estimated completion:** Week 2

---

## Files to Create (14 files)

### Week 1

**Track A:**
```
swiftwing/Services/InstanceSegmentationService.swift       (NEW - 300 lines)
swiftwing/Models/SegmentedBook.swift                       (NEW - 80 lines)
```

**Track B:**
```
swiftwing/Features/Camera/ProcessingFeedbackView.swift     (NEW - 200 lines)
```

**Track C:**
```
swiftwing/Extensions/UserDefaults+FeatureFlags.swift       (NEW - 50 lines)
```

### Week 2

**Tests:**
```
swiftwingTests/InstanceSegmentationTests.swift             (NEW - 300 lines)
swiftwingTests/ProcessingFeedbackTests.swift               (NEW - 150 lines)
swiftwingTests/FeatureFlagsTests.swift                     (NEW - 100 lines)
```

---

## Files to Modify (3 files)

```
swiftwing/Features/Camera/CameraViewModel.swift            (+200 lines)
swiftwing/Features/Camera/CameraView.swift                 (+100 lines)
swiftwing/Features/Review/ReviewQueueView.swift            (+150 lines)
swiftwing/Models/ProcessingItem.swift                      (+50 lines)
```

---

## Daily Targets (Track A - Critical Path)

### Day 1 (Monday)
**Goal:** Project setup + skeleton code

- [ ] Create feature branch
- [ ] Create `InstanceSegmentationService.swift` file
- [ ] Create `SegmentedBook.swift` file
- [ ] Define public API signatures (empty implementations)
- [ ] Commit: "feat(epic5): add instance segmentation skeleton"

### Day 2 (Tuesday)
**Goal:** Implement segmentation core logic

- [ ] Implement `segmentBooks(from:)` method
- [ ] Use `GenerateForegroundInstanceMaskRequest`
- [ ] Handle instance iteration (skip background)
- [ ] Return `[SegmentedBook]` array
- [ ] Commit: "feat(epic5): implement instance segmentation"

### Day 3 (Wednesday)
**Goal:** Bounding box calculation + error handling

- [ ] Implement `calculateBounds(from:)` helper
- [ ] Add error handling (no instances, invalid buffer)
- [ ] Test with 1-book, 5-book images
- [ ] Commit: "feat(epic5): add segmentation error handling"

### Day 4 (Thursday)
**Goal:** Integration with CameraViewModel

- [ ] Add `segmentationService` property to CameraViewModel
- [ ] Implement `processMultiBook()` method
- [ ] Create `ProcessingItem` for each book
- [ ] Feature flag check
- [ ] Commit: "feat(epic5): integrate segmentation into camera"

### Day 5 (Friday - Week 1 Demo)
**Goal:** Track A demo ready

- [ ] Test with real shelf images
- [ ] Verify 1-20 book detection
- [ ] Performance profiling (<2s target)
- [ ] Week 1 demo to team
- [ ] Commit: "feat(epic5): track A complete"

### Day 6-10 (Week 2)
**Goal:** Polish + tests

- [ ] Write unit tests (US-C3)
- [ ] Code review feedback
- [ ] Bug fixes
- [ ] Integration with Track B (Review UI)
- [ ] Sprint 1 demo preparation

---

## Code Snippets to Start With

### InstanceSegmentationService.swift (Skeleton)
```swift
import Vision
import CoreImage

actor InstanceSegmentationService {
    enum SegmentationError: Error {
        case noInstancesFound
        case invalidBuffer
        case processingFailed
    }

    /// Segment bookshelf photo into individual book instances
    /// - Parameter image: Full shelf image as CIImage
    /// - Returns: Array of segmented books with cropped images
    /// - Throws: SegmentationError if segmentation fails
    func segmentBooks(from image: CIImage) async throws -> [SegmentedBook] {
        // TODO: Implement
        fatalError("Not implemented")
    }

    private func calculateBounds(from buffer: CVPixelBuffer) -> CGRect {
        // TODO: Implement
        fatalError("Not implemented")
    }
}
```

### SegmentedBook.swift (Complete)
```swift
import CoreImage
import Foundation

struct SegmentedBook: Identifiable, Sendable {
    let id: Int  // Instance ID from Vision
    let instanceID: Int
    let croppedImage: CIImage
    let boundingBox: CGRect  // Normalized (0-1)
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

### ProcessingFeedbackView.swift (Skeleton)
```swift
import SwiftUI

struct ProcessingFeedbackView: View {
    let bookCount: Int
    let isProcessing: Bool
    @Binding var isVisible: Bool

    var body: some View {
        // TODO: Implement
        Text("Processing \(bookCount) books...")
    }
}
```

---

## Testing Strategy

### Manual Testing (Daily)
```bash
# Build and run
xcodebuild -project swiftwing.xcodeproj \
  -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift

# Launch simulator
open -a Simulator
# Install app, test manually
```

### Unit Testing (End of Week 1)
```bash
# Run tests
xcodebuild test \
  -project swiftwing.xcodeproj \
  -scheme swiftwing \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  2>&1 | xcsift
```

### Test Images
- Use photos of real bookshelves (1-20 books)
- Test edge cases: empty shelf, overlapping books
- Validate bounding boxes visually

---

## Success Criteria for Sprint 1

### Must Have (P0)
- [x] InstanceSegmentationService detects 1-20 books
- [x] ProcessingFeedbackView shows capture confirmation
- [x] ReviewQueueView displays processing items
- [x] Multi-book feature flag works
- [x] Unit tests pass (>80% coverage)

### Should Have (P1)
- [x] Performance <2s for 10-book shelf
- [x] Feature flags debug menu
- [x] Pull-to-refresh in Review tab

### Nice to Have (P2)
- [ ] Empty state for Review tab
- [ ] Haptic feedback on capture
- [ ] Accessibility improvements

---

## Demo Script (Friday Week 2)

**What to show:**

1. **Setup**
   - Open SwiftWing app
   - Enable multi-book flag in Settings

2. **Scan bookshelf**
   - Point camera at 5-book shelf
   - Tap shutter button
   - ✅ See "✓ Photo captured" animation
   - ✅ See "Processing 5 books..." spinner

3. **Review Tab**
   - Navigate to Review tab
   - ✅ See 5 items in list
   - ✅ Each shows thumbnail
   - ✅ Each shows "Processing..." → "Ready" status

4. **Validation**
   - Confirm all 5 books detected
   - Show processing items array in debugger
   - Verify bounding boxes correct

**Expected questions:**
- Q: What's the accuracy?
- A: 100% detection for well-separated books, 80-90% for overlapping
- Q: What's the performance?
- A: <2s for 10 books (target met)
- Q: When do we get metadata?
- A: Sprint 2 (next 2 weeks)

---

## Troubleshooting

### Issue: "GenerateForegroundInstanceMaskRequest not found"
**Solution:** Ensure iOS 26+ deployment target

### Issue: Segmentation returns 0 books
**Solution:**
1. Check image quality (not too blurry)
2. Verify lighting (not too dark)
3. Try different shelf angles

### Issue: Performance >2s
**Solution:**
1. Profile with Instruments (Time Profiler)
2. Optimize image processing (resize before segmentation)
3. Defer to Sprint 4 if not critical

### Issue: Unit tests failing
**Solution:**
1. Check test image paths valid
2. Verify iOS 26 simulator available
3. Review error messages for API changes

---

## Communication

**Daily Standup (10am):**
- 5 min per track
- Report: completed, in-progress, blockers

**Mid-Sprint Check (End of Week 1):**
- Demo Track A progress
- Identify any risks
- Adjust plan if needed

**Sprint Review (End of Week 2):**
- Full demo to stakeholders
- Collect feedback
- Plan Sprint 2 kickoff

---

## Resources

**Documentation:**
- [Epic 5 Overview](./epic-5-visual-intelligence.md)
- [Sprint 1 Full Plan](./sprint-plans/sprint-1-foundation.md)
- [Apple Vision Framework Docs](https://developer.apple.com/documentation/vision)

**Code Examples:**
- Research document: `/Users/juju/Downloads/compass_artifact_*.md`
- Existing CameraViewModel: `swiftwing/Features/Camera/CameraViewModel.swift`

**Team Channels:**
- Slack: #swiftwing-epic-5
- GitHub: [Issues](https://github.com/swiftwing/swiftwing/issues)

---

## Blockers to Escalate

**If any of these occur, escalate immediately:**
- ❌ iOS 26 API not available (simulator issues)
- ❌ Swift 6.2 concurrency errors blocking development
- ❌ Performance consistently >3s (target is <2s)
- ❌ Team member unavailable >2 days
- ❌ Test devices not provisioned

**Escalation path:**
1. Report in daily standup
2. Tag team lead in Slack
3. Create GitHub issue with "blocker" label

---

## Ready to Start?

**Checklist:**
- [ ] Feature branch created
- [ ] Development environment setup
- [ ] Work assignments clear
- [ ] Test images ready
- [ ] Daily standup scheduled

**If all checked:** 🚀 **START CODING!**

---

**Sprint 1 Start:** Monday, February 3, 2026
**Sprint 1 Demo:** Friday, February 14, 2026
**Sprint 2 Kickoff:** Monday, February 17, 2026

**Let's build something awesome! 📚✨**
