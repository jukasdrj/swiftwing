# Claude Code Configuration for SwiftWing

This directory contains rules and settings for Claude Code to follow when working on this project.

## Directory Structure

```
.claude/
├── README.md                          # This file
├── settings.json                      # Claude Code settings
├── rules/
│   ├── build-workflow.md             # MANDATORY xcodebuild + xcsift usage
│   ├── planning-mandatory.md         # MANDATORY planning-with-files for >4 tools
│   └── swiftdata-patterns.md         # SwiftData environment key patterns
├── skills/                            # Custom skills for Swift/iOS
│   ├── swiftui-pro/SKILL.md          # SwiftUI best practices
│   ├── swiftdata-pro/SKILL.md         # SwiftData patterns
│   ├── swift-testing-pro/SKILL.md     # Modern Swift Testing
│   ├── swift-concurrency-pro/SKILL.md # Concurrency correctness
│   ├── new-feature-slice.md           # Vertical slice development
│   └── run-contract-tests.md          # OpenAPI contract validation
└── agents/                            # Autonomous agents
    ├── talaria-contract-reviewer.md   # API contract validation
    └── swift-concurrency-reviewer.md  # Concurrency code review

## Related Documentation

- **Project AGENTS.md** — Agent-optimized architecture + skills catalog
- **Project CLAUDE.md** — Main guidance for Claude Code
- **Skills Manifest** — `skills/available.json` (machine-readable catalog)
- **PRD.md** — Product requirements
- Planning files (`*_task_plan.md`, `*_findings.md`) — Created per task

## Quick Start for Claude

**When starting ANY complex task:**
1. ✅ Read CLAUDE.md for project context
2. ✅ Read relevant rules from `.claude/rules/`
3. ✅ Invoke `/planning-with-files` if >4 tools needed
4. ✅ Use `xcodebuild ... | xcsift` for builds
5. ✅ Follow SwiftData patterns from `swiftdata-patterns.md`
6. ✅ Document everything in planning files

**Never:**
- ❌ Skip planning for complex tasks
- ❌ Call xcodebuild without xcsift
- ❌ Use non-existent environment keys
- ❌ Go in circles without documented attempts
