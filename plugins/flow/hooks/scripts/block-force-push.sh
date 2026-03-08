#!/bin/bash
# [flow] PreToolUse hook: Block force-push operations
# Exit 2 = block the tool call with feedback message

set -euo pipefail

# Fail-safe: if jq unavailable, block rather than allow
if ! command -v jq &>/dev/null; then
  echo "BLOCKED: jq not available — cannot verify command safety. Install jq to proceed." >&2
  exit 2
fi

# Read tool input from stdin
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Allow --force-with-lease (safe remote-aware push) but block --force and -f
# When both --force and --force-with-lease are present, --force wins → block
# Strategy: strip --force-with-lease first, then check for remaining force flags
STRIPPED=$(echo "$COMMAND" | sed 's/--force-with-lease//g')
if echo "$STRIPPED" | grep -qE 'git\s+push\s+.*(-f|--force)\b'; then
  echo "BLOCKED: Force-push detected. This is a Tier 3 action that requires manual execution." >&2
  echo "If you need to force-push, ask the user to run the command directly." >&2
  echo "Note: --force-with-lease is allowed as a safe alternative." >&2
  exit 2
fi

exit 0
