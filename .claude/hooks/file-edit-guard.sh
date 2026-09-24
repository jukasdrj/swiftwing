#!/bin/bash
# Advisory Edit/Write hook. Tool input arrives as JSON on stdin.
# Claude uses tool_input; Grok uses toolInput.
#
# Do not reference $CLAUDE_TOOL_INPUT from the settings command. Grok
# refuses to run a hook command that names an env var it does not set
# ("required env var(s) not set: ${CLAUDE_TOOL_INPUT}").
#
# Usage: file-edit-guard.sh openapi|swift
# Always exits 0. A match prints a stderr note and additionalContext JSON.

set -euo pipefail

mode="${1:-}"
command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
path="$(printf '%s' "$payload" | jq -r '
  [
    .toolInput.file_path,
    .toolInput.target_file,
    .tool_input.file_path,
    .tool_input.target_file
  ] | map(select(type == "string" and . != "")) | first // empty
' 2>/dev/null || true)"

[ -z "$path" ] && exit 0

case "$mode" in
  openapi)
    case "$path" in
      *talaria-openapi.yaml*) ;;
      *) exit 0 ;;
    esac
    event="PreToolUse"
    msg="WARNING: Editing committed API spec. Use ./Scripts/update-api-spec.sh instead."
    ;;
  swift)
    case "$path" in
      *.swift) ;;
      *) exit 0 ;;
    esac
    event="PostToolUse"
    msg="🔨 Swift file changed — run /build-sim to verify 0 errors, 0 warnings"
    ;;
  *)
    exit 0
    ;;
esac

printf '%s\n' "$msg" >&2
jq -n --arg event "$event" --arg ctx "$msg" '{
  hookSpecificOutput: {
    hookEventName: $event,
    additionalContext: $ctx
  }
}'
exit 0
