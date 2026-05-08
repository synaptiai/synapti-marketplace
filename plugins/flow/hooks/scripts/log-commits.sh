#!/bin/bash
# [flow] PostToolUse hook: Log git commits to decision journal
# Runs after Bash operations to capture commit decisions

set -euo pipefail

# Graceful: if jq unavailable, skip logging
command -v jq &>/dev/null || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only process git commit commands
echo "$COMMAND" | grep -qE 'git\s+commit' || exit 0

# Determine journal directory from the standard Claude Code settings cascade
# (highest first): project-local → project-shared → user-global → plugin default.
JOURNAL_DIR=".decisions"
for SETTINGS_FILE in ".claude/settings.flow.local.json" ".claude/settings.flow.json" "${HOME:-/nonexistent}/.claude/settings.flow.json" "${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json"; do
  if [ -f "$SETTINGS_FILE" ]; then
    DIR=$(jq -r '.journal.dir // empty' "$SETTINGS_FILE" 2>/dev/null)
    [ -n "$DIR" ] && JOURNAL_DIR="$DIR" && break
  fi
done

# Get current branch and issue number
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+' || echo "")

# Determine journal file
if [ -n "$ISSUE_NUM" ]; then
  JOURNAL_FILE="$JOURNAL_DIR/issue-$ISSUE_NUM.md"
else
  JOURNAL_FILE="$JOURNAL_DIR/session-$(date +%Y-%m-%d).md"
fi

# Only log if journal exists
if [ -d "$JOURNAL_DIR" ] && [ -f "$JOURNAL_FILE" ]; then
  # Refuse if the journal path is a symlink. After `gh pr checkout` of a
  # hostile fork, attacker-staged `.decisions/issue-N.md` could be a symlink
  # to `~/.bashrc`, `~/.ssh/authorized_keys`, etc.; bash `>>` follows
  # symlinks and would append our auto-log lines (with a partially
  # attacker-controlled commit subject) to the symlink target. Skip silently
  # — this hook is best-effort journal logging, not a security boundary.
  [ -L "$JOURNAL_FILE" ] && exit 0

  TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
  LAST_MSG=$(git log -1 --format="%s" 2>/dev/null || echo "unknown")

  # Guard 1: skip explicit housekeeping commits ("chore(decisions): ...")
  case "$LAST_MSG" in
    "chore(decisions):"*) exit 0 ;;
  esac

  # Guard 2: skip if the most recent commit only touched the journal file itself.
  # Both $CHANGED (from git diff-tree) and $JOURNAL_FILE are repo-relative, so
  # exact equality is sufficient as long as JOURNAL_DIR stays relative.
  CHANGED=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null || echo "")
  if [ "$CHANGED" = "$JOURNAL_FILE" ]; then
    exit 0
  fi

  # Sanitize the commit subject before embedding it inside an HTML comment.
  # An attacker-supplied subject containing `-->` would close the comment
  # early; subsequent text would land in the journal as renderable markdown,
  # which `/flow:explain` and `/flow:review` later feed back to Claude as
  # context — a prompt-injection vector against future sessions.
  LAST_MSG_SAFE=${LAST_MSG//-->/-- >}
  LAST_MSG_SAFE=${LAST_MSG_SAFE//<!--/< !--}

  echo "" >> "$JOURNAL_FILE"
  echo "<!-- auto-log: $TIMESTAMP commit \"$LAST_MSG_SAFE\" -->" >> "$JOURNAL_FILE"
fi

exit 0
