# Planning-with-Files Workflow with Specialist Agents

## Automated Enforcement

**Hook:** `.claude/hooks/enforce-planning.sh` runs on every prompt submission.

**Complexity Scoring:**
- High complexity patterns (build fail, debug, integrate): +3 points
- Medium complexity (implement, refactor): +2 points
- Multi-file indicators: +2 points
- Multi-step verbs (then, also, next): +1 point

**Threshold:** Score ≥5 triggers mandatory planning (equivalent to >3 tool calls expected)

**Override:** Add "skip-planning" to prompt (not recommended)

## Recommended Workflow for Complex Tasks

### Phase 1: Planning Setup
```bash
/planning-with-files
```

**Creates:**
- `{task_name}_task_plan.md` - Structured plan with phases
- `{task_name}_findings.md` - Research and discoveries
- `{task_name}_progress.md` - Session log (optional)

### Phase 2: Specialist Agent Execution (Concurrent)

**Use Task agents for parallel work:**

```swift
// Example: Build failure investigation
Task 1 (Explore): "Find all Swift files with AVFoundation imports"
Task 2 (Explore): "Locate SwiftData model definitions and @Query usage"
Task 3 (general-purpose): "Search for camera session configuration code"

// All run concurrently, results aggregated in planning files
```

**Available Specialist Agents:**
- `Explore` - Fast codebase exploration (quick/medium/thorough)
- `Plan` - Architecture planning and design
- `general-purpose` - Complex research and multi-step tasks
- `Bash` - Command execution (git, xcodebuild, etc.)

**Pattern for Concurrent Execution:**
```markdown
// In single message, launch multiple Task tool calls:
Task(subagent_type="Explore", prompt="...", description="...")
Task(subagent_type="Explore", prompt="...", description="...")
Task(subagent_type="general-purpose", prompt="...", description="...")
```

### Phase 3: PAL MCP Review (Quality Gate)

**After specialist agents complete, use PAL for validation:**

#### For Code Quality Review:
```javascript
mcp__pal__codereview({
    step: "Review specialist agent outputs for Swift 6.2 compliance",
    step_number: 1,
    total_steps: 2,
    next_step_required: true,
    findings: "Agent found 3 potential data race issues...",
    model: "grok-code-fast-1",  // Fast expert validation
    relevant_files: ["/absolute/path/to/file1.swift", "/absolute/path/to/file2.swift"]
})
```

#### For Debugging/Root Cause Analysis:
```javascript
mcp__pal__debug({
    step: "Analyze build failure from xcsift output",
    hypothesis: "Missing modelContext environment key",
    findings: "Specialist found @Environment(\.modelContainer) usage...",
    confidence: "medium",
    model: "grok-code-fast-1",
    relevant_files: ["/path/to/LibraryView.swift"]
})
```

#### For Architecture Decisions:
```javascript
mcp__pal__thinkdeep({
    step: "Evaluate actor isolation pattern for camera service",
    findings: "Agent discovered AVCaptureSession requires main queue...",
    hypothesis: "Need MainActor isolation, not generic actor",
    confidence: "high",
    model: "grok-code-fast-1"
})
```

#### For Multi-Model Consensus:
```javascript
mcp__pal__consensus({
    step: "Should SwiftWing use auto-generated OpenAPI client or manual TalariaService?",
    models: [
        {model: "grok-code-fast-1", stance: "for"},
        {model: "gemini-2.5-flash", stance: "against"},
        {model: "gemini-3-flash-preview", stance: "neutral"}
    ],
    findings: "Agent analyzed current manual implementation..."
})
```

### Phase 4: Implementation

**Execute plan with continuous updates:**
1. Mark phases as `in_progress` in `task_plan.md`
2. Log errors in errors table (never repeat failed fixes)
3. Update findings as new discoveries emerge
4. Mark phases `complete` only when verified

### Phase 5: Verification

**Build + Test:**
```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | xcsift
```

**Success Criteria:**
- 0 errors ✅
- 0 warnings ✅ (not negotiable)
- All phases marked complete
- Findings documented

## PAL Model Selection Strategy

**grok-code-fast-1:**
- Fast expert validation (256K context)
- Code generation and review
- Best for real-time feedback loops
- **Use for:** 80% of reviews

**gemini-3-flash-preview / gemini-3-pro-preview:**
- Deep reasoning (1M context, thinking mode)
- Complex architectural decisions
- **Use for:** Strategic planning, multi-model consensus

**gemini-2.5-flash:**
- General-purpose, reliable
- Good balance of speed and quality
- **Use for:** Routine analysis

## Real-World Example

**Task:** "Fix build failures after code review changes"

**Without Hook (Old Way):**
- Try random fixes
- Repeat same mistakes
- 8+ circular attempts
- Hours wasted

**With Hook + Planning (New Way):**
```bash
# Hook detects complexity (score: 12 - keywords: "fix", "build", "fail")
# ╔════════════════════════════════════════════╗
# ║  🚨 COMPLEXITY THRESHOLD EXCEEDED          ║
# ║  MANDATORY: Use /planning-with-files       ║
# ╚════════════════════════════════════════════╝

User: /planning-with-files

# Phase 1: Create planning files
# Phase 2: Launch specialist agents (concurrent)
#   - Task(Explore): Find all SwiftData environment usage
#   - Task(Explore): Locate @Model definitions
#   - Task(general-purpose): Search for modelContainer references

# Phase 3: PAL review with grok-code-fast-1
#   → Identifies: @Environment(\.modelContainer) doesn't exist
#   → Root cause: Should use @Environment(\.modelContext)

# Phase 4: Apply systematic fix
# Phase 5: Verify
#   → xcodebuild ... | xcsift
#   → Result: 0 errors, 0 warnings ✅

# Total time: 20 minutes (vs. hours of circular debugging)
```

## Hook Bypass (Emergency Use Only)

**To override planning requirement:**
```
User: "Fix this typo in README.md skip-planning"
```

**Valid bypass scenarios:**
- Single-line typo fixes
- Obvious one-character bugs
- Simple questions (no file changes)

**Invalid bypass usage:**
- Build failures (always complex)
- Multi-file refactors
- "Quick" architecture changes
- Performance optimization

## Success Metrics

**Planning Files Should Contain:**
- ✅ Clear goal statement
- ✅ 3-5 phases with status tracking
- ✅ Errors table (all failed attempts logged)
- ✅ Findings from specialist agents
- ✅ PAL review outcomes
- ✅ Final verification results

**If Missing Any Above:** Planning was not used correctly.

## Integration with SwiftWing Rules

**This workflow combines with:**
- `.claude/rules/build-workflow.md` - xcodebuild + xcsift requirement
- `.claude/rules/planning-mandatory.md` - Planning enforcement policy
- `.claude/rules/swiftdata-patterns.md` - Domain-specific rules

**Result:** Systematic, error-tracked, expert-validated development.
