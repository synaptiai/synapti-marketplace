---
description: "[flow] Start work on a GitHub issue. Assigns issue, creates branch, decomposes tasks from acceptance criteria, and guides implementation with autonomous execution."
argument-hint: <issue-number-or-url>
allowed-tools: Bash, Read, Write, Edit, Agent, Skill, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, TaskGet, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, API calls, TaskCreate),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.

VARIABLE PERSISTENCE NOTE:
Bash variables do NOT persist across separate tool calls. Each Bash invocation
is independent. Store values mentally and substitute in subsequent commands.
-->

# Start Work on Issue #$ARGUMENTS

Skill-driven workflow from issue assignment through implementation. Follows the Explore > Plan > Code > Verify loop with Task-driven progress tracking.

## Required Skills

This command operates with these domain skills loaded:
- `branch-and-task-management` — branch creation, task decomposition
- `change-classification` — change context awareness
- `capability-discovery` — detect available quality tools
- `debugging-patterns` — activates on-demand for ALL issues when any verification step fails (not gated on `bug` label)

## Phase 1: EXPLORE

Gather all context before planning.

**Bug issue detection**: If issue labels include `bug`:
- Phase 3 becomes: reproduce → isolate root cause → write failing test → fix → verify

**Note**: `debugging-patterns` activates automatically for ALL issues when any verification step fails (build, test, server start, smoke test). No `bug` label required.

Execute these in parallel:

**Parallel Bash calls:**

```bash
# 1. Issue details
gh issue view $ARGUMENTS --json title,body,labels,assignees,milestone

# 2. Issue comments
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
gh api repos/$REPO/issues/$ARGUMENTS/comments --jq '.[] | "---\n@\(.user.login):\n\(.body)\n"'

# 3. Default branch and repo info
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
echo "DEFAULT_BRANCH=$DEFAULT_BRANCH"

# 4. Current git state
git status --short
git branch --show-current
```

**Parallel Agent + Skill calls:**

- `Agent(Explore)`: "Read CLAUDE.md (.claude/CLAUDE.md or CLAUDE.md). Identify tech stack, testing commands, coding conventions, and any project-specific rules. Also search for code related to the issue keywords to understand affected modules."
- `Skill(capability-discovery)`: Discover available agents, quality commands, and tech stack.

**Assign the issue:**

```bash
gh issue edit $ARGUMENTS --add-assignee @me
```

## Phase 2: PLAN

Create branch and decompose tasks.

**Branch creation** (Tier 1 — autonomous):

```bash
git fetch origin $DEFAULT_BRANCH
git checkout -b "feature/issue-$ARGUMENTS-{kebab-desc}" "origin/$DEFAULT_BRANCH"
```

**Initialize decision journal:**

```bash
mkdir -p .decisions
```

Write journal header to `.decisions/issue-$ARGUMENTS.md`.

**Task decomposition** — dispatch implementation-planner agent:

```
Agent(implementation-planner):
  "Parse acceptance criteria from issue #$ARGUMENTS and create tasks.
   Issue context: {pre-fetched issue title, body, comments}

   For each acceptance criterion, use TaskCreate with:
   - subject: imperative description
   - description: criterion text + likely files + verification method

   Set dependencies with TaskUpdate(addBlockedBy).
   Identify parallel execution opportunities.
   Return: task list, dependency graph, suggested order."
```

Display task plan. Proceed unless user objects.

## Phase 3: CODE

**TDD guidance**: Apply `tdd-patterns` knowledge during implementation:
- For each task: write failing test → implement → verify test passes → refactor
- Check `settings.json` → `testing.tddMode` for enforcement level

Execute tasks following the task-driven loop:

```
For each task (in dependency order):
  1. TaskUpdate(taskId, status: "in_progress")
  2. Read relevant files (follow existing patterns)
  3. Implement the change
  4. Run related tests if available
  5. Incremental commit (Tier 1: autonomous)
  6. TaskUpdate(taskId, status: "completed")
```

**Parallel task detection**: If tasks have no overlapping files and agent teams are enabled, suggest parallel execution via agent team.

**Quality loop** (bounded by `qualityCheckMaxIterations`):

```bash
# Run quality commands discovered in Phase 1 (parallel)
$LINT_CMD
$TEST_CMD
$TYPECHECK_CMD
```

If failures: fix and re-run. After max iterations, escalate to user.

**Build-and-run verification** (before proceeding to Phase 4):

1. **Build the project** → if build fails, apply debugging-patterns: read errors, fix, rebuild (up to `closedLoop.maxBuildIterations`)
2. **Start dev server** (if applicable) → if won't start, read logs, fix, retry (up to `closedLoop.maxServerRetries`)
3. **Smoke test** → hit key endpoints or run the CLI with sample input
4. If any step fails → enter debug-fix-retest loop. Do NOT proceed to Phase 4 until code builds and runs.

Only skip for config-only or markdown-only changes with explicit justification.

## Phase 4: VERIFY

Prove everything works with fix-forward:

1. **Run full quality suite** (parallel Bash calls for lint, test, typecheck)
2. **Runtime verification** (MANDATORY — not conditional on skill availability):
   - Build the project if not already built in Phase 3
   - Start dev server if applicable, smoke test endpoints
   - Only skip for markdown-only or config-only projects with explicit justification
3. **Self-review with fix-forward** — dispatch Agent(code-reviewer):
   ```
   Agent(code-reviewer):
     "Review the diff on this branch against $DEFAULT_BRANCH.
      Check for: logic errors, security issues, missing edge cases,
      convention violations. Return P1/P2/P3 findings with file:line."
   ```
   **Fix-forward** (max `fixForwardMaxIterations`, default 2):
   - P1 findings → fix immediately (you just wrote this code, no "pre-existing" excuse)
   - P2 findings → fix immediately
   - P3 findings → fix if contained (<10 lines, same file), otherwise note for PR body
   - After fixes: re-run quality commands, then targeted re-review on files changed by fixes
4. **TaskList** — confirm all tasks show status: completed
5. **Visual verification** — if UI-relevant changes detected (changed .tsx/.jsx/.vue/.html/.css/.scss files OR acceptance criteria mention UI/page/render/display):
   ```
   TaskCreate("Visual verification", "Screenshot-analyze-verify for UI-facing changes")
   TaskCreate("Browser tool discovery", "Detect available browser automation tools")
   TaskCreate("Responsive check", "Verify UI across configured viewports")
   ```
   - `TaskUpdate(browserToolTaskId, status: "in_progress")` → detect browser tools → `TaskUpdate(browserToolTaskId, status: "completed", result: "{tool or SKIP}")`
   - `TaskUpdate(visualVerificationTaskId, status: "in_progress")` → take screenshots of affected pages at configured viewports → analyze visually → record findings (P1 blocks completion, P2 noted) → save screenshot evidence to `visualVerification.screenshotDir` → `TaskUpdate(visualVerificationTaskId, status: "completed", result: "PASS/FAIL — {summary}")`
   - `TaskUpdate(responsiveTaskId, status: "in_progress")` → test each viewport → `TaskUpdate(responsiveTaskId, status: "completed", result: "{viewports tested}")`
   - If not applicable (no UI files): `TaskUpdate` all three as completed with result "SKIP"
   - If browser tools not found and `requireVisualVerification: false`: result is "SKIP_WARN"
   - If browser tools not found and `requireVisualVerification: true`: result is "BLOCKED"
   - `TaskList` — confirm all visual verification tasks resolved
6. **Completion gate**: ALL of:
   - All quality checks pass
   - Runtime verification passed (or justified N/A for config/markdown-only)
   - No unresolved P1 findings
   - All tasks completed
   - Visual verification: no BLOCKED results (see escalation below)

   **Visual verification escalation**: If any visual verification task has result containing "BLOCKED", use `AskUserQuestion`:
   > Visual verification is required (`requireVisualVerification: true`) but no browser tools are available.
   > UI files changed: {list of changed .tsx/.jsx/.vue/.html/.css/.scss files}
   >
   > Options:
   > 1. Skip visual verification for this change (will be noted in PR body)
   > 2. I will verify visually myself (manual verification)
   > 3. Help me install browser tools (Playwright MCP recommended)

   Based on response:
   - Option 1 → `TaskUpdate` visual tasks with result "SKIP_USER_APPROVED"
   - Option 2 → `TaskUpdate` visual tasks with result "MANUAL — user will verify"
   - Option 3 → Provide Playwright MCP installation guidance, then retry browser tool cascade
7. **Display summary**:
   - Tasks completed: N/N
   - Quality checks: pass/fail
   - Self-review findings: P1: X, P2: Y, P3: Z (all P1/P2 fixed via fix-forward)
   - Runtime verification: pass/fail/skip
   - Visual verification: PASS / FAIL / SKIP / SKIP_WARN / SKIP_USER_APPROVED / MANUAL
   - Branch: ready for PR

## Completion

Present next steps:

- `/flow:pr` — create pull request (primary suggestion — fix-forward should have committed everything)
- `/flow:commit` — if uncommitted changes remain
- Continue working — keep implementing

## Tier Classification

| Action | Tier | Behavior |
|--------|------|----------|
| Branch creation | 1 | Autonomous |
| File edits | 1 | Autonomous |
| Commits | 1 | Autonomous, logged by hook |
| Issue assignment | 2 | Journal-and-proceed |
| Push | 2 | Journal-and-proceed |
