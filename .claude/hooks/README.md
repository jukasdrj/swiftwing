# SwiftWing hooks

Grok and Claude Code load these from `.claude/settings.json`. Stock OpenCode does not run this file.

| Event | Command | What it does |
|-------|---------|--------------|
| SessionStart | echo | Prints the iOS 27 session banner |
| PreToolUse `Edit\|Write\|write` | `hooks/file-edit-guard.sh openapi` | Warns when an edit targets `talaria-openapi.yaml` |
| PostToolUse `Edit\|Write\|write` | `hooks/file-edit-guard.sh swift` | Reminds the agent to `/build-sim` after a `.swift` edit |

Both guards read the hook event JSON on stdin (`toolInput` or `tool_input`). They exit 0 and send `additionalContext`. They do not block the edit.

Do not put `$CLAUDE_TOOL_INPUT` in a hook `command` string. Grok refuses to start a hook that names an environment variable it does not set. `$CLAUDE_PROJECT_DIR` is set by the runner.

Reload hooks in an already-open Grok session with `/hooks`, then `r`.
