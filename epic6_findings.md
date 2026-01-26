# Epic 6: Launch Prep - Findings & Research

**Created:** January 25, 2026, 7:50 PM

---

## SwiftWing Brand Identity (Established)

### Design System: Swiss Glass Hybrid
- **60% Swiss Utility:** Black (#0D0D0D), grid layouts, monospace fonts
- **40% Liquid Glass:** `.ultraThinMaterial`, rounded corners, spring animations
- **Accent Color:** International Orange (#FF4F00)
- **Typography:**
  - Data/IDs: JetBrains Mono (custom font in Assets)
  - UI text: San Francisco Pro (system font)

### Existing Theme Implementation
- **Location:** `swiftwing/Theme.swift`
- **Extensions:**
  - `Color.swissBackground`, `.swissText`, `.swissError`, `.internationalOrange`
  - `Font.jetBrainsMono`
  - `View.swissGlassCard()`, `.swissGlassOverlay()`

**Implication for Epic 6:**
- App icon should reflect Swiss Glass aesthetic (geometric, minimal, black/orange)
- Launch screen must use existing theme constants
- Onboarding slides follow established design patterns

---

## iOS 26 App Icon Requirements ✅ RESEARCHED

### iOS 26 Liquid Glass Update (2026)
**MAJOR CHANGE:** iOS 26 introduces **Liquid Glass** design treatment

**How It Works:**
- Submit square 1024x1024 icon
- System automatically applies:
  - Rounded corners
  - Liquid Glass effect (layered glass appearance)
  - Subtle reflections and depth
  - Light effects

**Design Implications for SwiftWing:**
- ⚠️ **Clear foreground/background separation CRITICAL**
- Avoid merged shapes (Liquid Glass can flatten unclear designs)
- Bold, geometric shapes work best
- Swiss Glass aesthetic PERFECT match (already geometric)

### Size Requirements (Simplified)
- **Master Icon:** 1024x1024 PNG (no transparency/alpha channel)
- **System Auto-Generates:** All device sizes (60x60@2x, 60x60@3x, etc.)
- **Color Space:** sRGB or Display P3
- **Format:** PNG only

**Sources:**
- [Apple App Icon Guidelines](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [iOS App Icon Requirements 2026](https://splitmetrics.com/blog/guide-to-mobile-icons/)
- [How to Design an App Icon: Sizes and Specs for 2026](https://adapty.io/blog/how-to-design-app-icon/)

---

## Existing Info.plist Configuration

### Camera Permission (Already Configured)
```xml
<key>NSCameraUsageDescription</key>
<string>SwiftWing uses your camera to scan book spines for automatic identification.</string>
```

**Source:** US-105 (Epic 1)
**Status:** ✅ Complete

**Implication:** Onboarding Slide 2 can reference existing permission flow.

---

## SwiftData & Privacy Considerations

### Data Collection (Current Implementation)
1. **Scanned Images:**
   - Captured via AVFoundation
   - Sent to Talaria API (https://api.oooefam.net)
   - Not stored locally after upload
   - Talaria processes and returns metadata

2. **Book Metadata:**
   - Stored locally in SwiftData (Books.store)
   - Fields: title, author, ISBN, coverUrl, format, confidence
   - Never leaves device except during initial scan

3. **Network Data:**
   - Upload: JPEG images (multipart/form-data)
   - Download: SSE stream with AI results
   - Offline queue: Stored locally until network returns

**Privacy Policy Requirements:**
- Explain camera usage (book spine scanning)
- Disclose Talaria API integration
- Clarify local-only storage of library
- State no user accounts, no cloud sync

---

## Onboarding Flow Design

### User Journey (First Launch)
1. **Install App** → Splash screen → Onboarding
2. **Slide 1:** Welcome + Value Prop
   - "Scan book spines, get instant metadata"
   - Swiss Glass hero image
3. **Slide 2:** Camera Permission
   - "We need camera access to scan books"
   - Visual: Camera viewfinder mockup
   - Explanation of NSCameraUsageDescription
4. **Slide 3:** Core Features
   - Scan → AI Recognition → Library Management
   - Visual: 3-panel feature showcase
5. **Get Started Button** → Dismiss onboarding, show CameraView

### First-Launch Detection
- **Method:** UserDefaults flag
- **Key:** `hasCompletedOnboarding`
- **Logic:**
  ```swift
  @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

  if !hasCompletedOnboarding {
      // Show OnboardingView
  } else {
      // Show MainTabView
  }
  ```

---

## App Store Metadata Research

### Description Strategy
**Hook (First 3 lines - visible without "more"):**
- "Scan book spines with your camera."
- "Get instant metadata from AI."
- "Build your digital library in seconds."

**Features:**
- Zero-lag camera preview
- Real-time AI recognition (Talaria backend)
- Duplicate detection
- Offline mode with queue
- Full-text search
- Swiss Glass design aesthetic

**Keywords (100 char max):**
- Primary: book, scanner, library, ISBN, catalog, collection
- Secondary: camera, AI, organize, metadata, spine

**Category:** Productivity or Reference

---

## TestFlight Beta Testing Plan

### Target Testers (Friends & Family)
- **Group Size:** 5-10 testers
- **Platforms:** iPhone 15 Pro, iPhone 16 Pro, iPhone 17 Pro Max
- **iOS Versions:** iOS 26.0+
- **Test Duration:** 1-2 weeks

### Test Scenarios
1. **First Launch:** Onboarding flow completion
2. **Camera:** Scan 10+ book spines
3. **AI Results:** Verify Talaria integration works
4. **Library:** Search, edit, delete books
5. **Edge Cases:** Offline mode, rate limiting, duplicates
6. **Performance:** App feels fast (<0.5s camera cold start)

### Feedback Collection
- **Method:** TestFlight feedback + direct messages
- **Focus Areas:**
  - App icon/branding appeal
  - Onboarding clarity
  - Feature discoverability
  - Bugs/crashes

---

## Existing Assets Review

### Current Assets.xcassets Structure ✅ VERIFIED
**Location:** `swiftwing/Assets.xcassets/`

**Discovered:**
- `AppIcon.appiconset/` - Placeholder only (1024x1024 universal iOS, no actual images)
- `AccentColor.colorset/` - Empty placeholder
- No theme colors in Assets (defined in Theme.swift code instead)

**AppIcon Status:**
- Contents.json configured for single 1024x1024 universal image
- **NO ACTUAL ICON FILES PRESENT** - needs complete creation
- Modern iOS 26 format (single universal asset, not multiple sizes)

**Action Required:**
1. Design 1024x1024 app icon (Swiss Glass aesthetic)
2. Export to PNG (no transparency)
3. Add to AppIcon.appiconset/
4. Update Contents.json if needed

---

## App Icon Design Concept ✅ DESIGNED

### SwiftWing Icon: "Swiss Glass Book Spine"

**Concept:** Minimalist book spine silhouette with Swiss precision, optimized for iOS 26 Liquid Glass

**Visual Elements:**
1. **Background:** Pure black (#0D0D0D) - Swiss foundation
2. **Foreground:** Geometric book spine (white vertical rectangle)
3. **Accent:** International Orange (#FF4F00) vertical stripe (camera scan line)
4. **Layout:** Centered, bold separation for Liquid Glass depth

**Geometry (1024x1024):**
```
┌────────────────────────────────────┐
│         Black Background           │
│                                    │
│     ┌──┬────────────┬──┐          │
│     │  │   White    │  │          │  ← Book Spine
│     │O │   Book     │  │          │     (720x200)
│     │R │   Spine    │  │          │
│     │A │            │  │          │  ← Orange Stripe
│     │N │            │  │          │     (40x720, left edge)
│     │G │            │  │          │
│     │E │            │  │          │
│     └──┴────────────┴──┘          │
│                                    │
└────────────────────────────────────┘
```

**Dimensions:**
- Canvas: 1024x1024px
- Book spine: 200px wide × 720px tall (centered)
- Orange stripe: 40px wide × full spine height (left edge)
- Padding: 152px from edges (ensures no clipping after rounding)

**Why This Works:**
- ✅ **Clear separation:** White book vs. black background (Liquid Glass won't flatten)
- ✅ **Bold shapes:** Geometric precision (Swiss aesthetic)
- ✅ **Brand identity:** Orange accent = SwiftWing signature
- ✅ **Function clarity:** Immediately communicates "book scanning"
- ✅ **Depth potential:** Liquid Glass will add dimension to layered rectangles

**Alternative Concept (if too minimal):**
- Add subtle "SW" monogram inside book spine
- JetBrains Mono font (brand consistency)
- Keep orange stripe for recognition

### Implementation Plan
1. Create in vector (Sketch/Figma/Illustrator)
2. Export 1024x1024 PNG (no transparency)
3. Test in iOS 26 simulator (verify Liquid Glass treatment)
4. Add to AppIcon.appiconset/
5. Build and verify icon appears on Home Screen

---

## Launch Screen Design Options

### Option A: Storyboard (Traditional)
- Use LaunchScreen.storyboard
- Static image or color
- Limited customization

### Option B: SwiftUI (iOS 26)
- Create `LaunchScreenView.swift`
- Use SwiftUI modifiers
- More flexibility

**Recommendation:** Use SwiftUI for consistency with main app.

**Design:**
- Black background (Color.swissBackground)
- "SwiftWing" wordmark (JetBrains Mono)
- Tagline: "AI-Powered Book Scanner"
- Minimal, Swiss aesthetic

---

## Version & Build Numbering

### Current Version (Pre-Epic 6) ✅ VERIFIED
**Info.plist Status:** MISSING version keys entirely

**Findings:**
- NO CFBundleShortVersionString (Version)
- NO CFBundleVersion (Build)
- Only contains: UIAppFonts, NSCameraUsageDescription
- **CRITICAL:** Must add version/build keys for App Store submission

**Epic 6 Target:**
- **Version:** 1.0.0 (CFBundleShortVersionString) - **MUST ADD**
- **Build:** 1 (CFBundleVersion) - **MUST ADD**
- **Bundle ID:** com.ooheynerds.swiftwing (from CLAUDE.md)

**Future Versioning:**
- 1.0.1, 1.0.2: Bug fixes
- 1.1.0: Minor features (Epic 7+)
- 2.0.0: Major redesign

---

## Epic Dependencies Verification

### Epic 1 (Foundation) ✅ Complete
- SwiftData Book model
- Basic theme constants
- Camera permission primer

### Epic 2 (Camera) ✅ Complete
- Zero-lag camera preview
- Non-blocking shutter
- Processing queue UI

### Epic 3 (Library) ✅ Complete
- Library grid view
- Full-text search
- Book detail sheets

### Epic 4 (AI) ✅ Complete
- Talaria API integration
- SSE streaming
- Offline queue

### Epic 5 (Refactoring) ✅ Complete
- MVVM pattern
- All view components extracted
- 77% code reduction

**Status:** All prerequisites complete. Ready for Epic 6.

---

## Research Tasks Remaining

1. **Apple Documentation:**
   - App Store submission checklist (2026 version)
   - iOS 26 app icon requirements
   - TestFlight beta review process

2. **Privacy Policy Templates:**
   - Find iOS app privacy policy generator
   - Ensure GDPR/CCPA compliance (if applicable)

3. **Screenshot Best Practices:**
   - Apple's screenshot guidelines
   - Competitor analysis (book scanner apps)

4. **Asset Generation Tools:**
   - Xcode built-in icon generator
   - Third-party tools (IconKit, etc.)

---

## Notes

- SwiftWing is a **solo developer project** (no team onboarding needed)
- Target launch: TestFlight beta first, then App Store review
- No monetization in v1.0 (free app)
- No user accounts or authentication
- Local-first architecture (privacy advantage)
