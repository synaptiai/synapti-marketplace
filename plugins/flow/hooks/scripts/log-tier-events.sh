#!/bin/bash
# [flow] PostToolUse hook: Log Tier 2 / Tier 3 events to decision journal
# Runs after Bash operations to capture team-visible (T2) and confirm-required (T3) actions.
# T2: git push (non-force), gh pr create, gh issue edit --add-assignee
# T3: gh pr merge, gh release create
# T1 commits are handled by log-commits.sh; T1 file edits by log-file-changes.sh.

set -euo pipefail

# Graceful: if jq unavailable, skip logging
command -v jq &>/dev/null || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Skip if no command
[ -z "$COMMAND" ] && exit 0

# Detect tier and action — first match wins (mixed-tier commands log only the leading action)
TIER=""
ACTION=""

# Tier 3 (most consequential — check first so a `gh pr merge` masquerading as a push lands as T3)
if echo "$COMMAND" | grep -qE '(^|[[:space:];|&])gh\s+pr\s+merge\b'; then
  TIER="T3"
  ACTION="merge"
elif echo "$COMMAND" | grep -qE '(^|[[:space:];|&])gh\s+release\s+create\b'; then
  TIER="T3"
  ACTION="release"
# Tier 2
elif echo "$COMMAND" | grep -qE '(^|[[:space:];|&])gh\s+pr\s+create\b'; then
  TIER="T2"
  ACTION="pr-create"
elif echo "$COMMAND" | grep -qE '(^|[[:space:];|&])gh\s+issue\s+edit\b' && echo "$COMMAND" | grep -qE -- '--add-assignee\b'; then
  TIER="T2"
  ACTION="issue-assign"
elif echo "$COMMAND" | grep -qE '(^|[[:space:];|&])git\s+push\b'; then
  # git push is T2 even when --force-with-lease (the lease variant is journal-allowed; plain --force is hook-blocked elsewhere)
  TIER="T2"
  ACTION="push"
else
  exit 0
fi

# Determine journal directory from settings
JOURNAL_DIR=".decisions"
for SETTINGS_FILE in ".claude/settings.flow.local.json" ".claude/settings.flow.json" "$HOME/.claude/settings.flow.json" "plugins/flow/settings.json"; do
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

# Only log if journal file exists (init creates it)
if [ -d "$JOURNAL_DIR" ] && [ -f "$JOURNAL_FILE" ]; then
  TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
  echo "" >> "$JOURNAL_FILE"
  echo "<!-- auto-log: $TIMESTAMP $TIER $ACTION -->" >> "$JOURNAL_FILE"
fi

exit 0
