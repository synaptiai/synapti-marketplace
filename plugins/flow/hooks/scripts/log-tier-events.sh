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

# Strip quoted strings so trigger words inside commit messages or echo args don't false-match.
# Order matters: handle escaped quotes within strings minimally — the goal is to remove the
# bulk of quoted content so it can't appear as a "command" in pattern matching.
UNQUOTED=$(printf '%s' "$COMMAND" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")

# Detect tier and action. T3 checked first (highest tier wins on mixed-tier commands like
# `gh pr merge && git push`). Anchor patterns require keyword to follow a command boundary
# (BOL, whitespace, ;, |, &, (, \`) and to be terminated by whitespace, end-of-string, or
# another non-word char excluding hyphens — avoids matching `git push-foo`, `gh pr-merge`.
ANCHOR='(^|[[:space:];|&(`])'
END='([[:space:]]|$|[^a-zA-Z0-9_-])'

TIER=""
ACTION=""

# Tier 3
if echo "$UNQUOTED" | grep -qE "${ANCHOR}gh[[:space:]]+pr[[:space:]]+merge${END}"; then
  TIER="T3"
  ACTION="merge"
elif echo "$UNQUOTED" | grep -qE "${ANCHOR}gh[[:space:]]+release[[:space:]]+create${END}"; then
  TIER="T3"
  ACTION="release"
# Tier 2
elif echo "$UNQUOTED" | grep -qE "${ANCHOR}gh[[:space:]]+pr[[:space:]]+create${END}"; then
  TIER="T2"
  ACTION="pr-create"
elif echo "$UNQUOTED" | grep -qE "${ANCHOR}gh[[:space:]]+issue[[:space:]]+edit${END}" && echo "$UNQUOTED" | grep -qE -- '(^|[[:space:]])--add-assignee([[:space:]]|=|$)'; then
  TIER="T2"
  ACTION="issue-assign"
elif echo "$UNQUOTED" | grep -qE "${ANCHOR}git[[:space:]]+push${END}"; then
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
