---
description: Use to start work on a GitHub issue - assigns issue, creates branch, guides implementation with task tracking, and prepares for PR
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
-->

# Start Work on Issue #$ARGUMENTS

Complete workflow from issue assignment through implementation with task-based tracking. Ends with option to create PR via `/gh-pr` or continue working.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** for interactive dialogues at key decision points, and **TaskCreate/TaskUpdate** tools for tracking implementation progress.

## Contract

**GOAL**: All acceptance criteria from issue #$ARGUMENTS have corresponding completed tasks with passing tests. Testable: `TaskList` shows all tasks completed, quality gates passed.

**CONSTRAINTS**:
- Read CLAUDE.md before starting implementation and follow all project conventions
- Never skip quality gates (lint, tests, code review, test review)
- Never leave placeholder/mock/stub code in source files
- All implementations must be production-ready before marking tasks complete
- When asserting code behaves a certain way, cite the specific file:line. If unable to cite, mark as UNVERIFIED

**FORMAT**: Task-based progress tracking using TaskCreate/TaskUpdate. Each acceptance criterion becomes a tracked task.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- Tasks not created from acceptance criteria (jumped straight to coding)
- Implementation started without reading CLAUDE.md
- Quality gates skipped or deferred
- Placeholder, mock, or TODO code left in source files
- Tests not run before declaring implementation complete
- User not presented with next-step options at completion

## Phase 1: Project Context Handshake

Before any implementation work:

1. **Read project CLAUDE.md** using the **Read tool** (not cat/Bash):
   - Try `.claude/CLAUDE.md` first, then `CLAUDE.md`
   - If neither exists, note this and proceed with auto-detected conventions

2. **Extract and display project constraints** relevant to this implementation:
   - Tech stack requirements (languages, frameworks, libraries)
   - Testing requirements and quality commands
   - Any "do not" or "always" rules
   - Coding conventions and patterns

3. **Briefly confirm constraints** before proceeding:
   > "Project constraints detected: [list key ones]. Proceeding with implementation following these constraints."

## Phase 2: Setup

### Step 2.1: Normalize Input

`$ARGUMENTS` can be an issue number (e.g., `42`) or a full URL (e.g., `https://github.com/owner/repo/issues/42`). Extract the issue number for use throughout the workflow:

```bash
# Extract issue number from URL or use directly
ISSUE_NUM=$(echo "$ARGUMENTS" | grep -oE '[0-9]+$')
[[ -n "$ISSUE_NUM" ]] || { echo "ERROR: Could not extract issue number from: '$ARGUMENTS'"; exit 1; }
echo "Issue number: $ISSUE_NUM"
```

Use the extracted `ISSUE_NUM` in all subsequent commands where `$ARGUMENTS` was previously referenced.

### Step 2.2: Gather Context (Parallel)

**Execute these in parallel** (single message, multiple Bash tool calls). Each call defines `REPO` independently since Bash variables don't persist across calls:

1. **Fetch the issue**:
   ```bash
   gh issue view $ISSUE_NUM
   ```

2. **Fetch all issue comments**:
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/issues/$ISSUE_NUM/comments --jq '.[] | "---\n**@\(.user.login)** on \(.created_at):\n\(.body)\n"'
   ```

3. **Fetch issue timeline for related context**:
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/issues/$ISSUE_NUM/timeline --jq '.[] | select(.event == "cross-referenced" or .event == "referenced") | "\(.event): \(.source.issue.title // .commit_id)"'
   ```

4. **Check for linked issues/PRs**:
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/issues/$ISSUE_NUM --jq '.body' | grep -oE '#[0-9]+'
   ```

5. **Assign the issue**:
   ```bash
   gh issue edit $ISSUE_NUM --add-assignee @me
   ```

**If issue not found** (gh issue view fails): Report error and stop:
> "Issue #$ISSUE_NUM not found. Verify the issue number and try again."

### Step 2.2b: Familiarity Prompt (Conditional)

**Check configuration** — read `.commands.ghStartFamiliarityPrompt` from settings. Default: `true`. If `false`, skip this step.

After gathering the issue context (Step 2.2), present a lightweight familiarity baseline using the **AskUserQuestion tool**:

> "Before implementing, how familiar are you with the areas this issue touches?"

**Options:**
1. "I know this code well — I've written or modified it before"
2. "I've read it but haven't changed it"
3. "I've never seen the relevant code"
4. "Skip — proceed to implementation"

**Behavior by response:**
- Options 1-2: Record familiarity level and proceed
- Option 3: Suggest reading the key files identified in the issue before implementing (non-blocking — list files and proceed)
- Option 4: Proceed without recording

The familiarity level is recorded for reference during the implementation session.

### Step 2.3: Branch Setup (Sequential)

These steps depend on each other and must run in order:

1. **Review all comments and linked issues** from Step 2.2 before proceeding

2. **Detect default branch and pull latest**:
   ```bash
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   git checkout $DEFAULT_BRANCH && git pull origin $DEFAULT_BRANCH
   ```

3. **Read branch patterns from settings** (local > project > user > defaults):
   ```bash
   # Read configured branch patterns + additional types
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

   **Determine branch type** based on issue labels and context:
   - Issue has `bug`/`defect` label → use `FIX_PATTERN`
   - Issue has `documentation` label → use `DOCS_PATTERN`
   - Otherwise → use `FEATURE_PATTERN`

   Also check `conventions.additionalBranchTypes` for extra types (e.g., `refactor/`, `chore/`). If found, include them as options.

   **If ambiguous** (e.g., could be feature or fix), use the **AskUserQuestion tool** with configured patterns:
   - **Option 1**: "{FEATURE_PATTERN}" - New functionality
   - **Option 2**: "{FIX_PATTERN}" - Bug fix
   - **Option 3**: "{DOCS_PATTERN}" - Documentation only
   - Plus any additional branch types from settings

   ```bash
   git checkout -b {branch-name}
   ```

4. **Confirm setup** with user before beginning implementation

### Step 2.4: Initialize Decision Journal

After branch creation, invoke the **decision-journal** skill in `init` mode using the **Skill tool**:

```
Skill: decision-journal —
  "Mode: init
   Issue number: {ISSUE_NUM}
   Branch name: {branch-name}
   Issue title: {title}
   Issue body: {body}"
```

The skill returns a journal header and the resolved journal directory (from `.journal.dir` in settings, default `.decisions`). Write the header to `{journal-dir}/issue-{ISSUE_NUM}.md`:

```bash
# Use the journal directory returned by the skill (default: .decisions)
mkdir -p {journal-dir}
```

Use the **Write tool** to create `{journal-dir}/issue-{ISSUE_NUM}.md` with the returned header content.

## Phase 3: Capability Discovery

Before implementation, discover available project capabilities by invoking the **capability-discovery** skill using the **Skill tool**.

The skill runs in a forked context and returns:
- Available agents and skills
- Quality commands from CLAUDE.md
- Tech stack detection
- Verification capabilities

**After skill returns**, extract and store for later phases:
```
LINT_CMD="{detected lint command}"    # e.g., ruff check ., npm run lint, go vet ./...
TEST_CMD="{detected test command}"    # e.g., pytest, npm test, go test ./...
TYPECHECK_CMD="{detected typecheck}"  # e.g., pyright, tsc --noEmit, (skip if N/A)
```

Store these for use in Phase 6 verification. If a command is not applicable (e.g., no type checker), note it as "N/A — skip".

**Graceful fallback**: If the Skill tool invocation fails, discover capabilities inline:

**Execute these in parallel**:

1. **Check for custom skills**:
   ```bash
   ls .claude/skills/*/SKILL.md plugins/*/skills/*/SKILL.md 2>/dev/null
   ```

2. **Check for custom agents**:
   ```bash
   ls .claude/agents/*.md plugins/*/agents/*.md 2>/dev/null
   ```

3. **Parse CLAUDE.md for quality commands**:
   ```bash
   grep -E "(lint|test|check|format|typecheck):" .claude/CLAUDE.md 2>/dev/null
   grep -E "(ruff|pytest|npm run|go vet|cargo)" .claude/CLAUDE.md 2>/dev/null
   ```

4. **Detect tech stack**:
   ```bash
   ls pyproject.toml package.json tsconfig.json go.mod Cargo.toml 2>/dev/null
   ```

Build the quality command set from detected results.

## Phase 4: Impact Analysis

**Skip if**: Issue is documentation-only, config-only change, or single-file modification with no downstream dependents.

For multi-file or behavioral changes, map the blast radius of planned changes:

1. **Identify modules to modify** from acceptance criteria

2. **Find dependents** — files that import/reference modules being changed:
   ```bash
   # For each key module to be modified, find who depends on it
   grep -rn "import.*{module}" --include="*.ts" --include="*.py" --include="*.go" . 2>/dev/null | head -20
   ```

3. **Find tests that import or mock affected modules** (not just filename matching):
   ```bash
   # For each module being changed, find ALL tests that depend on it
   grep -rln "import.*{module}\|from.*{module}\|require.*{module}\|mock.*{module}\|jest\.mock.*{module}\|patch.*{module}" --include="*test*" --include="*spec*" . 2>/dev/null
   grep -rln "import.*{module}\|from.*{module}\|require.*{module}" tests/ test/ __tests__/ spec/ 2>/dev/null
   ```

4. **Check for middleware/interceptors/decorators** that might be affected:
   ```bash
   grep -rn "middleware\|interceptor\|decorator\|@app\.\|@router\." --include="*.py" --include="*.ts" . 2>/dev/null | head -10
   ```

5. **Map test setup requirements** for each affected test file:
   ```bash
   head -30 {test_file}  # Check imports and fixtures
   grep -n "setUp\|fixture\|beforeEach\|beforeAll\|@pytest.fixture\|conftest\|TestCase" {test_file} 2>/dev/null
   ```

6. **Document impact** — present as a summary table:

```
   | Module | Dependents | Tests Exist | Risk |
   |--------|-----------|-------------|------|
   | [module] | [N files] | [yes/no] | [low/med/high] |
```

   Also list tests to run after each change and note potential side effects (e.g., "Adding auth middleware will affect all POST handlers").

7. **Snapshot current test state** before implementing:
   ```bash
   {test_cmd} 2>&1 | tail -5  # Record baseline pass/fail counts
   ```

## Phase 5: Task-Based Implementation

### Step 5.1: Create Task Breakdown (via Implementation Planner)

Dispatch the **implementation-planner** agent using the **Agent tool** to analyze the issue and create a structured task breakdown.

Pass the issue context already gathered in Phase 2 (issue body, comments, linked issues) so the agent doesn't re-fetch:

```
Agent call: implementation-planner —
  "Plan implementation for Issue #{ISSUE_NUM}.

  Issue title: {title}
  Issue body: {body}
  Comments: {comments from Step 2.2}
  Linked issues: {from Step 2.2}
  Impact analysis: {from Phase 4, if performed}

  Create TaskCreate entries for each acceptance criterion with:
  - Dependencies between tasks (via addBlockedBy)
  - Implementation notes with relevant file paths
  - Suggested implementation order

  Return the implementation plan with dependency graph and suggested order."
```

The agent returns:
- Tasks created via TaskCreate with dependency chains
- Dependency graph showing implementation order
- Suggested parallel groups (if any)
- Questions or assumptions that need user input

**If agent flags ambiguities**, use the **AskUserQuestion tool** to clarify before proceeding.

### Step 5.1a: Decision Logging & Gate Check

After the task breakdown is finalized, invoke the **decision-journal** skill in `log` mode using the **Skill tool**:

```
Skill: decision-journal —
  "Mode: log
   Phase: task breakdown complete
   Description: Task breakdown for Issue #{ISSUE_NUM} — planning phase decisions"
```

The skill returns:
1. **Decision entries** — append these to `{journal-dir}/issue-{ISSUE_NUM}.md` using the **Edit tool** (where `journal-dir` is returned by the skill, default `.decisions`)
2. **Gate triggers** — if any gates fired with config `on`:

Present each gate trigger using the **AskUserQuestion tool** in this format:

```
COMPREHENSION GATE: {category}

{Context explaining what triggered the gate}

{Findings / decision details}

Options:
1. "Approve: {recommended approach}" (Recommended)
2. "Alternative: {alternative A}" — {trade-off}
3. "I need more information"
4. "Proceed anyway — skip this gate"
```

Log the human's response back to the journal:
- Options 1-2: `Gate: Yes — human approved`
- Option 3: Provide additional context, then re-present
- Option 4: `Gate: Bypassed — human chose to skip`

If no gate triggers returned, proceed without interruption.

**Graceful fallback**: If the agent fails, create tasks inline:

For each acceptance criterion found in the issue:
```
TaskCreate:
  subject: "[Criterion summary - imperative form]"
  description: "[Full criterion text from issue]\n\nImplementation notes: [any technical context]"
  activeForm: "Implementing [criterion]"
```

Example breakdown:
- Issue says "Users can filter by date" → Task: "Add date filtering to search endpoint"
- Issue says "Validation errors show helpful messages" → Task: "Implement validation error formatting"

### Step 5.1b: Identify Parallel Implementation Opportunities

After the task breakdown is created (by agent or fallback), analyze the dependency graph to find tasks that can run in parallel:

**Parallelism criteria** (ALL must be true):
1. Tasks share the same dependency set (same `blockedBy` or no dependencies)
2. Tasks modify **different files** (no file overlap)
3. Tasks don't create code that the other imports (no cross-task dependencies)
4. Each task produces a testable increment

**If safe parallel groups found**:
1. Dispatch **Agent tool calls in parallel** for each task in the group (using `isolation: "worktree"` if available — this feature requires worktree support in the environment)
2. Each agent receives: task description, relevant file paths, project conventions from CLAUDE.md
3. After agents complete → verify no file conflicts (`git diff --name-only` across worktrees)
4. Run quality checks on merged result
5. Mark parallel tasks as complete

**If no safe parallel groups found** → fall back to sequential Step 5.2. This is the **default** — incorrect parallelism causes merge conflicts, so err on the side of sequential.

### Step 5.2: Work Through Tasks Systematically

For each task from TaskList:

1. **Mark task in progress**:
   ```
   TaskUpdate: taskId={id}, status=in_progress
   ```

2. **Implement the requirement**:
   - Reference similar existing code patterns
   - Follow project guidelines (CLAUDE.md)
   - Write tests alongside implementation (if applicable)

3. **Incremental commit** (when logical unit complete):
   - Commit after each task or meaningful progress
   - Use conventional commit format
   - Reference task in commit if helpful

4. **Mark task complete**:
   ```
   TaskUpdate: taskId={id}, status=completed
   ```

5. **Check progress**:
   ```
   TaskList
   ```

### Step 5.3: Progress Tracking

After each task completion, show progress:
```
## Implementation Progress
| Task | Status |
|------|--------|
| [task 1] | Completed |
| [task 2] | In Progress |
| [task 3] | Pending |

Progress: 1/3 tasks completed
```

## Phase 6: Quality Checks

Use the quality commands discovered in Phase 3 (LINT_CMD, TEST_CMD, TYPECHECK_CMD). If Phase 3 was skipped, detect commands now from CLAUDE.md or tech stack:

| Indicator | Commands |
|-----------|----------|
| pyproject.toml | `ruff check .`, `pytest` |
| package.json | `npm run lint`, `npm test` |
| tsconfig.json | `tsc --noEmit` |
| go.mod | `go vet ./...`, `go test ./...` |
| Cargo.toml | `cargo clippy`, `cargo test` |

### Step 6.1: Quality Verification Loop (Bounded)

Execute a bounded fix-verify cycle. **Fix immediately — do not create tasks** for lint/test failures. These are mechanical fixes.

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
   - Bash call 1: {lint_cmd}       # e.g., ruff check . 2>&1
   - Bash call 2: {test_cmd}       # e.g., pytest 2>&1
   - Bash call 3: {typecheck_cmd}  # e.g., tsc --noEmit 2>&1
   ```

2. **If ALL pass** → proceed to Step 6.2

3. **If ANY fail**:
   - Parse error output to identify root cause (file, line, error type)
   - Fix the issue inline immediately (Edit tool, not TaskCreate)
   - Commit the fix: `git commit -m "fix: [what was fixed]"`
   - Re-run ALL checks (go back to step 1)

4. **Max MAX_ITERATIONS** (default: 3). After MAX_ITERATIONS failed iterations → escalate to user via **AskUserQuestion tool**:
   - **Option 1**: "Show me the failures, I'll fix manually"
   - **Option 2**: "Skip failing checks and proceed" — note which checks were skipped
   - **Option 3**: "Abort — I need to investigate"

### Step 6.2: Verify All Tasks Complete

```
TaskList
```

If incomplete tasks remain: **Complete remaining tasks before PR**
If clarifications or decisions are needed before proceeding: **Use AskUserQuestion tool** with clear options.

## Phase 7: Runtime Verification

After quality checks pass, verify the implementation actually works at runtime.

Invoke the **runtime-verification** skill using the **Skill tool**. The skill runs in a forked context and:
- Discovers verification capabilities (dev server, E2E frameworks, verify scripts)
- Starts services and runs smoke tests
- Executes E2E tests and visual verification of changes in the browser (if available)
- Verifies acceptance criteria programmatically
- Returns structured results table

After the skill returns, incorporate results into the pre-PR gate assessment.

**Graceful fallback**: If the Skill tool invocation fails, check inline:
```bash
# Discover capabilities
grep -E "^(dev-server|verify|e2e|smoke|health):" .claude/CLAUDE.md 2>/dev/null
ls verify.sh scripts/verify* playwright.config.* cypress.config.* 2>/dev/null
cat package.json 2>/dev/null | grep -E '"(dev|start|serve|e2e|test:e2e)"'
```

If capabilities found, run them. If dev server discovered: start in background, wait for ready (timeout from `.timeouts.devServerStartup`, default: 30s), run smoke tests, kill server. If E2E framework found, run it (timeout from `.timeouts.e2eTest`, default: 120s). If nothing found, skip with note "Runtime verification skipped — no dev server or E2E framework found."

**Handle failures**: If runtime tests fail → analyze root cause, fix, re-run (max iterations from settings, default: 3). If dev server won't start → report error with logs, proceed (not blocking).

**IMPORTANT**: Runtime verification is additive, not blocking. If a project has no dev server or E2E framework, this phase completes with "skipped" status and the workflow continues.

## Phase 8: Code Review (Self-Review)

Before creating PR, perform systematic code review on the diff.

Read the **code review checklist** from `references/code-review-checklist.md` (relative to the gh-workflow plugin directory) and follow its instructions. The checklist covers:
- Agent-assisted review (preferred, using `code-reviewer` agent if available)
- Manual review fallback with 7-point checklist
- Output format for findings

**Task creation policy for review findings**:
- **P1/P2 findings** (design decisions needed): Create tasks via TaskCreate, implement fixes, re-run quality checks
- **P3 findings** (straightforward fixes): Fix inline immediately, no task overhead needed

## Phase 9: Test Review (Self-Review)

Review tests in the current diff.

Read the **test review checklist** from `references/test-review-checklist.md` (relative to the gh-workflow plugin directory) and follow its instructions. The checklist covers:
- Coverage gaps (missing behavior, edge cases, error paths)
- Assertion quality
- Test design patterns
- Output format for findings

After identifying issues:
1. Create tasks for missing coverage and significant issues
2. Implement new/improved tests
3. Run test suite
4. Verify all tests pass

## Phase 10: Pre-PR Gate (Mandatory)

Before proceeding to PR creation, verify ALL of the following:

**Completeness Check**:
```
TaskList
```
- [ ] All tasks status=completed
- [ ] No pending or in_progress tasks
- [ ] If incomplete tasks exist → resolve or explicitly scope out

**Quality Gate**:
- [ ] Linter passes (zero errors)
- [ ] Type checker passes (zero errors)
- [ ] All tests pass
- [ ] Code review issues addressed
- [ ] Test review issues addressed

**Production Readiness**:
- [ ] No mocks/stubs/placeholders in src code
- [ ] No TODO comments for shipped code
- [ ] No debug/console output left
- [ ] All implementations are complete

**If ANY gate fails**:
1. Apply the verification loop pattern (Phase 6 Step 6.1): fix inline immediately, re-run checks
2. Max iterations (from settings, default: 3) before escalating to user via AskUserQuestion
3. Only proceed when all checks pass

## Phase 11: Ready for PR

**All quality gates passed.** Implementation is complete and ready for pull request.

### Step 11.1: Final Commit Check

Ensure all changes are committed:

```bash
git status --porcelain
```

If uncommitted changes exist, **use AskUserQuestion tool**:
- **Option 1**: "Run /gh-commit first" (Recommended) - Commit remaining changes
- **Option 2**: "Continue without committing" - Changes will not be in PR

### Step 11.2: Display Summary

```markdown
## Implementation Complete

**Branch**: {branch-name}
**Issue**: #{issue-number} - {issue-title}
**Commits**: {N} commits ahead of {default-branch}

### Tasks Completed
| Task | Status |
|------|--------|
| {task 1} | Completed |
| {task 2} | Completed |
| {task 3} | Completed |

**Progress**: {M}/{M} tasks completed

### Quality Gates
- [x] All tasks completed
- [x] Code review (self-review) passed
- [x] Test review passed
- [x] Linter passed
- [x] Type checker passed
- [x] All tests pass

### Runtime Verification Results

| Check | Status | Evidence |
|-------|--------|----------|
| Dev server starts | Pass/Fail/Skipped | [details] |
| API endpoints respond | Pass/Fail/Skipped | [details] |
| E2E tests | Pass/Fail/Skipped | [X passed, Y failed] |
| Acceptance criteria | Pass/Partial/Skipped | [details per criterion] |

#### Items Requiring Manual Verification
| Item | Why |
|------|-----|
| [criterion] | No automation available — verify visually |
```
### Files Changed
- {file1} (created)
- {file2} (modified)
- {file3} (modified)
```

### Step 11.3: Next Step Selection

**Use the AskUserQuestion tool** to determine next action:

- **Option 1**: "Create PR now" (Recommended) - Invoke `/gh-pr` workflow for full PR creation with reviewer suggestions
- **Option 2**: "Defer to /gh-pr later" - End gh-start, create PR manually with `/gh-pr`
- **Option 3**: "Make more changes first" - Continue working, commit with `/gh-commit` when ready

### If Option 1 Selected (Create PR Now)

Seamlessly continue into PR creation by invoking the gh-pr skill:

```markdown
**Creating PR...**

Invoking `/gh-pr` workflow which includes:
1. Full code review (with P1/P2/P3 findings)
2. Convention compliance check
3. Reviewer suggestions based on file expertise
4. PR preview and creation
```

Use the **Skill tool** to invoke `gh-pr` — this continues the workflow without requiring the user to type a separate command. The PR creation inherits all context from the current implementation session.

### If Option 2 Selected (Defer)

```markdown
## Implementation Ready

Your changes are committed and ready for PR creation.

**When you're ready**, run:
```
/gh-pr
```

This will:
- Run full code review
- Check conventions
- Suggest reviewers
- Create PR with your approval
```

### If Option 3 Selected (Continue Working)

```markdown
## Continue Working

Make additional changes, then:
1. Run `/gh-commit` to commit changes
2. Run `/gh-pr` when ready to create PR

**Current Status**:
- Branch: {branch}
- Commits: {N} ahead of {default-branch}
- Tasks: {M}/{M} completed
```

## Arguments

- `$ARGUMENTS`: Issue number or issue URL (required). Examples: `42`, `https://github.com/owner/repo/issues/42`
- To override base branch: mention it in your message (e.g., "start 42, target release branch")

## Rules

- **Always detect default branch dynamically** - never assume `main` or `master`
- Commits must follow conventional format
- **ALWAYS display findings BEFORE asking questions** - users must see status and summaries before being asked for decisions
- **Use the AskUserQuestion tool** at decision points:
  - Branch type selection (when ambiguous)
  - Incomplete tasks handling
  - Next step selection (PR now / defer / continue)
- **Use TaskCreate/TaskUpdate** to track implementation progress
- **Run parallel operations** when possible (multiple API calls, file reads)
- **Do not create PR directly** - offer choice to invoke `/gh-pr` or defer

## Success Criteria

Before completing, verify:
- [ ] Issue assigned to user
- [ ] Branch created from latest default branch
- [ ] All acceptance criteria from issue addressed
- [ ] All implementation tasks completed
- [ ] Code review (self-review) passed
- [ ] Test review (self-review) passed
- [ ] Pre-PR gate passed (lint, tests, no placeholders)
- [ ] User presented with next step options
- [ ] User informed of how to proceed (create PR or continue)

## Related Commands

- **`/gh-commit`**: Context-aware commits with change classification
- **`/gh-pr`**: Create PR with full review and reviewer suggestions
- **`/gh-review`**: Review a pull request
- **`/gh-address`**: Address PR review comments
