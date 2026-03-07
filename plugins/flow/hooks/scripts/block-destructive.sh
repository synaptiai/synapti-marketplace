#!/bin/bash
# [flow] PreToolUse hook: Block destructive operations
# Prevents rm -rf, branch deletion, and checkout destructive resets

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Block rm -rf (except in safe dirs like node_modules, .git, build artifacts)
if echo "$COMMAND" | grep -qE 'rm\s+(-rf|-fr|--recursive\s+--force)\s+' && \
   ! echo "$COMMAND" | grep -qE 'rm\s+(-rf|-fr)\s+(node_modules|\.next|dist|build|tmp|\.cache|__pycache__)'; then
  echo "BLOCKED: Destructive rm -rf detected. Review the target path and run manually if intended." >&2
  exit 2
fi

# Block git branch -D (force delete)
if echo "$COMMAND" | grep -qE 'git\s+branch\s+-D\s'; then
  echo "BLOCKED: Force branch deletion detected. Use 'git branch -d' for safe delete, or run -D manually." >&2
  exit 2
fi

# Block git checkout -- . (discard all changes)
if echo "$COMMAND" | grep -qE 'git\s+checkout\s+--\s+\.'; then
  echo "BLOCKED: Discarding all changes detected. Use selective checkout or stash instead." >&2
  exit 2
fi

# Block git reset --hard
if echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard'; then
  echo "BLOCKED: Hard reset detected. This discards uncommitted work. Run manually if intended." >&2
  exit 2
fi

# Block git clean -f (force clean untracked files)
if echo "$COMMAND" | grep -qE 'git\s+clean\s+.*-f'; then
  echo "BLOCKED: Force clean detected. This removes untracked files permanently. Run manually if intended." >&2
  exit 2
fi

exit 0
