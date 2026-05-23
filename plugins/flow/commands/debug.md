---
description: "Debug an issue with structured root cause analysis. Guides evidence gathering, hypothesis testing, and fix validation."
argument-hint: [description-or-error-message]
allowed-tools: Bash, Read, Write, Edit, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations, invoke ALL relevant tools
simultaneously in a single message rather than sequentially.
-->

# Debug: $ARGUMENTS

Structured debugging with root cause analysis. Follows Explore > Plan > Code > Verify loop.

## Required Skills

This command operates with these domain skills loaded:
- `debugging-patterns` — root cause methodology, hypothesis testing
- `change-classification` — change context awareness

## Phase 1: EXPLORE

Gather all evidence before theorizing. Execute in parallel:

```!
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`.

echo "### Recent History"
# Capture into a var so an empty result emits an explicit STATE=empty
# sentinel rather than a silent heading.
RECENT_LOG=$(git log --oneline -10 2>/dev/null)
if [ -z "$RECENT_LOG" ]; then
  echo "STATE=empty"
else
  printf '%s\n' "$RECENT_LOG" | sed 's/^/COMMIT=/'
fi

echo ""
echo "### Recent Diff (last 3 commits)"
RECENT_DIFF=$(git diff HEAD~3..HEAD --stat 2>/dev/null)
if [ -z "$RECENT_DIFF" ]; then
  echo "STATE=empty"
else
  # Prefix raw stat lines with DIFF_STAT= per command-output-format.md.
  printf '%s\n' "$RECENT_DIFF" | sed 's/^/DIFF_STAT=/'
fi

echo ""
echo "### Current State"
echo "BRANCH=$(git branch --show-current 2>/dev/null)"
UNCOMMITTED_COUNT=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
echo "UNCOMMITTED_COUNT=$UNCOMMITTED_COUNT"
[ "$UNCOMMITTED_COUNT" != "0" ] && git status --short 2>/dev/null | head -20 | sed 's/^/UNCOMMITTED_LINE=/'

true
```

### FlowRun (v3 runtime)

`/flow:debug` is a long-running workflow, so it gets a durable FlowRun. The companion FlowGoal is created later (after hypothesis confirmation), so the run forward-references its id. Runs are gated by `flow.runtime.enabled` (default `true`); v2 projects that opted out see `FLOW_RUN_STATE=skip` and the wiring is a no-op.

```!
# FLOW_RUN_BLOCK_BEGIN
CASCADE="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh"
if [ ! -x "$CASCADE" ]; then
  echo "FLOW_RUN_STATE=blocked"
  echo "FLOW_RUN_ERROR=cascade-resolve.sh missing or non-executable at $CASCADE"
  true; exit 0
fi
RUNTIME_ENABLED=$("$CASCADE" --default "true" '.flow.runtime.enabled' 2>/dev/null)
if [ "$RUNTIME_ENABLED" != "true" ]; then
  echo "FLOW_RUN_STATE=skip"
  echo "FLOW_RUN_REASON=flow.runtime.enabled is not true (v2 mode)"
else
  TS="$(date -u +%Y%m%dT%H%M%SZ)"
  RUN_ID="${TS}-debug"
  echo "FLOW_RUN_STATE=create"
  echo "RUN_ID=$RUN_ID"
  echo "WORKFLOW=debug"
  echo "INITIAL_PHASE=preflight"
  echo "GOAL_LINK=debug-${TS}"
fi
# FLOW_RUN_BLOCK_END
true
```

When `FLOW_RUN_STATE=create`, invoke `Skill(run-state-management)` to create `.flow/runs/$RUN_ID/run.yaml` (workflow=`debug`, goal=`$GOAL_LINK` — the debug FlowGoal created in Phase 3 below), initial phase `preflight`. Phase order: `preflight → reproduce → diagnose → fix → verify`. Write a FlowActivity at each boundary.

**Parallel searches:**

- `Grep`: Search for error message keywords in the codebase
- `Grep`: Search for related function/class names
- `Glob`: Find test files related to the affected area

**Error context:**
- Read the full error message, stack trace, or user description from `$ARGUMENTS`
- If an error file/line is mentioned, read that file immediately
- Check logs if a log directory exists (`logs/`, `log/`, `tmp/`)

**Parallel Agent call:**

```
Agent(Explore):
  "Search the codebase for code related to: $ARGUMENTS.
   Find the affected modules, recent changes, and related tests.
   Report: affected files, last modified dates, test coverage."
```

## Phase 2: PLAN

Form hypotheses based on evidence:

```
TaskCreate("Hypothesis 1: {most likely cause}", "Confidence: High\nTest: {how to verify}\nEvidence: {what points here}")
TaskCreate("Hypothesis 2: {alternative cause}", "Confidence: Medium\nTest: {how to verify}\nEvidence: {what points here}")
TaskCreate("Hypothesis 3: {less likely cause}", "Confidence: Low\nTest: {how to verify}\nEvidence: {what points here}")
TaskCreate("Fix validation", "Write reproducing test, implement fix, verify")
```

**Rules from debugging-patterns:**
- Maximum 3 hypotheses (more means insufficient evidence — go back to EXPLORE)
- Test highest confidence first
- Test ONE at a time

Display hypothesis table for visibility.

## Phase 3: CODE

Test hypotheses one at a time:

```
For each hypothesis (highest confidence first):
  1. TaskUpdate(taskId, status: "in_progress")
  2. Design a specific test for this hypothesis
  3. Execute the test
  4. If CONFIRMED:
     a. Write a failing test that reproduces the bug
     b. Verify the test fails for the right reason
     c. Implement the fix (minimal, surgical)
     d. Verify the test now passes
     e. TaskUpdate(taskId, status: "completed")
     f. Skip remaining hypotheses
  5. If DISPROVEN:
     a. Record what was learned
     b. TaskUpdate(taskId, status: "completed", result: "disproven")
     c. Move to next hypothesis
```

**FlowGoal creation (after the confirmed hypothesis — end of the diagnose phase):** when `FLOW_RUN_STATE=create`, invoke `Skill(goal-contract-capture)` with invocation reason `debug`, goal id `$GOAL_LINK` (from the entry block), and the outcome template "The reported failure `$ARGUMENTS` is reproduced, root-caused, and a fix is verified." The acceptance criterion is the reproducing test written in step 4a; constraints come from the confirmed root cause. Then invoke `Skill(goal-lifecycle)` to transition `draft → active`, and write a FlowActivity for the diagnose→fix boundary.

**Stop conditions from debugging-patterns:**
- 3+ failed fix attempts → problem is architectural, return to EXPLORE
- Can't explain current behavior → investigate more, don't guess
- Tunnel vision → step back, list what you KNOW vs ASSUME

## Phase 4: VERIFY

1. **Run full quality suite** (parallel Bash calls for lint, test, typecheck)
2. **Verify the reproducing test passes** — the specific test written in Phase 3
3. **Check for regressions** — full test suite must still pass
4. **Visual verification** (for UI bugs only) — if the bug involves visual/rendering issues:
   Condition: `$ARGUMENTS` or issue labels mention visual/UI terms, OR the confirmed hypothesis involved UI rendering code.
   ```
   TaskCreate("Visual fix verification", "Screenshot-verify the UI bug fix resolves the visual issue")
   TaskUpdate(visualFixTaskId, status: "in_progress")
   ```
   - Take "after" screenshot to verify the fix visually
   - Compare against the bug description / expected behavior
   - Verify no visual regressions on related pages
   - Save screenshots as evidence of the fix
   ```
   TaskUpdate(visualFixTaskId, status: "completed", result: "PASS/FAIL — {description of visual state after fix}")
   ```
   If not applicable (non-UI bug): skip TaskCreate entirely.
5. **TaskList** — confirm all tasks show status: completed
6. **FlowGoal evaluation + FlowRun terminal transition** (when `FLOW_RUN_STATE=create`): invoke `Skill(goal-evaluator)` with `trigger=command` to evaluate the debug FlowGoal against the reproducing test evidence; persist the proposed lifecycle transition (the skill does not write terminal status itself). When the goal reaches `achieved`, transition the FlowRun to `state.status: completed`; if the bug could not be root-caused, transition to `state.status: blocked` (with `blocked_reason`) so `/flow:resume` can pick it up.
7. **Display summary**:
   - Root cause: {description}
   - Hypothesis confirmed: #{N}
   - Fix: {what was changed}
   - Test: {reproducing test location}
   - Quality checks: pass/fail

## Completion

Present next steps:

- `/flow:commit` — commit the fix with context
- `/flow:pr` — create pull request
- Continue investigating — if more issues remain

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read logs / stack traces / recent changes | 1 | Autonomous, read-only |
| Hypothesis tracking (max 3 at a time) | 1 | Autonomous |
| Write reproducing test (RED phase) | 1 | Autonomous |
| File edits (fix root cause) | 1 | Autonomous |
| Commits (`fix:`) | 1 | Autonomous, logged by hook |
