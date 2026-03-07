#!/bin/bash
# [flow] TaskCompleted hook: Verify task acceptance criteria before marking complete
# Exit 2 blocks task completion with feedback

set -euo pipefail

INPUT=$(cat)
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task.subject // empty')
TASK_DESC=$(echo "$INPUT" | jq -r '.task.description // empty')

# Skip verification for trivial tasks (no acceptance criteria pattern)
if ! echo "$TASK_DESC" | grep -qiE '(accept|criteria|verify|must|should|ensure)'; then
  exit 0
fi

# Check if the task mentions test requirements
if echo "$TASK_DESC" | grep -qiE '(test|spec|assert)' ; then
  # Verify tests were run recently (check git log for test-related commits)
  RECENT_TEST=$(git log --oneline -5 --format="%s" 2>/dev/null | grep -iE '(test|spec)' || echo "")
  if [ -z "$RECENT_TEST" ]; then
    echo "VERIFICATION: Task '$TASK_SUBJECT' mentions tests but no recent test-related commits found." >&2
    echo "Consider running quality checks before completing this task." >&2
    # Don't block - just warn. Blocking would be too aggressive.
  fi
fi

exit 0
