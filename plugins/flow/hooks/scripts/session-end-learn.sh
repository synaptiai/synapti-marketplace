#!/bin/bash
# [flow] SessionEnd hook: Flag pending learning analysis
# Lightweight — only marks pending, does NOT run full analysis (too slow for session end)

set -euo pipefail

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# Determine journal directory
JOURNAL_DIR=".decisions"
for SETTINGS_FILE in ".claude/settings.flow.local.json" ".claude/settings.flow.json" "$HOME/.claude/settings.flow.json"; do
  if [ -f "$SETTINGS_FILE" ]; then
    DIR=$(jq -r '.journal.dir // empty' "$SETTINGS_FILE" 2>/dev/null)
    [ -n "$DIR" ] && JOURNAL_DIR="$DIR" && break
  fi
done

# Check if learning is enabled
LEARNING_ENABLED="true"
for SETTINGS_FILE in ".claude/settings.flow.local.json" ".claude/settings.flow.json" "$HOME/.claude/settings.flow.json"; do
  if [ -f "$SETTINGS_FILE" ]; then
    ENABLED=$(jq -r '.learning.enabled // empty' "$SETTINGS_FILE" 2>/dev/null)
    [ -n "$ENABLED" ] && LEARNING_ENABLED="$ENABLED" && break
  fi
done

[ "$LEARNING_ENABLED" != "true" ] && exit 0

# Check if journal has entries from today
TODAY=$(date +%Y-%m-%d)
HAS_ENTRIES=false
for JFILE in "$JOURNAL_DIR"/*.md; do
  [ -f "$JFILE" ] || continue
  if grep -q "$TODAY" "$JFILE" 2>/dev/null; then
    HAS_ENTRIES=true
    break
  fi
done

# Flag for next session if there are today's entries
if [ "$HAS_ENTRIES" = "true" ]; then
  PENDING_DIR="${HOME}/.claude"
  mkdir -p "$PENDING_DIR"
  echo "$TODAY" > "$PENDING_DIR/flow-learn-pending"
fi

exit 0
