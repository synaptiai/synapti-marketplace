#!/bin/bash
# [flow] PreToolUse hook: Block commands that might expose secrets
# Detects inline secrets in commands (not in env vars or files)

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Check for inline secret patterns in commands
# Matches: password=xyz, token=xyz, api_key=xyz, secret=xyz, API_KEY=xyz
if echo "$COMMAND" | grep -qiE '(password|token|api_key|secret|private_key|aws_secret|credentials)\s*=\s*['\''"]?[A-Za-z0-9+/=_-]{8,}'; then
  echo "BLOCKED: Possible secret detected in command. Use environment variables or config files instead of inline secrets." >&2
  exit 2
fi

# Check for curl with auth headers containing literal tokens
if echo "$COMMAND" | grep -qiE 'curl.*(-H|--header)\s+['\''"]?(Authorization|X-API-Key):\s*(Bearer\s+)?[A-Za-z0-9+/=_-]{20,}'; then
  echo "BLOCKED: Literal auth token detected in curl command. Use environment variables for tokens." >&2
  exit 2
fi

exit 0
