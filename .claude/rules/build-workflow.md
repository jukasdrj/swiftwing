# Build Workflow Rules

## MANDATORY: xcodebuild + xcsift Pattern

**ABSOLUTE RULE: NEVER call xcodebuild without piping through xcsift**

### ✅ CORRECT Pattern
```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift
```

### ❌ FORBIDDEN Patterns
```bash
# NEVER do this - raw xcodebuild output is unparseable
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing build

# NEVER do this - xcsift is not a build command, it's a formatter
xcsift build

# NEVER do this - xcsift needs xcodebuild piped to stdin
xcsift -project swiftwing.xcodeproj
```

## Why This Matters

**xcsift Purpose:**
- Parses xcodebuild's verbose output into structured JSON
- Extracts errors, warnings, line numbers, file paths
- Makes build failures machine-readable
- Essential for automated diagnosis with PAL tools

**Example Output:**
```json
{
  "errors": [
    {
      "file": "/path/to/LibraryView.swift",
      "line": 40,
      "message": "cannot infer key path type from context"
    }
  ],
  "summary": {
    "errors": 3,
    "warnings": 14
  }
}
```

## Build Verification Workflow

**ABSOLUTE REQUIREMENT: ZERO WARNINGS**

Build success criteria:
- ✅ 0 errors
- ✅ **0 warnings** (not negotiable)
- ✅ Clean console output (no runtime errors)

**Before Code Reviews:**
1. ✅ Build to verify base code works **with zero warnings**
2. ✅ Run code review / analysis
3. ✅ Apply fixes
4. ✅ Build again to verify fixes **with zero warnings**

**NEVER:**
- ❌ Review code that doesn't build
- ❌ Assume changes compile without verification
- ❌ Skip builds because "it should work"
- ❌ **Accept ANY warnings - must be 0/0**

**Validation Command:**
```bash
xcodebuild -project swiftwing.xcodeproj -scheme swiftwing -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | xcsift

# Check output: errors: 0, warnings: 0
# If warnings > 0: STOP and fix all warnings before proceeding
```

## Real Example from This Project

**What Went Wrong:**
- Ran code reviews on code with missing files
- Files existed but weren't in Xcode project
- Spent hours fixing review findings
- Base code never built in first place

**Lesson:**
```
Build First → Review Second → Fix → Build Again
```

## When User Reports Build Failures

**Immediate Actions:**
1. Use `/planning-with-files` (mandatory for build issues)
2. Run `xcodebuild ... | xcsift` to get structured errors
3. Use PAL thinkdeep/debug to diagnose systematically
4. Document findings in `*_findings.md`
5. Fix root causes, not symptoms
6. Verify build succeeds before declaring done

**NEVER:**
- ❌ Go in circles trying random fixes
- ❌ Skip planning for "quick" build fixes
- ❌ Repeat same failed approaches
