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

# Determine journal directory. Excludes repo-local settings sources to keep
# a hostile fork PR from redirecting hook writes after `gh pr checkout` —
# same defense pattern as merge.markerTrust + agentTeams. User-global and
# plugin defaults only.
JOURNAL_DIR=".decisions"
for SETTINGS_FILE in "$HOME/.claude/settings.flow.json" "${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json"; do
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

  echo "" >> "$JOURNAL_FILE"
  echo "<!-- auto-log: $TIMESTAMP commit \"$LAST_MSG\" -->" >> "$JOURNAL_FILE"
fi

exit 0
