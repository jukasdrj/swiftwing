# idb-ui-test Skill

## Purpose
Expert UI/UX testing workflow using Facebook IDB (iOS Development Bridge) via MCP integration. Provides systematic testing of iOS apps with device interaction, screenshot capture, UI element inspection, and accessibility validation.

## Trigger Phrases
- "test the ui"
- "test with idb"
- "ui testing"
- "idb test"
- "check the interface"
- "validate the ui"
- "idb screenshot"
- "inspect ui elements"

## Skill Description
Comprehensive iOS UI/UX testing using idb MCP tools. Performs device interaction, UI inspection, screenshot capture, accessibility validation, and automated testing workflows.

## Capabilities

### 1. Device Discovery & Setup
- List available simulators and devices
- Boot/shutdown simulators
- Install/uninstall apps
- Launch apps with specific bundle IDs

### 2. UI Element Inspection
- Describe all UI elements with `idb ui describe-all`
- Extract frame coordinates for precise interactions
- Identify buttons, text fields, labels, and interactive elements
- Validate accessibility labels and identifiers

### 3. User Interactions
- **Tap:** Simulate taps at specific coordinates or on identified elements
- **Swipe:** Gesture navigation (scroll, swipe between views)
- **Text Input:** Type into text fields
- **Button Press:** Hardware buttons (Home, Lock, Side Button, Siri)
- **Key Events:** Keyboard input simulation

### 4. Screenshot & Visual Validation
- Capture screenshots for visual regression
- Compare UI states before/after interactions
- Document visual bugs and layout issues

### 5. Automated Test Flows
- Multi-step interaction sequences
- State validation between steps
- Error detection and recovery
- Performance timing measurements

## Workflow

### Phase 1: Test Planning
```markdown
## Test Plan: {Feature Name}

**Goal:** {What are we testing?}

**Target Device:** {Simulator/Device}
**App Bundle ID:** {com.ooheynerds.swiftwing}

**Test Scenarios:**
1. {Scenario 1}
2. {Scenario 2}
3. {Scenario 3}

**Expected Outcomes:**
- ✅ {Success criterion 1}
- ✅ {Success criterion 2}

**Risks:**
- ⚠️ {Potential issue 1}
```

### Phase 2: Device Setup
```bash
# List available devices
idb list-targets

# Boot simulator (if needed)
idb boot {simulator-udid}

# Install app (if needed)
idb install {path-to-app.app}

# Launch app
idb launch {bundle-id}
```

### Phase 3: UI Inspection
```bash
# Get full UI hierarchy
idb ui describe-all

# Analyze output for:
# - Element types (button, textField, etc.)
# - Frame coordinates (x, y, width, height)
# - Accessibility labels
# - Interactive states (enabled/disabled)
```

### Phase 4: Interaction Testing
```bash
# Example: Tap on button
# From describe-all: frame={{330, 876.33}, {110, 45.67}}
# Calculate center: x=330+110/2=385, y=876.33+45.67/2=899
idb ui tap 385 899

# Example: Swipe up (scroll)
idb ui swipe 200 800 200 200 --delta 10

# Example: Enter text
idb ui text "Test Book Title"

# Example: Press hardware button
idb ui button HOME
```

### Phase 5: Validation & Screenshots
```bash
# Capture current state
idb screenshot {filename}.png

# Verify UI state with describe-all
idb ui describe-all

# Check for expected elements
# Look for success indicators (e.g., "Success" label, new screen)
```

### Phase 6: Test Report
```markdown
## Test Results: {Feature Name}

**Date:** {YYYY-MM-DD}
**Device:** {iPhone 17 Pro Max Simulator}
**Build:** {Build number}

### Scenarios Tested

#### ✅ Scenario 1: {Name}
- Steps: {1, 2, 3}
- Result: PASS
- Screenshot: `test-scenario-1.png`

#### ❌ Scenario 2: {Name}
- Steps: {1, 2, 3}
- Result: FAIL
- Issue: {Description}
- Screenshot: `test-scenario-2-fail.png`
- Expected: {Expected behavior}
- Actual: {Actual behavior}

### Issues Found
| Issue | Severity | Screenshot | Status |
|-------|----------|------------|--------|
| {Description} | High | `issue-1.png` | Open |

### Performance Notes
- {Observation about UI responsiveness}
- {Animation smoothness}
- {Load times}

### Recommendations
- {Suggestion 1}
- {Suggestion 2}
```

## idb MCP Tool Reference

### Device Management
```bash
# List devices
idb list-targets

# List apps
idb list-apps

# Launch app
idb launch {bundle-id}

# Terminate app
idb terminate {bundle-id}
```

### UI Interaction
```bash
# Tap at coordinates
idb ui tap X Y [--duration DURATION]

# Swipe gesture
idb ui swipe X_START Y_START X_END Y_END [--delta STEP_SIZE]

# Press hardware button
idb ui button {APPLE_PAY|HOME|LOCK|SIDE_BUTTON|SIRI} [--duration DURATION]

# Type text
idb ui text "string"

# Key press
idb ui key KEYCODE [--duration DURATION]

# Key sequence
idb ui key-sequence KEYCODE1 KEYCODE2 ...
```

### UI Inspection
```bash
# Get full UI hierarchy with coordinates
idb ui describe-all

# Output includes:
# - element type
# - frame: {x, y, width, height}
# - accessibility label
# - value/state
# - AXFrame: "{{x, y}, {width, height}}" format
```

### Screenshot & Recording
```bash
# Screenshot
idb screenshot [--png|--jpeg] output.png

# Video recording (if supported)
idb record-video output.mp4
```

## Frame Coordinate Calculation

**Understanding idb ui describe-all Output:**

```json
{
  "type": "button",
  "label": "Capture",
  "frame": {
    "x": 150.0,
    "y": 750.0,
    "width": 100.0,
    "height": 50.0
  },
  "AXFrame": "{{150.0, 750.0}, {100.0, 50.0}}"
}
```

**To tap on element center:**
```python
center_x = x + (width / 2)  # 150 + 50 = 200
center_y = y + (height / 2)  # 750 + 25 = 775

# Command:
idb ui tap 200 775
```

## SwiftWing-Specific Test Scenarios

### Test 1: Camera Capture Flow
```markdown
**Goal:** Validate camera capture and processing queue

**Steps:**
1. Launch app: `idb launch com.ooheynerds.swiftwing`
2. Inspect UI: `idb ui describe-all` → Find "Capture" button
3. Tap Capture: `idb ui tap {x} {y}`
4. Screenshot: `idb screenshot capture-started.png`
5. Wait 2s: Verify processing queue UI
6. Inspect UI: `idb ui describe-all` → Check for processing indicator
7. Screenshot: `idb screenshot processing-queue.png`

**Expected:**
- ✅ Camera preview visible
- ✅ Capture button enabled
- ✅ Processing queue shows new item
- ✅ UI remains responsive (no freeze)
```

### Test 2: Library Grid Navigation
```markdown
**Goal:** Test library grid scrolling and book selection

**Steps:**
1. Navigate to Library tab: Inspect + tap tab button
2. Screenshot: `idb screenshot library-grid.png`
3. Swipe up: `idb ui swipe 200 800 200 200`
4. Screenshot: `idb screenshot library-scrolled.png`
5. Tap book: Find book in describe-all, tap center
6. Screenshot: `idb screenshot book-detail.png`

**Expected:**
- ✅ Grid renders with images
- ✅ Smooth scroll animation
- ✅ Book detail sheet appears
- ✅ Back navigation works
```

### Test 3: Search Functionality
```markdown
**Goal:** Validate full-text search

**Steps:**
1. Find search field: `idb ui describe-all`
2. Tap search: `idb ui tap {x} {y}`
3. Type query: `idb ui text "Swift Programming"`
4. Screenshot: `idb screenshot search-results.png`
5. Verify results: `idb ui describe-all` → Check result count

**Expected:**
- ✅ Search field accepts input
- ✅ Results filter in real-time
- ✅ Matching books highlighted
```

## Performance Benchmarking

**Camera Cold Start Test:**
```bash
# Terminate app
idb terminate com.ooheynerds.swiftwing

# Start timer and launch
START=$(date +%s.%N)
idb launch com.ooheynerds.swiftwing

# Wait for UI ready
sleep 2

# Capture screenshot
idb screenshot camera-cold-start.png

# Check UI state
idb ui describe-all | grep "Capture"

# Calculate duration
END=$(date +%s.%N)
DURATION=$(echo "$END - $START" | bc)
echo "Cold start: ${DURATION}s (target: <0.5s)"
```

## Accessibility Validation

**Check for Accessibility Labels:**
```bash
# Get UI hierarchy
idb ui describe-all > ui-dump.json

# Validate all interactive elements have labels
# Look for:
# - "label": null ❌ (missing accessibility label)
# - "label": "Button" ❌ (generic label)
# - "label": "Capture book spine" ✅ (descriptive label)
```

**Common Issues:**
- Missing labels on buttons (VoiceOver can't describe)
- Generic labels ("Button", "Image") → Non-descriptive
- Wrong traits (button marked as static text)

## Error Handling

**Common idb Errors:**

```bash
# Simulator not booted
Error: No device found
→ Fix: idb boot {udid}

# App not installed
Error: Bundle ID not found
→ Fix: idb install {app.app}

# UI element not found
Error: Tap failed
→ Fix: Run describe-all first, verify coordinates

# Screenshot fails
Error: Screenshot service unavailable
→ Fix: Reboot simulator
```

## Integration with Planning Workflow

**Use with `/planning-with-files` for complex test campaigns:**

1. **Create Test Plan File:** `ui_test_task_plan.md`
2. **Document Findings:** `ui_test_findings.md`
3. **Track Progress:** `ui_test_progress.md`

**Example Task Plan:**
```markdown
## Phase 1: Camera Testing [in_progress]
- [x] Cold start benchmark
- [x] Capture button interaction
- [ ] Processing queue validation
- [ ] Error state handling

## Phase 2: Library Testing [pending]
- [ ] Grid rendering
- [ ] Scroll performance
- [ ] Book detail navigation

## Errors Encountered
| Error | Command | Resolution | Status |
|-------|---------|------------|--------|
| Tap missed button | idb ui tap 100 200 | Recalculated center from describe-all | ✅ |
```

## PAL Integration for Analysis

**After testing, use PAL tools for review:**

```javascript
// Analyze test results with expert validation
mcp__pal__analyze({
    step: "Review UI test findings for usability issues",
    analysis_type: "quality",
    findings: "Found 3 accessibility label gaps, 1 performance issue (cold start 0.8s vs 0.5s target)",
    relevant_files: [
        "/Users/juju/dev_repos/swiftwing/swiftwing/CameraView.swift",
        "/Users/juju/dev_repos/swiftwing/swiftwing/LibraryView.swift"
    ],
    model: "grok-code-fast-1"
})
```

## Output Deliverables

**After testing session:**
1. Test plan markdown file
2. Test results report
3. Screenshots in organized directory structure:
   ```
   idb-tests/
   ├── YYYY-MM-DD-session/
   │   ├── camera-cold-start.png
   │   ├── capture-button.png
   │   ├── processing-queue.png
   │   └── test-results.md
   ```
4. UI hierarchy dumps (JSON from describe-all)
5. Performance measurements log
6. Issue tracker updates (if bugs found)

## Best Practices

### 1. Always Inspect Before Interacting
```bash
# ❌ Bad: Guess coordinates
idb ui tap 200 400

# ✅ Good: Inspect first
idb ui describe-all > ui-state.json
# Calculate center from frame data
idb ui tap {calculated-x} {calculated-y}
```

### 2. Screenshot State Transitions
```bash
# Before action
idb screenshot before-tap.png

# Perform action
idb ui tap 300 500

# After action (wait for animation)
sleep 0.5
idb screenshot after-tap.png
```

### 3. Use Descriptive Filenames
```bash
# ❌ Bad
idb screenshot test1.png

# ✅ Good
idb screenshot camera-capture-button-highlighted.png
```

### 4. Validate Each Step
```bash
# Tap button
idb ui tap 300 500

# Verify state changed
idb ui describe-all | grep "processing"
# If expected element not found → test failed
```

### 5. Document Assumptions
```markdown
**Assumptions:**
- Simulator is iPhone 17 Pro Max (screen size: 430x932)
- App is already installed and launched
- Camera permission already granted
- Test data exists (at least 10 books in library)
```

## Quick Command Reference

```bash
# Essential workflow
idb list-targets                    # Find device
idb launch com.ooheynerds.swiftwing # Start app
idb ui describe-all                 # Inspect UI
idb ui tap X Y                      # Interact
idb screenshot result.png           # Capture state

# Cleanup
idb terminate com.ooheynerds.swiftwing
idb shutdown {udid}
```

## Conclusion

This skill provides systematic iOS UI/UX testing using idb MCP integration. Use it for:
- ✅ Automated regression testing
- ✅ Accessibility validation
- ✅ Performance benchmarking
- ✅ Visual validation with screenshots
- ✅ User flow testing
- ✅ Bug reproduction and documentation

Always combine with planning workflow for complex test campaigns (>5 test scenarios).
