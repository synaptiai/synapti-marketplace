---
description: Autonomous issue-to-PR pipeline with iterative review-fix loops until zero findings — assigns issue, implements, reviews, addresses all findings, and creates PR
argument-hint: <issue-number-or-url>
allowed-tools: Bash, Read, Write, Edit, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, TaskGet, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, API calls, TaskCreate),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.
Err on the side of maximizing parallel tool calls.

VARIABLE PERSISTENCE NOTE:
Bash variables (like DEFAULT_BRANCH, REPO) do NOT persist across separate tool calls.
Each Bash invocation is an independent process. Store values mentally from output and
substitute them in subsequent commands. When running parallel Bash calls, each must
define any variables it needs inline.

AUTONOMOUS MODE:
This command makes all decisions autonomously. The ONLY interactive prompt is
PR creation approval at the end. All branch type selection, commit strategy,
review finding resolution, and quality gate handling are auto-defaulted.
-->

# Autonomous Start Work on Issue #$ARGUMENTS

Fully autonomous pipeline: assigns issue, creates branch, implements, reviews iteratively until zero findings, then creates PR. Only prompts the user for final PR creation approval.

**Tool Usage**: This workflow uses **TaskCreate/TaskUpdate** for tracking, dispatches **agents** for review, and uses **AskUserQuestion** ONLY for PR creation approval and unrecoverable escalations.

## Contract

**GOAL**: PR created with zero P1/P2/P3 review findings, all acceptance criteria met, all quality gates passed. Testable: `gh pr view --json number,state` returns a valid open PR AND the final self-review shows 0 findings.

**CONSTRAINTS**:
- Read CLAUDE.md before starting; follow all project conventions
- Never skip quality gates
- Never leave placeholder/mock/stub code
- Must iterate review-fix loops until 0 findings or max iterations
- Only prompt user for PR creation approval (all other decisions auto-defaulted)
- If max review iterations reached with remaining findings, escalate to user
- When asserting code behaves a certain way, cite the specific file:line. If unable to cite, mark as UNVERIFIED

**FORMAT**: Task-based progress tracking using TaskCreate/TaskUpdate.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- PR created with unresolved P1/P2/P3 findings
- Review-fix loop skipped entirely
- Quality gates skipped or deferred
- User not presented with PR creation approval
- Placeholders, mocks, stubs or TODO code left in source files
- Tasks not created from acceptance criteria (jumped straight to coding)
- Implementation started without reading CLAUDE.md

## Phase 1: Autonomous Setup

### Step 1.1: Project Context Handshake

1. **Read project CLAUDE.md** using the **Read tool** (not cat/Bash):
   - Try `.claude/CLAUDE.md` first, then `CLAUDE.md`
   - If neither exists, note this and proceed with auto-detected conventions

2. **Extract project constraints** relevant to this implementation:
   - Tech stack requirements (languages, frameworks, libraries)
   - Testing requirements and quality commands
   - Any "do not" or "always" rules
   - Coding conventions and patterns

3. **Briefly confirm constraints** before proceeding:
   > "Project constraints detected: [list key ones]. Proceeding autonomously."

### Step 1.2: Normalize Input

`$ARGUMENTS` can be an issue number (e.g., `42`) or a full URL (e.g., `https://github.com/owner/repo/issues/42`). Extract the issue number:

```bash
ISSUE_NUM=$(echo "$ARGUMENTS" | grep -oE '[0-9]+$')
[[ -n "$ISSUE_NUM" ]] || { echo "ERROR: Could not extract issue number from: '$ARGUMENTS'"; exit 1; }
echo "Issue number: $ISSUE_NUM"
```

### Step 1.3: Gather Context (Parallel)

**Execute these in parallel** (single message, multiple Bash tool calls):

1. **Fetch the issue**:
   ```bash
   gh issue view $ARGUMENTS
   ```

2. **Fetch all issue comments**:
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/issues/$ARGUMENTS/comments --jq '.[] | "---\n**@\(.user.login)** on \(.created_at):\n\(.body)\n"'
   ```

3. **Fetch issue timeline for related context**:
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/issues/$ARGUMENTS/timeline --jq '.[] | select(.event == "cross-referenced" or .event == "referenced") | "\(.event): \(.source.issue.title // .commit_id)"'
   ```

4. **Check for linked issues/PRs**:
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/issues/$ARGUMENTS --jq '.body' | grep -oE '#[0-9]+'
   ```

5. **Assign the issue**:
   ```bash
   gh issue edit $ARGUMENTS --add-assignee @me
   ```

**If issue not found** (gh issue view fails): Report error and stop:
> "Issue #$ARGUMENTS not found. Verify the issue number and try again."

### Step 1.4: Auto-Detect Branch Type & Create Branch

These steps run sequentially:

1. **Detect default branch and pull latest**:
   ```bash
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   git checkout $DEFAULT_BRANCH && git pull origin $DEFAULT_BRANCH
   ```

2. **Read branch patterns from settings** (local > project > user > defaults):
   ```bash
   FEATURE_PATTERN=$(jq -r '.conventions.branchPatterns.feature // empty' .claude/settings.gh-workflow.local.json 2>/dev/null)
   [ -z "$FEATURE_PATTERN" ] && FEATURE_PATTERN=$(jq -r '.conventions.branchPatterns.feature // empty' .claude/settings.gh-workflow.json 2>/dev/null)
   [ -z "$FEATURE_PATTERN" ] && FEATURE_PATTERN=$(jq -r '.conventions.branchPatterns.feature // empty' "$HOME/.claude/settings.gh-workflow.json" 2>/dev/null)
   [ -z "$FEATURE_PATTERN" ] && FEATURE_PATTERN="feature/issue-{N}-{desc}"

   FIX_PATTERN=$(jq -r '.conventions.branchPatterns.fix // empty' .claude/settings.gh-workflow.local.json 2>/dev/null)
   [ -z "$FIX_PATTERN" ] && FIX_PATTERN=$(jq -r '.conventions.branchPatterns.fix // empty' .claude/settings.gh-workflow.json 2>/dev/null)
   [ -z "$FIX_PATTERN" ] && FIX_PATTERN=$(jq -r '.conventions.branchPatterns.fix // empty' "$HOME/.claude/settings.gh-workflow.json" 2>/dev/null)
   [ -z "$FIX_PATTERN" ] && FIX_PATTERN="fix/issue-{N}-{desc}"

   DOCS_PATTERN=$(jq -r '.conventions.branchPatterns.docs // empty' .claude/settings.gh-workflow.local.json 2>/dev/null)
   [ -z "$DOCS_PATTERN" ] && DOCS_PATTERN=$(jq -r '.conventions.branchPatterns.docs // empty' .claude/settings.gh-workflow.json 2>/dev/null)
   [ -z "$DOCS_PATTERN" ] && DOCS_PATTERN=$(jq -r '.conventions.branchPatterns.docs // empty' "$HOME/.claude/settings.gh-workflow.json" 2>/dev/null)
   [ -z "$DOCS_PATTERN" ] && DOCS_PATTERN="docs/issue-{N}-{desc}"
   ```

3. **Auto-detect branch type from issue labels** (no prompt):
   - Issue has `bug`/`defect` label → use `FIX_PATTERN`
   - Issue has `documentation` label → use `DOCS_PATTERN`
   - Default (including ambiguous cases) → use `FEATURE_PATTERN`

   ```bash
   git checkout -b {branch-name}
   ```

### Step 1.5: Initialize Decision Journal

Invoke the **decision-journal** skill in `init` mode using the **Skill tool**:

```
Skill: decision-journal —
  "Mode: init
   Issue number: {ISSUE_NUM}
   Branch name: {branch-name}
   Issue title: {title}
   Issue body: {body}"
```

Write the returned header to `{journal-dir}/issue-{ISSUE_NUM}.md`.

### Step 1.6: Capability Discovery

Invoke the **capability-discovery** skill using the **Skill tool**.

Extract and store:
```
LINT_CMD="{detected lint command}"
TEST_CMD="{detected test command}"
TYPECHECK_CMD="{detected typecheck}"
```

**Graceful fallback**: If the Skill tool invocation fails, discover capabilities inline by checking for tech stack indicators (`pyproject.toml`, `package.json`, `tsconfig.json`, `go.mod`, `Cargo.toml`) and parsing CLAUDE.md for quality commands.

## Phase 2: Autonomous Implementation

### Step 2.1: Impact Analysis

**Skip if**: Issue is documentation-only, config-only change, or single-file modification with no downstream dependents.

For multi-file or behavioral changes:
1. Identify modules to modify from acceptance criteria
2. Find dependents — files that import/reference modules being changed
3. Find tests that import or mock affected modules
4. Check for middleware/interceptors/decorators
5. Map test setup requirements
6. Document impact as summary table
7. Snapshot current test state before implementing

### Step 2.2: Task Breakdown (via Implementation Planner)

Dispatch the **implementation-planner** agent using the **Agent tool**:

```
Agent call: implementation-planner —
  "Plan implementation for Issue #{ISSUE_NUM}.

  Issue title: {title}
  Issue body: {body}
  Comments: {comments from Step 1.3}
  Linked issues: {from Step 1.3}
  Impact analysis: {from Step 2.1, if performed}

  Create TaskCreate entries for each acceptance criterion with:
  - Dependencies between tasks (via addBlockedBy)
  - Implementation notes with relevant file paths
  - Suggested implementation order

  Return the implementation plan with dependency graph and suggested order."
```

**If agent flags ambiguities**: Accept the planner's best recommendation (no user prompt).

Log the task breakdown decision to the decision journal via the **decision-journal** skill in `log` mode.

**Graceful fallback**: If the agent fails, create tasks inline from acceptance criteria.

### Step 2.3: Work Through Tasks Systematically

For each task from TaskList:

1. **Mark task in progress**: `TaskUpdate: taskId={id}, status=in_progress`
2. **Implement the requirement**: Reference existing patterns, follow CLAUDE.md, write tests alongside
3. **Incremental commit** when logical unit complete (conventional commit format)
4. **Mark task complete**: `TaskUpdate: taskId={id}, status=completed`
5. **Check progress**: `TaskList`

## Phase 3: Quality Gate

Use quality commands discovered in Phase 1 (LINT_CMD, TEST_CMD, TYPECHECK_CMD).

### Step 3.1: Quality Verification Loop (Bounded)

Read max iterations from settings:
```bash
MAX_ITERATIONS=$(jq -r '.timeouts.qualityCheckMaxIterations // empty' .claude/settings.gh-workflow.local.json 2>/dev/null)
[ -z "$MAX_ITERATIONS" ] && MAX_ITERATIONS=$(jq -r '.timeouts.qualityCheckMaxIterations // empty' .claude/settings.gh-workflow.json 2>/dev/null)
[ -z "$MAX_ITERATIONS" ] && MAX_ITERATIONS=$(jq -r '.timeouts.qualityCheckMaxIterations // empty' "$HOME/.claude/settings.gh-workflow.json" 2>/dev/null)
[ -z "$MAX_ITERATIONS" ] && MAX_ITERATIONS="3"
```

**Iteration 1 (and up to MAX_ITERATIONS total):**

1. **Run all quality commands in parallel** (3 Bash tool calls in a single message):
   ```
   - Bash call 1: {lint_cmd}
   - Bash call 2: {test_cmd}
   - Bash call 3: {typecheck_cmd}
   ```

2. **If ALL pass** → proceed to Phase 4

3. **If ANY fail**: Parse errors, fix inline immediately (Edit tool), commit the fix, re-run ALL checks

4. **After MAX_ITERATIONS failed iterations** → escalate to user via **AskUserQuestion tool**:
   - **Option 1**: "Show failures, I'll fix manually"
   - **Option 2**: "Abort — I need to investigate"
   - (No "skip and proceed" option — this command targets zero issues)

## Phase 4: Review-Fix Loop

Run iterative loop that reviews the implementation, fixes all findings, and re-reviews until clean.

### Step 4.1: Read Max Review Iterations

```bash
MAX_REVIEW_ITERATIONS=$(jq -r '.automation.maxReviewIterations // empty' .claude/settings.gh-workflow.local.json 2>/dev/null)
[ -z "$MAX_REVIEW_ITERATIONS" ] && MAX_REVIEW_ITERATIONS=$(jq -r '.automation.maxReviewIterations // empty' .claude/settings.gh-workflow.json 2>/dev/null)
[ -z "$MAX_REVIEW_ITERATIONS" ] && MAX_REVIEW_ITERATIONS=$(jq -r '.automation.maxReviewIterations // empty' "$HOME/.claude/settings.gh-workflow.json" 2>/dev/null)
[ -z "$MAX_REVIEW_ITERATIONS" ] && MAX_REVIEW_ITERATIONS="5"
```

### Step 4.2: Review-Fix Iteration Loop

```
REVIEW_ITERATION = 0

LOOP:
  REVIEW_ITERATION += 1
```

#### 4.2a: Dispatch Review Agents + Runtime Verification (Parallel)

Dispatch these in parallel using the **Agent tool** and **Skill tool**:

- **Agent: code-reviewer** — Review the diff for P1/P2/P3 findings (design issues, bugs, security, performance)
- **Agent: convention-checker** — Validate commit messages, branch naming, formatting conventions
- **Agent: test-runner** — Run lint, test, typecheck as a verification pass
- **Skill: runtime-verification** — Start dev server, run smoke tests, E2E tests, visual checks (if available)

#### 4.2b: Create Review Tasks (Tracking)

After agents return, **create tasks in parallel** to track completion of each review facet. These ensure no facet is silently skipped:

```
TaskCreate:
  subject: "Review round {REVIEW_ITERATION}: Code Quality & Logic"
  description: "Analyze logic correctness, edge cases, error handling"
  activeForm: "Reviewing code quality"

TaskCreate:
  subject: "Review round {REVIEW_ITERATION}: Security Scan"
  description: "Check for hardcoded secrets, injection risks, data exposure"
  activeForm: "Security scanning"

TaskCreate:
  subject: "Review round {REVIEW_ITERATION}: TODO/Debug Check"
  description: "Find TODO comments, debug statements, console.log"
  activeForm: "Checking for debug code"

TaskCreate:
  subject: "Review round {REVIEW_ITERATION}: Test Coverage"
  description: "Verify tests exist for new functionality"
  activeForm: "Checking test coverage"

TaskCreate:
  subject: "Review round {REVIEW_ITERATION}: Conventions & Standards"
  description: "Commit messages, branch naming, format, issue linkage"
  activeForm: "Checking conventions"

TaskCreate:
  subject: "Review round {REVIEW_ITERATION}: Runtime Verification"
  description: "Dev server, smoke tests, E2E, visual checks"
  activeForm: "Verifying runtime behavior"
```

Mark each task as completed when its corresponding agent results are collected and incorporated into the synthesis. If an agent covered multiple facets (e.g., code-reviewer handles both Code Quality and Security), mark each task individually based on whether findings were reported for that facet.

**Why track these separately**: Agents may focus on high-signal findings and skip lower-priority checks like TODO/debug cleanup or test coverage gaps. Individual tasks ensure each facet gets explicit attention — either confirmed clean or with findings recorded.

#### 4.2c: Collect and Synthesize ALL Findings

After all agents and skills return:

1. Merge code review + convention + quality + runtime findings
2. Deduplicate by file:line, keep higher priority
3. Runtime failures (broken endpoints, E2E failures, server crash) → classify as P1 or P2
4. Count totals: `P1_COUNT`, `P2_COUNT`, `P3_COUNT`
5. Mark each review task from 4.2b as completed once its facet is analyzed

Verify all review tasks are marked completed before proceeding:
```
TaskList
```
If any review task is still pending or in-progress, complete the analysis for that facet before continuing.

#### 4.2d: Check Exit Condition — Zero Findings

**If `P1_COUNT + P2_COUNT + P3_COUNT == 0`**:
→ **BREAK** — implementation is clean (code, conventions, AND runtime). Proceed to Phase 5.

#### 4.2e: Check Max Iterations

**If `REVIEW_ITERATION >= MAX_REVIEW_ITERATIONS`**:
→ Escalate to user via **AskUserQuestion tool**:

Show remaining findings table, then present options:
- **Option 1**: "Continue fixing (N more iterations)"
- **Option 2**: "Proceed to PR with known issues"
- **Option 3**: "Abort"

If Option 1: increase MAX_REVIEW_ITERATIONS by N and continue loop.
If Option 2: proceed to Phase 5 with known issues noted.
If Option 3: stop execution.

#### 4.2f: Create Fix Tasks & Resolve Findings

For each finding, create a tracked task and resolve it:

- **P1 findings**: Create task per finding, implement fix, mark task completed
  ```
  TaskCreate:
    subject: "Fix P1: {finding summary}"
    description: "Round {REVIEW_ITERATION} — {full finding detail with file:line}"
    activeForm: "Fixing P1: {short description}"
  ```
- **P2 findings**: Create task per finding, implement fix, mark task completed
  ```
  TaskCreate:
    subject: "Fix P2: {finding summary}"
    description: "Round {REVIEW_ITERATION} — {full finding detail with file:line}"
    activeForm: "Fixing P2: {short description}"
  ```
- **P3 findings**: Fix inline immediately — no task needed for straightforward fixes

After all fix tasks are completed, commit:
`git commit -m "fix: address review findings (round {REVIEW_ITERATION})"`

Verify all fix tasks completed before committing:
```
TaskList
```

#### 4.2g: Re-run Quality Checks

Re-run the Phase 3 quality verification loop to ensure fixes didn't break anything.

#### 4.2h: Continue Loop

Go back to Step 4.2a.

### Step 4.3: Log Review Loop to Decision Journal

After the loop completes, invoke the **decision-journal** skill in `log` mode:

```
Skill: decision-journal —
  "Mode: log
   Phase: review-fix loop complete
   Description: Completed {REVIEW_ITERATION} review iterations for Issue #{ISSUE_NUM}.
   All P1/P2/P3 findings resolved."
```

## Phase 5: Commit & Push

### Step 5.1: Final Commit

Check for uncommitted changes and auto-commit:

```bash
git status --porcelain
```

If uncommitted changes exist:
- Stage all in-context changes
- Generate conventional commit message from diff analysis
- Commit: `git commit -m "{type}: {description}"`

### Step 5.2: Push to Origin

```bash
git push -u origin {branch-name}
```

**If push fails due to conflicts**:
1. Auto-rebase: `git pull --rebase origin {branch-name}`
2. Retry push (1 attempt)
3. If still fails → escalate to user via **AskUserQuestion tool**

## Phase 6: PR Creation (Only User Prompt)

### Step 6.1: Generate PR Body

1. **Generate comprehension report** via the **comprehension-report** skill (if `commands.ghPrComprehensionReport` is enabled)
2. **Generate decision summary** via the **decision-journal** skill in `summarize` mode (if `commands.ghPrDecisionSummary` is enabled)
3. **Build PR body** from `templates/pr-template.md` including:
   - Comprehension report
   - Decision summary
   - Review loop summary: "{N} review iterations, all findings resolved"
   - Acceptance criteria checklist

### Step 6.2: Auto-Select Reviewer & Labels

1. **Suggest reviewer** via the **suggest-users** skill — select the top-ranked reviewer
2. **Select labels** from issue labels + detected change type

### Step 6.3: PR Preview & Approval (AskUserQuestion)

Show PR preview with title, body, reviewer, and labels. Then use the **AskUserQuestion tool**:

- **Option 1**: "Create this PR" (Recommended)
- **Option 2**: "Edit title or body"
- **Option 3**: "Cancel PR creation"

**If Option 1**: Create PR via `gh pr create` with the generated body, reviewer, and labels.
**If Option 2**: Allow user to specify changes, then re-present preview.
**If Option 3**: Stop. Changes remain committed and pushed on the branch.

### Step 6.4: Verify PR Creation

```bash
gh pr view --json number,url,state
```

## Output Format

```markdown
## gh-start-auto Complete

**Issue**: #{issue} — {title}
**Branch**: {branch}
**PR**: #{pr_number} — {pr_url}

### Pipeline Summary
| Phase | Status | Details |
|-------|--------|---------|
| Setup | Done | Branch: {branch}, {N} capabilities detected |
| Implementation | Done | {M} tasks completed |
| Quality Gate | Passed | lint + test + typecheck green |
| Review Loops | {N} iterations | Started with {X} findings → 0 findings |
| Runtime | Passed/Skipped | Verified in review loop (round {R}) |
| PR Created | Done | Reviewer: @{reviewer}, Labels: {labels} |

### Review Loop History
| Round | P1 | P2 | P3 | Runtime | Action |
|-------|----|----|-----|---------|--------|
| 1 | 2 | 3 | 1 | 1 fail | Fixed 7 findings (incl. broken endpoint) |
| 2 | 0 | 1 | 0 | 0 fail | Fixed 1 finding |
| 3 | 0 | 0 | 0 | 0 fail | Clean — loop complete |

### Next Steps
1. Wait for reviewer feedback
2. Address comments with `/gh-address {pr_number}`
3. Merge with `/gh-merge {pr_number}` when approved
```

## Arguments

- `$ARGUMENTS`: Issue number or issue URL (required). Examples: `42`, `https://github.com/owner/repo/issues/42`

## Rules

- **Always detect default branch dynamically** — never assume `main` or `master`
- Commits must follow conventional format
- **Zero interactive prompts except PR creation** — all decisions auto-defaulted
- **Use TaskCreate/TaskUpdate** to track implementation progress
- **Run parallel operations** when possible (multiple API calls, file reads, agent dispatches)
- **Review-fix loop is mandatory** — never skip it
- **Review-fix loop is bounded** — escalate after maxReviewIterations
- **Fix all P1/P2/P3 findings** — do not leave known issues unresolved unless user explicitly approves

## Success Criteria

Before completing, verify:
- [ ] Issue assigned to user
- [ ] Branch created from latest default branch
- [ ] All acceptance criteria from issue addressed
- [ ] All implementation tasks completed
- [ ] Quality gates passed (lint, tests, typecheck)
- [ ] Review-fix loop completed with 0 findings (or user-approved exceptions)
- [ ] All changes committed and pushed
- [ ] PR created with review loop summary in body
- [ ] User approved PR creation via AskUserQuestion

## Related Commands

- **`/gh-start`**: Interactive version with 9 decision points
- **`/gh-commit`**: Context-aware commits with change classification
- **`/gh-pr`**: Create PR with full review and reviewer suggestions
- **`/gh-review`**: Review a pull request
- **`/gh-address`**: Address PR review comments
