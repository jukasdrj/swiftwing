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
- **[START-HERE.md](../START-HERE.md)** - Entry point for new contributors

### Compliance & Legal
- **[PRIVACY.md](../PRIVACY.md)** - Privacy policy
- **[TERMS.md](../TERMS.md)** - Terms of service
- **[APP_STORE_PRIVACY.md](../APP_STORE_PRIVACY.md)** - App Store privacy policy

## Directory Structure

```
docs/
├── architecture/          # Design & architecture decisions
│   ├── DESIGN-DECISION.md      # Swiss Glass theme rationale
│   ├── VERTICAL-SLICES.md      # Epic-based development strategy
│   └── EPIC-ROADMAP.md         # Epics 1-6 progression (Epics 1-5 complete)
│
├── testing/              # Testing documentation
│   └── TESTING-CHECKLIST.md    # Active regression checklist (Epics 1-5 features)
│
└── guides/               # User story guides
    (completed story guides archived to .archive/docs/guides/)
```

> Archived docs: completed test reports and user-story guides for Epics 1-5 have been
> moved to `.archive/docs/` for historical reference.

## Development Conventions

### Swift 6.2 & iOS 26
See [`.claude/rules/swift-conventions.md`](../.claude/rules/swift-conventions.md)

### Build Workflow
See [`.claude/rules/build-workflow.md`](../.claude/rules/build-workflow.md)

### Planning Requirements
See [`.claude/rules/planning-mandatory.md`](../.claude/rules/planning-mandatory.md)

---

**Documentation Last Updated:** February 19, 2026
