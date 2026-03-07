#!/bin/bash
# [flow] TeammateIdle hook: Nudge idle teammates toward unclaimed tasks
# Exit 2 sends feedback to the idle teammate

set -euo pipefail

# Graceful: if jq unavailable, skip nudge
command -v jq &>/dev/null || exit 0

INPUT=$(cat)
TEAMMATE_ID=$(echo "$INPUT" | jq -r '.teammate.id // empty')
IDLE_SECONDS=$(echo "$INPUT" | jq -r '.idle_seconds // 0')

# Only nudge after significant idle time (>60s)
if [ "$IDLE_SECONDS" -lt 60 ] 2>/dev/null; then
  exit 0
fi

# TeammateIdle: exit 0 always. Feedback is delivered via stderr output.
# exit 2 has no defined semantics for this event type.
echo "You've been idle for ${IDLE_SECONDS}s. Check the shared task list for unclaimed tasks." >&2
echo "Use TaskList to find pending tasks and TaskUpdate to claim one." >&2
exit 0
