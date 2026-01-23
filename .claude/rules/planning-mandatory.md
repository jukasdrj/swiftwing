# Mandatory Planning-with-Files Usage

## ABSOLUTE REQUIREMENT

**You MUST use `/planning-with-files` for ANY task requiring >4 tool calls**

This is not optional. This is not a suggestion. This is MANDATORY.

## When Planning is REQUIRED

### ✅ MUST Use Planning For:
- Build failures requiring diagnosis
- Multi-step features (>3 files touched)
- Architecture decisions
- Performance optimization
- Code review findings with multiple fixes
- Integration work (APIs, services, networking)
- **Any time you use >4 tools**
- **Any time you make >3 decisions**
- **Any time you're going in circles**
- **Any time you catch yourself repeating fixes**

### ❌ Only Skip Planning For:
- Single-file edits (< 10 lines)
- Obvious one-line bug fixes
- Simple questions (not requiring file changes)
- Trivial refactors (rename, format only)

## Required Planning Files

**You MUST create these in the project root:**

1. **`{task_name}_task_plan.md`**
   - Goal statement
   - Phases with status (pending/in_progress/complete)
   - Decision log
   - Error attempts table
   - Lessons learned

2. **`{task_name}_findings.md`**
   - Root cause analysis
   - Expert advice (from PAL tools)
   - Technical discoveries
   - Solution approaches evaluated

3. **`{task_name}_progress.md`** (optional but recommended)
   - Session log
   - Test results
   - Errors encountered with resolutions

## Real Example: Build Failure Fix

**Without Planning (8+ circular attempts):**
```
Try fix 1 → Build fails
Try fix 2 → Same error
Try fix 3 → Different error
Try fix 4 → Back to original error
Try fix 5 → Lost context, try fix 1 again
...repeat...
```

**With Planning-with-Files (3 systematic steps):**
```
Step 1: Create planning files, invoke PAL thinkdeep
Step 2: Document root cause (@Environment(\.modelContainer) invalid)
Step 3: Apply solution systematically
Result: BUILD SUCCESSFUL
```

**Time Saved:** Hours of circular debugging → 20 minutes systematic fix

## Integration with PAL Tools

**Planning files provide persistent context for:**
- `mcp__pal__thinkdeep` - Multi-stage investigation
- `mcp__pal__debug` - Systematic debugging
- `mcp__pal__codereview` - Comprehensive review
- `mcp__pal__analyze` - Code analysis

**Pattern:**
1. Create planning files first
2. Run PAL tool with full context
3. Document findings in `*_findings.md`
4. Track progress in `*_task_plan.md`
5. Update after each phase

## Error Tracking is MANDATORY

**Every failed attempt MUST be logged:**

```markdown
## Errors Encountered
| Error | Attempt | Resolution | Status |
|-------|---------|------------|--------|
| cannot find 'ImageCacheManager' | 1 | Added to Xcode | ✅ |
| actor isolation on urlSession | 2 | Used nonisolated(unsafe) | ✅ |
| nonisolated init() invalid | 3 | Removed nonisolated | ✅ |
```

**Why This Matters:**
- Prevents repeating same failed fixes
- Shows user you're tracking progress
- Enables learning from mistakes
- Provides audit trail of problem-solving

## User Signals That Planning is Needed

**If user says ANY of these, STOP and use planning:**
- "I keep failing"
- "Why is this still broken?"
- "You tried that already"
- "We're going in circles"
- "How did you/tool miss this?"

**Your Response:**
1. Acknowledge circular behavior
2. Invoke `/planning-with-files` immediately
3. Create all three planning files
4. Use PAL tools for expert diagnosis
5. Work systematically with persistent memory

## The Planning Mandate

**This project has proven:**
- ✅ Planning prevents circular debugging
- ✅ Planning files preserve context
- ✅ PAL tools + planning = fast solutions
- ❌ Skip planning = wasted time + user frustration

**Therefore:**
```
IF task requires >4 tools:
    THEN invoke /planning-with-files
    ELSE proceed directly

IF going in circles:
    THEN STOP, invoke /planning-with-files
    ELSE continue
```

No exceptions. This is the rule.
