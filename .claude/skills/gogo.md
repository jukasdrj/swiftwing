---
name: gogo
version: "1.0.0"
description: Commit staged changes and push to remote. Quick workflow for continuous integration without creating PRs.
allowed-tools: Bash, Read, Grep
---

# Gogo - Commit and Push

Fast commit and push workflow for SwiftWing development.

## What This Does

1. Analyzes staged changes with `git status` and `git diff`
2. Reviews recent commit messages for style consistency
3. Creates a commit with AI-generated message following project conventions
4. Pushes to remote origin

## Usage

```bash
/gogo
```

Or with custom message:
```bash
/gogo -m "feat: US-XXX - Custom commit message"
```

## Commit Message Format

Follows SwiftWing conventions:
- **feat:** New feature (e.g., "feat: US-206 - Add camera zoom controls")
- **fix:** Bug fix
- **refactor:** Code refactoring
- **docs:** Documentation updates
- **test:** Test additions/modifications
- **chore:** Build/tooling changes

## Attribution

All commits include:
```
Co-Authored-By: Claude Code <noreply@anthropic.com>
```

## Safety

- Never commits files with secrets (.env, .dev.vars, credentials)
- Warns if committing large files (>1MB)
- Shows diff before committing
- Validates Swift syntax if files are staged

## When to Use

✅ **Use /gogo when:**
- Working on a feature branch
- Making incremental progress commits
- Syncing work across machines
- Epic-based vertical slice development

❌ **Don't use /gogo when:**
- Ready to create a pull request (use /commit-push-pr instead)
- Committing to main branch (requires review)
- Large architectural changes (commit + create PR manually)

## Pre-commit Validation

Before committing, validates:
1. No sensitive files staged (.env, .dev.vars, keys)
2. Swift files have valid syntax
3. No hardcoded secrets in code
4. Commit message follows format

## Example Workflow

```bash
# Epic 2 - Camera integration work
# Make changes to CameraActor.swift
# Stage changes
git add swiftwing/Services/CameraActor.swift

# Quick commit and push
/gogo

# AI generates:
# "feat: US-203 - Implement camera session management
#
# - Add CameraActor for thread-safe session control
# - Implement startSession() and stopSession()
# - Add permission handling
#
# Co-Authored-By: Claude Code <noreply@anthropic.com>"

# Pushed to origin/your-branch-name
```

## Configuration

Respects `.claude/settings.json` attribution settings.

## Safety Mechanisms

- **Never** stages unstaged files automatically
- **Never** commits without user confirmation of message
- **Never** force pushes
- **Always** shows what will be committed

---

**Last Updated:** January 22, 2026
**For:** SwiftWing iOS development
**Epic Context:** All epics (1-6)
