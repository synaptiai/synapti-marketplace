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

## Phase 1: EXPLORE

Gather all context before planning. Execute these in parallel:

**Parallel Bash calls:**

```bash
# 1. Issue details
gh issue view $ARGUMENTS --json title,body,labels,assignees,milestone

# 2. Issue comments
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
gh api repos/$REPO/issues/$ARGUMENTS/comments --jq '.[] | "---\n@\(.user.login):\n\(.body)\n"'

# 3. Default branch and repo info
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"
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

## Phase 4: VERIFY

Prove everything works:

1. **Run full quality suite** (parallel Bash calls for lint, test, typecheck)
2. **Self-review** — dispatch Agent(code-reviewer):
   ```
   Agent(code-reviewer):
     "Review the diff on this branch against $DEFAULT_BRANCH.
      Check for: logic errors, security issues, missing edge cases,
      convention violations. Return P1/P2/P3 findings with file:line."
   ```
3. **TaskList** — confirm all tasks show status: completed
4. **Runtime verification** — if runtime-verification skill available, invoke it
5. **Display summary**:
   - Tasks completed: N/N
   - Quality checks: pass/fail
   - Self-review findings: P1: X, P2: Y, P3: Z
   - Branch: ready for PR

## Completion

Present next steps:

- `/flow commit` — if uncommitted changes remain
- `/flow pr` — create pull request
- Continue working — keep implementing

## Tier Classification

| Action | Tier | Behavior |
|--------|------|----------|
| Branch creation | 1 | Autonomous |
| File edits | 1 | Autonomous |
| Commits | 1 | Autonomous, logged by hook |
| Issue assignment | 2 | Journal-and-proceed |
| Push | 2 | Journal-and-proceed |
