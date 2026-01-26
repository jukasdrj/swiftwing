#!/bin/bash
# enforce-planning.sh
# Hook to enforce planning-with-files for complex tasks (>3 tool calls expected)

# Get the user prompt from stdin or environment
PROMPT="${CLAUDE_USER_MESSAGE:-}"

# Complexity indicators (weighted scoring)
COMPLEXITY_SCORE=0

# High complexity keywords (3 points each)
HIGH_COMPLEXITY_PATTERNS=(
    "build.*fail"
    "fix.*error"
    "debug"
    "refactor.*multiple"
    "integrate"
    "architecture"
    "performance.*optimi"
    "going.*circle"
    "keep.*fail"
    "not.*work"
    "still.*broken"
    "multi.*step"
    "several.*file"
)

# Medium complexity keywords (2 points each)
MEDIUM_COMPLEXITY_PATTERNS=(
    "add.*feature"
    "implement"
    "create.*and"
    "update.*and"
    "review.*and.*fix"
    "migrate"
    "refactor"
    "analyze"
)

# Multi-file indicators (2 points each)
MULTI_FILE_PATTERNS=(
    "across.*file"
    "[0-9]+.*file"
    "all.*swift"
    "entire.*codebase"
    "multiple.*component"
)

# Complexity verbs indicating multiple steps (1 point each)
MULTI_STEP_VERBS=(
    "then"
    "after.*that"
    "next"
    "also"
    "additionally"
    "furthermore"
)

# Count high complexity patterns
for pattern in "${HIGH_COMPLEXITY_PATTERNS[@]}"; do
    if echo "$PROMPT" | grep -qiE "$pattern"; then
        ((COMPLEXITY_SCORE += 3))
    fi
done

# Count medium complexity patterns
for pattern in "${MEDIUM_COMPLEXITY_PATTERNS[@]}"; do
    if echo "$PROMPT" | grep -qiE "$pattern"; then
        ((COMPLEXITY_SCORE += 2))
    fi
done

# Count multi-file patterns
for pattern in "${MULTI_FILE_PATTERNS[@]}"; do
    if echo "$PROMPT" | grep -qiE "$pattern"; then
        ((COMPLEXITY_SCORE += 2))
    fi
done

# Count multi-step verbs
for verb in "${MULTI_STEP_VERBS[@]}"; do
    if echo "$PROMPT" | grep -qiE "$verb"; then
        ((COMPLEXITY_SCORE += 1))
    fi
done

# Check if prompt already includes planning skill
if echo "$PROMPT" | grep -qE "^/?planning-with-files"; then
    # User explicitly invoked planning - allow through
    exit 0
fi

# Threshold: Score >= 5 requires planning (roughly >3 tool calls expected)
THRESHOLD=5

if [ "$COMPLEXITY_SCORE" -ge "$THRESHOLD" ]; then
    cat <<EOF

╔════════════════════════════════════════════════════════════════╗
║  🚨 COMPLEXITY THRESHOLD EXCEEDED (Score: $COMPLEXITY_SCORE/$THRESHOLD)           ║
║                                                                ║
║  This task appears to require >3 tool calls.                   ║
║  MANDATORY: Use /planning-with-files skill first               ║
║                                                                ║
║  Recommended Workflow:                                         ║
║  1. /planning-with-files - Create structured plan              ║
║  2. Use specialist Task agents (Explore, Plan, etc.)           ║
║  3. Review outputs with PAL MCP grok-code-fast-1               ║
║  4. Work systematically with persistent memory                 ║
║                                                                ║
║  Benefits:                                                     ║
║  ✓ Prevents circular debugging                                 ║
║  ✓ Persistent context (no memory loss)                         ║
║  ✓ Error tracking (avoid repeating failed fixes)              ║
║  ✓ Expert validation via PAL tools                             ║
║                                                                ║
║  To override (not recommended):                                ║
║  Add "skip-planning" to your prompt                            ║
╚════════════════════════════════════════════════════════════════╝

EOF

    # Check for override
    if echo "$PROMPT" | grep -qiE "skip-planning"; then
        echo "⚠️  Planning check overridden by user - proceeding without planning"
        exit 0
    else
        # Block execution - require planning
        echo "❌ BLOCKED: Please invoke /planning-with-files before proceeding"
        exit 1
    fi
fi

# Low complexity - allow through
exit 0
