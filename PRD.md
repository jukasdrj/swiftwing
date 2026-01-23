# Product Requirements Document: SwiftWing

**Version:** 1.0
**Date:** 2026-01-22
**Status:** Draft
**Target Platform:** iOS 17.0+ (Current Generation Devices)

---

## Executive Summary

**SwiftWing** is a native iOS application that transforms book spine scanning into a frictionless experience. Using advanced camera technology and AI-powered analysis via the Talaria backend, SwiftWing enables users to build and manage their personal library with a simple tap.

**Core Value Proposition:**
- **Zero-lag camera** - See your bookshelf instantly
- **One-tap scanning** - Capture multiple spines in seconds
- **Real-time enrichment** - AI identifies and enriches books as you scan
- **Offline-first** - Works without connectivity, syncs when online
- **Swiss precision** - High-contrast UI optimized for OLED devices

---

## Project Goals

### Primary Objectives

1. **Instant Capture** - Cold start to live camera feed in < 0.5 seconds
2. **Rapid Scanning** - Process 10+ book spines per minute
3. **High Accuracy** - 95%+ successful identification rate via Talaria AI
4. **Native Performance** - 60 FPS UI, no jank during scanning
5. **Data Ownership** - Full local storage with CSV export capability

### Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Camera Launch Time | < 0.5s | Instrumentation |
| Scan Success Rate | > 95% | Analytics |
| App Rating | > 4.5 stars | App Store |
| Daily Active Users | 1K+ | Analytics |
| Crash-Free Sessions | > 99.5% | Crash reporting |

---

## Target Audience

### Primary Users

**Book Collectors & Enthusiasts**
- Own 100+ physical books
- Want digital catalog without manual entry
- Value speed and accuracy over customization
- Appreciate minimal, functional design

**Demographics:**
- Age: 25-55
- Tech-savvy iOS users
- Own current-gen iPhones (iPhone 14+)
- Prefer native apps over web tools

### Use Cases

1. **New Collection Inventory** - Scan entire bookshelf in one session
2. **Book Shopping** - Check if book is already owned while browsing
3. **Library Management** - Quick lookup and search of owned books
4. **Data Portability** - Export collection for other tools/services

---

## Technical Stack

### Frontend (iOS)

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| UI Framework | **SwiftUI** | Declarative, native performance, modern |
| State Management | **Observation Framework** | iOS 17+ replacement for Combine/ObservableObject |
| Data Persistence | **SwiftData** | Modern Core Data replacement, SwiftUI integration |
| Concurrency | **Swift 6 (async/await, actors)** | Thread-safe, compiler-enforced |
| Camera | **AVFoundation** | Low-level control, maximum performance |
| Networking | **URLSession** | Native, no third-party dependencies |
| Real-time Updates | **Server-Sent Events (SSE)** | One-way streaming from backend |

### Backend Integration

| Service | Endpoint | Purpose |
|---------|----------|---------|
| **Talaria API** | POST /v3/jobs/scans | Image upload & job creation |
| **SSE Stream** | GET {streamUrl} | Real-time progress & results |
| **Cleanup** | DELETE /v3/jobs/scans/{jobId}/cleanup | Resource cleanup |

### Minimum Requirements

- **iOS:** 17.0+
- **Device:** iPhone 14 or newer (A15 Bionic+)
- **Storage:** 100 MB app + user data
- **Network:** Optional (offline-capable)

---

## Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    SwiftUI Layer                        │
│  • CameraView (AVFoundation preview)                    │
│  • LibraryGridView (LazyVGrid + AsyncImage)            │
│  • BookDetailSheet (Metadata editing)                   │
└────────────────┬────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────────┐
│              ViewModel Layer (@Observable)              │
│  • CameraViewModel                                      │
│  • LibraryViewModel                                     │
│  • ScanJobViewModel                                     │
└────────────────┬────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────────┐
│                 Actor-Based Services                    │
│  • CameraActor (AVCaptureSession isolation)            │
│  • NetworkActor (HTTP + SSE)                            │
│  • DataSyncActor (SwiftData writes)                     │
└────────────────┬────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────────┐
│              Data Layer (SwiftData)                     │
│  • Book @Model                                          │
│  • ScanJob @Model                                       │
│  • ModelContainer (persistent store)                    │
└─────────────────────────────────────────────────────────┘
```

### Concurrency Model

**Actors for Isolation:**
- `CameraActor` - Manages AVCaptureSession, prevents data races
- `NetworkActor` - Handles uploads and SSE streams
- `DataSyncActor` - Coordinates SwiftData writes

**AsyncStream for SSE:**
```swift
actor NetworkActor {
    func streamEvents(from url: URL) -> AsyncThrowingStream<SSEEvent, Error> {
        // Wrap SSE connection in async stream
    }
}
```

**Main Actor for UI:**
```swift
@MainActor
@Observable
class CameraViewModel {
    var isScanning: Bool = false
    var activeJobs: [ScanJob] = []
}
```

---

## Core Features

### Epic 1: Foundations & Architecture

**Scope:**
- Project setup with SwiftData + Observation
- Swiss Utility design system
- Secure device identity (Keychain)
- Offline-first network layer

**Technical Requirements:**
- Bundle ID: `com.ooheynerds.swiftwing`
- Min Deployment: iOS 17.0
- SwiftData container configuration
- Network path monitoring with `NWPathMonitor`

---

### Epic 2: The Viewfinder (Capture)

**Scope:**
- Zero-lag camera initialization
- Non-blocking shutter action
- Background image processing
- Manual focus & zoom controls

**Key Features:**

#### Camera Feed
- **Performance Target:** < 0.5s cold start
- **Frame Rate:** 30 FPS (balance quality vs battery)
- **Pixel Format:** YUV 420 for efficiency
- **Preview:** Full-screen with status bar hidden

#### Shutter Mechanics
- **UI:** 80px white ring at bottom center
- **Feedback:** Haptic impact + white flash overlay
- **Behavior:** Non-blocking (rapid-fire capable)

#### Image Processing
- **Isolation:** `Task.detached` with `.userInitiated` priority
- **Resize:** Max 1920px long-edge
- **Compression:** JPEG quality 0.85
- **Storage:** FileManager temp directory

#### Processing Queue UI
- **Layout:** Horizontal ScrollView above shutter
- **Items:** 40x60px thumbnails
- **State Colors:**
  - Yellow border: Uploading
  - Blue border: Analyzing
  - Green border: Done

---

### Epic 3: The Talaria Link (Integration)

**Scope:**
- Multipart image upload
- Server-Sent Events (SSE) listener
- Real-time progress visualization
- Result handling & data persistence

**API Flow:**

```
1. Capture Image
   ↓
2. POST /v3/jobs/scans
   ← 202 { jobId, streamUrl }
   ↓
3. Open SSE Stream (streamUrl)
   ← event: progress → "Looking..."
   ← event: progress → "Reading..."
   ← event: result → { isbn, title, author, ... }
   ← event: complete
   ↓
4. Save to SwiftData
   ↓
5. DELETE /v3/jobs/scans/{jobId}/cleanup
```

**Error Handling:**
- **429 Too Many Requests:** Disable shutter, show countdown
- **Network Loss:** Queue locally, retry when online
- **Timeout:** 5-minute max per SSE stream
- **Retry Logic:** Exponential backoff (1s, 2s, 4s max 3 attempts)

---

### Epic 4: The Library (SwiftData)

**Scope:**
- SwiftData schema definition
- Library grid view with lazy loading
- Real-time list updates via `@Query`
- Full-text search
- Review-needed indicator

**Data Model:**

```swift
@Model
final class Book {
    @Attribute(.unique) var isbn: String
    var title: String
    var author: String
    var coverUrl: URL?
    var format: String?
    var addedDate: Date
    var spineConfidence: Double?

    // Computed
    var needsReview: Bool {
        guard let confidence = spineConfidence else { return false }
        return confidence < 0.8
    }
}
```

**UI Components:**
- **Grid:** LazyVGrid with adaptive columns (min 100px)
- **Search:** `.searchable()` with predicate filtering
- **Sort:** Default by `addedDate` descending
- **Empty State:** ContentUnavailableView with instructions

---

### Epic 5: Detail & Interaction

**Scope:**
- Minimal book detail sheet
- Raw JSON toggle
- Context menu delete
- Haptic feedback strategy
- Cache management

**Book Detail Sheet:**
- **Presentation:** `.sheet()` with `.medium` / `.large` detents
- **Layout:** HStack { Cover | VStack { Metadata } }
- **Edit Mode:** Inline TextFields for corrections
- **Raw View:** Monospaced JSON in green syntax highlighting

**Haptic Strategy:**
| Action | Feedback Type |
|--------|---------------|
| Shutter tap | `.impact` |
| Scan success | `.success` |
| Error/retry | `.error` |

---

### Epic 6: Polish & Launch

**Scope:**
- App icon & launch screen
- Permission priming screens
- Empty state designs
- Error overlay system

**App Icon:**
- Solid black background
- White abstract wing glyph
- Adaptive for iOS

**Launch Screen:**
- Black background (#000000)
- "SwiftWing" in JetBrains Mono
- Fade out after 500ms or camera ready

---

## Design Language: Swiss Glass Hybrid

### Visual Principles

**Philosophy:** Blend high-contrast minimalism with iOS 26's Liquid Glass aesthetic. Precision meets platform convention.

**Balance:** 60% Swiss Utility / 40% Liquid Glass

### Typography

| Usage | Typeface | Weight | Size | Rationale |
|-------|----------|--------|------|-----------|
| Data/IDs | JetBrains Mono | Regular | 16-24pt | Brand identity |
| UI Labels | San Francisco Pro | Regular | 14-16pt | Native readability |
| Captions | San Francisco Pro | Medium | 12pt | iOS convention |

### Color Palette

```swift
extension Color {
    static let swissBackground = Color.black          // #000000 (Swiss)
    static let swissText = Color.white                // #FFFFFF (Swiss)
    static let internationalOrange = Color(           // #FF3B30 (Swiss accent)
        red: 1.0, green: 0.23, blue: 0.19
    )
}
```

**Usage:**
- Background: Pure black (OLED optimization, Swiss base)
- Text: Pure white (maximum contrast, Swiss)
- Accent: International Orange (CTAs, borders, Swiss identity)
- Glass: `.ultraThinMaterial` for overlays (Liquid Glass)

### UI Components

**Materials (Liquid Glass):**
```swift
.background(.ultraThinMaterial)     // Translucent overlays
.background(.thinMaterial)          // Menus, sheets
```

**Corners & Shapes:**
```swift
.clipShape(RoundedRectangle(cornerRadius: 12))  // Soft rounds (Glass)
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .stroke(.white, lineWidth: 2)  // White borders (Swiss)
)
```

**Shadows (Minimal):**
```swift
.shadow(color: .white.opacity(0.1), radius: 8)  // Subtle glow only
```

**Motion:**
```swift
.spring(duration: 0.2)  // Fluid animations (Glass)
.linear(duration: 0.1)  // Quick fades (Swiss)
```

**Haptics:**
```swift
.sensoryFeedback(.impact)     // Shutter
.sensoryFeedback(.success)    // Scan complete
.sensoryFeedback(.error)      // Error state
```

### Hybrid Design Examples

**Shutter Button:**
```swift
ZStack {
    Circle()
        .fill(.white.opacity(0.05))
        .background(.ultraThinMaterial.opacity(0.3), in: Circle())  // Glass
    Circle()
        .stroke(.white, lineWidth: 4)  // Swiss precision
}
.frame(width: 80, height: 80)
.shadow(color: .white.opacity(0.1), radius: 8)  // Minimal glow
```

**Processing Queue Thumbnails:**
```swift
thumbnailView
    .frame(width: 40, height: 60)
    .background(.ultraThinMaterial)  // Glass effect
    .clipShape(RoundedRectangle(cornerRadius: 8))  // Rounded
    .overlay(
        RoundedRectangle(cornerRadius: 8)
            .stroke(stateColor, lineWidth: 2)  // Colored borders (Swiss)
    )
```

---

## User Flows

### Flow 1: First Launch → First Scan

```
1. Launch app
   ↓
2. Permission primer screen
   "SwiftWing needs camera to see books"
   [Continue] button
   ↓
3. System camera permission prompt
   ↓
4. Camera view (full screen, live feed)
   - Shutter button at bottom
   - Empty processing queue
   ↓
5. User taps shutter
   - Haptic feedback
   - White flash
   - Thumbnail appears in queue (yellow border)
   ↓
6. Image uploads → SSE stream opens
   - Border turns blue
   - "Reading..." text overlay
   ↓
7. Result arrives
   - Border turns green
   - Haptic success
   - Book added to library
   ↓
8. User swipes to Library tab
   - Book appears in grid
   - Cover image loads asynchronously
```

### Flow 2: Bulk Shelf Scanning

```
1. User opens to camera view
   ↓
2. Rapid-fire shutter taps (10+ scans)
   - Each tap adds thumbnail to queue
   - UI never blocks
   ↓
3. Processing happens in parallel
   - Multiple SSE streams active
   - Queue shows mixed states (yellow/blue/green)
   ↓
4. Results arrive out-of-order
   - Each success triggers haptic
   - Books appear in library in real-time
   ↓
5. All scans complete
   - Queue auto-clears after 5s per item
```

### Flow 3: Offline Scanning

```
1. Network disconnects mid-session
   ↓
2. "OFFLINE" indicator appears (top-right)
   ↓
3. User continues scanning
   - Images queue locally
   - Thumbnails show in queue (gray border)
   ↓
4. Network reconnects
   - "OFFLINE" indicator disappears
   - Queued images auto-upload
   - SSE streams open for all queued jobs
```

---

## Non-Functional Requirements

### Performance

| Metric | Target | Critical Path |
|--------|--------|---------------|
| Camera cold start | < 0.5s | App launch → live feed |
| Shutter responsiveness | < 50ms | Tap → haptic + flash |
| Image processing | < 500ms | Capture → upload ready |
| UI frame rate | > 55 FPS | During active scanning |
| SSE connection time | < 200ms | Upload response → stream open |

### Reliability

- **Crash-Free Rate:** > 99.5%
- **Data Loss:** Zero tolerance (all scans must persist or retry)
- **Offline Mode:** 100% functional camera, queues sync on reconnect

### Security

- **Device ID:** Stored in iOS Keychain (survives app reinstall)
- **API Keys:** Never in source code (environment or secure backend)
- **Image Data:** Deleted from temp directory after upload
- **Network:** TLS 1.3+ for all Talaria communication

### Privacy

- **Camera Usage:** Explicit permission with clear primer
- **Data Collection:** Only device ID + scanned book metadata
- **Analytics:** Opt-in, anonymized crash/performance data
- **No Tracking:** No third-party SDKs, no ads

### Accessibility

- **Dynamic Type:** Support system font scaling
- **VoiceOver:** Label all interactive elements
- **Haptics:** Provide visual alternatives for deaf users
- **Contrast:** WCAG AAA (black/white already compliant)

---

## Dependencies & Integrations

### External Services

| Service | Purpose | Criticality | Fallback |
|---------|---------|-------------|----------|
| Talaria Backend | Book recognition & enrichment | Critical | Offline queue |
| Cover Image CDN | Book cover downloads | Medium | Gray placeholder |

### Third-Party Libraries

**None.** SwiftWing uses only native Apple frameworks to minimize dependencies and maximize performance.

---

## Assumptions & Constraints

### Assumptions

1. **Talaria API** is stable and available 99.9% uptime
2. **iOS 17+** adoption is sufficient in target market (iPhone 14+)
3. Users have **network connectivity** most of the time (offline is secondary)
4. Book **ISBN barcodes** are reliably extracted from spine images
5. Users scan **< 100 books per session** on average

### Constraints

1. **iOS Only** - No Android, web, or tablet versions in MVP
2. **English Language** - UI text in English only initially
3. **Rate Limits** - Talaria enforces per-device daily scan limits
4. **Camera Required** - App unusable without camera permission
5. **Current Gen Only** - No backward compatibility for iPhone 13 or older

---

## Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Talaria API downtime | High | Low | Local queue, retry logic, offline mode |
| iOS API changes (iOS 18) | Medium | Medium | Pin to iOS 17 SDK, test betas early |
| Poor lighting reduces accuracy | High | Medium | ML preprocessing, flash option, user guidance |
| Rate limit frustration | Medium | High | Clear messaging, countdown timer, daily quota display |
| Battery drain from camera | Medium | Medium | Auto-pause after 30s, optimize frame processing |

---

## Success Criteria (MVP)

### Must Have (P0)

- ✅ Camera launches in < 0.5s
- ✅ Non-blocking shutter allows rapid scanning
- ✅ SSE stream receives real-time updates
- ✅ Books persist to SwiftData
- ✅ Library grid displays with covers
- ✅ Offline mode queues scans
- ✅ Swiss Utility design fully implemented

### Should Have (P1)

- ✅ Manual focus and zoom
- ✅ Full-text search in library
- ✅ Processing queue UI with state colors
- ✅ Haptic feedback strategy
- ✅ Rate limit handling
- ✅ Permission priming screens

### Nice to Have (P2)

- ✅ Review-needed indicator
- ✅ CSV export
- ✅ Raw JSON toggle
- ✅ Cache management
- ✅ Empty states

### Future Enhancements (Post-MVP)

- Multi-language support (Spanish, French, etc.)
- iPad version with optimized layout
- Batch editing of metadata
- Collections/shelves organization
- Loan tracking (who borrowed what)
- Reading progress tracking
- Integration with Goodreads, LibraryThing

---

## Development Roadmap

### Phase 1: Foundation (Week 1-2)
- Project setup + SwiftData schema
- Swiss Utility design system
- Device ID + network layer
- **Milestone:** Clean build, basic UI shell

### Phase 2: Camera (Week 3-4)
- AVFoundation integration
- Shutter + image processing
- Processing queue UI
- **Milestone:** Can capture and process images locally

### Phase 3: Backend Integration (Week 5-6)
- Talaria API client
- SSE stream implementation
- Real-time result handling
- **Milestone:** End-to-end scan → enrichment → library

### Phase 4: Library & Polish (Week 7-8)
- Library grid + search
- Book detail sheet
- Error handling + offline mode
- **Milestone:** Feature complete MVP

### Phase 5: Testing & Launch (Week 9-10)
- Unit + integration tests
- Performance optimization
- App Store assets + submission
- **Milestone:** Live on App Store

---

## Open Questions

1. **Talaria API Rate Limits** - Exact quotas per device per day?
2. **Cover Image CDN** - CORS policy, rate limits, caching headers?
3. **Analytics Platform** - Firebase? TelemetryDeck? Native only?
4. **Crash Reporting** - Sentry? Bugsnag? None?
5. **Beta Testing** - TestFlight external beta size?
6. **App Store Pricing** - Free? Paid upfront? Freemium with IAP?
7. **Backend SLA** - What uptime guarantee does Talaria provide?

---

## Appendices

### Appendix A: Related Documents

- [US-swift.md](US-swift.md) - Detailed user stories (US-101 to US-130)
- [findings.md](findings.md) - Technical research and decisions
- [task_plan.md](task_plan.md) - Development task plan
- [flutter-legacy/prd.json](flutter-legacy/prd.json) - Flutter version reference

### Appendix B: Glossary

| Term | Definition |
|------|------------|
| **SSE** | Server-Sent Events - one-way streaming protocol |
| **SwiftData** | Apple's modern persistence framework (iOS 17+) |
| **Actor** | Swift concurrency primitive for thread-safe isolation |
| **Talaria** | Backend service providing AI book recognition |
| **Swiss Utility** | Design aesthetic: high contrast, minimal, functional |
| **MVP** | Minimum Viable Product |
| **P0/P1/P2/P3** | Priority levels (0=Critical, 3=Low) |

### Appendix C: Contact Information

**Product Owner:** [TBD]
**Lead Developer:** [TBD]
**Backend Team:** Talaria API team
**Design:** Swiss Utility aesthetic (no external designer)

---

**Document Status:** Draft
**Next Review:** After user feedback on scope
**Approval Required:** Product Owner, Engineering Lead
