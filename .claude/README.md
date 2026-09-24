# Agent configuration for SwiftWing

Rules, skills, commands, agents, and hooks for Grok and Claude Code. OpenCode loads `.claude/skills/<name>/SKILL.md` and `AGENTS.md`. It does not load `.claude/commands/`, `.claude/agents/`, or the hooks in `settings.json`.

## Layout

```
.claude/
├── settings.json           # Hooks and permissions
├── rules/                  # Build, planning, Swift, SwiftData
├── skills/<name>/SKILL.md  # Loaded by Grok and OpenCode
├── commands/               # /build-sim, /update-api (Grok)
├── agents/                 # Concurrency and Talaria reviewers (Grok)
└── hooks/                  # file-edit-guard.sh
```

## Skills

- `swiftui-pro`, `swiftdata-pro`, `swift-testing-pro`, `swift-concurrency-pro` — review and write against iOS 27 and Swift 6.4
- `new-feature-slice` — scaffold a feature slice
- `run-contract-tests` — Talaria contract tests only

A skill must be a directory containing `SKILL.md`. A loose `.md` file in `skills/` is ignored.

## When starting work

1. Read `CLAUDE.md` and `AGENTS.md`.
2. Read the rule that matches the change (build, Swift, SwiftData, or planning).
3. For a task that touches more than three files or a build failure, follow `rules/planning-mandatory.md`.
4. Build with `xcodebuild ... | xcsift` for iPhone 18 Pro Max. Warnings fail the build.
