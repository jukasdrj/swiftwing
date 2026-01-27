---
argument-hint: [epic-number]
model: haiku
allowed-tools:
  - Bash
  - Read
---

# Epic Status Check

Show status for Epic **{{$1 | default: "5"}}**

```bash
cd /Users/juju/dev_repos/swiftwing
cat epic-{{$1 | default: "5"}}.json | grep -E '"status"|"title"|"completionPercentage"' | head -20
```

**Active Epics**:
- Epic 1: ✅ Foundation (Complete - Jan 22)
- Epic 2: ✅ Camera (Complete - Jan 23)
- Epic 3: ✅ Library (Complete - Jan 24)
- Epic 4: ✅ AI Integration (Complete - Jan 25)
- Epic 5: 🔄 Refactoring (In Progress)
- Epic 6: ⚪ App Store Launch (Pending)

**Current Phase**: Epic 5 Phase 2A-2E complete
**Next**: Epic 5 remaining phases, then Epic 6 launch prep

**Documentation**: See `EPIC-ROADMAP.md` for full overview
