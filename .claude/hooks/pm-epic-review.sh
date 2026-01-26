#!/bin/bash
# pm-epic-review.sh
# Hook to trigger PM-level epic review with Task agents + PAL grok-code-fast-1

# Get the user prompt from stdin or environment
PROMPT="${CLAUDE_USER_MESSAGE:-}"

# Check if user explicitly requested PM review
if echo "$PROMPT" | grep -qiE "verify.*epic|epic.*status|pm.*review|review.*epic|get.*back.*phase|which.*epic"; then
    cat <<EOF

╔════════════════════════════════════════════════════════════════╗
║  📊 PM EPIC REVIEW TRIGGERED                                   ║
╚════════════════════════════════════════════════════════════════╝

🔍 RECOMMENDED WORKFLOW:

1️⃣  Launch Explore agents in PARALLEL to audit codebase:
   Task(Explore, "Find all completed Epic 1 user stories")
   Task(Explore, "Find all completed Epic 2 user stories")
   Task(Explore, "Find all completed Epic 3 user stories")
   Task(Explore, "Find all completed Epic 4 user stories")

2️⃣  Review findings with PAL grok-code-fast-1:
   mcp__pal__analyze({
     analysis_type: "architecture",
     model: "grok-code-fast-1",
     findings: "Aggregate outputs from Explore agents...",
     relevant_files: [absolute paths to key files]
   })

3️⃣  Cross-reference with epic JSONs (epic-1.json through epic-4.json)

4️⃣  Generate gap analysis report

Benefits of this approach:
✓ Parallel agent execution (fast codebase audit)
✓ Expert validation with grok-code-fast-1
✓ Systematic cross-referencing with epic specs
✓ Actionable gap analysis

EOF
    # Don't block execution - just provide guidance
    exit 0
fi

# Not a PM review request - allow through
exit 0
