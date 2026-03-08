---
description: "[flow] Debug an issue with structured root cause analysis. Guides evidence gathering, hypothesis testing, and fix validation."
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

**Parallel Bash calls:**

```bash
# 1. Recent changes that might have introduced the bug
git log --oneline -10

# 2. Recent diff
git diff HEAD~3..HEAD --stat

# 3. Current state
git status --short
git branch --show-current
```

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
6. **Display summary**:
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
