---
description: Use to start work on a GitHub issue - assigns issue, creates branch, guides implementation with task tracking, and prepares for PR
argument-hint: <issue-number>
allowed-tools: Bash, Read, Write, Edit, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, TaskGet, Skill
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, API calls, TaskCreate),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.
Err on the side of maximizing parallel tool calls.
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

## Phase 0: Project Context Handshake

Before any implementation work:

1. **Read project CLAUDE.md** (if it exists):
   ```bash
   cat .claude/CLAUDE.md 2>/dev/null || cat CLAUDE.md 2>/dev/null || echo "No CLAUDE.md found"
   ```

2. **Extract and display project constraints** relevant to this implementation:
   - Tech stack requirements (languages, frameworks, libraries)
   - Testing requirements and quality commands
   - Any "do not" or "always" rules
   - Coding conventions and patterns

3. **Briefly confirm constraints** before proceeding:
   > "Project constraints detected: [list key ones]. Proceeding with implementation following these constraints."

If no CLAUDE.md exists, note this and proceed with auto-detected conventions.

## Phase 1: Setup

**Execute these in parallel** (single message, multiple tool calls):

1. **Fetch the issue**:
   ```bash
   gh issue view $ARGUMENTS
   ```

2. **Fetch all issue comments for full context**:
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/issues/$ARGUMENTS/comments --jq '.[] | "---\n**@\(.user.login)** on \(.created_at):\n\(.body)\n"'
   ```

3. **Fetch issue timeline for related context**:
   ```bash
   gh api repos/$REPO/issues/$ARGUMENTS/timeline --jq '.[] | select(.event == "cross-referenced" or .event == "referenced") | "\(.event): \(.source.issue.title // .commit_id)"'
   ```

4. **Check for linked issues/PRs**:
   ```bash
   gh api repos/$REPO/issues/$ARGUMENTS --jq '.body' | grep -oE '#[0-9]+'
   ```

5. **Review all comments and linked issues** before confirming setup with user

6. **Assign the issue to yourself**:
   ```bash
   gh issue edit $ARGUMENTS --add-assignee @me
   ```

7. **Detect default branch and ensure on latest**:
   ```bash
   # Get default branch dynamically
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   git checkout $DEFAULT_BRANCH && git pull origin $DEFAULT_BRANCH
   ```

8. **Determine branch type** - If ambiguous, **use the AskUserQuestion tool**:

   When issue type is unclear (could be feature or fix), ask:
   - **Option 1**: "feature/issue-{number}-{desc}" - New functionality
   - **Option 2**: "fix/issue-{number}-{desc}" - Bug fix
   - **Option 3**: "docs/issue-{number}-{desc}" - Documentation only

   ```bash
   git checkout -b {branch-name}
   ```

9. **Confirm setup** with user before beginning implementation

## Phase 1.5: Capability Discovery

Before implementation, discover available project capabilities:

**Execute these in parallel**:

1. **Check for custom skills** that could help:
   ```bash
   ls .claude/skills/*/SKILL.md plugins/*/skills/*/SKILL.md 2>/dev/null
   ```

2. **Check for custom agents** available:
   ```bash
   ls .claude/agents/*.md plugins/*/agents/*.md 2>/dev/null
   ```

3. **Parse CLAUDE.md** for quality commands:
   ```bash
   grep -E "(lint|test|check|format|typecheck):" .claude/CLAUDE.md 2>/dev/null
   grep -E "(ruff|pytest|npm run|go vet|cargo)" .claude/CLAUDE.md 2>/dev/null
   ```

4. **Detect tech stack**:
   ```bash
   ls pyproject.toml package.json tsconfig.json go.mod Cargo.toml 2>/dev/null
   ```

5. **Build parallel quality command set** for reuse throughout the workflow:

   Based on CLAUDE.md commands or detected tech stack, compose three parallel commands:
   ```
   LINT_CMD="{detected lint command}"    # e.g., ruff check ., npm run lint, go vet ./...
   TEST_CMD="{detected test command}"    # e.g., pytest, npm test, go test ./...
   TYPECHECK_CMD="{detected typecheck}"  # e.g., pyright, tsc --noEmit, (skip if N/A)
   ```

   Store these for use in Phase 3.2 verification loop. If a command is not applicable (e.g., no type checker), note it as "N/A — skip".

## Phase 1.7: Impact Analysis

Before implementing, map the blast radius of planned changes:

1. **Identify modules to modify** from acceptance criteria

2. **Find dependents** - files that import/reference modules being changed:
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
   This catches tests in unrelated directories that import the module, which filename-pattern matching misses.

4. **Check for middleware/interceptors/decorators** that might be affected:
   ```bash
   grep -rn "middleware\|interceptor\|decorator\|@app\.\|@router\." --include="*.py" --include="*.ts" . 2>/dev/null | head -10
   ```

5. **Map test setup requirements** for each affected test file:
   ```bash
   # For each affected test file, extract setup patterns
   head -30 {test_file}  # Check imports and fixtures
   grep -n "setUp\|fixture\|beforeEach\|beforeAll\|@pytest.fixture\|conftest\|TestCase" {test_file} 2>/dev/null
   ```
   This prevents the pattern where tests break because they lack required setup (e.g., CSRF middleware added but test fixtures don't include it).

6. **Document impact** with test impact map:

   ```markdown
   ## Impact Analysis

   ### Modules to Modify
   | Module | Dependents | Tests Exist | Risk |
   |--------|-----------|-------------|------|
   | [module] | [N files] | [yes/no] | [low/med/high] |

   ### Test Impact Map
   | Module Being Changed | Test Files That Import/Mock It | Test Setup Requirements |
   |---------------------|-------------------------------|------------------------|
   | [module] | [test_file1, test_file2] | [fixtures, middleware, env vars] |

   ### Tests to Run After EACH Change
   1. `{test_cmd} {specific_test_file_1}`
   2. `{test_cmd} {specific_test_file_2}`
   3. `{full_test_suite_cmd}`

   ### Regression Guard
   Before implementing, snapshot current test state:
   ```bash
   {test_cmd} 2>&1 | tail -5  # Record baseline pass/fail counts
   ```
   After each change, compare against baseline to catch regressions immediately.

   ### Potential Side Effects
   - [e.g., "Adding auth middleware will affect all POST handlers"]
   - [e.g., "Changing schema will require test fixture updates"]
   ```

This prevents the pattern of adding middleware (e.g., CSRF) that silently breaks downstream tests.

## Phase 2: Task-Based Implementation

### Step 2.1: Create Task Breakdown

Parse issue acceptance criteria and create tasks using **TaskCreate**:

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

### Step 2.1a: Identify Parallel Implementation Opportunities

After creating the task breakdown, analyze the dependency graph to find tasks that can run in parallel:

**Parallelism criteria** (ALL must be true):
1. Tasks share the same dependency set (same `blockedBy` or no dependencies)
2. Tasks modify **different files** (no file overlap)
3. Tasks don't create code that the other imports (no cross-task dependencies)
4. Each task produces a testable increment

**If safe parallel groups found**:
1. Dispatch **Agent tool calls in parallel** for each task in the group (using `isolation: "worktree"`)
2. Each agent receives: task description, relevant file paths, project conventions from CLAUDE.md
3. After agents complete → verify no file conflicts (`git diff --name-only` across worktrees)
4. Run quality checks on merged result
5. Mark parallel tasks as complete

**If no safe parallel groups found** → fall back to sequential Step 2.2. This is the **default** — incorrect parallelism causes merge conflicts, so err on the side of sequential.

**Example**: If Task 1 = "Add validation schema" and Task 2 = "Update API docs", and they touch different files with no imports between them, they can safely run in parallel. But if Task 2 imports from Task 1's output, they must be sequential.

### Step 2.2: Work Through Tasks Systematically

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

### Step 2.3: Progress Tracking

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

## Phase 3: Quality Checks (Dynamic Discovery)

### Step 3.1: Discover Quality Tools

In priority order:

1. **Check CLAUDE.md** for explicit commands:
   ```bash
   grep -E "(lint|test|check)" .claude/CLAUDE.md 2>/dev/null
   ```

2. **Fallback to tech stack detection**:
   | Indicator | Commands |
   |-----------|----------|
   | pyproject.toml | `ruff check .`, `pytest` |
   | package.json | `npm run lint`, `npm test` |
   | tsconfig.json | `tsc --noEmit` |
   | go.mod | `go vet ./...`, `go test ./...` |
   | Cargo.toml | `cargo clippy`, `cargo test` |

### Step 3.2: Quality Verification Loop (Bounded)

Execute a bounded fix-verify cycle. **Fix immediately — do not create tasks** for lint/test failures.

**Iteration 1 (and up to 3 total):**

1. **Run all quality commands in parallel** (3 Bash tool calls in a single message):
   ```
   Execute 3 Bash tool calls in a single message:
   - Bash call 1: {lint_cmd}       # e.g., ruff check . 2>&1
   - Bash call 2: {test_cmd}       # e.g., pytest 2>&1
   - Bash call 3: {typecheck_cmd}  # e.g., tsc --noEmit 2>&1
   ```

2. **If ALL pass** → proceed to Step 3.4

3. **If ANY fail**:
   - Parse error output to identify root cause (file, line, error type)
   - Fix the issue inline immediately (Edit tool, not TaskCreate)
   - Commit the fix: `git commit -m "fix: [what was fixed]"`
   - Re-run ALL checks (go back to step 1)

4. **Max 3 iterations**. After 3 failed iterations → escalate to user via **AskUserQuestion tool**:
   - **Option 1**: "Show me the failures, I'll fix manually"
   - **Option 2**: "Skip failing checks and proceed" — note which checks were skipped
   - **Option 3**: "Abort — I need to investigate"

**Key principle**: Tight fix-verify cycles. Tasks add overhead to what should be a quick lint/test fix.

### Step 3.4: Verify All Tasks Complete

```
TaskList
```

If incomplete tasks remain, **use AskUserQuestion tool**:
- "Complete remaining tasks before PR"
- "Create PR noting partial implementation"
- "Mark remaining as out-of-scope"

## Phase 3.3: Runtime Verification

After quality checks pass (lint/test/typecheck), verify the implementation actually works:

### Step 3.3.1: Discover Verification Capabilities

Check what runtime verification is available for this project:
```bash
# From CLAUDE.md
grep -E "^(dev-server|verify|e2e|smoke|health):" .claude/CLAUDE.md 2>/dev/null

# From project files
ls verify.sh scripts/verify* 2>/dev/null
ls playwright.config.* cypress.config.* 2>/dev/null
cat package.json 2>/dev/null | grep -E '"(dev|start|serve|e2e|test:e2e)"'
```

### Step 3.3.2: Execute Available Verification

**If dev server command found**:
1. Start server in background
2. Wait for ready signal (health endpoint or port availability, max 30s)
3. Run smoke tests against new/modified endpoints
4. Run E2E tests if framework detected
5. Kill background server

**If verify script found** (`verify.sh`, `scripts/verify.sh`):
```bash
bash verify.sh 2>&1
```

**If E2E framework found** (Playwright, Cypress, etc.):
```bash
{e2e_cmd} 2>&1
```

**If acceptance criteria can be verified programmatically**:
For each criterion from the issue, attempt to verify it:
- API endpoint → make request, check response
- CLI command → run it, check output
- Data transformation → verify input/output
- Document result as VERIFIED or NEEDS_MANUAL_CHECK

### Step 3.3.3: Report Results

```markdown
## Runtime Verification Results

| Check | Status | Evidence |
|-------|--------|----------|
| Dev server starts | Pass/Fail/Skipped | [details] |
| API endpoints respond | Pass/Fail/Skipped | [details] |
| E2E tests | Pass/Fail/Skipped | [X passed, Y failed] |
| Acceptance criteria | Pass/Partial/Skipped | [details per criterion] |

### Items Requiring Manual Verification
| Item | Why |
|------|-----|
| [criterion] | No automation available — verify visually |
```

### Step 3.3.4: Handle Failures

Apply the verification loop pattern:
- If runtime tests fail → analyze root cause, fix, re-run (max 3 iterations)
- If dev server won't start → report error with logs, proceed to code review (not blocking)
- If no verification capabilities detected → note "Runtime verification skipped — no dev server or E2E framework found" and proceed

**IMPORTANT**: Runtime verification is additive, not blocking. If a project has no dev server or E2E framework, this phase completes with "skipped" status and the workflow continues. It should never prevent a PR from being created for projects that don't have runtime verification set up.

## Phase 3.5: Code Review (Self-Review)

Before creating PR, perform systematic code review on the diff:

```bash
# Get the diff to review
git diff origin/$DEFAULT_BRANCH..HEAD
```

**Review Checklist** (only analyze new code in diff):

1. **Unnecessary/Duplicate Code**
   - Identify redundant logic
   - Check for copy-paste duplication
   - Look for dead code paths

2. **Type Safety & Language Gotchas**
   - TypeScript: proper typing, no unnecessary `any`
   - Python: type hints, pyright compliance
   - Watch for common footguns

3. **Code Bloat**
   - Remove unnecessary comments
   - Delete debug code/console.logs
   - Remove commented-out code

4. **Complexity**
   - Simplify overly complicated logic
   - Extract complex conditions into named functions
   - Reduce nesting depth

5. **Naming**
   - Variable names are clear and descriptive
   - Function names describe what they do
   - Consistent naming patterns

6. **Pattern Consistency**
   - Use established project patterns
   - Don't introduce conflicting approaches
   - Check CLAUDE.md for conventions

7. **NO PLACEHOLDERS**
   - No mocks, demo data, placeholder code, stubs in src
   - All implementations must be production-ready

**Output Format**:
```
## Code Review Findings

### Issues Found
| # | Type | Location | Issue | Fix |
|---|------|----------|-------|-----|
| 1 | Duplicate | file:line | [desc] | [fix] |

### Fixes Applied
- [x] Fixed: [description]
```

After identifying issues:
1. Create tasks for each fix: `TaskCreate: subject="Fix: [issue]"`
2. Implement fixes
3. Re-run linters and type checkers
4. Verify all issues resolved

## Phase 3.6: Test Review (Self-Review)

Review tests in the current diff:

**Coverage Check**:
- Missing tests for new behavior/branches?
- Edge cases, boundary values, error paths?
- Negative cases, invalid inputs, failure modes?

**Assertion Quality**:
- Checking behavior, not implementation details?
- Weak assertions (too generic, no failure message)?
- Over-asserting unimportant details?

**Test Design**:
- Descriptive names (given/when/then or AAA)?
- Clear intent, minimal mental overhead?
- Magic values → constants/factories/helpers?
- Duplicated setup → fixtures/parametrized tests?

**Output Format**:
```
## Test Review Findings

### Missing Coverage
| Behavior | Suggested Test |
|----------|----------------|
| [behavior] | [test name and approach] |

### Issues Found
| # | Type | Test | Issue | Fix |
|---|------|------|-------|-----|
| 1 | Weak assertion | test_foo | [desc] | [fix] |

### Fixes Applied
- [x] Added: test_edge_case_X
- [x] Fixed: improved assertions in test_Y
```

After identifying issues:
1. Create tasks for each improvement
2. Implement new/improved tests
3. Run test suite
4. Verify all tests pass

## Phase 3.7: Pre-PR Gate (Mandatory)

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
1. Apply the verification loop pattern (Step 3.2): fix inline immediately, re-run checks
2. Max 3 iterations before escalating to user via AskUserQuestion
3. Only proceed when all checks pass

## Phase 4: Ready for PR

**All quality gates passed.** Implementation is complete and ready for pull request.

### Step 4.1: Final Commit Check

Ensure all changes are committed:

```bash
# Check for uncommitted changes
git status --porcelain

# If uncommitted changes exist, prompt for action
```

If uncommitted changes exist, **use AskUserQuestion tool**:
- **Option 1**: "Run /gh-commit first" (Recommended) - Commit remaining changes
- **Option 2**: "Continue without committing" - Changes will not be in PR

### Step 4.2: Display Summary

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

### Files Changed
- {file1} (created)
- {file2} (modified)
- {file3} (modified)
```

### Step 4.3: Next Step Selection

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

- `$ARGUMENTS`: Issue number (required)
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
