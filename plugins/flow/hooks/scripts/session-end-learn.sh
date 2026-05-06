#!/bin/bash
# [flow] SessionEnd hook: Flag pending learning analysis
# Lightweight — only marks pending, does NOT run full analysis (too slow for session end).
#
# Detects "recent activity" by file mtime rather than grepping for today's date string.
# The previous grep approach false-matched dates that appeared inside journal *content*
# (e.g. due-date references in older entries) rather than only matching entries actually
# written today. `find -mtime -1` is portable across BSD (macOS) and GNU find.

set -euo pipefail

# Graceful: if jq unavailable, skip learning
command -v jq &>/dev/null || exit 0

# Drain stdin (Claude Code passes JSON; reading prevents SIGPIPE on the writer side
# even though we currently do not consume any field from the payload).
INPUT=$(cat)
: "${INPUT:=}"  # silence "unused" warnings under set -u without dropping the drain

# Determine journal directory
JOURNAL_DIR=".decisions"
for SETTINGS_FILE in ".claude/settings.flow.local.json" ".claude/settings.flow.json" "$HOME/.claude/settings.flow.json" "plugins/flow/settings.json"; do
  if [ -f "$SETTINGS_FILE" ]; then
    DIR=$(jq -r '.journal.dir // empty' "$SETTINGS_FILE" 2>/dev/null)
    [ -n "$DIR" ] && JOURNAL_DIR="$DIR" && break
  fi
done

# Check if learning is enabled
LEARNING_ENABLED="true"
for SETTINGS_FILE in ".claude/settings.flow.local.json" ".claude/settings.flow.json" "$HOME/.claude/settings.flow.json" "plugins/flow/settings.json"; do
  if [ -f "$SETTINGS_FILE" ]; then
    ENABLED=$(jq -r '.learning.enabled // empty' "$SETTINGS_FILE" 2>/dev/null)
    [ -n "$ENABLED" ] && LEARNING_ENABLED="$ENABLED" && break
  fi
done

[ "$LEARNING_ENABLED" != "true" ] && exit 0

# Flag for next session if any journal file has been modified in the last 24 hours.
# Using mtime rather than content-grep avoids false positives on dates appearing in
# journal *content* (due-date references, links, etc.) and avoids false negatives on
# entries written without a date header.
if [ -d "$JOURNAL_DIR" ] && [ -n "$(find "$JOURNAL_DIR" -maxdepth 1 -name '*.md' -mtime -1 -print -quit 2>/dev/null)" ]; then
  PENDING_DIR="${HOME}/.claude"
  mkdir -p "$PENDING_DIR"
  date +%Y-%m-%d > "$PENDING_DIR/flow-learn-pending"
fi

exit 0
