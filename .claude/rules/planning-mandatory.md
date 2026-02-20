# Planning-with-Files — Policy & Workflow

## When Planning is REQUIRED

Use `/planning-with-files` before starting any task that involves >4 tool calls, >3 files, or any build failure diagnosis. This is not optional.

### Must use planning for:
- Build failures
- Multi-step features (>3 files touched)
- Architecture decisions
- Performance optimization
- Integration work (APIs, networking)
- Code review findings with multiple fixes
- Any time you are repeating fixes or going in circles

### Skip planning only for:
- Single-file edits (< 10 lines)
- Obvious one-line bug fixes
- Simple questions with no file changes
- Trivial renames or formatting

## Planning Files

Create these files (use a descriptive prefix, e.g. `camera_fix_`):

1. **`{task}_task_plan.md`** — goal, phases with status, decision log, error attempts table
2. **`{task}_findings.md`** — root cause, expert advice from PAL tools, solution approaches
3. **`{task}_progress.md`** (optional) — session log, test results, errors with resolutions

Planning files go in the project root. Archive or delete them when the task is complete.

## Error Tracking (Mandatory)

Log every failed attempt — prevents repeating the same fix:

```markdown
## Errors Encountered
| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| cannot find 'ImageCacheManager' | 1 | Added to Xcode | ✅ |
| actor isolation on urlSession | 2 | Used nonisolated(unsafe) | ✅ |
```

## Workflow

1. Invoke `/planning-with-files` — creates planning files
2. Run PAL tools for expert diagnosis, document findings
3. Execute plan phase by phase; log errors as you go
4. Mark phases complete only when verified
5. Build verify: `xcodebuild ... | xcsift` → 0 errors, 0 warnings
6. Delete or archive planning files after task completes

## PAL Tool Selection

| Situation | Tool |
|-----------|------|
| Build failure / data race | `mcp__pal__debug` |
| Architecture decision | `mcp__pal__thinkdeep` |
| Code quality review | `mcp__pal__codereview` |
| Multi-model consensus | `mcp__pal__consensus` |
| Code analysis | `mcp__pal__analyze` |

## Hook Enforcement

`.claude/hooks/enforce-planning.sh` scores task complexity on every prompt. Score ≥ 5 triggers a mandatory planning reminder. Override with `skip-planning` in prompt (for genuinely trivial tasks only).

## If Going in Circles

Stop. Invoke `/planning-with-files`. Document what has been tried. Use `mcp__pal__debug` or `mcp__pal__thinkdeep` with full context. Never repeat the same fix twice without logging it first.
