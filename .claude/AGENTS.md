# Claude Code Agent Configuration for SwiftWing

**Version:** 2.1.20+
**Last Updated:** January 30, 2026
**Project:** SwiftWing iOS 26 (Native Swift/SwiftUI)
**Status:** Epic 5 (Refactoring) - Active Development

---

## Purpose

This directory configures Claude Code's automated behavior for the SwiftWing iOS development project. It contains mandatory development conventions, automated enforcement hooks, custom workflows (skills), and helper commands that all AI agents MUST follow when working on this codebase.

**Key Principle:** SwiftWing enforces systematic development through planning, verification, and expert validation. No shortcuts.

---

## Directory Structure

```
.claude/
├── AGENTS.md (this file)           # Agent configuration and guidelines
├── README.md                         # Quick start for Claude Code
├── settings.json                     # Project settings (hooks, permissions)
├── VALIDATION-CHECKLIST.md          # Pre-commit and verification checklist
├── HOOK-SETUP-SUMMARY.md            # Hook configuration documentation
├── OPTIMIZATION_SUMMARY.md          # Performance optimization guidelines
│
├── rules/ (MANDATORY READING)        # Non-negotiable development rules
│   ├── swift-conventions.md          # Swift 6.2 & iOS 26 language rules
│   ├── build-workflow.md             # xcodebuild + xcsift requirement
│   ├── planning-mandatory.md         # Planning-with-files enforcement
│   ├── planning-workflow.md          # Planning + specialist agents workflow
│   └── swiftdata-patterns.md         # SwiftData environment patterns
│
├── hooks/ (AUTOMATED ENFORCEMENT)    # Trigger scripts on events
│   ├── README.md                     # Hook documentation
│   ├── enforce-planning.sh           # Complexity-based planning detection
│   └── pm-epic-review.sh             # Product manager workflow suggestion
│
├── skills/ (CUSTOM WORKFLOWS)        # Specialized task shortcuts
│   ├── gogo.md                       # Quick commit + push workflow
│   └── idb-ui-test.md                # iOS UI/UX testing with idb
│
├── commands/ (HELPER COMMANDS)       # Documented CLI helpers
│   ├── build-sim.md                  # Build for simulator shortcut
│   ├── epic-status.md                # Check epic progress
│   └── update-api.md                 # Update OpenAPI spec
│
├── plans/ (AUTO-GENERATED)           # Planning file outputs
│   └── {task}_task_plan.md           # Created by /planning-with-files
│
└── .gitignore                        # Excludes generated plans from git
```

---

## Quick Start for AI Agents

**When starting work on SwiftWing:**

### Step 1: Read These Files (IN ORDER)

1. **`../CLAUDE.md`** (project root)
   - Project overview, architecture, concurrency model
   - Build and run instructions
   - Epic-based development strategy
   - MUST read first to understand project context

2. **`.claude/rules/swift-conventions.md`**
   - Swift 6.2 language requirements
   - Actor patterns and MVVM architecture
   - SwiftData conventions
   - Performance standards

3. **`.claude/rules/build-workflow.md`**
   - xcodebuild + xcsift mandatory pattern
   - Build verification process
   - 0 errors, 0 warnings requirement

4. **`.claude/rules/planning-mandatory.md`**
   - When planning is REQUIRED (>4 tool calls)
   - Planning file structure and naming
   - Error tracking requirements

5. **`.claude/rules/swiftdata-patterns.md`**
   - @Environment(\.modelContext) vs @Environment(\.modelContainer)
   - Common mistakes and their fixes
   - Background task patterns

### Step 2: Understand Enforcement

The project uses **automated complexity detection** and **mandatory rules** to prevent circular debugging:

- **Hook: `enforce-planning.sh`** triggers when complexity score ≥5 (≈>3 tool calls)
- **Hook: `pm-epic-review.sh`** suggests PM workflow when user asks for status
- **Rule: Build workflow** requires xcodebuild piped through xcsift
- **Rule: Planning files** required for all complex tasks

### Step 3: Follow Rules

**Non-Negotiable Rules:**

| Rule | Enforced By | When Violated |
|------|------------|---------------|
| Use `xcodebuild \| xcsift` | You (code review) | No useful build output, circular debugging |
| Use `/planning-with-files` for >4 tools | Hook `enforce-planning.sh` | Execution blocked, warning shown |
| 0 errors, 0 warnings | Build step | Task marked incomplete |
| @Environment(\.modelContext) only | Compiler | Data race and environment errors |
| Document failed attempts | You (planning files) | Repeated same mistakes |

---

## Rules Directory: MANDATORY FOR ALL AGENTS

### `rules/swift-conventions.md`
**Read This First If:** Implementing Swift features, designing actors, using SwiftData

**Contents:**
- Swift 6.2 strict concurrency requirements
- Actor-based architecture patterns
- MVVM with @Observable view models
- SwiftData @Model conventions
- Vertical slice development (features, not layers)
- Performance targets (cold start <0.5s, 55 FPS UI, <500ms image processing)

**Key Rules:**
- ✅ Use actors for mutable shared state
- ✅ Use @MainActor for SwiftUI updates
- ✅ Use structured concurrency (TaskGroup, async let)
- ❌ Never mix DispatchQueue with async/await (deadlock risk)
- ❌ Never use Task.detached (breaks actor isolation)
- ❌ Never ignore Swift 6.2 concurrency warnings

**Real Example from Project:**
```swift
// ✅ CORRECT - Actor-isolated network service
actor TalariaService {
    private var urlSession: URLSession

    func uploadScan(image: Data) async throws -> (jobId: String, streamUrl: URL) {
        // Thread-safe network operations
    }
}

// ❌ WRONG - Not isolated
class TalariaService {  // Data races on urlSession
    var urlSession: URLSession
}
```

---

### `rules/build-workflow.md`
**Read This First If:** Building the project, debugging build failures, running CI

**Contents:**
- Mandatory xcodebuild + xcsift pattern
- Why xcsift is required (parses Xcode output to JSON)
- Build verification workflow
- Error diagnosis process
- Real example of build failure resolution

**Key Rule:**
```bash
# ✅ CORRECT - Always use xcsift
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift

# ❌ FORBIDDEN - Never use bare xcodebuild
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing build

# ❌ FORBIDDEN - xcsift is a formatter, not a build command
xcsift build
```

**Why:** xcsift parses unstructured build output into machine-readable JSON with error location and type, enabling automated diagnosis with PAL tools. Without it, build errors are unscannable.

**Build Success Criteria:**
- 0 errors (mandatory)
- 0 warnings (mandatory - not negotiable)
- Build time < 30s (clean)

---

### `rules/planning-mandatory.md`
**Read This First If:** Starting a complex task, going in circles, fixing multiple related issues

**Contents:**
- When planning is required (>4 tool calls expected)
- Planning file structure and naming conventions
- Mandatory error tracking table
- Integration with PAL tools for expert validation
- Real example (build failure fixed in 3 steps vs 8+ random attempts)

**Key Rule:**
```
IF task requires >4 tools:
    THEN invoke /planning-with-files
    AND create: {task}_task_plan.md, {task}_findings.md
    ELSE proceed directly

IF going in circles:
    THEN STOP immediately
    INVOKE /planning-with-files
    ELSE continue
```

**When NOT to Plan:**
- Single-file edits (<10 lines)
- Obvious one-line bug fixes
- Simple questions (no file changes)
- Trivial refactors (rename, format)

---

### `rules/planning-workflow.md`
**Read This First If:** Using /planning-with-files, coordinating specialist agents, validating with PAL

**Contents:**
- Full workflow: Setup → Specialists → PAL Review → Implementation → Verification
- How to use specialist agents concurrently (Explore, Plan, general-purpose)
- PAL model selection strategy (grok-code-fast-1 for 80% of reviews)
- Real-world example with timing comparison

**Workflow Phases:**
1. **Setup:** Create planning files with `/planning-with-files`
2. **Specialists:** Launch Task agents for parallel exploration/research
3. **PAL Review:** Use `mcp__pal__codereview`, `mcp__pal__debug`, or `mcp__pal__thinkdeep` for validation
4. **Implementation:** Systematic execution with phase tracking
5. **Verification:** Build + test, update planning files

---

### `rules/swiftdata-patterns.md`
**Read This First If:** Using SwiftData, accessing ModelContext/ModelContainer, debugging environment errors

**Contents:**
- ONLY `@Environment(\.modelContext)` exists as an environment key
- `@Environment(\.modelContainer)` does NOT exist (common mistake)
- How to access container from context for background tasks
- Common mistakes and quick fixes
- Real example from SwiftWing codebase

**Critical Pattern:**
```swift
// ✅ CORRECT - Use modelContext in views
@Environment(\.modelContext) private var modelContext
let container = modelContext.container  // Access via modelContext

// ❌ WRONG - This environment key doesn't exist
@Environment(\.modelContainer) private var modelContainer  // Compiler error!
```

**Real Bug from This Project:**
```swift
// BEFORE (broken) - LibraryView.swift:40
@Environment(\.modelContainer) private var modelContainer  // ❌

// AFTER (fixed) - LibraryView.swift:40
@Environment(\.modelContext) private var modelContext  // ✅
let container = modelContext.container  // Access via modelContext
```

---

## Hooks Directory: AUTOMATED ENFORCEMENT

### `hooks/enforce-planning.sh`
**Triggers:** On every user prompt submission (`UserPromptSubmit` hook)

**What It Does:**
1. Analyzes user message for complexity indicators
2. Calculates complexity score based on keywords
3. If score ≥5: Blocks execution, shows warning, requires `/planning-with-files`
4. If score <5: Allows prompt to execute normally

**Complexity Scoring:**
- **+3 points:** build fail, debug, refactor multiple, integrate, architecture, performance optimization
- **+2 points:** add feature, implement, multi-file indicators, create/update and operations
- **+1 point:** then, after that, next, also, furthermore

**Example Scores:**
- "Fix typo in README" → 0 points → ALLOWED ✅
- "Fix build failures in Camera integration" → 8 points → BLOCKED ❌ (requires `/planning-with-files`)
- "Refactor TalariaService skip-planning" → 7 points → ALLOWED ⚠️ (override)

**Output When Blocked:**
```
╔════════════════════════════════════════════════════════════════╗
║  🚨 COMPLEXITY THRESHOLD EXCEEDED (Score: 8/5)                 ║
║                                                                ║
║  This task appears to require >3 tool calls.                   ║
║  MANDATORY: Use /planning-with-files skill first               ║
║                                                                ║
║  Recommended Workflow:                                         ║
║  1. /planning-with-files - Create structured plan              ║
║  2. Use specialist Task agents (Explore, Plan, etc.)           ║
║  3. Review outputs with PAL MCP grok-code-fast-1               ║
║  4. Work systematically with persistent memory                 ║
╚════════════════════════════════════════════════════════════════╝

❌ BLOCKED: Please invoke /planning-with-files before proceeding
```

**Override:** Add "skip-planning" to prompt (use only for true simple tasks)

---

### `hooks/pm-epic-review.sh`
**Triggers:** When user asks about status/progress (keywords: "status", "progress", "epic", "where are we")

**What It Does:**
1. Suggests PM/team workflow (epic review, stakeholder sync)
2. Recommends checking `ralph-tui status` for progress
3. Suggests reading planning docs for context

**Output Example:**
```
💼 PM WORKFLOW SUGGESTION

When asking about project status, consider:
1. Run: ralph-tui status  (Check current epic)
2. Review: EPIC-X-STORIES.md (Current user stories)
3. Check: task_plan.md (Implementation progress)
4. Read: findings.md (Technical discoveries)

For team/stakeholder updates, use these as source of truth.
```

---

## Skills Directory: CUSTOM WORKFLOWS

Skills are specialized task shortcuts invoked with `/skill-name` or through auto-detection.

### `skills/gogo.md`
**Trigger Phrases:**
- `/gogo`
- `/gogo -m "custom message"`

**What It Does:**
1. Analyzes staged changes (git status, git diff)
2. Reviews recent commits for style
3. Creates AI-generated commit message following conventions
4. Pushes to remote

**Commit Message Format:**
- `feat: US-XXX - Feature description` (new features)
- `fix: Bug description` (bug fixes)
- `refactor: Refactoring description` (code refactoring)
- `docs: Documentation update` (docs)
- `test: Test addition` (tests)
- `chore: Build/tooling` (build changes)

**Attribution:**
All commits include: `Co-Authored-By: Claude Code <noreply@anthropic.com>`

**Safety Checks:**
- ❌ Rejects files with secrets (.env, .dev.vars)
- ⚠️ Warns if committing large files (>1MB)
- ✅ Shows diff before committing
- ✅ Validates Swift syntax

**When to Use:**
- ✅ Epic-based development (incremental commits)
- ✅ Feature branches with continuous progress
- ❌ Main branch (requires code review)
- ❌ Large architectural changes (commit manually + create PR)

**Example:**
```bash
git add swiftwing/Services/CameraActor.swift
/gogo

# Auto-generates:
# "feat: US-203 - Implement camera session management
#
# - Add CameraActor for thread-safe session control
# - Implement startSession() and stopSession()
# - Add permission handling
#
# Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### `skills/idb-ui-test.md`
**Trigger Phrases:**
- "test the ui"
- "test with idb"
- "ui testing"
- "idb test"
- "check the interface"
- "validate the ui"

**What It Does:**
Comprehensive iOS UI/UX testing using idb (Facebook's iOS Development Bridge) MCP integration.

**Capabilities:**
1. **Device Discovery:** List simulators, boot/shutdown, install/launch apps
2. **UI Inspection:** Describe all elements with frame coordinates
3. **User Interactions:** Tap, swipe, type, press hardware buttons
4. **Screenshots:** Capture visual state before/after interactions
5. **Automated Flows:** Multi-step test sequences with validation

**Workflow:**
1. Test Planning (goals, scenarios, expected outcomes)
2. Device Setup (boot simulator, install app)
3. UI Inspection (`idb ui describe-all` to get element coordinates)
4. Interaction Testing (tap, swipe, type at calculated coordinates)
5. Validation & Screenshots
6. Test Report (document results, issues, performance)

**Key Commands:**
```bash
idb list-targets                    # Find available devices
idb launch com.ooheynerds.swiftwing # Launch app
idb ui describe-all                 # Get UI hierarchy with coordinates
idb ui tap X Y                      # Tap at coordinates
idb ui swipe X1 Y1 X2 Y2            # Swipe gesture
idb ui text "string"                # Type into field
idb screenshot filename.png         # Capture state
```

**SwiftWing Test Scenarios:**
- **Camera Cold Start:** Measure time to first frame (<0.5s target)
- **Camera Capture Flow:** Validate capture button, processing queue
- **Library Grid Navigation:** Test scrolling, book selection, detail sheet
- **Search Functionality:** Full-text search with results filtering

**Performance Benchmarking:**
```bash
# Camera cold start test
START=$(date +%s.%N)
idb launch com.ooheynerds.swiftwing
sleep 2
idb screenshot camera-ready.png
END=$(date +%s.%N)
DURATION=$(echo "$END - $START" | bc)
echo "Cold start: ${DURATION}s (target: <0.5s)"
```

---

## Commands Directory: HELPER COMMANDS

Commands are documented CLI helpers that agents can reference when needed.

### `commands/build-sim.md`
**Usage:** For reference when building for simulator

**Command:**
```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name={{device}}' \
  build 2>&1 | xcsift
```

**Available Devices:**
- iPhone 17 Pro Max (default)
- iPhone 17 Pro
- iPhone 17
- iPad Pro (14-inch)

**Build Requirements:**
- 0 errors (mandatory)
- 0 warnings (mandatory)
- Clean build in < 30s

---

### `commands/epic-status.md`
**Usage:** For reference when checking epic progress

**Displays:**
- Current epic from `ralph-tui status`
- Planning file locations and status
- Epic user stories from `EPIC-X-STORIES.md`

**Commands:**
```bash
ralph-tui status        # Show current epic
ls -la task_plan.md     # Check planning file exists
grep -i "^## Phase" task_plan.md  # Show phase status
```

---

### `commands/update-api.md`
**Usage:** For reference when updating OpenAPI spec

**Purpose:**
Update Talaria API specification (committed to repo for reproducible builds)

**Command:**
```bash
./Scripts/update-api-spec.sh         # Normal update (checksum verify)
./Scripts/update-api-spec.sh --force # Force update (skip checksum)
```

**Why Committed:**
- ✅ Offline builds possible
- ✅ Reproducible builds
- ✅ No network dependency during development
- ✅ Explicit API version control

**Process:**
1. Fetch spec from Talaria server
2. Verify SHA256 checksum
3. Show diff preview
4. Require confirmation before updating
5. Commit changes to git

---

## Settings Configuration: `settings.json`

The `settings.json` file controls Claude Code behavior for SwiftWing:

**Hooks Enabled:**
- `UserPromptSubmit` → enforce-planning.sh (complexity detection)
- `UserPromptSubmit` → pm-epic-review.sh (status workflow)
- `SessionStart` → Startup reminder

**Permissions:**
- All tools enabled (Bash, Read, Write, Edit, Glob, Grep, Task)
- All skills enabled (planning-with-files, gogo, feature-dev, commit-push-pr)
- PAL MCP tools enabled (debug, codereview, analyze, thinkdeep, chat, consensus)

**File Suggestions:**
- Only Swift files (*.swift)
- JSON files (*.json)
- Markdown files (*.md)
- Excludes binaries, images, artifacts

**Attribution:**
Commits credited to: `Co-Authored-By: Claude Code <noreply@anthropic.com>`

---

## Verification Checklist: `VALIDATION-CHECKLIST.md`

Before committing or declaring a task complete, use this checklist:

**Pre-Commit Verification:**
- [ ] Build succeeds: `xcodebuild ... | xcsift` → 0 errors, 0 warnings
- [ ] No uncommitted generated files
- [ ] No secrets in staged files
- [ ] Swift syntax valid
- [ ] Commit message follows format
- [ ] Planning files updated (if task required planning)

**Post-Completion Verification:**
- [ ] All user stories marked complete
- [ ] All tests passing
- [ ] All errors documented and resolved
- [ ] Planning files archived (move to .claude/plans/)
- [ ] Epic status updated via ralph-tui

---

## Planning File Outputs: `plans/` Directory

When agents invoke `/planning-with-files`, output files are created:

```
.claude/plans/
├── camera_refactor_task_plan.md    # Structure: goal, phases, decisions
├── camera_refactor_findings.md      # Structure: root causes, expert advice
├── camera_refactor_progress.md      # Structure: session log, test results
├── build_failure_task_plan.md
├── build_failure_findings.md
└── ...
```

**File Naming:** `{task-description}_task_plan.md`, `{task-description}_findings.md`

**Lifecycle:**
1. Created during `/planning-with-files` invocation
2. Updated throughout task execution
3. Archived after task completion (moved to subdirectory with date)
4. Never committed to git (included in .gitignore)

---

## Comprehensive Agent Workflow

### For Simple Tasks (<4 tool calls)

```
User Request
    ↓
Hook: enforce-planning.sh (score <5)
    ↓
Execute Directly (no planning needed)
    ↓
Build + Test
    ↓
Complete
```

### For Complex Tasks (≥4 tool calls)

```
User Request
    ↓
Hook: enforce-planning.sh (score ≥5)
    ↓
Show Warning: BLOCKED - Invoke /planning-with-files
    ↓
User: /planning-with-files
    ↓
Create: task_plan.md, findings.md, progress.md (optional)
    ↓
Launch Specialist Agents Concurrently:
  - Task(Explore): Codebase exploration
  - Task(Plan): Architecture planning
  - Task(general-purpose): Multi-step research
    ↓
PAL Review: Use mcp__pal__codereview or mcp__pal__debug
    ↓
Update findings.md with expert validation
    ↓
Systematic Implementation (phases marked in_progress)
    ↓
Build + Test (xcodebuild ... | xcsift)
    ↓
Log errors in task_plan.md (never repeat)
    ↓
Verify: 0 errors, 0 warnings
    ↓
Mark Complete in task_plan.md
    ↓
Archive planning files
    ↓
Complete ✅
```

---

## Real Example: Build Failure Resolution

**Scenario:** Build failures after code review fixes

**Without Planning (8+ attempts):**
1. Try fix 1 → Build fails (same error)
2. Try fix 2 → Different error
3. Try fix 3 → Back to original error
4. Try fix 4 → Lost context, repeating attempt 1
5-8. Circular attempts continue...

**Result:** Hours wasted, user frustrated

**With Planning Workflow (3 systematic steps):**

**Phase 1: Planning Setup**
```bash
/planning-with-files
# Creates: build_failure_task_plan.md, build_failure_findings.md
```

**Phase 2: Specialist Agents**
```
Task(Explore): "Find all Swift files with @Environment(\.modelContainer) usage"
Task(Explore): "Search for @Model definitions and SwiftData patterns"
Result: 3 files using incorrect environment key
```

**Phase 3: PAL Review + Systematic Fix**
```
mcp__pal__debug({
    hypothesis: "@Environment(\.modelContainer) doesn't exist",
    findings: "Found in LibraryView.swift:40 and 2 other files"
})
# Expert confirms: CORRECT - use @Environment(\.modelContext) instead
```

**Phase 4: Implementation**
- Fix LibraryView.swift (let container = modelContext.container)
- Fix CameraView.swift
- Fix BookDetailView.swift
- Build: xcodebuild ... | xcsift → 0 errors, 0 warnings ✅

**Result:** 20 minutes systematic fix vs. hours of circular debugging

---

## Common Agent Mistakes & Fixes

### ❌ Mistake 1: Calling xcodebuild Without xcsift
```bash
# WRONG
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing build

# CORRECT
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing build 2>&1 | xcsift
```

**Why:** xcsift is essential for parsing errors into machine-readable JSON

---

### ❌ Mistake 2: Skipping Planning for Complex Tasks
```
# WRONG
User: "Implement camera, library, and AI integration"
Agent: *starts coding immediately without planning*
Result: Circular debugging, missed dependencies

# CORRECT
User: "Implement camera, library, and AI integration"
Hook: Detects complexity ≥5
Agent: Blocks, shows warning
User: /planning-with-files
Agent: Creates planning files, uses specialists, validates with PAL
Result: Systematic execution, zero circular debugging
```

---

### ❌ Mistake 3: Using Wrong SwiftData Environment Key
```swift
// WRONG
@Environment(\.modelContainer) var modelContainer  // Doesn't exist!

// CORRECT
@Environment(\.modelContext) var modelContext
let container = modelContext.container  // Access via modelContext
```

---

### ❌ Mistake 4: Repeating Failed Fixes
```
# WRONG - No error tracking
Try fix 1 → Fails → Try fix 2 → Fails → Try fix 1 again (forgot it failed)

# CORRECT - Track in planning file
## Errors Encountered
| Error | Attempt | Resolution | Status |
| ------ | -------- | ----------- | ------ |
| @Environment(\.modelContainer) not found | 1 | Doesn't exist, use modelContext | ✅ |
| nonisolated(unsafe) invalid on @Property | 2 | Remove nonisolated, use @MainActor | ✅ |
```

---

## Integration with oh-my-claudecode (OMC)

SwiftWing leverages the broader OMC orchestration system:

**Available Multi-Agent Skills:**
- **autopilot** - Full autonomous execution (detect "build me", "I want a")
- **plan** - Planning interview for requirements
- **ralph** - Persistence mode (don't stop until complete)
- **ultrawork** - Maximum parallel execution (detect "fast", "parallel", "ulw")
- **ecomode** - Token-efficient parallelism (detect "eco", "efficient", "budget")

**Available Specialist Agents:**
- `Explore` (haiku) - Fast codebase search
- `Explore-medium` (sonnet) - More thorough search
- `Explore-high` (opus) - Deep architectural search
- `Architect` (opus) - Complex architectural analysis
- `Writer` (haiku) - Documentation generation
- `Researcher` (sonnet) - API/framework research
- `Planner` (opus) - Strategic planning
- `Critic` (opus) - Design review and critique

**PAL MCP Tools (Expert Validation):**
- `mcp__pal__debug` - Systematic debugging with hypothesis testing
- `mcp__pal__codereview` - Architecture and code quality review
- `mcp__pal__analyze` - Comprehensive code analysis
- `mcp__pal__thinkdeep` - Multi-stage reasoning
- `mcp__pal__consensus` - Multi-model consensus
- `mcp__pal__chat` - Collaborative thinking
- `mcp__pal__tracer` - Code execution flow analysis
- `mcp__pal__testgen` - Test suite generation
- `mcp__pal__docgen` - Documentation generation

---

## Project Context & Standards

### Swift 6.2 Requirements
- **Strict Concurrency:** Enabled
- **Complete Concurrency Checking:** All warnings treated as errors
- **Target:** iOS 26.0+ only
- **Build Requirement:** 0 errors, 0 warnings (mandatory)

### Architecture
```
SwiftUI Views
    ↓
@Observable ViewModels
    ↓
Actor Services (TalariaService, CameraManager, DataSyncActor)
    ↓
SwiftData Models (@Model classes)
```

### Vertical Slice Development
Each epic delivers complete feature (UI → Logic → Data → Network):
- **Epic 1:** Foundation (walking skeleton)
- **Epic 2:** Camera (capture + processing queue)
- **Epic 3:** Library (grid view + search)
- **Epic 4:** AI Integration (Talaria + SSE streaming)
- **Epic 5:** Refactoring (in progress)
- **Epic 6:** App Store Launch (pending)

### Performance Targets
| Metric | Target | Measurement |
|--------|--------|-------------|
| Cold Start | <0.5s | Time to camera preview |
| UI Frame Rate | >55 FPS | Instruments measurement |
| Image Processing | <500ms | Compression + upload prep |
| SSE Connection | <200ms | First byte time |

---

## When to Escalate

Contact project maintainers if:

1. **Rule Conflicts:** Two rules contradict (document in issue)
2. **Hook Malfunction:** enforce-planning.sh not triggering correctly
3. **Unsupported Pattern:** Code pattern violates Swift 6.2 strict concurrency
4. **Planning Tool Failure:** `/planning-with-files` not creating files
5. **Build Environment:** xcsift not installed or failing

---

## Quick Reference Guide

### Build Command (Copy-Paste)
```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift
```

### Planning Workflow (Copy-Paste)
```bash
# Step 1: Create planning files
/planning-with-files

# Step 2: Launch specialist agents
Task(Explore): "Search for X"
Task(Plan): "Design Y"

# Step 3: PAL review
mcp__pal__debug({
    step: "Root cause analysis",
    hypothesis: "...",
    findings: "...",
    model: "grok-code-fast-1"
})

# Step 4: Build verification
xcodebuild ... | xcsift  # 0 errors, 0 warnings
```

### SwiftData Pattern (Copy-Paste)
```swift
// ✅ Correct
@Environment(\.modelContext) private var modelContext
let container = modelContext.container

// ❌ Wrong
@Environment(\.modelContainer) private var modelContainer
```

### Commit Workflow (Copy-Paste)
```bash
git add file1.swift file2.swift
/gogo
# Or with custom message:
/gogo -m "feat: US-XXX - Description"
```

---

## File Navigation

**For Different Tasks:**

| Task | Read First | Then Read | Tools |
|------|-----------|-----------|-------|
| Build issues | `build-workflow.md` | `planning-mandatory.md` | xcodebuild \| xcsift, mcp__pal__debug |
| Add feature | `swift-conventions.md` | `planning-workflow.md` | /planning-with-files, Explore, gogo |
| Debug crash | `planning-mandatory.md` | `swift-conventions.md` | mcp__pal__debug, xcsift |
| Refactor code | `swift-conventions.md` | `swiftdata-patterns.md` | mcp__pal__codereview, gogo |
| Fix SwiftData | `swiftdata-patterns.md` | `build-workflow.md` | xcodebuild \| xcsift |
| Test UI | `idb-ui-test.md` | `planning-workflow.md` | idb MCP, /planning-with-files |

---

## Related Documentation

**In This Directory:**
- `README.md` - Quick start (for humans)
- `settings.json` - Hook and permission configuration
- `VALIDATION-CHECKLIST.md` - Pre-commit verification
- `HOOK-SETUP-SUMMARY.md` - Hook implementation details

**In Project Root:**
- `CLAUDE.md` - Main Claude Code guidance (MUST READ)
- `PRD.md` - Product requirements
- `EPIC-X-STORIES.md` - Current epic user stories
- `START-HERE.md` - Project orientation

**Generated During Work:**
- `*_task_plan.md` - Planning file (phases, decisions, errors)
- `*_findings.md` - Planning file (root causes, expert advice)
- `*_progress.md` - Planning file (session log, test results)

---

## Summary: The SwiftWing Way

**Core Principle:** Build with **systematic excellence** through planning, verification, and expert validation.

**The Three Pillars:**
1. **Planning** - Mandatory for complexity (>4 tools, circular debugging)
2. **Verification** - Mandatory for builds (0 errors, 0 warnings)
3. **Expert Validation** - Mandatory for architecture (PAL tools)

**The Golden Rule:** Never solve the same problem twice. Track all attempts in planning files.

**Result:** Fast, reliable, circular-debugging-free development.

---

**Last Updated:** January 30, 2026
**Maintained By:** SwiftWing Development Team
**Status:** Active - All rules enforced via hooks
