# SwiftWing Documentation

## Quick Navigation

| Category | Location | Description |
|----------|----------|-------------|
| **Start Here** | [`/START-HERE.md`](../START-HERE.md) | Project orientation guide |
| **Architecture** | [`architecture/`](architecture/) | Design decisions and patterns |
| **Testing** | [`testing/`](testing/) | Test strategy and results |
| **Guides** | [`guides/`](guides/) | User story completion guides |

## Core Documentation (Root Level)

### Essential Reading
- **[CLAUDE.md](../CLAUDE.md)** - Project-wide instructions for AI agents (REQUIRED)
- **[PRD.md](../PRD.md)** - Complete Product Requirements Document
- **[CURRENT-STATUS.md](../CURRENT-STATUS.md)** - Real-time project status
- **[START-HERE.md](../START-HERE.md)** - Entry point for new contributors

### Planning & Tracking
- **[task_plan.md](../task_plan.md)** - Active task plan with phases
- **[findings.md](../findings.md)** - Technical research and discoveries
- **[progress.md](../progress.md)** - Session progress log

### Epic Documentation
- **[EPIC-1-STORIES.md](../EPIC-1-STORIES.md)** - Epic 1 user stories (Foundation)
- **[EPIC-5-REVIEW-SUMMARY.md](../EPIC-5-REVIEW-SUMMARY.md)** - Epic 5 code review outcomes

### Compliance & Legal
- **[PRIVACY.md](../PRIVACY.md)** - Privacy policy
- **[TERMS.md](../TERMS.md)** - Terms of service
- **[APP_STORE_PRIVACY.md](../APP_STORE_PRIVACY.md)** - App Store privacy policy

### Requirements
- **[US-swift.md](../US-swift.md)** - Swift migration user stories (30 stories)

## Directory Structure

```
docs/
├── architecture/          # Design & architecture decisions
│   ├── DESIGN-DECISION.md      # Swiss Glass theme rationale
│   ├── VERTICAL-SLICES.md      # Epic-based development
│   └── EPIC-ROADMAP.md         # Epics 1-6 progression
│
├── testing/              # Testing documentation
│   ├── TESTING-CHECKLIST.md
│   ├── TEST_COVERAGE_SUMMARY.md
│   ├── INTEGRATION_TEST_SETUP.md
│   ├── E2E_VALIDATION_COMPLETE.md
│   ├── PHASE-2A-TEST-RESULTS.md
│   └── EPIC-5-PHASE-2A-AUTOMATED-TEST-REPORT.md
│
└── guides/               # User story guides
    ├── US-315-VOICEOVER-TEST.md
    ├── US-408-TEST-INSTRUCTIONS.md
    ├── US-504-COMPLETION-GUIDE.md
    └── US-509_SUMMARY.md
```

## Development Conventions

### Swift 6.2 & iOS 26
See [`.claude/rules/swift-conventions.md`](../.claude/rules/swift-conventions.md)

### Build Workflow
See [`.claude/rules/build-workflow.md`](../.claude/rules/build-workflow.md)

### Planning Requirements
See [`.claude/rules/planning-mandatory.md`](../.claude/rules/planning-mandatory.md)

---

**Documentation Last Updated:** January 30, 2026
