#!/bin/bash
# [flow] PostToolUse hook: Log file edits to decision journal
# Runs after Edit|Write operations to maintain audit trail

set -euo pipefail

# Graceful: if jq unavailable, skip logging
command -v jq &>/dev/null || exit 0

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Skip if no file path
[ -z "$FILE_PATH" ] && exit 0

# Determine journal directory via bin/cascade-resolve.sh. Gracefully fall back
# to the default when the helper is unreachable — hooks run from arbitrary
# CWDs and CLAUDE_PLUGIN_ROOT may not always be set (e.g., in test harnesses
# that exercise the hook standalone).
HELPER="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh"
JOURNAL_DIR=".decisions"
[ -x "$HELPER" ] && JOURNAL_DIR=$("$HELPER" --default ".decisions" '.journal.dir // empty' 2>/dev/null)

# Get current branch and issue number
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+' || echo "")

# Determine journal file
if [ -n "$ISSUE_NUM" ]; then
  JOURNAL_FILE="$JOURNAL_DIR/issue-$ISSUE_NUM.md"
else
  JOURNAL_FILE="$JOURNAL_DIR/session-$(date +%Y-%m-%d).md"
fi

# Only log if journal directory exists (init creates it)
if [ -d "$JOURNAL_DIR" ] && [ -f "$JOURNAL_FILE" ]; then
  # Refuse if the journal path is a symlink — see log-commits.sh for the
  # threat model. Both hooks share the same risk surface.
  [ -L "$JOURNAL_FILE" ] && exit 0

  TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
  # Sanitize tool-name and file-path before embedding in the HTML comment;
  # `-->` would close the comment early and inject arbitrary markdown into
  # the journal that `/flow:explain` later feeds back to Claude.
  TOOL_NAME_SAFE=${TOOL_NAME//-->/-- >}
  TOOL_NAME_SAFE=${TOOL_NAME_SAFE//<!--/< !--}
  FILE_PATH_SAFE=${FILE_PATH//-->/-- >}
  FILE_PATH_SAFE=${FILE_PATH_SAFE//<!--/< !--}
  echo "" >> "$JOURNAL_FILE"
  echo "<!-- auto-log: $TIMESTAMP $TOOL_NAME_SAFE $FILE_PATH_SAFE -->" >> "$JOURNAL_FILE"
fi

exit 0
