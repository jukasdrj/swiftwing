# SwiftWing Planning Documentation

**Generated:** 2026-01-22
**Status:** Ready for User Review
**Methodology:** Planning-with-Files (Manus-style)

---

## 📋 What's Been Created

### Core Planning Files (in this directory)

| File | Lines | Purpose | Status |
|------|-------|---------|--------|
| **PRD.md** | ~700 | Complete Product Requirements Document | ✅ Ready |
| **DESIGN-DECISION.md** | ~400 | Design language choice analysis | 🚨 **Action Required** |
| **task_plan.md** | ~200 | Development roadmap with phases | ✅ Complete |
| **findings.md** | ~350 | Technical research & architecture decisions | ✅ Complete |
| **progress.md** | ~100 | Session log and timeline | ✅ Updated |
| **US-swift.md** | ~625 | User stories (30 stories) | ⚠️ Needs iOS 26 update |

---

## 🎯 Quick Start

### For Ralph-TUI Users

1. **Read DESIGN-DECISION.md** - Choose design language (A, B, or C)
2. **Review PRD.md** - Validate scope and technical approach
3. **Check findings.md** - Understand iOS 26 APIs and architecture
4. **Use task_plan.md** - Track development phases

### For Development Team

1. Start with **Epic 1: Foundations** (US-101 to US-104)
2. Reference **findings.md** for Swift 6.2 concurrency patterns
3. Follow **PRD.md** architecture diagram for module structure
4. Implement **iOS 26 Liquid Glass** (after design decision)

---

## 🚨 Critical Discovery

**iOS 26 is REAL and current** (released September 2025)

### Key Facts

- **iOS 26.2.1** is current version (January 2026)
- **Swift 6.2** released at WWDC '25
- **Liquid Glass** is the new design language
- **Zero Shutter Lag** API available
- Camera app completely redesigned

### Impact on Project

**Before Research:**
- Thought "iOS 26.1" was a typo or future version
- Planned "Swiss Utility" design language
- Referenced iOS 17 APIs

**After Research:**
- iOS 26 is confirmed and current
- Liquid Glass conflicts with Swiss Utility
- New camera APIs available (Zero Shutter Lag, AVCaptureEventInteraction)
- Swift 6.2 concurrency features

---

## 🎨 Design Language Decision Required

**User must choose:**

### Option A: Pure Liquid Glass
- Translucent, rounded, material-based
- Matches iOS 26 Camera app
- Platform-native, less distinctive

### Option B: Swiss Glass Hybrid (Recommended)
- Black background + glass overlays
- JetBrains Mono for data
- Unique identity + platform respect
- **60% Swiss / 40% Glass balance**

### Option C: Pure Swiss Utility
- Original vision from US-swift.md
- High-contrast, brutalist, 1px borders
- Maximum distinctiveness, fights platform

**See:** [DESIGN-DECISION.md](DESIGN-DECISION.md) for full analysis.

---

## 📊 Project Overview

### What is SwiftWing?

A native iOS 26 app that scans book spines using the camera and AI-powered recognition via the Talaria backend.

**Core Features:**
- Zero-lag camera (< 0.5s cold start)
- One-tap scanning (10+ books per minute)
- Real-time AI enrichment via SSE
- Offline-first with local queueing
- Library grid with search

**Technical Stack:**
- SwiftUI (declarative UI)
- SwiftData (persistence)
- Swift 6.2 Concurrency (actors, async/await)
- AVFoundation (camera)
- URLSession (SSE streaming)

---

## 🏗️ Architecture

```
SwiftUI Views
    ↓
ViewModels (@Observable)
    ↓
Actor Services (CameraActor, NetworkActor, DataSyncActor)
    ↓
SwiftData (Book @Model)
```

**Key Patterns:**
- **Actors** for isolated state (camera session, network, data sync)
- **AsyncStream** for Server-Sent Events
- **Structured concurrency** (no manual GCD)
- **@Observable** for reactive UI (replaces ObservableObject)

---

## 📈 Development Roadmap

### Phase 1: Foundation (Week 1-2)
- Project setup + SwiftData
- Design system (after user decision)
- Device ID + network layer

### Phase 2: Camera (Week 3-4)
- AVFoundation integration
- Zero Shutter Lag implementation
- Processing queue UI

### Phase 3: Backend Integration (Week 5-6)
- Talaria API client
- SSE streaming
- Real-time result handling

### Phase 4: Library & Polish (Week 7-8)
- Library grid + search
- Book detail sheets
- Error handling

### Phase 5: Testing & Launch (Week 9-10)
- Unit + integration tests
- Performance optimization
- App Store submission

**Total Estimate:** 10 weeks to MVP

---

## 🎯 Success Metrics

| Metric | Target |
|--------|--------|
| Camera Launch | < 0.5s |
| Scan Success Rate | > 95% |
| UI Frame Rate | > 55 FPS |
| Crash-Free Sessions | > 99.5% |
| App Rating | > 4.5 stars |

---

## 📚 Epic Breakdown

### Epic 1: Foundations & Architecture
- US-101: Xcode project setup
- US-102: Design system (Swiss/Glass/Hybrid)
- US-103: Device identity (Keychain)
- US-104: Offline-first network

### Epic 2: The Viewfinder (Capture)
- US-105: Zero-lag camera
- US-106: Non-blocking shutter
- US-107: Background image processing
- US-108: Processing queue UI
- US-109: Manual focus & zoom

### Epic 3: The Talaria Link
- US-110: Image upload (multipart)
- US-111: SSE listener
- US-112: Progress visualization
- US-113: Result handling
- US-114: Cleanup
- US-115: Rate limit handling

### Epic 4: The Library
- US-116: SwiftData schema
- US-117: Library grid
- US-118: Real-time updates
- US-119: Full-text search
- US-120: Review indicator
- US-121: CSV export

### Epic 5: Detail & Interaction
- US-122: Book detail sheet
- US-123: Raw JSON toggle
- US-124: Context menu delete
- US-125: Haptic feedback
- US-126: Cache management

### Epic 6: Polish & Launch
- US-127: App icon & launch screen
- US-128: Permission priming
- US-129: Empty states
- US-130: Error overlays

**Total:** 30 user stories across 6 epics

---

## 🔑 Key Technical Decisions

| Decision | Rationale |
|----------|-----------|
| Target iOS 26.0+ | Current generation, latest APIs |
| Swift 6.2 | Compile-time data race elimination |
| Actors for concurrency | Thread-safe, compiler-enforced |
| SwiftData | Modern, SwiftUI-native persistence |
| AsyncStream for SSE | Native async/await integration |
| No third-party deps | Maximum performance, minimal bloat |

---

## ⚠️ Open Questions

1. **Design Language** - Which option (A/B/C)?
2. **Talaria API** - Exact rate limits per device?
3. **Cover Image CDN** - CORS policy, caching headers?
4. **Analytics** - Which platform (Firebase, TelemetryDeck, none)?
5. **Crash Reporting** - Sentry, Bugsnag, or native only?
6. **App Store** - Pricing model (free, paid, freemium)?

---

## 📖 How to Use These Documents

### For Product Owners
1. Start with **PRD.md** - understand scope and business goals
2. Review **DESIGN-DECISION.md** - make design choice
3. Check **task_plan.md** - validate roadmap

### For Developers
1. Start with **findings.md** - understand iOS 26 APIs and patterns
2. Reference **PRD.md** - architecture and technical stack
3. Use **US-swift.md** - detailed acceptance criteria
4. Follow **task_plan.md** - phase-by-phase implementation

### For Designers
1. **DESIGN-DECISION.md** - choose design direction
2. **PRD.md** - design language section
3. **US-swift.md** - UI/UX requirements per story

### For Ralph-TUI
1. Next step: Generate JSON files from PRD + user stories
2. Create epic-1.json through epic-6.json
3. Map dependencies between user stories
4. Configure ralph-tui orchestration

---

## 🔄 Next Actions

### Immediate (User)
1. ✅ Read this README
2. 🚨 **Choose design language** (DESIGN-DECISION.md)
3. ✅ Review PRD.md and findings.md
4. ✅ Approve or request changes

### After User Approval
1. Update PRD design section with choice
2. Update US-swift.md with iOS 26 specifics
3. Generate ralph-tui JSON files
4. Begin Epic 1 implementation

---

## 📞 Questions or Feedback?

This planning documentation was created using the **planning-with-files** methodology:
- All research findings persisted to disk
- Critical decisions documented
- iOS 26 APIs researched via web search
- Design trade-offs analyzed

**Created by:** Claude Code with planning-with-files skill
**Research Sources:** Apple Developer Docs, Swift.org, iOS 26 release notes, HIG 2026

---

## 📎 Appendix: File Descriptions

### PRD.md
Comprehensive product requirements covering:
- Executive summary
- Target audience and use cases
- Technical stack and architecture
- All 6 epics with features
- Design language (Swiss Utility - needs update)
- User flows
- Non-functional requirements
- Risks and mitigations
- Development roadmap

### DESIGN-DECISION.md
Analysis of three design language options:
- Option A: Pure Liquid Glass
- Option B: Swiss Glass Hybrid (recommended)
- Option C: Pure Swiss Utility
- Visual comparisons
- Implementation examples
- Pros/cons for each

### findings.md
Technical research covering:
- iOS 26 confirmation and features
- Liquid Glass design language
- Swift 6.2 concurrency patterns
- Actor-based architecture
- iOS 26 camera APIs (Zero Shutter Lag, etc.)
- SwiftData schema design
- Performance optimization strategies
- Talaria backend integration
- Security and privacy

### task_plan.md
Development roadmap with:
- 7 phases from analysis to launch
- Completion status tracking
- Error log
- Decision log
- Dependencies

### progress.md
Session log showing:
- Timeline of work done
- Files created
- Critical discoveries (iOS 26!)
- Technical notes
- Questions for user

### US-swift.md (existing)
30 user stories organized by epic:
- Detailed acceptance criteria
- Priority levels (P0-P3)
- Estimates
- Dependencies
- Technical notes

---

**Status:** 📋 Planning Complete, 🚨 Design Decision Pending, ⏳ Ready for Implementation
