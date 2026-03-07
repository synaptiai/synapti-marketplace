#!/bin/bash
# [flow] PreToolUse hook: Tier 3 gate for merge operations
# Intercepts `gh pr merge` and requires explicit confirmation

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only intercept gh pr merge commands
if echo "$COMMAND" | grep -qE 'gh\s+pr\s+merge'; then
  # Extract PR number if present
  PR_NUM=$(echo "$COMMAND" | grep -oE 'merge\s+[0-9]+' | grep -oE '[0-9]+' || echo "unknown")
  echo "GATE: Merge is a Tier 3 action requiring human confirmation." >&2
  echo "PR #${PR_NUM} merge was requested. Please confirm this action explicitly." >&2
  echo "The /flow:merge command handles prerequisite verification before reaching this point." >&2
  exit 2
fi

exit 0
