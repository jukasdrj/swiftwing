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
└── skills/                            # Custom skills (if any)
```

## Enforcement Rules

### 🚨 ABSOLUTE REQUIREMENTS

These rules are **NON-NEGOTIABLE** and Claude MUST follow them:

#### 1. Build Commands: Always Use xcsift
```bash
# ✅ CORRECT - Always pipe xcodebuild through xcsift
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift

# ❌ FORBIDDEN - Never call xcodebuild directly
xcodebuild -project swiftwing.xcodeproj build

# ❌ FORBIDDEN - xcsift is not a build command
xcsift build
```

**Why:** xcsift parses build output into structured JSON for automated diagnosis.

#### 2. Planning: Mandatory for Complex Tasks
```bash
# MUST invoke for tasks requiring >4 tool calls
/planning-with-files
```

**Required For:**
- Build failures
- Multi-step features (>3 files)
- Code review findings
- Architecture decisions
- Performance optimization
- **Any circular debugging**

**Creates:**
- `{task}_task_plan.md` - Phases, decisions, error log
- `{task}_findings.md` - Root causes, expert advice
- `{task}_progress.md` - Session log (optional)

#### 3. SwiftData Environment Keys
```swift
// ✅ CORRECT - Only this exists
@Environment(\.modelContext) private var modelContext
let container = modelContext.container

// ❌ FORBIDDEN - This doesn't exist
@Environment(\.modelContainer) private var modelContainer
```

## Rule Files

### `build-workflow.md`
- xcodebuild + xcsift mandatory pattern
- Build verification workflow
- Error diagnosis process

### `planning-mandatory.md`
- When planning is required (>4 tools)
- Planning file structure
- Error tracking requirements
- Integration with PAL tools

### `swiftdata-patterns.md`
- Environment key patterns
- Background task patterns
- Common mistakes and fixes
- Quick reference table

## Settings Configuration

**`settings.json` enables:**
- Permissions for all tools (Bash, Read, Write, Edit, Glob, Grep, Task)
- Permissions for skills (planning-with-files, feature-dev, commit)
- Permissions for PAL MCP tools (thinkdeep, debug, analyze, codereview)
- File suggestions (Swift, JSON, MD files only)
- Git attribution in commits

## Verification

**To verify rules are being followed:**

1. **Check build commands:**
   ```bash
   # Should see xcodebuild piped to xcsift
   # Should NEVER see bare xcodebuild commands
   ```

2. **Check for planning files:**
   ```bash
   # For complex tasks, should see:
   ls *_task_plan.md *_findings.md
   ```

3. **Check SwiftData patterns:**
   ```swift
   // Should never see @Environment(\.modelContainer)
   # Only @Environment(\.modelContext)
   ```

## Real Example: Build Failure Resolution

**Before These Rules (8+ circular attempts):**
- Tried random fixes without planning
- Called xcodebuild without xcsift (couldn't parse errors)
- Lost context between attempts
- Repeated same failed approaches

**After These Rules (3 systematic steps):**
1. Invoked `/planning-with-files` immediately
2. Used PAL thinkdeep with structured xcsift output
3. Documented findings, fixed root cause systematically
4. Result: BUILD SUCCESSFUL

**Time Saved:** Hours → 20 minutes

## Updating Rules

**When to add new rules:**
- Discovered new mandatory patterns
- Common mistakes being repeated
- Framework-specific gotchas (like SwiftData)
- Project-specific conventions

**How to add rules:**
1. Create new `.md` file in `.claude/rules/`
2. Document pattern with ✅/❌ examples
3. Add "Why This Matters" section
4. Include real examples from project
5. Update this README

## Related Documentation

- `CLAUDE.md` (project root) - Main guidance for Claude Code
- `PRD.md` - Product requirements
- `EPIC-X-STORIES.md` - Current epic user stories
- Planning files (`*_task_plan.md`, `*_findings.md`) - Created per task

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
