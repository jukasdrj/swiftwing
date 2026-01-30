# SwiftWing Documentation for AI Agents

**Last Updated:** January 30, 2026
**Purpose:** Organized project documentation for AI agent navigation and context gathering

---

## Quick Navigation

| Category | Purpose | Key Files |
|----------|---------|-----------|
| **Architecture** | Design decisions and vertical slice strategy | `architecture/DESIGN-DECISION.md`, `VERTICAL-SLICES.md`, `EPIC-ROADMAP.md` |
| **Testing** | Comprehensive test coverage and validation results | `testing/TEST_COVERAGE_SUMMARY.md`, `TESTING-CHECKLIST.md` |
| **Guides** | User story completion procedures and checklists | `guides/US-504-COMPLETION-GUIDE.md`, `US-408-TEST-INSTRUCTIONS.md` |

---

## Documentation Structure

### Root Level (Parent Reference: `../`)

**Essential Project Files:**
- `../CLAUDE.md` - **AI Agent Instructions** (REQUIRED - read first for all tasks)
- `../PRD.md` - Complete Product Requirements Document
- `../START-HERE.md` - Project orientation for new contributors
- `../CURRENT-STATUS.md` - Real-time project status
- `../PRIVACY.md`, `../TERMS.md` - Legal documentation

**Planning & Task Tracking:**
- `../task_plan.md` - Active task phases with completion status
- `../findings.md` - Technical research discoveries and decisions
- `../progress.md` - Session-by-session progress log

**Epic Documentation:**
- `../EPIC-1-STORIES.md` - Foundation epic user stories
- `../EPIC-5-REVIEW-SUMMARY.md` - Epic 5 code review outcomes
- `../US-swift.md` - 30 Swift migration user stories

---

## Documentation by Category

### 1. Architecture (`docs/architecture/`)

**Purpose:** Design decisions and system architecture documentation

#### Files

| File | Purpose | Key Content |
|------|---------|-------------|
| **DESIGN-DECISION.md** | Swiss Glass theme selection | Design language rationale: Swiss Utility vs Liquid Glass (60/40 hybrid) |
| **VERTICAL-SLICES.md** | Epic-based development strategy | Feature-complete slices (UI → Logic → Data → Network per epic) |
| **EPIC-ROADMAP.md** | 6-epic progression plan | Epic sequence: Foundation → Camera → Library → AI → Polish → Launch |

#### When AI Agents Should Reference

- **Architecture decisions:** Read `DESIGN-DECISION.md` for iOS 26 design language constraints
- **Feature planning:** Study `VERTICAL-SLICES.md` to understand epic structure and acceptance criteria
- **Project scope:** Review `EPIC-ROADMAP.md` to understand current epic progress and dependencies
- **System design:** All three files together provide complete system architecture context

#### Key Concepts from Architecture Docs

**Swiss Glass Hybrid Design:**
- 60% Swiss Utility (minimalist, high contrast, precision)
- 40% Liquid Glass (iOS 26 native, translucent, fluid)
- Colors: Black (#0D0D0D) background, white text, international orange accent
- Typography: JetBrains Mono for data, SF Pro for UI
- Materials: `.ultraThinMaterial` for glass effects, 12px rounded corners

**Vertical Slice Development:**
- Each epic delivers ONE complete feature across all layers
- Not horizontal slicing (layers) but vertical (features)
- Epic 1: Foundation (skeleton architecture)
- Epic 2: Camera (AVFoundation + preview)
- Epic 3: Library (LazyVGrid + search)
- Epic 4: AI Integration (Talaria SSE + enrichment)
- Epic 5: Refactoring (MVVM + optimization)
- Epic 6: App Store launch

**Architecture Pattern:**
```
SwiftUI Views → @Observable ViewModels → Actor Services → SwiftData Models
```

---

### 2. Testing (`docs/testing/`)

**Purpose:** Test strategy, coverage reports, and validation documentation

#### Files

| File | Purpose | Content | Coverage |
|------|---------|---------|----------|
| **TEST_COVERAGE_SUMMARY.md** | Integration test overview | 6 end-to-end scenarios, 650 LOC, TalariaService 100% coverage | Network, SSE, SwiftData |
| **TESTING-CHECKLIST.md** | Pre-release test procedures | Manual testing checklist, acceptance criteria | UI, flow, edge cases |
| **INTEGRATION_TEST_SETUP.md** | Test infrastructure guide | MockURLProtocol, in-memory SwiftData, fixtures | Test framework |
| **E2E_VALIDATION_COMPLETE.md** | End-to-end validation results | Full workflow testing results, performance metrics | Complete flow |
| **PHASE-2A-TEST-RESULTS.md** | Epic 5 Phase 2A outcomes | Camera refactor test results | Camera ViewModel |
| **EPIC-5-PHASE-2A-AUTOMATED-TEST-REPORT.md** | Automated test report | Detailed test execution and results | All phases |

#### When AI Agents Should Reference

- **Before implementing features:** Read `TESTING-CHECKLIST.md` to understand acceptance criteria
- **After feature completion:** Verify test coverage in `TEST_COVERAGE_SUMMARY.md`
- **Understanding test infrastructure:** Study `INTEGRATION_TEST_SETUP.md` for mocking patterns
- **Debugging test failures:** Check `PHASE-2A-TEST-RESULTS.md` and `EPIC-5-PHASE-2A-AUTOMATED-TEST-REPORT.md` for patterns
- **End-to-end validation:** Reference `E2E_VALIDATION_COMPLETE.md` for complete workflow testing

#### Key Testing Information

**Test Coverage (Epic 4):**
- TalariaService: **100% coverage** (all endpoints, error cases, SSE streaming)
- Network layer: Multipart upload, SSE event parsing, cleanup
- SwiftData persistence: Book model validation, unique ISBN constraint
- Integration: Complete scan-to-library flow

**Test Scenarios (6 comprehensive flows):**
1. Happy path: Scan → Upload → SSE → Library → Cleanup
2. Error recovery: SSE error → Retry → Success
3. Rate limiting: 429 response with Retry-After handling
4. Timeout handling: Network timeout recovery
5. Offline queue: Offline capture → Background retry
6. Concurrent uploads: Multiple simultaneous scans

**Performance Baselines (from tests):**
- Camera cold start: < 0.5s
- Image processing: < 500ms
- SSE connection: < 200ms
- Upload latency: < 1000ms
- 5 concurrent uploads: < 10s total

---

### 3. Guides (`docs/guides/`)

**Purpose:** Detailed procedures for completing specific user stories

#### Files

| File | User Story | Purpose | Status |
|------|-----------|---------|--------|
| **US-504-COMPLETION-GUIDE.md** | US-504 | Type-safe Talaria client code generation | 80% complete (manual Xcode step required) |
| **US-408-TEST-INSTRUCTIONS.md** | US-408 | Performance testing procedures | Detailed manual test steps |
| **US-509_SUMMARY.md** | US-509 | Performance benchmarking results | Complete with metrics |
| **US-315-VOICEOVER-TEST.md** | US-315 | VoiceOver accessibility testing | Manual test procedures |

#### When AI Agents Should Reference

- **Implementing specific features:** Find the corresponding US-XXX guide
- **Testing procedures:** Use US-XXX guides for detailed manual test steps
- **Performance validation:** Reference `US-509_SUMMARY.md` for performance targets and measurement methods
- **Accessibility verification:** See `US-315-VOICEOVER-TEST.md` for VoiceOver testing procedures
- **OpenAPI setup:** Follow `US-504-COMPLETION-GUIDE.md` for client code generation steps

#### Key Procedures from Guides

**US-504 (OpenAPI Client Code):**
- Status: 80% complete (infrastructure in place)
- Pending: Manual Xcode UI step to enable build plugin
- Files: OpenAPI spec at `swiftwing/OpenAPI/talaria-openapi.yaml`
- Config: `openapi-generator-config.yaml` with Swift 6.2 settings
- Why not auto-generated yet: Focused on manual TalariaService implementation for rapid MVP

**US-408 (Performance Testing):**
- Comprehensive manual test procedures
- Camera start, image processing, network, UI metrics
- Targets: Camera < 0.5s, processing < 500ms, network < 200ms
- Tools: Instruments, timing functions, memory profiling

**US-509 (Performance Summary):**
- Benchmarking results across all epics
- Upload latency, SSE streaming, concurrent operations
- 100% of targets achieved in testing

---

## How AI Agents Should Use This Documentation

### Task: Implement a New Feature

1. **Start with architecture:** Read `docs/architecture/VERTICAL-SLICES.md` to understand epic structure
2. **Check design language:** Review `docs/architecture/DESIGN-DECISION.md` for UI constraints
3. **Find acceptance criteria:** Locate corresponding US-XXX in `docs/guides/`
4. **Understand test requirements:** Read `docs/testing/TESTING-CHECKLIST.md`
5. **Reference parent docs:** Check `../CLAUDE.md` for Swift 6.2 and actor patterns

### Task: Debug Build Failures

1. **Check project rules:** Review `../.claude/rules/build-workflow.md` (mandatory xcsift usage)
2. **Reference patterns:** Read `../CLAUDE.md` actor isolation section
3. **Test infrastructure:** See `docs/testing/INTEGRATION_TEST_SETUP.md` for mock patterns
4. **Architecture context:** Review `docs/architecture/VERTICAL-SLICES.md` if multi-epic impact

### Task: Add Tests

1. **Study coverage:** Read `docs/testing/TEST_COVERAGE_SUMMARY.md` for complete test patterns
2. **Check procedures:** Reference `docs/testing/INTEGRATION_TEST_SETUP.md`
3. **Review test results:** See `docs/testing/PHASE-2A-TEST-RESULTS.md` for similar test patterns
4. **Parent documentation:** Check `../CLAUDE.md` for actor-based testing patterns

### Task: Performance Optimization

1. **Check baselines:** Reference `docs/testing/TEST_COVERAGE_SUMMARY.md` or `docs/guides/US-509_SUMMARY.md`
2. **Review procedures:** See `docs/guides/US-408-TEST-INSTRUCTIONS.md`
3. **Architecture constraints:** Read `docs/architecture/VERTICAL-SLICES.md` for current design
4. **Parent performance guide:** Check `../CLAUDE.md` Performance Standards section

### Task: Design System/UI Work

1. **Understand theme:** Read `docs/architecture/DESIGN-DECISION.md` (Swiss Glass requirements)
2. **Check completed UI:** Review `docs/guides/US-315-VOICEOVER-TEST.md` for current UI state
3. **Architecture:** See `docs/architecture/VERTICAL-SLICES.md` for UI component patterns
4. **Parent design rules:** Check `../.claude/rules/swift-conventions.md` for theme constants

---

## Critical Information for AI Agents

### Project Configuration

**From `../CLAUDE.md` (REQUIRED READING):**
- Swift 6.2 strict concurrency enabled (data races are compilation errors)
- iOS 26.0+ minimum deployment
- MVVM architecture with actor-based services
- Zero warnings policy (0/0 errors/warnings required for all builds)
- Planning-with-files mandatory for tasks >4 tools or >3 decisions

**From `.claude/rules/`:**
- `build-workflow.md`: Always use `xcodebuild ... | xcsift` (never raw xcodebuild)
- `planning-mandatory.md`: Use `/planning-with-files` for complex tasks
- `swift-conventions.md`: Actor patterns, SwiftData access patterns
- `swiftdata-patterns.md`: ModelContext vs ModelContainer rules

### Key SwiftData Pattern (Critical)

**From `../.claude/rules/swiftdata-patterns.md`:**

**CORRECT:**
```swift
@Environment(\.modelContext) private var modelContext
let container = modelContext.container  // Access container via modelContext
```

**WRONG (Will cause compiler error):**
```swift
@Environment(\.modelContainer) private var modelContainer  // ❌ Does not exist
```

### Concurrency Rules

**From `../CLAUDE.md`:**
- ✅ Use `actor` for mutable shared state
- ✅ Use `@MainActor` for all UI updates
- ✅ Use structured concurrency (TaskGroup, async let)
- ❌ Never use DispatchQueue with async/await (deadlock risk)
- ❌ Never use Task.detached (breaks actor isolation)

---

## Directory Map for Quick Access

```
docs/
├── AGENTS.md (← You are here)
│
├── README.md
│   └── Documentation index and directory structure
│
├── architecture/
│   ├── DESIGN-DECISION.md
│   │   └── Swiss Glass theme selection rationale
│   ├── VERTICAL-SLICES.md
│   │   └── Epic-based development strategy
│   └── EPIC-ROADMAP.md
│       └── 6-epic progression plan
│
├── testing/
│   ├── TEST_COVERAGE_SUMMARY.md
│   │   └── Integration test overview (100% TalariaService coverage)
│   ├── TESTING-CHECKLIST.md
│   │   └── Pre-release test procedures
│   ├── INTEGRATION_TEST_SETUP.md
│   │   └── Test infrastructure and fixtures
│   ├── E2E_VALIDATION_COMPLETE.md
│   │   └── End-to-end validation results
│   ├── PHASE-2A-TEST-RESULTS.md
│   │   └── Epic 5 Phase 2A outcomes
│   └── EPIC-5-PHASE-2A-AUTOMATED-TEST-REPORT.md
│       └── Detailed automated test execution
│
└── guides/
    ├── US-504-COMPLETION-GUIDE.md
    │   └── OpenAPI client code generation (80% complete)
    ├── US-408-TEST-INSTRUCTIONS.md
    │   └── Performance testing procedures
    ├── US-509_SUMMARY.md
    │   └── Performance benchmarking summary
    └── US-315-VOICEOVER-TEST.md
        └── VoiceOver accessibility testing
```

---

## Architecture Overview (For Context)

**Current Project Status:**
- Epic 1 (Foundation): ✅ Complete - Grade A (95/100)
- Epic 2 (Camera): ✅ Complete - Grade A (98/100)
- Epic 3 (Library): ✅ Complete - Grade A (97/100)
- Epic 4 (AI Integration): ✅ Complete - Grade A (99/100)
- Epic 5 (Refactoring): 🔄 In Progress - Phases 2A-2E complete
- Epic 6 (App Store Launch): ⚪ Pending

**Key Architectural Patterns:**
1. **MVVM + Actors:** SwiftUI Views → @Observable ViewModels → Actor Services
2. **Vertical Slices:** Each epic delivers complete feature (UI through database)
3. **Swift 6.2 Concurrency:** Strict data race prevention, structured concurrency only
4. **SwiftData:** In-app persistence with `@Model` classes and `@Query`
5. **Network:** TalariaService actor for Talaria API with SSE streaming

**Design System:**
- Swiss Glass Hybrid (60% Swiss Utility + 40% Liquid Glass)
- Black base (#0D0D0D), white text, international orange accents
- JetBrains Mono for data, SF Pro for UI
- 12px rounded corners, `.ultraThinMaterial` glass effects

---

## References

- **Parent Directory:** `../README.md` (main documentation index)
- **Agent Instructions:** `../CLAUDE.md` (REQUIRED - read for all tasks)
- **Quick Start:** `../START-HERE.md`
- **Rules:** `../.claude/rules/` (swift-conventions, build-workflow, planning-mandatory, etc.)

---

**For questions about documentation organization, see `docs/README.md`**
**For AI agent instructions, see `../CLAUDE.md`**
**For quick project orientation, see `../START-HERE.md`**
