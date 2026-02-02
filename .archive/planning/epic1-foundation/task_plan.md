# Task Plan: SwiftWing Project Documentation

**Goal:** Create comprehensive PRD and user stories for SwiftWing, a native iOS 26.1+ app that scans book spines using camera and connects to Talaria backend for AI analysis.

**Date Started:** 2026-01-22
**Status:** in_progress

---

## Context

SwiftWing is a complete rewrite of the Flutter-based Wingtip app, now targeting iOS 26.1+ exclusively with:
- **SwiftUI** for declarative UI
- **SwiftData** for local persistence
- **Modern Swift Concurrency** (async/await, actors, structured concurrency)
- **AVFoundation** for zero-lag camera capture
- **Server-Sent Events (SSE)** for real-time backend updates
- **"Swiss Utility" Design Language** - high contrast, minimal, precise

The app connects to the **Talaria backend** which provides AI-powered book spine recognition and metadata enrichment.

---

## Phases

### Phase 1: Analyze Existing Materials ✅
**Status:** complete
**Actions:**
- [x] Read US-swift.md (existing Swift user stories)
- [x] Read flutter-legacy/prd.json (Flutter version reference)
- [x] Understand app architecture and flow
- [x] Identify key technical requirements

**Findings:**
- 30 user stories already drafted for Swift (US-101 to US-130)
- Flutter version had comprehensive acceptance criteria
- Swiss Utility design language well-defined
- Core epics: Foundations, Viewfinder (Camera), Talaria Link, Library, Detail/Interaction, Polish

---

### Phase 2: Consult Grok for iOS 26.1 Best Practices ✅
**Status:** complete
**Actions:**
- [x] Request iOS development guidance from Grok
- [x] Get Swift concurrency patterns advice
- [x] Learn about iOS 17+ camera APIs (Note: iOS 26.1 likely refers to iOS 17+)
- [x] Understand performance optimizations

**Key Insights from Grok:**
- iOS 17+ is likely the actual target (iOS 26.1 may be version notation)
- Use **Actors** for camera session and SSE stream isolation
- **AsyncStream/AsyncThrowingStream** for SSE integration
- Enhanced AVFoundation APIs in iOS 17 (CameraControl framework)
- MVVM architecture recommended with actor-based services
- Performance: Target 30 FPS camera, use YUV format for efficiency

---

### Phase 3: Create Findings Document ✅
**Status:** complete
**Actions:**
- [x] Create findings.md
- [x] Document technical architecture decisions
- [x] Log iOS 26.1/17+ API recommendations
- [x] Note design patterns and trade-offs

**Output:** findings.md (~280 lines covering Swift concurrency, iOS 17 APIs, architecture, performance)

---

### Phase 4: Create Comprehensive PRD ✅
**Status:** complete
**Actions:**
- [x] Write executive summary
- [x] Define project scope and objectives
- [x] Document technical stack (SwiftUI, SwiftData, etc.)
- [x] Outline architecture patterns
- [x] Define success metrics
- [x] List assumptions and constraints
- [x] Create epic breakdown (all 6 epics)
- [x] Add user flows, non-functional requirements
- [x] Include risks, roadmap, and open questions

**Output:** PRD.md (~700 lines, comprehensive product requirements)

---

### Phase 5: Refine User Stories for Swift/iOS 26.1
**Status:** pending
**Actions:**
- [ ] Update existing US-swift.md user stories
- [ ] Incorporate iOS 17+ API recommendations from Grok
- [ ] Add Swift-specific acceptance criteria
- [ ] Update priority levels based on MVP requirements
- [ ] Add technical notes for SwiftData, actors, async/await patterns
- [ ] Ensure alignment with Talaria backend integration

**Output:** Updated `US-swift.md`

---

### Phase 6: Create Ralph-TUI JSON Files
**Status:** pending
**Actions:**
- [ ] Convert PRD to ralph-tui compatible JSON format
- [ ] Create epic-based JSON files (epic-1.json, epic-2.json, etc.)
- [ ] Ensure proper dependency mapping
- [ ] Validate JSON structure

**Output:** JSON files for ralph-tui orchestration

---

### Phase 7: Review and Validation
**Status:** pending
**Actions:**
- [ ] Cross-check all documents for consistency
- [ ] Verify technical feasibility of user stories
- [ ] Ensure complete coverage of app features
- [ ] Validate against Talaria backend capabilities
- [ ] Get user confirmation

---

## Dependencies

- US-swift.md (existing user stories)
- flutter-legacy/prd.json (reference architecture)
- Talaria backend API documentation (assumed available)
- iOS 17+ SDK documentation

---

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|
| flutter-legacy PRD.md not found | 1 | Found prd.json instead - using that |
| flutter-legacy US.md not found | 1 | Using prd.json which contains user stories |

---

## Decisions Made

| Decision | Rationale | Date |
|----------|-----------|------|
| Target iOS 17+ (not 26.1) | Grok clarified iOS 26.1 likely means iOS 17+ | 2026-01-22 |
| Use Actor pattern for camera/SSE | Thread-safety for concurrent operations | 2026-01-22 |
| Keep Swiss Utility design | Strong existing design language from US-swift.md | 2026-01-22 |
| MVVM + Actors architecture | Recommended pattern for SwiftUI + concurrency | 2026-01-22 |

---

## Next Steps

1. ✅ ~~Complete findings.md with technical recommendations~~
2. ✅ ~~Draft comprehensive PRD.md~~
3. 🚨 **USER DECISION REQUIRED:** Design language (see DESIGN-DECISION.md)
4. Update PRD and US-swift.md based on design choice
5. Enhance user stories with iOS 26 specific APIs
6. Create ralph-tui JSON files for orchestration

---

## ✅ Design Language Decision Made

**Choice:** Option B - Swiss Glass Hybrid (60% Swiss / 40% Glass)

**Implementation:**
- Black background (Swiss OLED optimization)
- Translucent overlays with `.ultraThinMaterial` (Liquid Glass)
- JetBrains Mono for data, SF Pro for UI (Hybrid typography)
- Rounded corners (12px) with white borders (Hybrid shapes)
- International orange accent (Swiss identity)

**Updated:** PRD.md design section reflects this choice.

**See:** [DESIGN-DECISION.md](DESIGN-DECISION.md) for full rationale.
