#!/bin/bash
# [flow] PreToolUse hook: Tier 3 gate for release operations
# Intercepts `gh release create` and requires explicit confirmation

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only intercept gh release create commands
if echo "$COMMAND" | grep -qE 'gh\s+release\s+create'; then
  TAG=$(echo "$COMMAND" | grep -oE 'create\s+[v0-9][^\s]*' | sed 's/create\s*//' || echo "unknown")
  echo "GATE: Release is a Tier 3 action requiring human confirmation." >&2
  echo "Release tag '${TAG}' creation was requested. Please confirm this action explicitly." >&2
  echo "The /flow:release command handles changelog and verification before reaching this point." >&2
  exit 2
fi

exit 0
