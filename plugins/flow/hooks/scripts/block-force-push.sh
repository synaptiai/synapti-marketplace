#!/bin/bash
# [flow] PreToolUse hook: Block force-push operations
# Exit 2 = block the tool call with feedback message

set -euo pipefail

# Read tool input from stdin
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Check for force-push patterns
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*(-f|--force|--force-with-lease)'; then
  echo "BLOCKED: Force-push detected. This is a Tier 3 action that requires manual execution." >&2
  echo "If you need to force-push, ask the user to run the command directly." >&2
  exit 2
fi

exit 0
