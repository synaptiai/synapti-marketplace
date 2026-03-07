#!/bin/bash
# [flow] PreToolUse hook: Tier 3 gate for release operations
# Intercepts `gh release create` and requires explicit confirmation

set -euo pipefail

# Fail-safe: if jq unavailable, block rather than allow
if ! command -v jq &>/dev/null; then
  echo "BLOCKED: jq not available — cannot verify command safety. Install jq to proceed." >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only intercept gh release create commands
if echo "$COMMAND" | grep -qE 'gh\s+release\s+create'; then
  # Extract tag: anything after 'create' that looks like a version/tag
  TAG=$(echo "$COMMAND" | sed -E 's/.*create\s+//' | awk '{print $1}' || echo "unknown")
  echo "GATE: Release is a Tier 3 action requiring human confirmation." >&2
  echo "Release tag '${TAG}' creation was requested. Please confirm this action explicitly." >&2
  echo "The /flow:release command handles changelog and verification before reaching this point." >&2
  exit 2
fi

exit 0
