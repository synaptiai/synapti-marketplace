---
name: preflight-checks
description: "Validate environment prerequisites including clean git state, issue existence, gh CLI authentication, and remote accessibility using fast bash checks with no LLM calls. Use when starting any workflow to fail fast before planning begins."
allowed-tools: Bash
context: fork
agent: general-purpose
---

# Pre-flight Checks

Pure bash validation that runs before any LLM reasoning. Fail fast, save tokens.

## Iron Law

**NO LLM CALLS IN PRE-FLIGHT.** Every check is a bash command with a pass/fail exit code. If pre-flight fails, the workflow stops before spending any tokens on planning.

## Checks

Run all checks in a single Bash call:

```bash
ERRORS=0
WARNINGS=0

# 1. Git state is clean (no uncommitted changes that could conflict)
if [ -n "$(git status --porcelain)" ]; then
  echo "PREFLIGHT FAIL: Uncommitted changes detected. Commit or stash before starting."
  ERRORS=$((ERRORS+1))
fi

# 2. Not on detached HEAD
if ! git symbolic-ref HEAD >/dev/null 2>&1; then
  echo "PREFLIGHT FAIL: Detached HEAD. Checkout a branch first."
  ERRORS=$((ERRORS+1))
fi

# 3. gh CLI authenticated
if ! gh auth status >/dev/null 2>&1; then
  echo "PREFLIGHT FAIL: gh CLI not authenticated. Run 'gh auth login'."
  ERRORS=$((ERRORS+1))
fi

# 4. Issue exists and is open
ISSUE_STATE=$(gh issue view $ARGUMENTS --json state --jq '.state' 2>/dev/null)
if [ "$ISSUE_STATE" != "OPEN" ]; then
  echo "PREFLIGHT FAIL: Issue #$ARGUMENTS not found or not open (state: ${ISSUE_STATE:-not found})."
  ERRORS=$((ERRORS+1))
fi

# 5. Remote is accessible
if ! git ls-remote --exit-code origin >/dev/null 2>&1; then
  echo "PREFLIGHT FAIL: Cannot reach remote 'origin'."
  ERRORS=$((ERRORS+1))
fi

# 6. Already on a feature branch for this issue (warning only)
CURRENT_BRANCH=$(git branch --show-current)
if echo "$CURRENT_BRANCH" | grep -q "issue-$ARGUMENTS"; then
  echo "PREFLIGHT WARN: Already on branch '$CURRENT_BRANCH' for issue #$ARGUMENTS."
  WARNINGS=$((WARNINGS+1))
fi

echo ""
echo "PREFLIGHT RESULT: $ERRORS error(s), $WARNINGS warning(s)"
[ $ERRORS -gt 0 ] && echo "PREFLIGHT: BLOCKED — fix errors above before proceeding." && exit 1
echo "PREFLIGHT: PASSED"
```

## Behavior

- **ERRORS** (any > 0): Halt workflow. Do not proceed to EXPLORE.
- **WARNINGS** (errors = 0): Note in output, proceed normally.
- No LLM calls, no Agent dispatches, no Skill invocations.
- Total execution: one Bash call, sub-second.

## When to Use

Invoked as Phase 0 of `/flow:start` before the EXPLORE phase. Substitute `$ARGUMENTS` with the issue number from command arguments.
