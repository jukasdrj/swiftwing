# Planning-with-Files — Policy & Workflow

## When Planning is REQUIRED

Create planning files (see below) before starting any task that involves >4 tool calls, >3 files, or any build failure diagnosis. This is not optional. There is no `/planning-with-files` slash command in this repo — the policy lives in this rules file.

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
2. **`{task}_findings.md`** — root cause and the fix that addresses it
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

1. Create the planning files listed above. There is no slash command that creates them.
2. Diagnose from the code and from `xcodebuild ... | xcsift`. Write the cause in the findings file.
3. Execute plan phase by phase; log errors as you go.
4. Mark phases complete only when verified.
5. Build verify: `xcodebuild ... | xcsift` → 0 errors, 0 warnings.
6. Delete or archive planning files after the task completes.

## If Going in Circles

Stop. Write down what has already been tried in the findings file, then change approach. Never repeat the same fix twice without logging it first.
