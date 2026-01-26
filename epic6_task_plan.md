# Epic 6: Launch Prep - Task Plan

**Created:** January 25, 2026, 7:50 PM
**Goal:** Prepare SwiftWing for App Store submission with all required assets, onboarding, legal documentation, and TestFlight beta distribution.

**Success Criteria:**
- ✅ App icon designed and implemented (all required sizes)
- ✅ Launch screen configured with Swiss Glass branding
- ✅ 3-slide onboarding flow explaining camera permissions and core features
- ✅ Privacy policy and terms of service documented
- ✅ App Store screenshots created (6.9" and 6.7" displays)
- ✅ TestFlight beta build submitted for friends & family testing
- ✅ Build succeeds with 0 errors, 0 warnings

---

## Phases

### Phase 1: Research & Design Planning ✅ complete
**Objective:** Analyze existing assets, research iOS 26/App Store requirements, design app icon and onboarding flow.

**Tasks:**
1. ✅ Review Apple's App Store submission guidelines (2026)
2. ✅ Check SwiftWing brand identity (Swiss Glass + International Orange)
3. ✅ Research iOS 26 app icon requirements (sizes, formats, guidelines)
4. ✅ Design app icon concept (Swiss Glass aesthetic)
5. ✅ Plan 3-slide onboarding flow (permissions, scanning, library)
6. ✅ Review privacy requirements for camera/network usage
7. ✅ Check existing Assets.xcassets structure

**Actual Output:**
- ✅ App icon design: "Swiss Glass Book Spine" with orange scan line
- ✅ iOS 26 Liquid Glass research (auto-rounded corners + depth effect)
- ✅ Assets.xcassets audit: AppIcon placeholder exists, no images
- ✅ Info.plist audit: **CRITICAL - missing version/build keys**
- ✅ Onboarding flow designed (documented in findings.md)
- ✅ Privacy requirements documented (camera, Talaria API, local storage)

**Actual Duration:** ~30 minutes

**Key Findings:**
- iOS 26 Liquid Glass perfectly aligns with Swiss Glass aesthetic
- Info.plist needs CFBundleShortVersionString (1.0.0) + CFBundleVersion (1)
- Single 1024x1024 icon required (system auto-scales all sizes)

---

### Phase 2: App Icon & Launch Screen (US-601) ✅ complete
**Objective:** Create and implement app icon in all required sizes plus launch screen.

**Tasks:**
1. ✅ Create app icon design (1024x1024 master)
2. ✅ Generate programmatically via Swift/CoreGraphics script
   - iOS 26: Single 1024x1024 universal icon (system auto-scales)
   - No multiple sizes needed (simplified from iOS 25)
3. ✅ Add icon to Assets.xcassets/AppIcon.appiconset
4. ✅ Update Contents.json with icon reference
5. ✅ Create SwiftUI launch screen (LaunchScreenView.swift)
6. ⏭️ Test launch screen on simulator (deferred to Phase 7 final verification)
7. ⏭️ Verify icon appears in Home Screen (deferred to Phase 7 final verification)

**Actual Output:**
- ✅ AppIcon.png (1024x1024, 21KB) in appiconset
- ✅ LaunchScreenView.swift with Swiss Glass branding
- ✅ Scripts/generate-app-icon.swift (programmatic generation)
- ✅ Info.plist updated (version 1.0.0, build 1)
- ✅ Build verification: 0 errors, 0 warnings

**Actual Duration:** ~20 minutes

**Implementation Notes:**
- Used Swift/CoreGraphics for programmatic icon generation (no design tools needed)
- "Swiss Glass Book Spine" design: Black + white spine + orange stripe accent
- Optimized for iOS 26 Liquid Glass auto-treatment
- Launch screen uses existing Theme extensions

---

### Phase 3: Onboarding Flow (US-602) ✅ complete
**Objective:** Build 3-slide SwiftUI onboarding explaining permissions and features.

**Tasks:**
1. ✅ Create OnboardingView.swift with PageTabViewStyle
2. ✅ Slide 1: Welcome + Swiss Glass hero visual (book spine)
3. ✅ Slide 2: Camera Permission explanation (privacy messaging)
4. ✅ Slide 3: Core features (4 feature rows with icons)
5. ✅ Add "Get Started" button on final slide
6. ✅ Implement @AppStorage flag for first-launch detection
7. ✅ Add skip button on all slides
8. ⏭️ Test onboarding flow in simulator (deferred to Phase 7)

**Actual Output:**
- ✅ OnboardingView.swift (241 lines)
  - 3 slide views (Slide1Welcome, Slide2CameraPermission, Slide3CoreFeatures)
  - FeatureRow reusable component
  - Page navigation with dots indicator
  - Next/Skip/Get Started buttons
- ✅ First-launch detection with @AppStorage("hasCompletedOnboarding")
- ✅ RootView.swift integration (conditional rendering)

**Actual Duration:** ~20 minutes

**Implementation Notes:**
- Swiss Glass design: Black background + white/orange typography
- Page indicator: 8px circles (orange = active, white opacity = inactive)
- Spring animations for smooth transitions (0.3s duration)
- Slide 1: Book spine hero visual matches app icon design
- Slide 2: Privacy-focused messaging (photos never stored)
- Slide 3: 4 features with SF Symbols icons (camera, wand, books, wifi.slash)
- Skip button provides escape hatch on all slides
- hasCompletedOnboarding persists in UserDefaults across launches

---

### Phase 4: Privacy Policy & Terms (US-603) ⚪ pending
**Objective:** Document privacy practices and terms of service for App Store compliance.

**Tasks:**
1. Create PRIVACY.md with camera/network data usage
2. Explain Talaria API integration and data handling
3. Document what data is collected (scanned images, book metadata)
4. Clarify data retention policy (local SwiftData, no cloud storage)
5. Create TERMS.md with basic terms of service
6. Link privacy policy in app (Settings or About screen)
7. Prepare App Store privacy nutrition labels data

**Expected Output:**
- PRIVACY.md (500+ words)
- TERMS.md (300+ words)
- App Store privacy answers documented

**Estimated Duration:** 2 hours

---

### Phase 5: App Store Screenshots & Metadata (US-604) ⚪ pending
**Objective:** Capture marketing screenshots and prepare App Store listing metadata.

**Tasks:**
1. Launch simulator with iPhone 17 Pro Max (6.9" display)
2. Capture 6-8 screenshots showcasing:
   - Camera view with scanning in progress
   - Processing queue with live results
   - Library grid with books
   - Book detail view
   - Offline mode indicator
   - AI results from Talaria
3. Add captions/annotations if needed
4. Draft App Store description (4000 char max)
5. Draft App Store keywords (100 char max)
6. Write promotional text (170 char max)
7. Prepare What's New text for v1.0

**Expected Output:**
- 6-8 polished screenshots (PNG format)
- App Store metadata.txt with all copy
- Keywords optimized for discovery

**Estimated Duration:** 3 hours

---

### Phase 6: TestFlight Beta Setup (US-605) ⚪ pending
**Objective:** Create archive, upload to App Store Connect, invite beta testers.

**Tasks:**
1. Increment version to 1.0 (build 1)
2. Update Info.plist with correct bundle ID and version
3. Archive app via Xcode (Product → Archive)
4. Validate archive for App Store distribution
5. Upload to App Store Connect via Xcode Organizer
6. Set up TestFlight beta testing group
7. Add external testers (email addresses)
8. Submit for beta review (if required)
9. Distribute beta build to testers

**Expected Output:**
- SwiftWing v1.0 build 1 uploaded to TestFlight
- Beta testing group configured
- Invitation emails sent to testers

**Estimated Duration:** 2 hours

---

### Phase 7: Final Verification & Documentation ⚪ pending
**Objective:** Ensure all Epic 6 deliverables complete, update project status.

**Tasks:**
1. Build app with 0 errors, 0 warnings
2. Test full user journey: Install → Onboarding → Scan → Library
3. Verify app icon displays correctly on device
4. Check all 6 epics marked complete in EPIC-ROADMAP.md
5. Update CURRENT-STATUS.md with Epic 6 completion
6. Create Git tag: v1.0.0-epic6-launch
7. Push all changes to main branch

**Expected Output:**
- Clean build status
- All epics marked complete
- Git tag created

**Estimated Duration:** 1 hour

---

## Total Estimated Duration: 14 hours

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-01-25 | Use planning-with-files for Epic 6 | Complex multi-phase task requiring organization |
| | | |

---

## Errors Encountered

| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| (None yet) | - | - | - |

---

## Files to Create/Modify

**New Files:**
- `swiftwing/OnboardingView.swift`
- `swiftwing/OnboardingSlide.swift`
- `PRIVACY.md`
- `TERMS.md`
- `AppStoreMetadata.txt`
- Screenshots in `Marketing/` directory

**Modified Files:**
- `swiftwing/Assets.xcassets/AppIcon.appiconset/`
- `swiftwing/Info.plist` (version, build number)
- `swiftwing/SwiftwingApp.swift` (onboarding integration)
- `CURRENT-STATUS.md`
- `EPIC-ROADMAP.md`

---

## Dependencies

**Blockers:**
- None (Epic 5 complete, all features working)

**Prerequisites:**
- Apple Developer account (for TestFlight)
- Xcode 16+ installed
- iOS 26 simulator available

---

## Notes

- SwiftWing brand: Swiss Glass (60%) + Liquid Glass (40%)
- Color palette: Black (#0D0D0D), White, International Orange (#FF4F00)
- Typography: JetBrains Mono (data), SF Pro (UI)
- Camera permission: Already in Info.plist (US-105)
- Network: Talaria API integration complete (Epic 4)
