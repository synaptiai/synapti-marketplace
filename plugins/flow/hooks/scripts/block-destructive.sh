#!/bin/bash
# [flow] PreToolUse hook: Block destructive operations
# Prevents rm -rf, branch deletion, and checkout destructive resets

set -euo pipefail

# Fail-safe: if jq unavailable, block rather than allow
if ! command -v jq &>/dev/null; then
  echo "BLOCKED: jq not available — cannot verify command safety. Install jq to proceed." >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Block rm -rf (except in safe dirs like node_modules, build artifacts)
# Handles: rm -rf, rm -fr, rm -r -f, and multiple path arguments
SAFE_DIRS="node_modules|\.next|dist|build|tmp|\.cache|__pycache__|coverage|\.turbo|\.parcel-cache|\.vite"
if echo "$COMMAND" | grep -qE 'rm\s+(-[rfRF]+\s+)+|rm\s+(-[a-zA-Z]\s+)*-[a-zA-Z]*[rR][a-zA-Z]*\s+.*-[a-zA-Z]*[fF]|rm\s+(-[a-zA-Z]\s+)*-[a-zA-Z]*[fF][a-zA-Z]*\s+.*-[a-zA-Z]*[rR]'; then
  # Extract paths: remove 'rm' and all flag arguments (use [[:space:]] for macOS sed)
  PATHS=$(echo "$COMMAND" | sed -E 's/^rm[[:space:]]+//; s/-[a-zA-Z]+[[:space:]]*//g')
  ALL_SAFE=true
  for P in $PATHS; do
    BASENAME=$(basename "$P")
    if ! echo "$BASENAME" | grep -qE "^($SAFE_DIRS)$"; then
      ALL_SAFE=false
      break
    fi
  done
  if [ "$ALL_SAFE" = "false" ]; then
    echo "BLOCKED: Destructive rm -rf detected. Review the target path and run manually if intended." >&2
    exit 2
  fi
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
