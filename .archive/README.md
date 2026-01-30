# SwiftWing Archive

This directory contains completed planning files, historical documentation, and resolved issue tracking.

## Directory Structure

```
.archive/
├── planning/
│   ├── epics/           # Completed epic planning (Epics 1-5)
│   ├── user-stories/    # Completed user story planning (US-401, 408, etc.)
│   └── *.md            # Miscellaneous completed planning
├── legacy/              # Deprecated implementations (Flutter)
└── WARNINGS_RESOLVED.md # Historical warning fixes
```

## Files in This Archive

### Planning Files (Completed Work)

All `*_task_plan.md`, `*_findings.md`, and `*_progress.md` files represent completed work using the planning-with-files methodology:
- **task_plan.md** - Structured plan with phases and decision log
- **findings.md** - Root cause analysis and technical discoveries
- **progress.md** - Session log and timeline

### Epic Planning (Epics 1-5 Complete)
- `build_fix_*.md` - Build failure resolution (Epic 1-2)
- `warnings_fix_*.md` - Warning elimination (Epic 5)
- `epic5_review_*.md` - Epic 5 code review outcomes
- `e2e_validation_*.md` - End-to-end validation (Epic 5)
- `fix_review_*.md` - Code review fixes (Epic 5)
- `pre-epic3-cleanup-plan.md` - Technical debt cleanup (pre-Epic 3)
- `epic6_*.md` - Epic 6 planning (App Store Launch)

### User Story Planning (All Complete)
- `us401_*.md` - US-401: SSE streaming performance
- `us408_*.md` - US-408: Rate limit handling
- `US-410_*.md` - US-410: Stream concurrency management
- `us504_*.md` - US-504: Processing queue UI
- `us509_*.md` - US-509: TalariaService benchmarks
- `us510_*.md` - US-510: Network error handling

### Feature Documentation
- `camera-rotation-fix-summary.md` - Camera rotation bug fix (Jan 30, 2026)
- `ROTATION-FIX-TESTING.md` - Rotation testing guide

### Resolved Issues
- `WARNINGS_RESOLVED.md` - All 14 warnings eliminated (Epic 5)

## Active Planning Files (NOT in Archive)

Current work uses these files in the **project root**:
- `/task_plan.md` - Active task plan
- `/findings.md` - Current research findings
- `/progress.md` - Session progress log

## Archival Policy

Files are moved to `.archive/` when:
1. ✅ Work is complete and merged
2. ✅ All acceptance criteria met
3. ✅ Tests passing
4. ✅ No longer referenced in active planning

## Retrieval

To reference archived planning:
```bash
# Search for specific topic
grep -r "SSE streaming" .archive/

# Find all files for a user story
ls .archive/planning/user-stories/us408_*

# View completed epic planning
cat .archive/planning/epics/epic5_review_task_plan.md
```

---

**Archive Created:** January 30, 2026
**SwiftWing Version:** Epic 5 (Refactoring) → Epic 6 (Launch)
